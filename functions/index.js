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
 * resolvePhoneLookup — 🛑 NAYA (secure phone_lookup read)
 * ============================================================================
 * Login (Owner/Office Manager/Field Manager/Personal Farmer + Company
 * Farmer number-check) aur Forgot Password — teeno flows ko phone_lookup
 * padhna padta hai LOGIN SE PEHLE hi (taaki authEmail/companyId mil sake).
 * Us waqt user Firebase Auth se signed-in nahi hota, isliye client-side
 * Firestore security rule (jo "allow read: if isSignedIn()" thi) hamesha
 * permission-denied deti thi jab bhi koi fresh login try karta (logout ke
 * baad, naye device par, app reinstall ke baad, waghera).
 *
 * Fix: ab phone_lookup collection client se BILKUL read nahi hoti
 * (firestore.rules mein `allow read: if false`) — sirf ye Cloud Function
 * (Admin SDK use karti hai, jo security rules bypass karta hai) ise padhti
 * hai, aur sirf wahi fields wapas bhejti hai jo login ke liye zaroori hain
 * (poora document expose nahi hota, na hi kisi aur phone ka data leak hota
 * hai — sirf jo phone number specifically pucha gaya hai).
 *
 * Is function ko unauthenticated call karna allowed hai (jaan-boojh kar —
 * login se pehle hi to call hota hai, tab tak koi auth token hota hi nahi).
 */
exports.resolvePhoneLookup = functions.https.onCall(async (data, context) => {
  const rawPhone = ((data && data.phone) || "").toString();
  const phone = rawPhone.replace(/\D/g, "").slice(-10);

  if (!phone || phone.length !== 10) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Sahi 10 digit phone number chahiye."
    );
  }

  const db = admin.firestore();
  const snap = await db.collection("phone_lookup").doc(phone).get();

  if (!snap.exists) {
    return { exists: false };
  }

  const d = snap.data();
  return {
    exists: true,
    companyId: d.companyId || null,
    role: d.role || null,
    authEmail: d.authEmail || null,
    displayName: d.displayName || null,
  };
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
 * 🆕 verifyCompanyIdsExist — coupon ko "specific companies" scope dene se
 * pehle check karta hai ki har Company ID actually Firestore ke
 * "companies" collection mein maujood hai. Isse ek typo wala Company ID
 * silently ek coupon ko hamesha ke liye bekaar nahi bana deta — admin ko
 * turant pata chal jaata hai ki kaunsa ID galat hai.
 */
async function verifyCompanyIdsExist(db, companyIds) {
  if (!companyIds || companyIds.length === 0) return;
  const refs = companyIds.map((id) => db.collection("companies").doc(id));
  const snaps = await db.getAll(...refs);
  const missing = [];
  snaps.forEach((snap, i) => {
    if (!snap.exists) missing.push(companyIds[i]);
  });
  if (missing.length > 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `Ye Company ID(s) nahi mile — check karke dobara try karo: ${missing.join(", ")}`
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

  // 🆕 discountType: "percent" (existing behaviour) ya "flat" (₹ fixed
  // amount off). Backward compatible: agar purana client abhi bhi
  // discountPercent bhejta hai aur discountType nahi bhejta, to use
  // percent maan lete hain.
  const discountType = (data && data.discountType) === "flat" ? "flat" : "percent";
  const discountValue = Number(
    (data && data.discountValue) != null ? data.discountValue : data && data.discountPercent
  );

  const validFromMs = Number(data && data.validFrom);
  const validUntilMs = Number(data && data.validUntil);
  const scope = (data && data.scope) === "specific" ? "specific" : "all";
  const companyIds = Array.isArray(data && data.companyIds)
    ? data.companyIds.map((c) => String(c).trim()).filter(Boolean)
    : [];

  // 🆕 maxUses: optional. null/undefined/0 => unlimited. Agar diya gaya
  // hai to positive integer hona chahiye.
  const maxUsesRaw = data && data.maxUses;
  let maxUses = null;
  if (maxUsesRaw !== null && maxUsesRaw !== undefined && maxUsesRaw !== "") {
    maxUses = Number(maxUsesRaw);
    if (!Number.isFinite(maxUses) || !Number.isInteger(maxUses) || maxUses <= 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Max uses ek positive number hona chahiye (ya khali chhodo unlimited ke liye)."
      );
    }
  }

  // 🆕 onePerCompany: true hone par har company sirf EK baar hi is
  // coupon ko use kar payegi (chahe maxUses global limit abhi baaki ho).
  // Tracking coupons/{code}/usedBy/{companyId} subcollection mein hoti
  // hai, aur wahan entry SIRF successful payment ke baad hi banti hai.
  const onePerCompany = !!(data && data.onePerCompany);

  if (!code || !/^[A-Z0-9_-]{3,30}$/.test(code)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Coupon code 3-30 characters ka hona chahiye (sirf letters/numbers/-/_)."
    );
  }
  if (!Number.isFinite(discountValue) || discountValue <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Discount value 0 se zyada hona chahiye."
    );
  }
  if (discountType === "percent" && discountValue > 100) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Percentage discount 1 se 100 ke beech hona chahiye."
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

  // 🆕 Company IDs ko save karne se pehle Firestore mein verify kar lo —
  // taaki ek typo silently coupon ko kabhi kaam na karne wala na bana de.
  if (scope === "specific") {
    await verifyCompanyIdsExist(db, companyIds);
  }

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
    discountType,
    discountValue,
    // 🛑 discountPercent field ko purane clients/reports ke liye bhi
    // bharke rakhte hain jab type "percent" ho — kisi cheez ko todta nahi.
    discountPercent: discountType === "percent" ? discountValue : null,
    maxUses, // null = unlimited
    onePerCompany,
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

