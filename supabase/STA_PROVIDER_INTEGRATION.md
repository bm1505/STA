# STA Provider Integration — Current Implementation

## Fixed architecture

| Capability | Provider |
|---|---|
| Payments and payouts | AzamPay |
| SMS | SwalaSMS |
| Transactional email | Resend |
| Database, Auth, Storage, Realtime | Supabase |
| Server-side integrations | Supabase Edge Functions |

No credentials belong in Flutter or in source control.

## Implemented in this change

### SwalaSMS
- Added `swalasms-send` Edge Function.
- Requires a valid Supabase session and an active administrator profile.
- Calls the official SwalaSMS endpoint `POST https://swalasms.com/api/v1/sms/messages` using server-side `SWALASMS_API_KEY` and `SWALASMS_SENDER_ID`.
- Accepts Tanzanian E.164-style numbers in `255XXXXXXXXX` form.
- Stores a recipient hash and delivery state, not the phone number or message body.
- Uses a unique internal idempotency key. Ambiguous network errors and provider 429/5xx responses become `unknown`; the function does not blindly send again.

### Delivery ledger
- Added `provider_delivery_jobs` with a unique (provider, idempotency_key) constraint.
- RLS is enabled and all access is revoked from anon/authenticated. Only the service role can write/read the ledger.
- Status values distinguish `processing`, `accepted`, `failed`, and `unknown`.

### AzamPay payment request foundation
- Added payment metadata columns for provider status, checkout URL, initiation time and confirmation time.
- Replaced `sta_create_payment_request` so new requests use provider `azampay` and an internal `STA-<payment UUID>` reference.
- This only creates a pending request. It does NOT start an AzamPay checkout or mark a payment successful.

## Not yet complete

- **AzamPay checkout and callback reconciliation:** not implemented. The public developer landing page links to the Tanzania merchant API, but the exact auth, checkout payload, callback signature/authentication and transaction-status contract must be confirmed from the merchant account. No endpoint or signature has been guessed. Do not enable digital payment success until this is implemented and verified.
- **Resend:** Supabase Auth must be configured to use Resend SMTP in the Supabase Dashboard. No credentials are in the repository. The Resend direct transactional mail Edge Function was not added in this change.
- **SwalaSMS delivery webhooks and retries:** sending is implemented, but signed webhook verification and status polling remain disabled until the provider's exact signing headers and status API are verified. The current ledger records acceptance, not final handset delivery.
- **Supabase Storage:** new license, insurance and national-ID uploads store `pg://<object-path>` references. `PostgresImage` resolves them through 5-minute Supabase signed URLs. Migration `20261106152000_sta_private_driver_documents.sql` converts matching legacy public URLs, makes `driver-documents` private, and adds owner/active-admin access policies plus restrictive guards. Existing non-matching legacy URLs are intentionally not rewritten; inspect them before applying the migration.
- **Firebase removal:** `pubspec.yaml` and `pubspec.lock` contain no Firebase packages; Android Gradle/manifest and iOS project configuration inspected in this pass contain no Firebase plugin/config references; the four Flutter entry points contain no Firebase initialization; obsolete `fcmToken` model field was removed and migration `20261106153000_sta_remove_legacy_fcm_tokens.sql` clears the stale token from profile JSON. The code-search scan found no Firebase imports or initialization matches. Re-run a full local text scan before release to catch any generated or unindexed file.

## Required Supabase Function secrets

- `SWALASMS_API_KEY`
- `SWALASMS_SENDER_ID`

For Resend SMTP, configure the SMTP host, port, username, password and verified sender in Supabase Authentication settings. If direct transactional mail is added later, use `RESEND_API_KEY` only as a Function secret.

The standard Supabase Function secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are required by the SwalaSMS function.

## Deployment and verification

1. Review and apply the provider delivery, AzamPay request, private driver-document, and legacy FCM-token cleanup SQL migrations on a staging Supabase project. Confirm legacy document references and Storage policies before applying the private-bucket migration.
2. Set SwalaSMS Function secrets in Supabase.
3. Deploy `swalasms-send` with JWT verification enabled.
4. Test with an approved internal recipient and verify the SwalaSMS portal and `provider_delivery_jobs`.
5. Configure Resend SMTP in Supabase Auth and test signup/OTP/password-reset delivery.
6. Obtain/confirm the AzamPay Tanzania merchant API contract before implementing checkout and callbacks.
7. Test driver uploads and owner/admin document viewing against the private bucket, including a non-owner denial test.
8. Run a full local Firebase residue scan and verify all app flavors/platforms before release.

No SQL migration has been applied to a Supabase project, no Edge Function has been deployed, no external SMS/email/payment has been sent, and no Flutter build has been run from this change.


## Private driver document storage

- New license, insurance and national-ID uploads persist a bucket object reference (`pg://<user-id>/<filename>`) in `profiles.user_data`.
- `PostgresImage` requests a 5-minute signed URL from Supabase Storage; it no longer depends on the old local HTTP proxy or a hard-coded LAN IP.
- The private-bucket migration converts only legacy URLs that explicitly contain the Supabase public/signed path for the `driver-documents` bucket. Other URL formats are left unchanged for manual review.
- Storage policies allow the owning driver and an active STA administrator to read a document. Uploads are restricted to the driver's own folder. Restrictive guards prevent an older permissive policy from widening access.
- The bucket is made private by the migration. Existing public URLs for other profile/vehicle images are not changed by this migration.
