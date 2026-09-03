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
 * `functions/.env` file se aate hain.
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
 * ADMIN ACCESS
 * ============================================================================
 */
const ADMIN_EMAIL = "gopi119snp@gmail.com";

function assertIsAdmin(context) {
  if (
    !context.auth ||
    !context.auth.token ||
    !context.auth.token.email ||
    context.auth.token.email.toLowerCase() !== ADMIN_EMAIL.toLowerCase()
  ) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Sirf admin coupons manage kar sakta hai."
    );
  }
}

/**
 * ============================================================================
 * COUPONS
 * ============================================================================
 */
exports.createCoupon = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const code = ((data && data.code) || "").trim().toUpperCase();
  const discountPercent = Number(data && data.discountPercent);
  const validFromMs = Number(data && data.validFrom);
  const validUntilMs = Number(data && data.validUntil);
  const scope = (data && data.scope) === "specific" ? "specific" : "all";
  const companyIds = Array.isArray(data && data.companyIds)
    ? data.companyIds.map((c) => String(c).trim()).filter(Boolean)
    : [];

  if (!code || !/^[A-Z0-9_-]{3,30}$/.test(code)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Coupon code 3-30 characters ka hona chahiye (sirf letters/numbers/-/_)."
    );
  }
  if (!Number.isFinite(discountPercent) || discountPercent <= 0 || discountPercent > 100) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Discount 1 se 100 ke beech hona chahiye."
    );
  }
  if (!Number.isFinite(validFromMs) || !Number.isFinite(validUntilMs) || validUntilMs <= validFromMs) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Valid-from date, valid-until date se pehle honi chahiye."
    );
  }
  if (scope === "specific" && companyIds.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Specific companies ke liye kam se kam ek Company ID chahiye."
    );
  }

  const db = admin.firestore();
  const couponRef = db.collection("coupons").doc(code);
  const existing = await couponRef.get();
  if (existing.exists) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Ye coupon code pehle se maujood hai — koi doosra code try karo."
    );
  }

  await couponRef.set({
    code,
    discountPercent,
    validFrom: admin.firestore.Timestamp.fromMillis(validFromMs),
    validUntil: admin.firestore.Timestamp.fromMillis(validUntilMs),
    scope,
    companyIds: scope === "specific" ? companyIds : [],
    active: true,
    usedCount: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: context.auth.token.email,
  });

  return { success: true, code };
});

exports.listCoupons = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const db = admin.firestore();
  const snap = await db.collection("coupons").orderBy("createdAt", "desc").get();

  return {
    coupons: snap.docs.map((d) => {
      const c = d.data();
      return {
        code: c.code,
        discountPercent: c.discountPercent,
        validFrom: c.validFrom ? c.validFrom.toMillis() : null,
        validUntil: c.validUntil ? c.validUntil.toMillis() : null,
        scope: c.scope,
        companyIds: c.companyIds || [],
        active: !!c.active,
        usedCount: c.usedCount || 0,
      };
    }),
  };
});

exports.setCouponActive = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const code = ((data && data.code) || "").trim().toUpperCase();
  const active = !!(data && data.active);
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "Coupon code chahiye.");
  }

  const couponRef = admin.firestore().collection("coupons").doc(code);
  const snap = await couponRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Ye coupon nahi mila.");
  }

  await couponRef.update({ active });
  return { success: true };
});

exports.deleteCoupon = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const code = ((data && data.code) || "").trim().toUpperCase();
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "Coupon code chahiye.");
  }

  await admin.firestore().collection("coupons").doc(code).delete();
  return { success: true };
});

/**
 * ============================================================================
 * RAZORPAY CONFIG & PRICING
 * ============================================================================
 */
function getRazorpayInstance() {
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
}

const RATE_PER_FARMER = 200;
const COMPANY_MIN_SLOTS = 10;
const MAX_FARMER_SLOTS = 1000;
const PERSONAL_FARMER_PRICE = RATE_PER_FARMER;
const SUBSCRIPTION_PERIOD_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * companyId se us company ka phone_lookup record dhoondta hai (role +
 * authEmail). Ye wahi record hai jo login.html billing login ke waqt
 * check karta hai.
 */
async function getOwnerLookup(db, companyId) {
  const lookupSnap = await db
    .collection("phone_lookup")
    .where("companyId", "==", companyId)
    .limit(1)
    .get();
  if (lookupSnap.empty) return null;
  return lookupSnap.docs[0].data();
}

/**
 * 🛑 NAYA: Ye function confirm karta hai ki abhi jo user logged in hai
 * (context.auth), wahi is companyId ka asli Owner/Personal Farmer hai —
 * pehle billing functions sirf companyId le lete the bina check kiye ki
 * caller uska malik hai bhi ya nahi. Ab har billing-related call se
 * pehle ye check hota hai.
 */