/**
 * 🆕 updateCoupon — admin ko existing coupon ki details (discount,
 * dates, scope, maxUses, onePerCompany) edit karne deta hai, bina use
 * delete karke dobara banaye. Code (doc ID) aur usage history
 * (usedCount, usedBy, createdAt) is se kabhi touch nahi hote — sirf
 * "active/inactive" already alag se setCouponActive se control hota hai,
 * yahan bhi nahi chhedte.
 */
exports.updateCoupon = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const code = ((data && data.code) || "").trim().toUpperCase();
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "Coupon code chahiye.");
  }

  const db = admin.firestore();
  const couponRef = db.collection("coupons").doc(code);
  const existing = await couponRef.get();
  if (!existing.exists) {
    throw new functions.https.HttpsError("not-found", "Ye coupon nahi mila.");
  }

  const discountType = (data && data.discountType) === "flat" ? "flat" : "percent";
  const discountValue = Number(data && data.discountValue);
  const validFromMs = Number(data && data.validFrom);
  const validUntilMs = Number(data && data.validUntil);
  const scope = (data && data.scope) === "specific" ? "specific" : "all";
  const companyIds = Array.isArray(data && data.companyIds)
    ? data.companyIds.map((c) => String(c).trim()).filter(Boolean)
    : [];

  const maxUsesRaw = data && data.maxUses;
  let maxUses = null;
  if (maxUsesRaw !== null && maxUsesRaw !== undefined && maxUsesRaw !== "") {
    maxUses = Number(maxUsesRaw);
    if (!Number.isFinite(maxUses) || !Number.isInteger(maxUses) || maxUses <= 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Max uses ek positive number hona chahiye (ya khali chhodo unlimited ke liye)."
      );
    }
  }
  const onePerCompany = !!(data && data.onePerCompany);

  if (!Number.isFinite(discountValue) || discountValue <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Discount value 0 se zyada hona chahiye."
    );
  }
  if (discountType === "percent" && discountValue > 100) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Percentage discount 1 se 100 ke beech hona chahiye."
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

  // 🆕 Yahan bhi wahi verification — edit karte waqt bhi Company IDs
  // Firestore mein genuinely exist karte hon.
  if (scope === "specific") {
    await verifyCompanyIdsExist(db, companyIds);
  }

  // 🛑 Yahan jaan-boojh kar sirf .update() (poora .set() nahi) use kar
  // rahe hain, taaki usedCount, usedBy, active, createdAt, createdBy
  // jaise fields kabhi accidentally overwrite na ho jaayein.
  await couponRef.update({
    discountType,
    discountValue,
    discountPercent: discountType === "percent" ? discountValue : null,
    maxUses,
    onePerCompany,
    validFrom: admin.firestore.Timestamp.fromMillis(validFromMs),
    validUntil: admin.firestore.Timestamp.fromMillis(validUntilMs),
    scope,
    companyIds: scope === "specific" ? companyIds : [],
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: context.auth.token.email,
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
        discountType: c.discountType || "percent",
        discountValue: c.discountValue != null ? c.discountValue : c.discountPercent,
        maxUses: c.maxUses != null ? c.maxUses : null,
        onePerCompany: !!c.onePerCompany,
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

  const db = admin.firestore();
  const couponRef = db.collection("coupons").doc(code);

  // 🛑 FIX — Firestore subcollections apne aap delete nahi hoti jab
  // parent doc delete hota hai. Pehle sirf coupons/{code} delete hota
  // tha, lekin coupons/{code}/usedBy/{companyId} records pade reh jaate
  // the. Agar admin baad mein wahi code (e.g. FIRSTTIME) dobara ek NAYE
  // coupon ke liye banata, to purane usedBy records ki wajah se un
  // companies ko naye coupon se bhi galat tarike se "already used" bolke
  // block kar diya jaata — jabki unka naye coupon se koi lena-dena nahi
  // hota. Isliye ab usedBy ke saare docs bhi coupon ke saath hi delete
  // karte hain.
  const usedBySnap = await couponRef.collection("usedBy").get();
  if (!usedBySnap.empty) {
    const batch = db.batch();
    usedBySnap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  await couponRef.delete();
  return { success: true };
});

/**
 * 🆕 listCouponUsage — admin ye dekh sake ki konsi companies ne ye
 * coupon (successful payment ke saath) use kiya hai. Data
 * coupons/{code}/usedBy/{companyId} subcollection se aata hai, jo
 * activateSubscriptionForPayment mein hi (payment confirm hone ke baad)
 * banti hai.
 */
exports.listCouponUsage = functions.https.onCall(async (data, context) => {
  assertIsAdmin(context);

  const code = ((data && data.code) || "").trim().toUpperCase();
  if (!code) {
    throw new functions.https.HttpsError("invalid-argument", "Coupon code chahiye.");
  }

  const db = admin.firestore();
  const snap = await db
    .collection("coupons")
    .doc(code)
    .collection("usedBy")
    .orderBy("usedAt", "desc")
    .get();

  return {
    usage: snap.docs.map((d) => {
      const u = d.data();
      return {
        companyId: d.id,
        paymentId: u.paymentId || null,
        usedAtMs: u.usedAt ? u.usedAt.toMillis() : null,
      };
    }),
  };
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
 * 🆕 COUPON GUESS-PROTECTION
 * ============================================================================
 * Bina kisi limit ke koi bhi logged-in Owner baar-baar alag-alag coupon
 * codes try kar sakta tha jab tak kisi valid/active coupon se takra na
 * jaaye — matlab chhote/private coupon codes brute-force kiye ja sakte
 * the. Ab har company ke liye galat coupon tries track hoti hain
 * (coupon_attempts/{companyId} mein), aur bahut zyada galat tries ke
 * baad us company ke liye coupon-apply thodi der ke liye lock ho jaata
 * hai — bilkul waise hi jaise email OTP attempts already limited hain.
 */
const MAX_COUPON_FAILURES = 10;
const COUPON_FAILURE_WINDOW_MS = 30 * 60 * 1000; // 30 minute
const COUPON_LOCKOUT_MS = 30 * 60 * 1000; // 30 minute

async function assertCouponAttemptsNotLocked(attemptsRef) {
  const snap = await attemptsRef.get();
  if (!snap.exists) return;
  const d = snap.data();
  if (d.lockedUntil && d.lockedUntil.toMillis() > Date.now()) {
    const minsLeft = Math.ceil((d.lockedUntil.toMillis() - Date.now()) / 60000);
    throw new functions.https.HttpsError(
      "resource-exhausted",
      `Bahut zyada galat coupon tries ho gaye — ${minsLeft} minute baad dobara try karo.`
    );
  }
}

async function recordCouponAttemptFailure(attemptsRef) {
  const db = admin.firestore();
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(attemptsRef);
    const d = snap.exists ? snap.data() : {};
    const windowStartMs = d.windowStart ? d.windowStart.toMillis() : null;
    const withinWindow = windowStartMs && now - windowStartMs < COUPON_FAILURE_WINDOW_MS;
    const newCount = withinWindow ? (d.failCount || 0) + 1 : 1;

    const update = {
      failCount: newCount,
      windowStart: withinWindow
        ? d.windowStart
        : admin.firestore.Timestamp.fromMillis(now),
    };

    if (newCount >= MAX_COUPON_FAILURES) {
      update.lockedUntil = admin.firestore.Timestamp.fromMillis(now + COUPON_LOCKOUT_MS);
      update.failCount = 0;
      update.windowStart = admin.firestore.FieldValue.delete();
    }

    tx.set(attemptsRef, update, { merge: true });
  });
}

async function resetCouponAttempts(attemptsRef) {
  await attemptsRef.set(
    {
      failCount: 0,
      windowStart: admin.firestore.FieldValue.delete(),
      lockedUntil: admin.firestore.FieldValue.delete(),
    },
    { merge: true }
  );
}

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

/**
 * 🆕 computeCouponDiscount — ek jagah se coupon ki validity + limit
 * check karta hai aur discount amount (rupees mein) nikalta hai, chahe
 * coupon percent-based ho ya flat ₹ amount based.
 *
 * IMPORTANT: yahan sirf coupon "apply/preview" hota hai — usedCount
 * yahan kabhi nahi badhta. usedCount sirf activateSubscriptionForPayment
 * mein, payment confirm hone ke baad hi badhta hai. Isliye order banate
 * waqt (ya payment cancel/fail hone par) coupon ki limit kabhi consume
 * nahi hoti — sirf successful subscription hi usse consume karti hai.
 */
function computeCouponDiscount(coupon, amountInRupees, companyId) {
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
  // 🆕 Max-uses check. usedCount sirf confirmed/successful subscriptions
  // se badhta hai (dekho activateSubscriptionForPayment), isliye ye check
  // kabhi kisi genuine baar-baar-try-kar-raha user ko galat tarike se
  // block nahi karega — sirf tab block karega jab coupon vaastav mein
  // apni limit tak use ho chuka ho.
  if (coupon.maxUses != null && (coupon.usedCount || 0) >= coupon.maxUses) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Ye coupon apni use-limit tak pahunch chuka hai."
    );
  }

  const discountType = coupon.discountType || "percent";
  const discountValue = coupon.discountValue != null ? coupon.discountValue : coupon.discountPercent;

  let discountedAmount;
  if (discountType === "flat") {
    discountedAmount = Math.max(amountInRupees - discountValue, 1);
  } else {
    const discountAmount = Math.round((amountInRupees * discountValue) / 100);
    discountedAmount = Math.max(amountInRupees - discountAmount, 1);
  }

  return {
    amountInRupees: discountedAmount,
    appliedCoupon: { code: coupon.code, discountType, discountValue },
  };
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
    // 🆕 Coupon try karne se pehle check karo ki is company ne bahut
    // zyada galat coupon codes to nahi try kar liye (guess/brute-force
    // protection). Genuine users kabhi 10 baar galat coupon nahi
    // dalte — isliye ye kisi normal use-case ko affect nahi karega.
    const couponAttemptsRef = db.collection("coupon_attempts").doc(companyId);
    await assertCouponAttemptsNotLocked(couponAttemptsRef);

    try {
      const couponSnap = await db.collection("coupons").doc(couponCode).get();
      if (!couponSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Ye coupon code valid nahi hai.");
      }
      const coupon = couponSnap.data();

      // 🆕 onePerCompany check — is company ne pehle kabhi is coupon se
      // successful subscription li hai ya nahi (usedBy subcollection mein
      // sirf tabhi entry banti hai jab payment confirm ho chuka ho — dekho
      // activateSubscriptionForPayment). Isliye ye check bilkul reliable
      // hai: cancel/failed attempts kabhi is subcollection mein nahi aate.
      if (coupon.onePerCompany) {
        const usedByDoc = await db
          .collection("coupons")
          .doc(couponCode)
          .collection("usedBy")
          .doc(companyId)
          .get();
        if (usedByDoc.exists) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Ye coupon aapki company pehle hi use kar chuki hai."
          );
        }
      }

      // 🆕 sab validity + max-uses + percent/flat discount logic ek hi
      // shared helper mein — koi usedCount yahan nahi badhta, sirf preview.
      const result = computeCouponDiscount(coupon, amountInRupees, companyId);
      amountInRupees = result.amountInRupees;
      appliedCoupon = result.appliedCoupon;

      // Coupon genuinely valid nikla — is company ke purane galat
      // attempts (agar the) clear kar do.
      await resetCouponAttempts(couponAttemptsRef);
    } catch (err) {
      // Har HttpsError ka matlab hai coupon invalid/expired/wrong-scope/
      // already-used tha — isse ek "galat try" gina jaata hai. Doosri
      // (unexpected/internal) errors ko is counter mein nahi ginte.
      if (err instanceof functions.https.HttpsError) {
        await recordCouponAttemptFailure(couponAttemptsRef);
      }
      throw err;
    }
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

  if (event === "payment.captured") {
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
    return;
  }

  // 🆕 REFUND / CHARGEBACK HANDLING
  // ==========================================================================
  // Pehle koi refund/chargeback handle hi nahi hota tha — agar Razorpay se
  // paisa wapas chala jaata (chahe manual refund ho ya dispute/chargeback),
  // to company ka subscription active hi rehta tha aur coupon "used" hi
  // maana jaata rehta. Ab "refund.processed" event par: agar ye FULL refund
  // hai aur ye wahi payment hai jisne abhi company ka current plan diya
  // tha, to access wapas le lete hain aur agar coupon use hua tha to uska
  // usage bhi revert kar dete hain (taaki company use dobara legitimately
  // use kar sake). PARTIAL refund par koi automatic action nahi lete —
  // wo shayad ek chhota adjustment ho, poori subscription cancel karna
  // theek nahi hoga — sirf log hota hai taaki admin manually dekh sake.
  if (event === "refund.processed") {
    try {
      await handleRazorpayRefund(req.body.payload);
      res.status(200).send("OK");
    } catch (err) {
      console.error("[razorpayWebhook] refund handling failed:", err);
      res.status(500).send("Internal error");
    }
    return;
  }

  res.status(200).send("Event ignored");
});

