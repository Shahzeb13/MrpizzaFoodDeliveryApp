# MrPizza — Progress Log
Changes done by Shahzeb
## 2026-09-13

- **Add `supabase_flutter` dependency**: added `supabase_flutter: ^2.0.0` to pubspec.yaml and ran `flutter pub get` (resolved 2.17.2).
- **Add `flutter_dotenv` for secrets**: added `flutter_dotenv: ^6.0.0`, registered `.env` under `flutter: assets`, created root `.env` with `SUPABASE_URL` / `SUPABASE_ANON_KEY` placeholders, and added `.env` to `.gitignore` to keep keys out of source control.
- **Initialize Supabase before `runApp`**: `main()` is now async, loads dotenv, and calls `Supabase.initialize()` with `publishableKey` (replacing deprecated `anonKey`) before `runApp()`.
- **Add Supabase shorthand accessor**: replaced the placeholder in `lib/core/network/supabase_client.dart` with `final supabase = Supabase.instance.client;` so screens can import one line instead of calling `Supabase.instance.client` directly.