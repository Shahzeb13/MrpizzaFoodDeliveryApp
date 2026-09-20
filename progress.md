# MrPizza — Progress Log
Changes done by Shahzeb
## 2026-09-20 — Premium design overhaul (uncommitted)

- **New design system**: warm ivory/espresso/brick palette (`AppColors`), Plus Jakarta Sans (`AppTheme`), and reusable theme widgets in `lib/core/theme/widgets.dart` (`MrCard`, `MrDoubleBezel`, `MrIconWell`, `MrSectionTitle`, `MrEyebrow`, `MrPriceText`, `MrFadeDivider`).
- **Converted screens** to the new system: splash, login, signup, role_select, home, menu, checkout, app_drawer, shared components (earlier session), then `my_orders`, `order_tracking`, `rider`, `profile`, `addresses`, `favorites`, `loyalty_points`, `wallet`, `support_center`, `account_deletion` (this session).
- **Cleanups**: removed unused `app_theme.dart` imports; fixed `MrCard`/`MrPriceText` API misuse; replaced deprecated `RadioListTile groupValue/onChanged` with `RadioGroup`; fixed remaining `prefer_const_constructors` infos incl. pre-existing `app.dart` and unused `_authSubscription` (now cancelled in `dispose`).
- **Result**: `flutter analyze` → No issues found.

## 2026-09-13

- **Add `supabase_flutter` dependency**: added `supabase_flutter: ^2.0.0` to pubspec.yaml and ran `flutter pub get` (resolved 2.17.2).
- **Add `flutter_dotenv` for secrets**: added `flutter_dotenv: ^6.0.0`, registered `.env` under `flutter: assets`, created root `.env` with `SUPABASE_URL` / `SUPABASE_ANON_KEY` placeholders, and added `.env` to `.gitignore` to keep keys out of source control.
- **Initialize Supabase before `runApp`**: `main()` is now async, loads dotenv, and calls `Supabase.initialize()` with `publishableKey` (replacing deprecated `anonKey`) before `runApp()`.
- **Add Supabase shorthand accessor**: replaced the placeholder in `lib/core/network/supabase_client.dart` with `final supabase = Supabase.instance.client;` so screens can import one line instead of calling `Supabase.instance.client` directly.
- **Resolve `git pull` merge conflict (pubspec.lock + pubspec.yaml)**: merged `origin/main` (PR #1 `allayan`) into local `main`. Fixed auto-merge duplicate `assets:` section in pubspec.yaml (combined `.env` + `assets/images/`), regenerated pubspec.lock via `flutter pub get`, and committed merge. Working tree clean.