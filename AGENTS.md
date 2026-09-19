# AGENTS.md — MrPizza

## Project Overview
MrPizza is a Flutter food delivery app for a real restaurant ("Mr. Pizza", Abbottabad + Mansehra branches, Pakistan). Single codebase shared by customers and delivery riders, with role-based access. Backend: Supabase. Payments: Safepay (+ EasyPaisa/JazzCash via Raast).

## Tech Stack
- Flutter (state management: Provider)
- Supabase (auth, database, storage, Edge Functions)
- Safepay for payment gateway — **no official Flutter SDK exists**; integration is done via Supabase Edge Functions acting as a backend proxy to Safepay's REST API
- <!-- fill in: maps/location package if used for delivery tracking -->

## Roles & Access
- **Owner**: sees all branches
- **Branch manager**: scoped to their own branch's orders; creates rider accounts
- **Customer**: self-signup, places orders (delivery or pickup)
- **Rider**: account created by branch manager; sees assigned orders, customer/order details

Role-based guards separate what each role can access within the shared codebase — keep this logic centralized rather than scattered across screens.

## Build & Run
```bash
flutter pub get
flutter attach
flutter build apk --debug
```
<!-- fill in any flavor/environment flags, e.g. --dart-define for Supabase keys -->

## Code Style / Conventions
- Folder structure: feature-first — `lib/features/<feature>/{data, models, providers, screens}` (e.g. `features/auth/`, `features/menu/`, `features/orders/`, `features/payment/`, `features/profile/`, `features/rider/`), plus shared `lib/app/` and `lib/core/`
- Naming: names must be self-documenting — a function/widget name alone should make its purpose, inputs, and output/behavior guessable without reading the body. Avoid vague names (`handleData`, `process`, `update`); prefer names that state the action and subject clearly (e.g. `fetchOrderById`, `buildRiderStatusBadge`, `calculateDeliveryFee`). Apply this to widgets, providers, and repository/data methods alike.
- UI priority: minimize taps for ordering — skip item detail screen for simple items where possible

## Payment Integration (Safepay)
- No official Flutter SDK — do NOT try to add a `safepay_flutter` package or similar; it doesn't exist
- Two flows through Supabase Edge Functions:
  - **Outgoing**: Flutter app → Edge Function → Safepay REST API (initiate/create payment)
  - **Incoming**: Safepay Webhook → Edge Function → Supabase DB (payment confirmation updates order/payment status)
- Safepay secret keys live only in Edge Function environment variables (Supabase secrets), never bundled into the Flutter app
- Webhook Edge Function MUST verify Safepay's signature/HMAC on incoming requests before trusting the payload — otherwise anyone who finds the endpoint URL could fake a "payment successful" callback
- Webhook handler should be idempotent (same webhook delivered twice shouldn't double-credit an order) — check current order status before applying the update
- Payment amount/currency should be re-validated server-side in the Edge Function against the order record, never trusted from the client alone
- <!-- fill in: names/paths of the specific Edge Functions handling checkout, payment confirmation, webhooks -->
- <!-- fill in: how the app polls/listens for payment status (Supabase realtime? polling an orders table?) -->
- Never commit API keys or secrets — reference them via environment config only

## Do Not Touch / Be Careful With
- <!-- fill in: any files with fragile logic, e.g. payment callback handlers, role guard middleware -->

## Testing
- <!-- fill in: how to run tests, e.g. flutter test -->

## Known Gotchas
- <!-- fill in as they come up, e.g. platform-specific build quirks, Supabase RLS policy gotchas -->
