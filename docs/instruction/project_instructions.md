# MrPizza — Project Instructions

This document captures the build instructions for the **MrPizza** Flutter app. It is a learning-stage document: the goal is to understand how Gradle/AGP/Manifest files evolve before adding native-heavy packages.

## Scope of the current stage

- **Tech stack:** Flutter only. No Supabase, no Safepay, no Maps SDK, no Firebase.
- **No backend calls.** No hardcoded/mock data either — each screen is a simple placeholder (e.g. "Welcome to Menu Screen").
- **Apps:** One Flutter app serving two roles (Customer and Rider) via a hardcoded/mock role toggle. Admin dashboard is skipped for now.
- **Single restaurant** — no multi-vendor/marketplace logic anywhere.

## Core use cases (later stages)

- **Customer:** browse menu, search/filter items, place order, apply coupon, track order in real time, cancel order, rate & review, manage profile.
- **Rider:** accept/reject delivery, update delivery status, navigate to customer (Google Maps), view earnings, set availability.
- **Shared:** order status changes trigger notifications (Supabase Realtime + FCM); payment happens at "place order" via Safepay; Maps SDK is called directly from the client, not routed through Supabase.

## Architecture pattern

Feature-based structure, NOT full Clean Architecture.

```
lib/
├── main.dart
├── app.dart
├── widgets/
│   └── shared_components.dart
├── core/
│   ├── config/          (env.dart, api_endpoints.dart)
│   ├── network/         (supabase_client.dart, api_response.dart, auth_interceptor.dart)
│   ├── providers/       (language_provider.dart, role_provider.dart) + providers.dart
│   ├── routing/         (router.dart, route_guard.dart)
│   ├── storage/         (token_storage.dart)
│   ├── theme/           (app_colors.dart, app_theme.dart, widgets.dart)
│   ├── l10n/            (app_translations.dart)
│   └── utils/           (date_utils.dart, validators.dart)
└── features/
    ├── auth/   – customer  (screens, providers, models, data)
    ├── home/   – dashboard (screens)
    ├── menu/              (screens, providers, models, data)
    ├── orders/            (screens, providers incl. order_realtime_provider, models, data)
    ├── payment/           (screens incl. checkout_screen with Safepay WebView, providers, models, data)
    ├── rider/             (screens, providers incl. location_provider, models, data)
    └── profile/           (screens, providers, models, data)
```

Per feature: `data/` = data source (Supabase/Edge Function calls) + repository (maps to `ApiResponse`, catches exceptions) → `providers/` (Riverpod) → `screens/` (UI only, never touches Supabase directly).

## Backend & payments — NOT in the current stage

Do not scaffold Supabase tables, Edge Functions, or Safepay integration yet. `core/network/`, `core/config/env.dart`, and `data/` folders exist only as empty placeholders — no Supabase/Safepay code, no API keys, no network calls.

## Gradle / Android build setup rules — follow exactly

1. Run `flutter doctor -v` first; confirm no red flags before scaffolding anything.
2. Use `flutter create` to scaffold — never hand-write `android/build.gradle`, `android/app/build.gradle`, or `android/settings.gradle` from scratch.
3. Use the Gradle wrapper only (`./gradlew`) — never a global Gradle install.
4. Do **not** upgrade AGP, Gradle, or Kotlin versions independently of each other. If a bump is ever needed, check the official compatibility matrix for that exact combination first.
5. Before adding any native-heavy package (Google Maps, Safepay), check that package's README/issues for AGP/minSdkVersion compatibility — before adding it, not after a build failure.
6. Set `minSdkVersion` explicitly (21+).
7. After any Gradle file change: `flutter clean && flutter pub get` before rebuilding.
8. Add and verify **one dependency at a time**, confirming `flutter run` still works after each addition. Current stage allows only state management (Riverpod) and routing (go_router).

## Current android/ file state (Flutter 3.44.6 — Kotlin DSL `.kts`)

- `android/build.gradle.kts`: repo declarations + `clean` task; moves build output to root `build/`.
- `android/settings.gradle.kts`: reads `flutter.sdk` from `local.properties`, `includeBuild`s the Flutter Gradle plugin; declares AGP **9.0.1**, Kotlin **2.3.20**, plugin-loader **1.0.0** (keep these aligned when upgrading).
- `android/app/build.gradle.kts`: applies `com.android.application` + Flutter Gradle plugin; `compileSdk`/`ndkVersion` from `flutter.*`; `minSdk = 24`; Java 17; release uses debug signing (TO-DO).
- `AndroidManifest.xml`: single `MainActivity` (`launchMode=singleTop`, `exported=true`), `flutterEmbedding=2`.