/**
 * 🆕 handleRazorpayRefund — Razorpay se aaya hua "refund.processed" event
 * process karta hai. Idempotent hai (processed_razorpay_refunds collection
 * se dedupe) — Razorpay retries bhejta hai to duplicate processing nahi
 * hogi.
 */
async function handleRazorpayRefund(payload) {
  const paymentEntity = payload && payload.payment && payload.payment.entity;
  const refundEntity = payload && payload.refund && payload.refund.entity;

  if (!paymentEntity || !refundEntity) {
    console.error("[handleRazorpayRefund] payload mein payment/refund entity missing hai — ignore.");
    return;
  }

  const paymentId = paymentEntity.id;
  const refundId = refundEntity.id;
  const companyId = paymentEntity.notes && paymentEntity.notes.companyId;
  const couponCode = (paymentEntity.notes && paymentEntity.notes.couponCode) || null;

  if (!companyId) {
    console.error("[handleRazorpayRefund] payment mein companyId nahi mila:", paymentId);
    return;
  }

  // Partial refund — poora paisa wapas nahi gaya, isliye subscription
  // cancel karna zyada aggressive hoga. Sirf log karke chhod dete hain.
  const isFullRefund = Number(refundEntity.amount) >= Number(paymentEntity.amount);
  if (!isFullRefund) {
    console.warn(
      `[handleRazorpayRefund] partial refund (${refundEntity.amount}/${paymentEntity.amount}) for payment ${paymentId} — no automatic action, review manually.`
    );
    return;
  }

  const db = admin.firestore();
  const refundDedupeRef = db.collection("processed_razorpay_refunds").doc(refundId);
  const mainDocRef = db.collection("companies").doc(companyId).collection("data").doc("main");
  const couponRef = couponCode ? db.collection("coupons").doc(couponCode) : null;
  const couponUsedByRef = couponRef ? couponRef.collection("usedBy").doc(companyId) : null;

  await db.runTransaction(async (tx) => {
    const dedupeSnap = await tx.get(refundDedupeRef);
    if (dedupeSnap.exists) {
      return; // ye refund pehle hi process ho chuka hai
    }

    const mainSnap = await tx.get(mainDocRef);
    const couponSnap = couponRef ? await tx.get(couponRef) : null;
    const couponUsedBySnap = couponUsedByRef ? await tx.get(couponUsedByRef) : null;
    const mainData = mainSnap.exists ? mainSnap.data() : {};

    // Agar ye refund wale payment ne hi company ka current CHALTA HUA
    // plan diya tha (koi naya legitimate payment ise supersede nahi kar
    // chuka), to access wapas le lo. Agar beech mein koi naya valid
    // payment ho chuka hai (lastPaymentId ab match nahi karta), to us
    // naye payment ke access ko chhedte nahi — sirf ye purana refund hai.
    if (mainData.lastPaymentId === paymentId) {
      tx.set(
        mainDocRef,
        {
          subscriptionStatus: "expired",
          subscriptionExpiry: admin.firestore.Timestamp.fromMillis(Date.now()),
          refundedPaymentId: paymentId,
          refundedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // Agar ye payment kisi pending "next-cycle" scheduled plan ke liye
    // tha (abhi tak activate nahi hua tha), use bhi cancel kar do.
    if (mainData.scheduledPlan && mainData.scheduledPlan.paymentId === paymentId) {
      tx.set(mainDocRef, { scheduledPlan: admin.firestore.FieldValue.delete() }, { merge: true });
    }

    // Coupon usage revert — is refund ki wajah se ye ek "genuine" use
    // nahi raha, isliye usedCount wapas kam karo. usedBy record sirf
    // tabhi delete karte hain jab wo record isi paymentId ka ho (agar
    // isi company ne baad mein isi coupon ka koi doosra valid use kiya
    // hai, to wo record touch nahi hota).
    if (couponRef && couponSnap && couponSnap.exists) {
      const currentUsedCount = couponSnap.data().usedCount || 0;
      if (currentUsedCount > 0) {
        tx.set(couponRef, { usedCount: admin.firestore.FieldValue.increment(-1) }, { merge: true });
      }
      if (
        couponUsedBySnap &&
        couponUsedBySnap.exists &&
        couponUsedBySnap.data().paymentId === paymentId
      ) {
        tx.delete(couponUsedByRef);
      }
    }

    tx.set(refundDedupeRef, {
      companyId,
      paymentId,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  console.log(
    `[handleRazorpayRefund] refund ${refundId} for payment ${paymentId} (company ${companyId}) processed.`
  );
}

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
  const couponRef = couponCode ? db.collection("coupons").doc(couponCode) : null;
  const couponUsedByRef =
    couponCode ? couponRef.collection("usedBy").doc(companyId) : null;

  await db.runTransaction(async (tx) => {
    // 🛑 Firestore transactions require ALL reads before ANY writes —
    // isliye coupon doc bhi yahin, dusre reads ke saath hi, upar hi
    // padh lete hain (usedCount +1 sirf yahi, payment confirm hone ke
    // baad hota hai — order create/coupon-apply time par kabhi nahi).
    const dedupeSnap = await tx.get(dedupeRef);
    if (dedupeSnap.exists) {
      return;
    }

    const mainSnap = await tx.get(mainDocRef);
    const couponSnap = couponRef ? await tx.get(couponRef) : null;
    const couponUsedBySnap = couponUsedByRef ? await tx.get(couponUsedByRef) : null;

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
        // 🛑 NAYA — naya payment aa gaya, matlab account phir se active ho
        // gaya. Purana "expiry email bhej di gayi thi" wala flag clear
        // karo, taaki agli baar jab ye plan bhi expire ho, naya email
        // dobara ja sake (warna sirf pehli baar hi email jaati rehti).
        expiryEmailSentAt: admin.firestore.FieldValue.delete(),
      };
      if (farmerSlots) subscriptionUpdate.subscribedFarmerSlots = farmerSlots;
      if (accountType) subscriptionUpdate.accountType = accountType;

      tx.set(mainDocRef, subscriptionUpdate, { merge: true });
    }

    tx.set(dedupeRef, {
      companyId,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 🆕 usedCount sirf tabhi badhta hai jab payment yahan tak pahuncha
    // hai — matlab subscription genuinely confirm ho chuki hai. Coupon
    // apply/preview karte waqt (createRazorpayOrder) ye kabhi nahi badhta,
    // isliye cancel/failed/retry attempts kabhi limit consume nahi karte.
    if (couponRef && couponSnap && couponSnap.exists) {
      const coupon = couponSnap.data();
      const atLimit = coupon.maxUses != null && (coupon.usedCount || 0) >= coupon.maxUses;
      // 🆕 onePerCompany: agar is company ka usedBy record pehle se
      // maujood hai, to iska matlab ye company is coupon ko pehle hi
      // (kisi successful payment mein) use kar chuki hai. Ye almost
      // kabhi nahi hoga (createRazorpayOrder mein pehle hi check hota
      // hai), lekin agar do checkouts race karke yahan tak pahunch bhi
      // jayein, to yahan bhi doubly-protected hai.
      const alreadyUsedByCompany = !!(coupon.onePerCompany && couponUsedBySnap && couponUsedBySnap.exists);

      if (!atLimit && !alreadyUsedByCompany) {
        tx.set(
          couponRef,
          { usedCount: admin.firestore.FieldValue.increment(1) },
          { merge: true }
        );
        if (couponUsedByRef) {
          tx.set(couponUsedByRef, {
            paymentId,
            usedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      } else {
        // Edge case: do parallel checkouts ne almost saath-saath is
        // coupon ka last hi slot use kar liya (ya isi company ne race
        // condition mein dobara try kiya). Payment already ho chuka hai
        // (paisa le liya gaya), isliye subscription normally activate
        // hogi — sirf coupon usage dobara record nahi hoga.
        console.warn(
          `[activateSubscriptionForPayment] coupon ${couponCode} not incremented for company ${companyId} (atLimit=${atLimit}, alreadyUsedByCompany=${alreadyUsedByCompany}, payment ${paymentId}).`
        );
      }
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
          // 🛑 NAYA — naya plan seamlessly activate ho gaya, isliye purana
          // expiry-email flag bhi clear karo (defensive — normally ye
          // scenario checkExpiredSubscriptions khud hi pehle handle kar
          // lega, lekin agar Owner ne dashboard pehle khol liya to bhi
          // consistent rahe).
          expiryEmailSentAt: admin.firestore.FieldValue.delete(),
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

/**
 * ============================================================================
 * checkExpiredSubscriptions — 🛑 NAYA
 * ============================================================================
 * Har 6 ghante mein automatically chalta hai (Cloud Scheduler). Iska kaam:
 * 1. Aise companies dhoondhna jinka TRIAL khatam ho chuka hai (koi payment
 *    nahi hui) ya PAID plan khatam ho chuka hai (koi scheduled next-plan
 *    nahi hai).
 * 2. Unka subscriptionStatus 'expired' set karna.
 * 3. Owner ko ek email bhejna (sirf ek baar — dobara subscribe karke phir
 *    se expire hone tak dobara nahi jaayegi) jisme website ka login link
 *    ho, taaki wo turant subscription renew kar sake.
 *
 * NOTE — jin companies ka scheduledPlan pending hai (Owner ne "next-cycle"
 * wala switch choose kiya tha), unke liye ye function seamlessly naya plan
 * activate kar dega — email NAHI jaayegi, kyunki access mein koi break hi
 * nahi aaya.
 */
async function getCompanyOwnerContactInfo(db, companyId) {
  const lookupSnap = await db
    .collection("phone_lookup")
    .where("companyId", "==", companyId)
    .where("role", "==", "Owner")
    .limit(1)
    .get();

  const authEmail = lookupSnap.empty ? null : lookupSnap.docs[0].data().authEmail;
  if (!authEmail) return null;

  const profileSnap = await db.collection("companies").doc(companyId).get();
  const companyName = profileSnap.exists
    ? profileSnap.data().companyName || "aapki company"
    : "aapki company";
  const ownerName = profileSnap.exists ? profileSnap.data().ownerName || "" : "";

  return { authEmail, companyName, ownerName };
}

async function sendExpiryNotificationEmail({ authEmail, companyName, ownerName }) {
  const loginUrl = "https://trackoapp.in/login.html";
  const greeting = ownerName ? `Namaste ${ownerName},` : "Namaste,";

  try {
    const transporter = getMailTransporter();
    await transporter.sendMail({
      from: `"Tracko" <${process.env.GMAIL_USER}>`,
      to: authEmail,
      subject: `Tracko — ${companyName} ka account access limited ho gaya hai`,
      text: `${greeting}\n\n"${companyName}" ka Tracko subscription/trial khatam ho gaya hai, isliye account access abhi limited hai.\n\nDobara access paane ke liye is link se login karke subscription renew karein:\n${loginUrl}\n\nAgar koi sawal ho to humein contact karein.`,
      html: `<div style="font-family:sans-serif;">
        <p>${greeting}</p>
        <p><b>"${companyName}"</b> ka Tracko subscription/trial khatam ho gaya hai, isliye account access abhi limited hai.</p>
        <p>Dobara access paane ke liye neeche diye button se login karke subscription renew karein:</p>
        <p style="margin:24px 0;">
          <a href="${loginUrl}" style="background:#1B5E20;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:bold;display:inline-block;">
            Login &amp; Renew Karo
          </a>
        </p>
        <p style="color:#888;font-size:12px;">Agar button kaam na kare, to ye link browser mein khol lein: ${loginUrl}</p>
      </div>`,
    });
    return true;
  } catch (err) {
    console.error("[sendExpiryNotificationEmail] failed:", err);
    return false;
  }
}

/**
 * Ek data/main doc ke liye: agar genuinely expired hai (aur koi scheduled
 * plan continuation nahi hai), status 'expired' set karta hai aur decide
 * karta hai ki email bhejni hai ya nahi (transaction ke andar hi decide
 * hota hai, taaki concurrent runs mein duplicate na ho).
 */
async function expireAndMaybeNotify(dataDocRef, nowMs) {
  const db = admin.firestore();

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(dataDocRef);
    if (!snap.exists) return "none";
    const data = snap.data();

    const expiryMs = data.subscriptionExpiry ? data.subscriptionExpiry.toMillis() : null;
    const trialExpiryMs = data.trialExpiry ? Date.parse(data.trialExpiry) : null;

    const stillExpiredActive =
      data.subscriptionStatus === "active" && expiryMs !== null && expiryMs < nowMs;
    const stillExpiredTrial =
      data.subscriptionStatus === "trial" && trialExpiryMs !== null && trialExpiryMs < nowMs;

    if (!stillExpiredActive && !stillExpiredTrial) {
      return "none"; // pehle se hi kisi aur tareeke se handle ho chuka
    }

    if (stillExpiredActive && data.scheduledPlan) {
      // Scheduled next-plan seamlessly activate ho jayega — koi
      // interruption nahi, isliye email ki zaroorat nahi.
      const sp = data.scheduledPlan;
      const newStartMs = expiryMs;
      const newExpiryMs = newStartMs + SUBSCRIPTION_PERIOD_MS;
      tx.set(
        dataDocRef,
        {
          subscriptionStatus: "active",
          subscriptionStartDate: admin.firestore.Timestamp.fromMillis(newStartMs),
          subscriptionExpiry: admin.firestore.Timestamp.fromMillis(newExpiryMs),
          subscribedFarmerSlots: sp.farmerSlots,
          accountType: sp.accountType,
          scheduledPlan: admin.firestore.FieldValue.delete(),
          expiryEmailSentAt: admin.firestore.FieldValue.delete(),
        },
        { merge: true }
      );
      return "scheduled_applied";
    }

    // 🛑 FIX — pehle yahan 'expiryEmailSentAt' isi transaction mein set
    // ho jata tha, chahe email baad mein actually bheji jaaye ya nahi.
    // Agar bhejne mein koi transient error aata (network, Gmail quota),
    // to flag phir bhi set reh jaata aur function kabhi dobara try nahi
    // karta — Owner ko silently email kabhi milti hi nahi. Ab flag SIRF
    // status set karta hai; 'expiryEmailSentAt' caller mein tabhi likhi
    // jaayegi jab email successfully bhej di jaaye (neeche dekho).
    const alreadyNotified = !!data.expiryEmailSentAt;
    tx.set(dataDocRef, { subscriptionStatus: "expired" }, { merge: true });

    return alreadyNotified ? "already_notified" : "needs_email";
  });

  return outcome === "needs_email";
}

exports.checkExpiredSubscriptions = functions.pubsub
  .schedule("every 6 hours")
  .onRun(async () => {
    const db = admin.firestore();
    const nowMs = Date.now();
    const nowIso = new Date(nowMs).toISOString();

    const results = [];

    // 1) TRIAL companies jinki trialExpiry nikal chuki hai
    try {
      const trialSnap = await db
        .collectionGroup("data")
        .where("subscriptionStatus", "==", "trial")
        .where("trialExpiry", "<", nowIso)
        .get();
      trialSnap.forEach((doc) => results.push(doc.ref));
    } catch (err) {
      console.error("[checkExpiredSubscriptions] trial query failed:", err);
    }

    // 2) ACTIVE (paid) companies jinki subscriptionExpiry nikal chuki hai
    try {
      const activeSnap = await db
        .collectionGroup("data")
        .where("subscriptionStatus", "==", "active")
        .where("subscriptionExpiry", "<", admin.firestore.Timestamp.fromMillis(nowMs))
        .get();
      activeSnap.forEach((doc) => results.push(doc.ref));
    } catch (err) {
      console.error("[checkExpiredSubscriptions] active query failed:", err);
    }

    console.log(`[checkExpiredSubscriptions] ${results.length} candidate(s) found.`);

    for (const dataDocRef of results) {
      try {
        const shouldSendEmail = await expireAndMaybeNotify(dataDocRef, nowMs);
        if (!shouldSendEmail) continue;

        const companyId = dataDocRef.parent.parent.id;
        const contact = await getCompanyOwnerContactInfo(db, companyId);
        if (!contact) {
          console.error(`[checkExpiredSubscriptions] no Owner email found for ${companyId}`);
          continue;
        }

        const sent = await sendExpiryNotificationEmail(contact);
        if (sent) {
          // 🛑 FIX — flag ab sirf successful send ke baad likhi jaati hai.
          // Agar send fail ho jaaye, flag set nahi hogi, isliye agla
          // scheduled run (6 ghante baad) dobara try karega.
          await dataDocRef.set(
            { expiryEmailSentAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
          );
        }
        console.log(
          `[checkExpiredSubscriptions] company ${companyId}: email ${sent ? "sent" : "failed — will retry next run"}.`
        );
      } catch (err) {
        console.error(`[checkExpiredSubscriptions] failed for ${dataDocRef.path}:`, err);
      }
    }
  });