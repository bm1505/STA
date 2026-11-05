const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');
const nodemailer = require('nodemailer');

admin.initializeApp();

// Email Transporter (Sanidi hii kwa email yako ya kampuni/Gmail)
// Kwa Gmail: Unahitaji kutumia "App Password" ikiwa una 2FA
const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: 'barakamahega05@gmail.com', // Badilisha na email yako
        pass: process.env.SMTP_PASSWORD
    }
});

/**
 * 1. sendOtpEmail
 * Inazalisha OTP, inahifadhi Firestore, na kutuma email.
 */
exports.sendOtpEmail = functions.https.onCall(async (data, context) => {
    const email = data.email;
    if (!email) {
        throw new functions.https.HttpsError('invalid-argument', 'Email is required');
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    try {
        // Hifadhi OTP kwenye Firestore (Iishe muda baada ya dk 10)
        await admin.firestore().collection('otp_codes').doc(email).set({
            otp: otp,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: Date.now() + (10 * 60 * 1000) // Dk 10
        });

        // Tuma Email
        const mailOptions = {
            from: '"STA Ride" <no-reply@sta.com>',
            to: email,
            subject: 'Namba yako ya Siri (OTP) - STA Registration',
            text: `Namba yako ya siri ya uhakiki ni: ${otp}. Itatumika kwa dakika 10.`,
            html: `<h3>Karibu STA Ride</h3><p>Namba yako ya siri ya uhakiki ni:</p><h1 style="color: #FFD700;">${otp}</h1><p>Itatumika kwa dakika 10 pekee.</p>`
        };

        await transporter.sendMail(mailOptions);
        console.log(`OTP sent to ${email}`);
        return { success: true };

    } catch (error) {
        console.error('Error sending OTP:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

/**
 * 2. verifyOtp
 * Inahakiki kama OTP iliyoingizwa ni sahihi.
 */
exports.verifyOtp = functions.https.onCall(async (data, context) => {
    const email = data.email;
    const enteredOtp = data.otp;

    if (!email || !enteredOtp) {
        throw new functions.https.HttpsError('invalid-argument', 'Email and OTP are required');
    }

    try {
        const doc = await admin.firestore().collection('otp_codes').doc(email).get();

        if (!doc.exists) {
            return { success: false, message: 'OTP not found' };
        }

        const otpData = doc.data();

        // Angalia kama imekwisha muda
        if (Date.now() > otpData.expiresAt) {
            await doc.ref.delete();
            return { success: false, message: 'OTP expired' };
        }

        if (otpData.otp === enteredOtp) {
            // Futa OTP baada ya kutumika
            await doc.ref.delete();
            return { success: true };
        } else {
            return { success: false, message: 'Incorrect OTP' };
        }

    } catch (error) {
        console.error('Error verifying OTP:', error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// Configuration for M-Pesa (Sandbox)
// In production, these should be moved to environment variables (functions.config())
const MPESA_CONFIG = {
    consumerKey: process.env.MPESA_CONSUMER_KEY,
    consumerSecret: process.env.MPESA_CONSUMER_SECRET,
    shortCode: process.env.MPESA_SHORT_CODE,
    passkey: process.env.MPESA_PASSKEY,
    region: 'us-west4' // Optimized for Safaricom latency
};

/**
 * 1. Process M-Pesa Payment (STK Push)
 * Triggered when a new document is created in the 'payments' collection.
 */
exports.processMpesaPayment = functions.region(MPESA_CONFIG.region).firestore
    .document('payments/{paymentId}')
    .onCreate(async (snapshot, context) => {
        const paymentData = snapshot.data();

        // Skip if already processed or not pending
        if (paymentData.status !== 'pending') return null;

        try {
            // Get Access Token
            const auth = Buffer.from(`${MPESA_CONFIG.consumerKey}:${MPESA_CONFIG.consumerSecret}`).toString('base64');
            const tokenRes = await axios.get('https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials', {
                headers: { Authorization: `Basic ${auth}` }
            });
            const accessToken = tokenRes.data.access_token;

            const timestamp = new Date().toISOString().replace(/[^0-9]/g, '').slice(0, 14);
            const password = Buffer.from(`${MPESA_CONFIG.shortCode}${MPESA_CONFIG.passkey}${timestamp}`).toString('base64');

            // Format phone number (Ensure it starts with 254 for Sandbox)
            let phone = paymentData.phoneNumber.toString().replace(/\+/g, '');
            if (phone.startsWith('0')) {
                phone = '254' + phone.slice(1);
            } else if (phone.startsWith('7') || phone.startsWith('1')) {
                phone = '254' + phone;
            }

            // Initiate STK Push
            const stkResponse = await axios.post('https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest', {
                BusinessShortCode: MPESA_CONFIG.shortCode,
                Password: password,
                Timestamp: timestamp,
                TransactionType: 'CustomerPayBillOnline',
                Amount: Math.round(paymentData.amount),
                PartyA: phone,
                PartyB: MPESA_CONFIG.shortCode,
                PhoneNumber: phone,
                // Callback URL points to our mpesaCallback function in the same region
                CallBackURL: `https://${MPESA_CONFIG.region}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/mpesaCallback`,
                AccountReference: paymentData.rideId || 'STA_TOPUP',
                TransactionDesc: 'STA Ride Payment'
            }, {
                headers: { Authorization: `Bearer ${accessToken}` }
            });

            return snapshot.ref.update({
                checkoutRequestId: stkResponse.data.CheckoutRequestID,
                status: 'stk_sent',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (error) {
            console.error('M-Pesa STK Push Error:', error.response ? error.response.data : error.message);
            return snapshot.ref.update({
                status: 'failed',
                error: error.message,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }
    });

/**
 * 2. M-Pesa Callback Handler
 * Receives the result of the STK Push from Safaricom.
 */
exports.mpesaCallback = functions.region(MPESA_CONFIG.region).https.onRequest(async (req, res) => {
    try {
        const callbackData = req.body.Body.stkCallback;
        const checkoutRequestId = callbackData.CheckoutRequestID;
        const resultCode = callbackData.ResultCode;

        console.log(`Received callback for ${checkoutRequestId} with ResultCode ${resultCode}`);

        // Find the payment document
        const paymentQuery = await admin.firestore().collection('payments')
            .where('checkoutRequestId', '==', checkoutRequestId)
            .limit(1)
            .get();

        if (paymentQuery.empty) {
            console.error('Payment document not found for request ID:', checkoutRequestId);
            return res.status(404).send('Payment not found');
        }

        const paymentDoc = paymentQuery.docs[0];
        const data = paymentDoc.data();
        const userId = data.userId;
        const amount = data.amount;
        const userRole = data.userRole || 'rider';

        if (resultCode === 0) {
            // Success! Update payment status and user balance
            const batch = admin.firestore().batch();

            batch.update(paymentDoc.ref, {
                status: 'completed',
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            const collectionName = (userRole === 'driver') ? 'drivers' : 'riders';
            const userRef = admin.firestore().collection(collectionName).doc(userId);

            batch.update(userRef, {
                walletBalance: admin.firestore.FieldValue.increment(amount)
            });

            await batch.commit();
            console.log(`Successfully processed payment. Added ${amount} to ${collectionName}/${userId}`);
        } else {
            // Failed or Cancelled
            await paymentDoc.ref.update({
                status: 'failed',
                resultCode: resultCode,
                errorMessage: callbackData.ResultDesc,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`Payment failed for ${checkoutRequestId}: ${callbackData.ResultDesc}`);
        }

        res.status(200).send('Success');
    } catch (error) {
        console.error('Callback processing error:', error);
        res.status(500).send('Internal Error');
    }
});

/**
 * Simple Health Check
 */
exports.healthCheck = functions.region(MPESA_CONFIG.region).https.onRequest((req, res) => {
    res.send("STA Serverless Backend is healthy and running on " + MPESA_CONFIG.region);
});