function assertOwnerAuth(context, lookup) {
  if (!context.auth || !context.auth.token || !context.auth.token.email) {
    throw new functions.https.HttpsError("unauthenticated", "Login required.");
  }
  if (!lookup || !lookup.authEmail) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Ye account kisi company se linked nahi hai."
    );
  }
  if (context.auth.token.email.toLowerCase() !== String(lookup.authEmail).toLowerCase()) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Aap is company ke liye authorized nahi hain."
    );
  }
}

exports.createRazorpayOrder = functions.https.onCall(async (data, context) => {
  const companyId = ((data && data.companyId) || "").trim();
  const couponCode = ((data && data.couponCode) || "").trim().toUpperCase();
  const requestedSlotsRaw = Number(data && data.farmerSlots);
  const requestedScheduleMode =
    (data && data.scheduleMode) === "next-cycle" ? "next-cycle" : "immediate";

  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId chahiye.");
  }

  const db = admin.firestore();

  const lookup = await getOwnerLookup(db, companyId);
  assertOwnerAuth(context, lookup);
  const isPersonalFarmer = lookup.role === "Personal Farmer";

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

  // 🛑 NAYA: current plan abhi bhi valid hai ya nahi, ye check karke
  // decide karte hain ki "next-cycle" (schedule) wala choice honor karna
  // hai ya nahi. Agar koi active plan hi nahi hai (trial/expired/first
  // time), to schedule karne ka koi matlab nahi — turant hi apply hoga.
  const now = Date.now();
  const currentExpiryMs = docData.subscriptionExpiry ? docData.subscriptionExpiry.toMillis() : null;
  const currentlyActive =
    docData.subscriptionStatus === "active" && currentExpiryMs && currentExpiryMs > now;
  const scheduleMode = currentlyActive ? requestedScheduleMode : "immediate";

  let farmerSlots;
  let amountInRupees;

  if (isPersonalFarmer) {
    farmerSlots = 1;
    amountInRupees = PERSONAL_FARMER_PRICE;
  } else {
    let slots = Number.isFinite(requestedSlotsRaw) && requestedSlotsRaw > 0
      ? Math.ceil(requestedSlotsRaw / 5) * 5
      : COMPANY_MIN_SLOTS;

    slots = Math.min(Math.max(slots, COMPANY_MIN_SLOTS), MAX_FARMER_SLOTS);

    if (slots < activeFarmerCount) {
      slots = Math.min(Math.max(Math.ceil(activeFarmerCount / 5) * 5, COMPANY_MIN_SLOTS), MAX_FARMER_SLOTS);
    }

    farmerSlots = slots;
    amountInRupees = slots * RATE_PER_FARMER;
  }

  let appliedCoupon = null;
  if (couponCode) {
    const couponSnap = await db.collection("coupons").doc(couponCode).get();
    if (!couponSnap.exists) {
      throw new functions.https.HttpsError("not-found", "Ye coupon code valid nahi hai.");
    }
    const coupon = couponSnap.data();
    const nowMs = Date.now();

    if (!coupon.active) {
      throw new functions.https.HttpsError("failed-precondition", "Ye coupon ab active nahi hai.");
    }
    if (coupon.validFrom && nowMs < coupon.validFrom.toMillis()) {
      throw new functions.https.HttpsError("failed-precondition", "Ye coupon abhi shuru nahi hua hai.");
    }
    if (coupon.validUntil && nowMs > coupon.validUntil.toMillis()) {
      throw new functions.https.HttpsError("failed-precondition", "Ye coupon expire ho chuka hai.");
    }
    if (coupon.scope === "specific" && !(coupon.companyIds || []).includes(companyId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Ye coupon aapki company ke liye valid nahi hai."
      );
    }

    const discountAmount = Math.round((amountInRupees * coupon.discountPercent) / 100);
    amountInRupees = Math.max(amountInRupees - discountAmount, 1);
    appliedCoupon = { code: couponCode, discountPercent: coupon.discountPercent };
  }

  const amountInPaise = amountInRupees * 100;

  try {
    const razorpay = getRazorpayInstance();
    const order = await razorpay.orders.create({
      amount: amountInPaise,
      currency: "INR",
      receipt: `tracko_${companyId}_${Date.now()}`,
      notes: {
        companyId,
        accountType: isPersonalFarmer ? "personal" : "company",
        farmerSlots: String(farmerSlots),
        farmerCount: String(activeFarmerCount),
        couponCode: appliedCoupon ? appliedCoupon.code : "",
        scheduleMode,
      },
    });

    return {
      orderId: order.id,
      amount: amountInPaise,
      currency: "INR",
      accountType: isPersonalFarmer ? "personal" : "company",
      farmerSlots,
      farmerCount: activeFarmerCount,
      appliedCoupon,
      scheduleMode,
    };
  } catch (err) {
    console.error("[createRazorpayOrder] failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Order create nahi ho paaya: " + err.message
    );
  }
});

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

  const db = admin.firestore();
  const lookup = await getOwnerLookup(db, companyId);
  assertOwnerAuth(context, lookup);

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

    await activateSubscriptionForPayment({
      companyId,
      paymentId: razorpay_payment_id,
      couponCode: (order.notes && order.notes.couponCode) || null,
      farmerSlots: (order.notes && Number(order.notes.farmerSlots)) || null,
      accountType: (order.notes && order.notes.accountType) || null,
      scheduleMode: (order.notes && order.notes.scheduleMode) || "immediate",
    });

    return { success: true };
  } catch (err) {
    console.error("[verifyRazorpayPayment] failed:", err);
    throw new functions.https.HttpsError(
      "internal",
      "Verification mein error: " + err.message
    );
  }
});

