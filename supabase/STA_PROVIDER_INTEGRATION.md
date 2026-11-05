# STA Provider Integration — Supabase Architecture

This document records the required production architecture for payment, messaging, email, authentication, realtime and file storage. It is intentionally explicit about what is and is not active.

## Fixed provider decisions

| Capability | Required provider |
|---|---|
| Payment collection and payouts | AzamPay |
| SMS | SwalaSMS |
| Transactional email | Resend |
| Database | Supabase PostgreSQL |
| Authentication | Supabase Auth |
| File storage | Supabase Storage |
| Realtime | Supabase Realtime |
| Server-side integration/runtime | Supabase Edge Functions |

Do not add or substitute another provider without an explicit product decision.

## Security boundaries

- All AzamPay, SwalaSMS and Resend credentials must be stored as Supabase Function secrets or configured in the Supabase Auth SMTP settings. Never place credentials in Flutter, public app configuration, source files, or client logs.
- Flutter must call authenticated Supabase Edge Functions for provider operations. Never call payment or SMS provider APIs directly from the app.
- Validate the authenticated Supabase user and authorize the requested action on the server before initiating a provider operation.
- A payment is not successful because checkout initiation returned successfully or because the client returned from a checkout page. Only a verified provider confirmation may transition a payment to paid.
- Payment callbacks must be verified using the exact signature/authentication mechanism specified by AzamPay. Reject invalid callbacks. Make callback processing idempotent using the provider transaction reference and the internal payment ID.
- Never accept amount, currency, owner, or payment status from a callback without matching it to the server-created pending payment record.
- SMS/email delivery requests must have a stable internal request ID, persist provider message IDs and delivery state, and use bounded retry with duplicate protection.
- Verify SwalaSMS webhook signatures using its documented signing scheme before changing delivery state.
- Use Supabase Auth for identity and session validation. Do not create a parallel password or session store.
- Keep private documents in private Supabase Storage buckets. Authorize upload/download through RLS/storage policies and issue short-lived signed URLs only after authorization. Do not expose private driver identity documents through public object URLs.
- Keep sensitive payment data to the minimum required for reconciliation. Never store PINs, OTPs, card security codes, or mobile-money credentials.

## Required Edge Function boundaries

### AzamPay
- Authenticated payment-initiation endpoint: accept an internal payment request ID, load the pending payment and amount from PostgreSQL, validate ownership and state, then initiate the appropriate AzamPay checkout.
- Provider callback endpoint: validate AzamPay authenticity, reconcile the provider reference against the pending payment, and perform an atomic/idempotent status transition.
- Payment-status endpoint: return only the caller-authorized payment state.
- Payout endpoint: administrator/authorized server-side action only; enforce role and balance/ledger rules.
- Store provider references and sanitized status metadata; never trust client-supplied payment success.

### SwalaSMS
- Authenticated/authorized send endpoint for OTP-independent operational SMS, alerts and receipts.
- Normalize Tanzanian phone numbers before sending; validate sender ID against the configured approved sender ID.
- Persist request status and provider message ID. Handle provider rate limits and transient errors with bounded retries.
- Signed delivery webhook updates delivery status only after signature verification.
- Do not bypass Supabase Auth email/phone OTP verification or weaken the existing trusted-device authentication rules.

### Resend
- Configure Resend as the SMTP provider for Supabase Auth where supported, so Supabase Auth continues to own OTP generation, expiry, verification and session issuance.
- Configure the verified sender/domain and SMTP credentials in Supabase Auth settings, not Flutter.
- Use a server-side Resend Edge Function only for application transactional email that is not an Auth OTP. Add idempotency keys and delivery event handling for these messages.
- Do not generate or verify login OTPs independently in Flutter or a custom email function.

## Supabase Storage
- Audit every existing bucket and all upload/download call sites before changing bucket visibility.
- Driver identity, license, insurance and vehicle verification documents must be private.
- Store stable object paths in PostgreSQL/profile metadata, not expiring signed URLs.
- Generate signed URLs after checking the caller's relationship to the document (owner, assigned reviewer, or authorized administrator).
- Keep public access only for assets that are intentionally public, such as approved public profile/vehicle images, and only after a separate explicit policy decision.

## Firebase removal
Firebase removal is not complete until all of the following are verified:
- No Firebase packages remain in Flutter dependencies or lockfiles.
- No Firebase initialization, options, generated configuration, platform plist/json files, Gradle plugins, or Android/iOS service wiring remain where unused.
- No Firestore, Realtime Database, Firebase Storage, Firebase Auth, FCM, Analytics, Crashlytics or Firebase Messaging runtime references remain.
- All required data and workflows have a working Supabase equivalent before each Firebase dependency is removed.
- Existing Supabase Auth sessions, role checks, RLS, realtime subscriptions and local notifications continue to work.
- Remove only Firebase-specific artifacts; do not remove unrelated local notifications, permissions, shared preferences or other platform services.

## Deployment secrets and configuration

Configure secrets in the intended Supabase project, never in this repository:

- `AZAMPAY_CLIENT_ID`
- `AZAMPAY_CLIENT_SECRET`
- `AZAMPAY_APP_NAME`
- `AZAMPAY_ENVIRONMENT` (sandbox until verified, then production)
- `SWALASMS_API_KEY`
- `SWALASMS_SENDER_ID`
- `RESEND_API_KEY` (only if application transactional mail is sent directly by an Edge Function)

Use the exact endpoint, token flow, payload schema, callback verification, and webhook signing rules from each provider's current official merchant documentation. Do not infer production endpoints or callback signatures from third-party SDKs or examples.

Supabase Auth SMTP is configured separately in the Supabase Dashboard using Resend's SMTP credentials and the verified sending domain.

## Current implementation status (verified during this change)

- Supabase Auth is already used by the Flutter authentication provider.
- Payment requests are currently recorded as pending through the `sta_create_payment_request` RPC. No AzamPay checkout is initiated yet.
- The Flutter payment service currently does not prove provider settlement; pending must remain pending until a verified provider callback.
- Current notification service presents local device notifications. It is not a SwalaSMS delivery implementation.
- Email OTP currently uses Supabase Auth's built-in email OTP flow. Resend SMTP must be configured at the Supabase Auth level.
- The driver document upload implementation currently obtains public URLs. This must be migrated carefully to private object paths and authorized signed-URL reads; changing only the upload call would break consumers.
- No provider credentials have been supplied to the deployment environment, no Edge Functions have been deployed by this change, and no live payment/SMS/email has been sent.

## Safe completion sequence

1. Inspect the existing payment schema, RPCs, triggers and RLS before adding provider references or changing payment state transitions.
2. Implement and test AzamPay initiation and callback verification in sandbox, with atomic idempotent reconciliation.
3. Implement SwalaSMS send, delivery-status persistence and signed webhook verification from its official API reference.
4. Configure Resend SMTP for Supabase Auth; separately implement application email only where required.
5. Audit every storage bucket and document URL consumer, then migrate private documents to stable paths and signed reads.
6. Search the full application and platform configuration for Firebase remnants; remove only verified-unused Firebase components.
7. Run migration review on staging, configure secrets, deploy functions and perform end-to-end tests before production.

Do not mark any item complete until its code, deployment configuration and behavior have been verified.
