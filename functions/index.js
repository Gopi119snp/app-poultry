const crypto = require("crypto");
const Razorpay = require("razorpay");

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

  try {
    const targetUser = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(targetUser.uid, { password: newPassword });
    await tokenRef.delete();

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
 * sendEmailOtp
 * ============================================================================
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
 * verifyEmailOtp
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
 * verifyEmailOtpForReset
 * ============================================================================
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

/**
 * ============================================================================
 * RAZORPAY — Subscription billing (website only, per-active-farmer pricing)
 * ============================================================================
 * ✅ NEW — RAZORPAY_KEY_ID aur RAZORPAY_KEY_SECRET `functions/.env` se
 * aate hain, bilkul GMAIL_USER/GMAIL_APP_PASSWORD ki tarah — kabhi code
 * mein hardcode mat karna.
 */
function getRazorpayInstance() {
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
}

/**
 * ✅ NEW — createRazorpayOrder: Amount hamesha SERVER khud calculate karta
 * hai (active farmer count × ₹200), client se bheja hua amount kabhi
 * trust nahi karte — warna koi bhi client-side amount chhed-chhaad karke
 * kam paisa mein "pay" kar sakta tha.
 */
exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
  const companyId = ((data && data.companyId) || "").trim();
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId chahiye.");
  }

  const db = admin.firestore();
  const dataSnap = await db
    .collection("companies")
    .doc(companyId)
    .collection("data")
    .doc("main")
    .get();
  const docData = dataSnap.exists ? dataSnap.data() : {};

  let farmers = [];
  try {
    farmers = JSON.parse(docData.companyFarmers || "[]");
  } catch (_) {}
  const activeFarmerCount =
    farmers.filter((f) => f.status === "active").length || farmers.length || 0;

  const RATE_PER_FARMER = 200; // ₹ per farmer per month
  const amountInRupees = Math.max(activeFarmerCount, 1) * RATE_PER_FARMER;
  const amountInPaise = amountInRupees * 100;

  try {
    const razorpay = getRazorpayInstance();
    const order = await razorpay.orders.create({
      amount: amountInPaise,
      currency: "INR",
      receipt: `tracko_${companyId}_${Date.now()}`,
      notes: { companyId, farmerCount: String(activeFarmerCount) },
    });

    return {
      orderId: order.id,
      amount: amountInPaise,
      currency: "INR",
      farmerCount: activeFarmerCount,
    };
  } catch (err) {
    console.error("[createRazorpayOrder] failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Order create nahi ho paaya: " + err.message
    );
  }
});

/**
 * ✅ NEW — verifyRazorpayPayment: payment ke baad client isse call karta
 * hai. Signature Razorpay ke Key Secret se verify hoti hai — sirf tabhi
 * subscriptionStatus 'active' hota hai jab signature genuinely match kare.
 */
exports.verifyRazorpayPayment = functions.https.onCall(async (data, context) => {
  const companyId = ((data && data.companyId) || "").trim();
  const razorpay_order_id = (data && data.razorpay_order_id) || "";
  const razorpay_payment_id = (data && data.razorpay_payment_id) || "";
  const razorpay_signature = (data && data.razorpay_signature) || "";

  if (!companyId || !razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Payment details incomplete hain."
    );
  }

  const expectedSignature = crypto
    .createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpay_order_id}|${razorpay_payment_id}`)
    .digest("hex");

  if (expectedSignature !== razorpay_signature) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Payment verify nahi ho paaya — signature match nahi kar rahi."
    );
  }

  try {
    const razorpay = getRazorpayInstance();
    const order = await razorpay.orders.fetch(razorpay_order_id);
    if (!order || !order.notes || order.notes.companyId !== companyId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Order is company ka nahi hai."
      );
    }

    const db = admin.firestore();
    const oneMonthMs = 30 * 24 * 60 * 60 * 1000;

    await db
      .collection("companies")
      .doc(companyId)
      .collection("data")
      .doc("main")
      .set(
        {
          subscriptionStatus: "active",
          subscriptionExpiry: admin.firestore.Timestamp.fromMillis(
            Date.now() + oneMonthMs
          ),
          lastPaymentId: razorpay_payment_id,
          lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    return { success: true };
  } catch (err) {
    console.error("[verifyRazorpayPayment] failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Verification mein error: " + err.message
    );
  }
});