exports.razorpayWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  const signature = req.headers["x-razorpay-signature"];

  if (!webhookSecret || !signature) {
    console.error("[razorpayWebhook] missing secret or signature header");
    res.status(400).send("Missing signature");
    return;
  }

  const expectedSignature = crypto
    .createHmac("sha256", webhookSecret)
    .update(req.rawBody)
    .digest("hex");

  if (expectedSignature !== signature) {
    console.error("[razorpayWebhook] signature mismatch — possible spoof attempt");
    res.status(400).send("Invalid signature");
    return;
  }

  const event = req.body && req.body.event;

  if (event !== "payment.captured") {
    res.status(200).send("Event ignored");
    return;
  }

  try {
    const payment = req.body.payload.payment.entity;
    const companyId = payment.notes && payment.notes.companyId;
    const paymentId = payment.id;
    const couponCode = (payment.notes && payment.notes.couponCode) || null;
    const farmerSlots = (payment.notes && Number(payment.notes.farmerSlots)) || null;
    const accountType = (payment.notes && payment.notes.accountType) || null;
    const scheduleMode = (payment.notes && payment.notes.scheduleMode) || "immediate";

    if (!companyId) {
      console.error("[razorpayWebhook] payment has no companyId in notes:", paymentId);
      res.status(200).send("No companyId — ignored");
      return;
    }

    await activateSubscriptionForPayment({
      companyId,
      paymentId,
      couponCode,
      farmerSlots,
      accountType,
      scheduleMode,
    });

    res.status(200).send("OK");
  } catch (err) {
    console.error("[razorpayWebhook] processing failed:", err);
    res.status(500).send("Internal error");
  }
});

