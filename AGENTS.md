# AGENTS.md — MrPizza

## Project Overview
MrPizza is a Flutter food delivery app for a real restaurant ("Mr. Pizza", Abbottabad + Mansehra branches, Pakistan). Single codebase shared by customers and delivery riders, with role-based access. Backend: Supabase. Payments: Safepay (+ EasyPaisa/JazzCash via Raast).

## ⚠️ Supabase Safety Rule — READ FIRST
**Never perform a write operation against Supabase (via MCP, CLI, or any tool) without first explicitly asking for and receiving my permission — no exceptions.**

This includes but is not limited to:
- INSERT, UPDATE, DELETE, or any SQL that mutates data
- Creating, altering, or dropping tables/columns
- Generating OR applying database migrations
- Deploying or modifying Edge Functions
- Changing RLS policies, auth settings, storage buckets, or any project configuration

**Read-only operations are fine without asking** — querying data, inspecting schema, listing tables, reading Edge Function source code.

If a task seems to require a write operation, stop and describe exactly what you intend to run (the SQL, the migration, the deploy) and wait for my explicit go-ahead before executing it. Assume every Supabase-facing action is destructive until proven otherwise — this project handles real customer orders and real payment data for a live restaurant.

## Tech Stack
- Flutter (state management: Provider)
- Supabase (auth, database, storage, Edge Functions)
- Safepay for payment gateway — **no official Flutter SDK exists**; integration is done via Supabase Edge Functions acting as a backend proxy to Safepay's REST API
- <!-- fill in: maps/location package if used for delivery tracking -->

## Location Capture
- GPS only, no map picker: `geolocator` (`lib/features/location/data/geolocator_device_location_source.dart`) reads the fix; there is no Google Maps dependency.
- Street address text comes from OpenStreetMap Nominatim (`nominatim_address_lookup.dart`) — no API key. Nominatim's usage policy requires a real contact in the User-Agent: `nominatimUserAgent` in `lib/core/providers/location_provider.dart` still has a placeholder email and **must be replaced before release**.
- Location is optional. Permission denied / blocked / services off / GPS timeout / reverse-geocode failure must all leave manual address entry usable — never block checkout. Failures surface as `LocationCaptureException` and `LocationState.errorMessage`.
- A reverse-geocode failure keeps the GPS pin and leaves the address text empty; a hand-typed address clears the pin (`LocationNotifier.setLocation`) so a stale pin can never match the branch to the wrong place.
- `CheckoutState.branchIsNearest` is the only thing allowed to label a branch "nearest". `BranchSelection` returns `isNearestToAddress: false` unless both the address and the branch have coordinates. Never hardcode that word again.
- Platform permissions already added: `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` in `android/app/src/main/AndroidManifest.xml`, `NSLocationWhenInUseUsageDescription` in `ios/Runner/Info.plist`.
- Branch coordinates live in nullable `public.branches.latitude` / `.longitude` (added by migration `branches_add_coordinates`). Mansehra's values are a city-centre placeholder, not the real shop.
- Do not use `OrdersRepository.bundledBranches` for anything that reaches the database — those ids are not real UUIDs and would fail the `orders.branch_id` foreign key. `BranchCatalog.usedFallbackData` exists so the UI can say so.

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