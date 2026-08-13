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
 * resetPasswordAfterOtp — Secure server-side password reset (EMAIL OTP based)
 * ============================================================================
 *
 * Kyun zaroori hai: Firebase ka client-side SDK sirf CURRENTLY SIGNED-IN
 * user ka apna password change kar sakta hai. "Forgot Password" ka poora
 * matlab hi ye hai ki user sign-in NAHI kar sakta (password bhool gaya) —
 * isliye client se seedha password change karna Firebase allow hi nahi
 * karta. Isiliye ye server-side Cloud Function (Admin SDK use karke)
 * chahiye, jo kisi bhi user ka password force-update kar sakti hai.
 *
 * Security: Mobile OTP (Phone Auth) ki jagah ab Email OTP + ek short-lived
 * "resetToken" use hota hai — koi Firebase phone-auth session ki zaroorat
 * nahi. Flow:
 *   1. User "Forgot Password" mein apna email daalta hai
 *   2. sendEmailOtp(email) → 6-digit code email par jata hai
 *   3. verifyEmailOtpForReset(email, code) → code sahi hone par server
 *      ek random `resetToken` generate karke Firestore mein 10-minute
 *      expiry ke saath store karta hai, aur usi token ko client ko
 *      wapas bhejta hai (client isse spoof nahi kar sakta kyunki server
 *      hi generate karta hai)
 *   4. Client isi resetToken + newPassword ke saath resetPasswordAfterOtp
 *      call karta hai
 *   5. Function token verify karti hai (exists + expire nahi hua +
 *      email match), phir email se asli Firebase Auth user dhundke
 *      password update karti hai, aur token consume (delete) kar deti hai
 */
exports.resetPasswordAfterOtp = functions.https.onCall(async (data, context) => {
  const email = ((data && data.email) || "").trim().toLowerCase();
  const resetToken = ((data && data.resetToken) || "").trim();
  const newPassword = data && data.newPassword;

  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email chahiye.");
  }
  if (!resetToken) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Email OTP verify nahi hua hai. Pehle OTP verify karo."
    );
  }
  if (!newPassword || typeof newPassword !== "string" || newPassword.length < 6) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Password kam se kam 6 characters ka hona chahiye."
    );
  }

  const db = admin.firestore();

  // ── 1. resetToken valid hai? ──────────────────────────────────────────
  const tokenRef = db.collection("password_reset_tokens").doc(resetToken);
  const tokenSnap = await tokenRef.get();

  if (!tokenSnap.exists) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Reset session expire ho gaya — email OTP dobara verify karo."
    );
  }

  const tokenData = tokenSnap.data();

  if (Date.now() > tokenData.expiresAt.toMillis()) {
    await tokenRef.delete();
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Reset session expire ho gaya — email OTP dobara verify karo."
    );
  }

  if (tokenData.email !== email) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Ye reset session is email ka nahi hai."
    );
  }

  // ── 2. phone_lookup se is email wale account ka role check karo ────────
  // (existing app rule — sirf Owner/Personal Farmer khud reset kar sakte
  // hain, Manager ka password Owner set/reset karta hai)
  const lookupSnap = await db
    .collection("phone_lookup")
    .where("authEmail", "==", email)
    .limit(1)
    .get();

  if (!lookupSnap.empty) {
    const role = lookupSnap.docs[0].data().role || "";
    if (role !== "Owner" && role !== "Personal Farmer") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Sirf Owner ya Personal Farmer apna password reset kar sakte hain."
      );
    }
  }

  // ── 3. Asli Firebase Auth user dhundo aur password update karo ────────
  try {
    const targetUser = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(targetUser.uid, { password: newPassword });
    await tokenRef.delete(); // token ek hi baar use ho sakta hai

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

  // ✅ Har email ka time IST mein saaf dikhana + subject line mein bhi
  // time daalna — taaki Gmail purane/naye OTP emails ko ek hi thread mein
  // group na kare (jisse confusion hota tha ki konsa email latest hai).
  // Isse har naya OTP email ALAG dikhega, inbox mein sabse upar (sabse
  // naya time), aur email ke andar bhi explicit warning hai ki agar isse
  // purana koi email dikhe to use ignore karo.
  const sentTimeIST = new Date().toLocaleTimeString("en-IN", {
    timeZone: "Asia/Kolkata",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: true,
  });

  try {
    const transporter = getMailTransporter();
    await transporter.sendMail({
      from: `"PoultryPro" <${process.env.GMAIL_USER}>`,
      to: email,
      subject: `PoultryPro — Verification Code (${sentTimeIST})`,
      text: `Aapka NAYA verification code hai: ${code}\n\nYe code ${sentTimeIST} par bheja gaya hai aur 5 minute mein expire ho jayega.\n\n⚠️ Agar aapke inbox mein isse PURANA koi PoultryPro OTP email hai, use IGNORE karein — sirf yahi (sabse naya) code use karein.\n\nAgar aapne ye request nahi ki, to is email ko ignore kar dein.`,
      html: `<div style="font-family:sans-serif;">
        <p>Namaste,</p>
        <p>Aapka <b>NAYA</b> PoultryPro verification code hai:</p>
        <p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${code}</p>
        <p style="color:#555;font-size:13px;">Bheja gaya: <b>${sentTimeIST}</b> · 5 minute mein expire hoga.</p>
        <div style="background:#FFF3E0;border:1px solid #FFCC80;border-radius:8px;padding:10px 14px;margin-top:12px;">
          <p style="margin:0;font-size:12.5px;color:#E65100;">⚠️ Agar aapke inbox mein isse <b>purana</b> koi PoultryPro OTP email hai, use <b>ignore</b> karein — sirf yehi (sabse naya, upar wala) code use karein.</p>
        </div>
        <p style="color:#888;font-size:12px;margin-top:14px;">Agar aapne ye request nahi ki, to is email ko ignore kar dein.</p>
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

/**
 * ============================================================================
 * verifyEmailOtpForReset — Forgot Password ke liye Email OTP verify karta hai
 * ============================================================================
 * verifyEmailOtp jaisa hi hai, bas success hone par ek short-lived
 * `resetToken` bhi generate karke Firestore mein 10-minute expiry ke saath
 * store karta hai aur client ko wapas bhejta hai. Ye token hi
 * resetPasswordAfterOtp mein "main genuinely OTP-verified hoon" prove karta
 * hai — client kabhi khud se ye token fake nahi bana sakta.
 */
exports.verifyEmailOtpForReset = functions.https.onCall(async (data, context) => {
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

  // Reset token generate karo — random 32-char hex string
  const resetToken = Array.from({ length: 32 }, () =>
    Math.floor(Math.random() * 16).toString(16)
  ).join("");

  await db.collection("password_reset_tokens").doc(resetToken).set({
    email,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { success: true, resetToken };
});