async function activateSubscriptionForPayment({
  companyId,
  paymentId,
  couponCode,
  farmerSlots,
  accountType,
  scheduleMode,
}) {
  const db = admin.firestore();

  const dedupeRef = db.collection("processed_razorpay_payments").doc(paymentId);
  const mainDocRef = db
    .collection("companies")
    .doc(companyId)
    .collection("data")
    .doc("main");

  await db.runTransaction(async (tx) => {
    const dedupeSnap = await tx.get(dedupeRef);
    if (dedupeSnap.exists) {
      return;
    }

    const mainSnap = await tx.get(mainDocRef);
    const currentData = mainSnap.exists ? mainSnap.data() : {};
    const now = Date.now();
    const currentExpiryMs = currentData.subscriptionExpiry
      ? currentData.subscriptionExpiry.toMillis()
      : null;
    const currentlyActive =
      currentData.subscriptionStatus === "active" && currentExpiryMs && currentExpiryMs > now;

    if (scheduleMode === "next-cycle" && currentlyActive) {
      // 🛑 NAYA: Current plan abhi bhi valid hai — naya plan turant apply
      // nahi karna, balki current plan expire hone par (getBillingStatus
      // dashboard load ke waqt ye check karega) activate karne ke liye
      // schedule karna hai. Current active plan bilkul untouched rehta hai.
      tx.set(
        mainDocRef,
        {
          scheduledPlan: {
            farmerSlots: farmerSlots || null,
            accountType: accountType || null,
            paymentId,
            purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          lastPaymentId: paymentId,
          lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      // Turant apply — pehli baar subscribe kar rahe ho, plan expire ho
      // chuka hai, ya explicitly "right now" switch choose kiya gaya hai.
      // Ye kisi bhi purane scheduledPlan ko bhi clear kar deta hai, kyunki
      // turant purchase usse supersede kar deta hai.
      const subscriptionUpdate = {
        subscriptionStatus: "active",
        subscriptionStartDate: admin.firestore.Timestamp.fromMillis(now),
        subscriptionExpiry: admin.firestore.Timestamp.fromMillis(now + SUBSCRIPTION_PERIOD_MS),
        lastPaymentId: paymentId,
        lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
        scheduledPlan: admin.firestore.FieldValue.delete(),
      };
      if (farmerSlots) subscriptionUpdate.subscribedFarmerSlots = farmerSlots;
      if (accountType) subscriptionUpdate.accountType = accountType;

      tx.set(mainDocRef, subscriptionUpdate, { merge: true });
    }

    tx.set(dedupeRef, {
      companyId,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (couponCode) {
      const couponRef = db.collection("coupons").doc(couponCode);
      tx.set(
        couponRef,
        { usedCount: admin.firestore.FieldValue.increment(1) },
        { merge: true }
      );
    }
  });
}

/**
 * ============================================================================
 * getBillingStatus — 🛑 NAYA
 * ============================================================================
 * Dashboard load hote hi ye call hota hai. Isका kaam:
 * 1. Check karna ki current plan expire ho chuka hai ya nahi.
 * 2. Agar expire ho chuka hai aur koi scheduledPlan pending hai, to usko
 *    turant activate kar dena (seamlessly — start date wahi hoti hai
 *    jahan purana plan khatam hua tha, taaki koi gap na aaye).
 * 3. Agar expire ho chuka hai aur koi scheduledPlan nahi hai, to status ko
 *    "expired" set kar dena (pehle koi bhi jagah ye set hi nahi hota tha).
 * 4. Current billing state (plan, dates, scheduled plan) client ko wapas
 *    bhej dena, taaki dashboard usse render kar sake.
 */
exports.getBillingStatus = functions.https.onCall(async (data, context) => {
  const companyId = ((data && data.companyId) || "").trim();
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId chahiye.");
  }

  const db = admin.firestore();
  const lookup = await getOwnerLookup(db, companyId);
  assertOwnerAuth(context, lookup);

  const mainDocRef = db
    .collection("companies")
    .doc(companyId)
    .collection("data")
    .doc("main");

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(mainDocRef);
    const docData = snap.exists ? snap.data() : {};
    const now = Date.now();
    const expiryMs = docData.subscriptionExpiry ? docData.subscriptionExpiry.toMillis() : null;

    if (expiryMs !== null && now > expiryMs && docData.scheduledPlan) {
      const sp = docData.scheduledPlan;
      const newStartMs = expiryMs;
      const newExpiryMs = newStartMs + SUBSCRIPTION_PERIOD_MS;

      tx.set(
        mainDocRef,
        {
          subscriptionStatus: "active",
          subscriptionStartDate: admin.firestore.Timestamp.fromMillis(newStartMs),
          subscriptionExpiry: admin.firestore.Timestamp.fromMillis(newExpiryMs),
          subscribedFarmerSlots: sp.farmerSlots,
          accountType: sp.accountType,
          scheduledPlan: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );

      return {
        subscriptionStatus: "active",
        subscriptionStartDateMs: newStartMs,
        subscriptionExpiryMs: newExpiryMs,
        subscribedFarmerSlots: sp.farmerSlots,
        accountType: sp.accountType,
        scheduledPlan: null,
        companyFarmers: docData.companyFarmers || "[]",
      };
    }

    if (expiryMs !== null && now > expiryMs && docData.subscriptionStatus === "active") {
      tx.set(mainDocRef, { subscriptionStatus: "expired" }, { merge: true });

      return {
        subscriptionStatus: "expired",
        subscriptionStartDateMs: docData.subscriptionStartDate
          ? docData.subscriptionStartDate.toMillis()
          : null,
        subscriptionExpiryMs: expiryMs,
        subscribedFarmerSlots: docData.subscribedFarmerSlots || null,
        accountType: docData.accountType || null,
        scheduledPlan: docData.scheduledPlan
          ? {
              farmerSlots: docData.scheduledPlan.farmerSlots,
              accountType: docData.scheduledPlan.accountType,
            }
          : null,
        companyFarmers: docData.companyFarmers || "[]",
      };
    }

    return {
      subscriptionStatus: docData.subscriptionStatus || "trial",
      subscriptionStartDateMs: docData.subscriptionStartDate
        ? docData.subscriptionStartDate.toMillis()
        : null,
      subscriptionExpiryMs: expiryMs,
      subscribedFarmerSlots: docData.subscribedFarmerSlots || null,
      accountType: docData.accountType || null,
      scheduledPlan: docData.scheduledPlan
        ? {
            farmerSlots: docData.scheduledPlan.farmerSlots,
            accountType: docData.scheduledPlan.accountType,
          }
        : null,
      companyFarmers: docData.companyFarmers || "[]",
    };
  });

  return result;
});