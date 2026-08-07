const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/**
 * Gmail SMTP transporter — GMAIL_USER aur GMAIL_APP_PASSWORD
 * `functions/.env` file se aate hain (Firebase CLI khud load kar leta hai,
 * .env commit mat karna — .gitignore mein daal do).
 */
function getMailTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: process.env.GMAIL_USER,
      pass: process.env.GMAIL_APP_PASSWORD,
    },
  });
}

/**
 * ============================================================================
 * resetPasswordAfterOtp — Secure server-side password reset
 * ============================================================================
 *
 * Kyun zaroori hai: Firebase ka client-side SDK sirf CURRENTLY SIGNED-IN
 * user ka apna password change kar sakta hai. "Forgot Password" ka poora
 * matlab hi ye hai ki user sign-in NAHI kar sakta (password bhool gaya) —
 * isliye client se seedha password change karna Firebase allow hi nahi
 * karta. Isiliye ye server-side Cloud Function (Admin SDK use karke)
 * chahiye, jo kisi bhi user ka password force-update kar sakti hai.
 *
 * Security: Ye function TRUST karta hai `context.auth.token.phone_number`
 * — jo sirf Firebase khud set karta hai jab client ne successfully Phone
 * OTP verify kiya ho (signInWithCredential). Client kabhi bhi ye phone
 * number field khud se spoof/fake nahi kar sakta — Firebase server-side
 * ise verify karke token mein daalta hai. Isliye humein client se phone
 * number ALAG se bhejwane/trust karne ki zaroorat nahi — humesha
 * context.auth.token.phone_number hi authoritative source hai.
 *
 * Flow (Flutter side se):
 *   1. User "Forgot Password" mein apna phone daalta hai
 *   2. OtpService.sendOtp(phone) → Firebase SMS bhejta hai
 *   3. OtpService.verifyOtp(code) → user Firebase Auth mein
 *      PHONE-VERIFIED signed-in ho jata hai (temporary session)
 *   4. Isi signed-in state mein ye Cloud Function call hoti hai
 *      (Firebase Functions SDK automatically ID token attach karta hai)
 *   5. Function verify karti hai ki caller genuinely us phone se verified
 *      hai, phir uska ASLI (email-based) account dhundke password badalti hai
 *   6. Flutter side OtpService.signOutOtpSession() call karke temporary
 *      phone-session se signout kar deta hai
 *   7. User naye password se normal login karta hai
 */
exports.resetPasswordAfterOtp = functions.https.onCall(async (data, context) => {
  // ── 1. Caller genuinely Phone-OTP-verified hai? ──────────────────────
  if (!context.auth || !context.auth.token || !context.auth.token.phone_number) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Phone verify nahi hua hai. Pehle OTP verify karo."
    );
  }

  // Firebase E.164 format mein deta hai: "+919661371205"
  const verifiedPhoneE164 = context.auth.token.phone_number;
  const verifiedPhone10Digit = verifiedPhoneE164.replace(/\D/g, "").slice(-10);

  // ── 2. Naya password valid hai? ──────────────────────────────────────
  const newPassword = data && data.newPassword;
  if (!newPassword || typeof newPassword !== "string" || newPassword.length < 6) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Password kam se kam 6 characters ka hona chahiye."
    );
  }

  // ── 3. phone_lookup se is number ka asli (email-based) account dhundo ──
  const db = admin.firestore();
  const lookupSnap = await db.collection("phone_lookup").doc(verifiedPhone10Digit).get();

  if (!lookupSnap.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Yeh number kisi account se linked nahi hai."
    );
  }

  const lookupData = lookupSnap.data();
  const authEmail = lookupData.authEmail;
  const role = lookupData.role || "";

  // ✅ Sirf Owner aur Personal Farmer apna password reset kar sakte hain
  // (existing app rule — Manager ka password Owner ke paas hota hai)
  if (role !== "Owner" && role !== "Personal Farmer") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Sirf Owner ya Personal Farmer apna password reset kar sakte hain."
    );
  }

  if (!authEmail) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Is account ka email record nahi mila."
    );
  }

  // ── 4. Asli Firebase Auth user dhundo aur password update karo ──────
  try {
    const targetUser = await admin.auth().getUserByEmail(authEmail);
    await admin.auth().updateUser(targetUser.uid, { password: newPassword });

    return { success: true, message: "Password successfully update ho gaya." };
  } catch (err) {
    console.error("[resetPasswordAfterOtp] failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Password update karne mein error: " + err.message
    );
  }
});

/**
 * ============================================================================
 * sendEmailOtp — Company registration ke waqt email verify karne ke liye
 * ============================================================================
 * 6-digit code generate karti hai, Firestore mein 5-minute expiry ke saath
 * store karti hai, aur Gmail SMTP se real email bhejti hai.
 */
exports.sendEmailOtp = functions.https.onCall(async (data, context) => {
  const email = ((data && data.email) || "").trim().toLowerCase();

  if (!email || !/^[\w.-]+@[\w-]+\.[a-zA-Z]{2,}$/.test(email)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Sahi email address daalo."
    );
  }

  const code = Math.floor(100000 + Math.random() * 900000).toString();
  const db = admin.firestore();

  await db.collection("email_otps").doc(email).set({
    code,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
    attempts: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const transporter = getMailTransporter();
    await transporter.sendMail({
      from: `"PoultryPro" <${process.env.GMAIL_USER}>`,
      to: email,
      subject: "PoultryPro — Aapka Verification Code",
      text: `Aapka verification code hai: ${code}\n\nYe code 5 minute mein expire ho jayega. Agar aapne ye request nahi ki, to is email ko ignore kar dein.`,
      html: `<div style="font-family:sans-serif;">
        <p>Namaste,</p>
        <p>Aapka PoultryPro verification code hai:</p>
        <p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${code}</p>
        <p>Ye code 5 minute mein expire ho jayega.</p>
        <p style="color:#888;font-size:12px;">Agar aapne ye request nahi ki, to is email ko ignore kar dein.</p>
      </div>`,
    });
  } catch (err) {
    console.error("[sendEmailOtp] mail send failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Email bhejne mein error: " + err.message
    );
  }

  return { success: true };
});

/**
 * ============================================================================
 * verifyEmailOtp — user ne jo code type kiya, use Firestore se match karti hai
 * ============================================================================
 */
exports.verifyEmailOtp = functions.https.onCall(async (data, context) => {
  const email = ((data && data.email) || "").trim().toLowerCase();
  const code = ((data && data.code) || "").trim();

  if (!email || !code) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Email aur code dono chahiye."
    );
  }

  const db = admin.firestore();
  const docRef = db.collection("email_otps").doc(email);
  const snap = await docRef.get();

  if (!snap.exists) {
    return { success: false, message: "Pehle OTP mangwao." };
  }

  const otpData = snap.data();

  if (Date.now() > otpData.expiresAt.toMillis()) {
    await docRef.delete();
    return { success: false, message: "OTP expire ho gaya — dobara mangwao." };
  }

  if ((otpData.attempts || 0) >= 5) {
    await docRef.delete();
    return {
      success: false,
      message: "Bahut zyada galat attempts — dobara OTP mangwao.",
    };
  }

  if (otpData.code !== code) {
    await docRef.update({
      attempts: admin.firestore.FieldValue.increment(1),
    });
    return { success: false, message: "OTP galat hai." };
  }

  await docRef.delete();
  return { success: true };
});