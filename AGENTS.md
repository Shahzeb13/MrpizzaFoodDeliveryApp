# AGENTS.md — MrPizza

## Project Overview

MrPizza is a Flutter food delivery app for a real restaurant ("Mr. Pizza", Abbottabad + Mansehra branches, Pakistan). Single codebase shared by customers and delivery riders, with role-based access. Backend: Supabase. Payments: Safepay (+ EasyPaisa/JazzCash via Raast).

---

## ⚠️ Supabase Safety Rule — READ FIRST

**Never perform a write operation against Supabase (via MCP, CLI, or any tool) without first explicitly asking for and receiving my permission — no exceptions.**

Do NOT run the full Flutter test suite or full `flutter analyze` after every small change.

Only run targeted tests relevant to the files/features changed.

Run `flutter analyze` only when necessary to validate the final state.

For example, if modifying a specific test:

```bash
flutter test test/live_order_resolution_test.dart
```

Do not repeatedly run the entire test suite after every edit unless the change is broad enough to justify it.

Also do not spend time fixing unrelated deprecation warnings unless they are directly caused by your changes.

This includes but is not limited to:

* INSERT, UPDATE, DELETE, or any SQL that mutates data
* Creating, altering, or dropping tables/columns
* Generating OR applying database migrations
* Deploying or modifying Edge Functions
* Changing RLS policies, auth settings, storage buckets, or any project configuration

**Read-only operations are fine without asking** — querying data, inspecting schema, listing tables, reading Edge Function source code.

If a task seems to require a write operation, stop and describe exactly what you intend to run (the SQL, migration, deploy, etc.) and wait for my explicit go-ahead.

Assume every Supabase-facing action is destructive until proven otherwise — this project handles real customer orders and real payment data for a live restaurant.

---

## Command Execution Rules

* Do not run expensive commands unless they are relevant to the current task.
* Prefer targeted validation over full-project validation.
* Do not run `flutter test` for every small change.
* Do not run `flutter analyze` for every small change.
* Do not run `flutter build apk` unless an APK/build check is actually relevant.
* Do not run `flutter pub upgrade` automatically.
* Run `flutter pub get` only when dependencies/pubspec changed.
* Format only changed files when possible.
* Do not run unrelated cleanup/refactoring just because warnings are discovered.

### Testing

Use targeted tests whenever possible:

```bash
flutter test test/<relevant_test>.dart
```

Run the full suite:

```bash
flutter test
```

only when explicitly requested or when the change affects shared/core behavior or multiple features.

### Analysis

Run:

```bash
flutter analyze
```

when needed for final validation or when the change affects enough code to justify it.

Do not fix unrelated analyzer warnings/deprecations.

### Build

Run:

```bash
flutter build apk --debug
```

only when Android/native configuration, plugins, permissions, Gradle, or APK-level behavior is involved, or when explicitly requested.

---

## Scope Control

Stay within the user's requested task.

Do not automatically fix unrelated:

* warnings
* deprecated APIs
* failing tests
* formatting
* refactoring opportunities
* architectural issues

Report unrelated issues separately instead of expanding the task.

---

## Tech Stack

* Flutter (state management: Provider)
* Supabase (auth, database, storage, Edge Functions)
* Safepay for payment gateway — **no official Flutter SDK exists**; integration is done via Supabase Edge Functions acting as a backend proxy to Safepay's REST API

---

## Location Capture

* GPS only, no map picker: `geolocator` (`lib/features/location/data/geolocator_device_location_source.dart`) reads the fix; there is no Google Maps dependency.
* Street address text comes from OpenStreetMap Nominatim (`nominatim_address_lookup.dart`) — no API key.
* Nominatim's usage policy requires a real contact in the User-Agent: `nominatimUserAgent` in `lib/core/providers/location_provider.dart` still has a placeholder email and **must be replaced before release**.
* Location is optional. Permission denied / blocked / services off / GPS timeout / reverse-geocode failure must all leave manual address entry usable — never block checkout.
* Failures surface as `LocationCaptureException` and `LocationState.errorMessage`.
* A reverse-geocode failure keeps the GPS pin and leaves the address text empty.
* A hand-typed address clears the pin (`LocationNotifier.setLocation`) so a stale pin can never match the branch to the wrong place.
* `CheckoutState.branchIsNearest` is the only thing allowed to label a branch "nearest".
* `BranchSelection` returns `isNearestToAddress: false` unless both the address and branch have coordinates.
* Never hardcode "nearest" again.
* Platform permissions already added:

  * `ACCESS_FINE_LOCATION`
  * `ACCESS_COARSE_LOCATION`
  * `NSLocationWhenInUseUsageDescription`
* Branch coordinates live in nullable `public.branches.latitude` / `.longitude` (added by migration `branches_add_coordinates`).
* Mansehra's values are city-centre placeholders, not the real shop.
* Do not use `OrdersRepository.bundledBranches` for anything that reaches the database — those IDs are not real UUIDs and would fail the `orders.branch_id` foreign key.
* `BranchCatalog.usedFallbackData` exists so the UI can say so.

---

## Roles & Access

* **Owner**: sees all branches
* **Branch manager**: scoped to their own branch's orders; creates rider accounts
* **Customer**: self-signup, places orders (delivery or pickup)
* **Rider**: account created by branch manager; sees assigned orders and customer/order details

Role-based guards separate what each role can access within the shared codebase — keep this logic centralized rather than scattered across screens.

---

## Build & Run

```bash
flutter pub get
flutter run
flutter attach
flutter build apk --debug
```

Do not automatically run all of these after every change.

---

## Code Style / Conventions

* Feature-first structure:
  `lib/features/<feature>/{data, models, providers, screens}`
* Shared code:
  `lib/app/` and `lib/core/`
* Names must be self-documenting.
* Avoid vague names such as `handleData`, `process`, `update`.
* Prefer names such as `fetchOrderById`, `buildRiderStatusBadge`, `calculateDeliveryFee`.
* Apply this to widgets, providers, repositories, and data methods.
* UI priority: minimize taps for ordering — skip item detail screen for simple items where possible.

---

## Payment Integration (Safepay)

* No official Flutter SDK — do NOT try to add a `safepay_flutter` package or similar.
* **Outgoing:** Flutter app → Edge Function → Safepay REST API
* **Incoming:** Safepay Webhook → Edge Function → Supabase DB
* Safepay secret keys live only in Edge Function environment variables.
* Never bundle secrets into the Flutter app.
* Webhook Edge Function MUST verify Safepay's signature/HMAC before trusting the payload.
* Webhook handler must be idempotent.
* Payment amount/currency must be re-validated server-side against the order record.
* Never trust payment amount/currency from the client alone.
* Never commit API keys or secrets.

---

## Do Not Touch / Be Careful With

* Payment callback/webhook handlers
* Role/authorization guards
* RLS policies
* Production database schema/data
* Order/payment state transitions

---

## Testing

Prefer targeted tests relevant to the changed feature.

```bash
flutter test test/<relevant_test>.dart
```

Use the full suite only when the change warrants it or the user explicitly requests it.

---

## Known Gotchas

* Do not use fake/fallback branch UUIDs for database orders.
* Mansehra coordinates are placeholders.
* Nominatim User-Agent email must be replaced before release.
* Do not block checkout because location fails.
* Do not install a fictional `safepay_flutter` package.
* Do not run unnecessary full-suite validation after small changes.
