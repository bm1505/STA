# STA Smart Platform — Deployment Notes

These changes are committed to `main`, but GitHub file updates do not deploy database migrations or Edge Functions to the Supabase project.

## 1. Apply database migrations

Apply the repository migrations to a staging Supabase project first. Review the resulting schema and RLS policies before applying them to production.

From the project directory, after the Supabase CLI is linked to the intended project:

```powershell
supabase db push
```

The new migrations add:
- Server-calculated fares, demand multipliers and secure ride lifecycle transitions.
- Persistent in-app notifications and administrator broadcast delivery.
- Historical next-hour demand forecasting.
- Driver GPS anomaly detection and administrator safety review.
- Vehicle owners, transport companies, branches, fleet, assignments, fuel, maintenance and contracts.
- Organization-scoped fleet monitoring and Realtime publication.
- Per-user quotas for paid routing and AI provider calls.

The ride-request insert policy is intentionally replaced by the authenticated `sta_create_ride_request` RPC. The current Flutter client has been changed to use that RPC.

## 2. Configure server-side secrets

Set secrets in Supabase; do not put provider keys in Flutter source, build arguments, or this repository.

```powershell
supabase secrets set GEMINI_API_KEY=YOUR_GEMINI_KEY
supabase secrets set GOOGLE_ROUTES_API_KEY=YOUR_GOOGLE_ROUTES_KEY
```

Enable the Google Routes API and billing for the Google key, and apply API restrictions and quotas. The Gemini key is used only by server-side Edge Functions.

## 3. Deploy Edge Functions

```powershell
supabase functions deploy sta-ai
supabase functions deploy traffic-route
supabase functions deploy route-advice
```

Keep JWT verification enabled. These functions expect an authenticated STA user and enforce per-user quotas before calling paid AI or routing providers.

## 4. Refresh Flutter dependencies

After the repository changes are pulled locally:

```powershell
flutter pub get
```

This regenerates the dependency lockfile for the current Flutter SDK. Firebase packages and client-side Gemini SDK usage have been removed from the application dependency set.

## 5. Current integration boundaries

- **M-Pesa STK Push:** not connected to a payment provider yet. The current wallet flow records a pending request only; it does not send an STK prompt. An administrator must not mark a payment paid until the external provider confirms it.
- **Remote push notifications:** not configured. Ride updates, safety alerts and admin broadcasts are stored in the Supabase in-app notification inbox. Push delivery while the app is closed needs a selected push provider and its credentials.
- **Live traffic:** becomes available only after the traffic Edge Function is deployed and `GOOGLE_ROUTES_API_KEY` is configured. Without it, the app uses a real road-route provider without claiming live traffic.
- **AI features:** require `sta-ai` / `route-advice` deployment and `GEMINI_API_KEY`.
- **Fleet, company and safety features:** require the migrations above to be applied before the corresponding screens can load their data.

No Flutter build or runtime test is claimed by this change set. Verify migrations on staging, deploy Edge Functions, then run end-to-end tests for rider booking, driver matching, ride completion, cash payment confirmation, notifications, fleet assignment and safety alerts before production rollout.
