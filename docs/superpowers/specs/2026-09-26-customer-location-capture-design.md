# Customer Location Capture — Design

**Date:** 2026-09-26
**Status:** Approved and implemented
**Supabase project:** `foodApp` (`eytsownrsujphibqpimt`)

---

## 1. Problem

The app already computes which branch is nearest to a customer using the Haversine
formula, but the feature is **silently dead**. Three things break it:

1. **`branches` has no `latitude` / `longitude` columns.** `Branch.fromMap()` reads
   them at `lib/features/orders/models/branch.dart:21-22` and always gets `null`.
2. **`nearestBranch()` falls back silently.** With no coordinates,
   `distanceTo()` returns `null` (`branch.dart:30`), every branch is skipped
   (`orders_provider.dart:122`), and it returns `branches.first`
   (`orders_provider.dart:128`). Branches are sorted alphabetically
   (`orders_repository.dart:13`), so **Abbottabad always wins regardless of address**.
3. **The screen then lies.** `checkout_screen.dart:819` displays
   *"Delivering from Abbottabad (nearest branch)"* — a claim that was never computed.

Separately, customers cannot supply coordinates at all. `addresses_screen.dart`
has manual latitude/longitude text fields (`:110`, `:127`) that a customer is
expected to type by hand, and `location_provider.dart:34` (`useCurrentLocation()`)
returns a **hardcoded fake string** with no GPS involvement.

Net effect: the "nearest branch" and free-delivery-radius logic cannot work, and
delivery addresses have no usable location data.

---

## 2. Goals

- Capture a customer's real coordinates with one tap.
- Turn those coordinates into readable, editable address text automatically.
- Store coordinates so the existing Haversine nearest-branch logic works.
- Make the checkout screen honest about how a branch was chosen.
- Work on both Android and iOS.

## 3. Non-goals (deliberately excluded)

Agreed with Shahzeb to keep this change small. None of these block the above:

- Map picker / drag-a-pin UI
- Google Maps (and its billing account + restricted API key)
- The 5 km delivery radius check
- Rider location tracking
- Address autocomplete / place search

The chosen approach is **deliberately the cheapest one that fixes the bug**, on the
reasoning that the stored data is identical under every option — only the input
widget differs. If a map picker is added later, only the input widget is replaced;
the database, nearest-branch logic, and any future radius check are unaffected.

---

## 4. Data layer

### 4.1 `branches` — add coordinates

```sql
alter table public.branches
  add column if not exists latitude  numeric,
  add column if not exists longitude numeric;
```

Both nullable: a branch without coordinates must not block anything, and the
honesty fix in §7 depends on `null` remaining a legal state.

`numeric` is chosen to match `addresses.latitude` / `addresses.longitude`, which
are already `numeric` (verified against the live schema). Keeping one type across
both tables avoids a future "why is this column different" question. Dart is
unaffected either way — `Branch.fromMap()` casts through `num`
(`branch.dart:21-22`), which handles both `numeric` and `double precision`.

### 4.2 Seed values

| Branch | `code` | `latitude` | `longitude` | Confidence |
|---|---|---|---|---|
| Abbottabad | `ABT` | `34.204008` | `73.238723` | **Good.** OpenStreetMap node for *Ayub Medical Complex, Mandian, Abbottabad* — the landmark named in the branch's own address ("opposite Ayub Medical Complex"). |
| Mansehra | `MSH` | `34.328686` | `73.199313` | **PLACEHOLDER.** OpenStreetMap centroid for *Mansehra city*. This is the city centre, **not** the actual shop. Must be replaced when the real Mansehra address is known. |

Discovered along the way: the existing mock coordinate for Abbottabad
(`34.1688, 73.2215`, `orders_repository.dart:26`) is roughly **4 km south** of the
real location. The Mansehra mock was within ~250 m. The Abbottabad mock being
wrong is precisely why the feature could not have worked even with coordinates
present.

### 4.3 `addresses` — no change

`latitude` and `longitude` already exist and are nullable. Nothing to add.

---

## 5. New code

### 5.1 `lib/features/location/data/location_repository.dart`

A single class with three responsibilities, deliberately kept together so that a
future map picker replaces one file rather than spreading GPS logic across the app:

| Method | Behaviour |
|---|---|
| `ensurePermissionGranted()` | Requests foreground location permission. Returns granted / denied / denied-forever. |
| `fetchCurrentCoordinates()` | Returns lat/lng. Throws a typed error for: permission denied, location services disabled, timeout. |
| `reverseGeocode(lat, lng)` | Looks up readable address text via OpenStreetMap Nominatim. Returns `null` on any failure — never throws, because a missing address string must not block the customer. |

**Nominatim usage policy compliance.** OpenStreetMap requires that automated
requests identify themselves and stay under 1 request/second. Therefore:

- Every request sends `User-Agent: MrPizza/1.0 (<contact>)`.
- Calls are limited to one per address save, initiated by an explicit user tap —
  never automatic, never on a loop, never batched.
- No retry loop. A failed lookup returns `null` and the customer types the text.

**Endpoint:** `GET https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lng}`

The app's contact address will be substituted for `(<contact>)` before release.

### 5.2 `lib/core/providers/location_provider.dart` (rewrite)

Current state: holds only a `String`, `useCurrentLocation()` returns the hardcoded
`'COMSATS University, Abbottabad Campus'` (`location_provider.dart:36`).

New `LocationState`:

- `double? latitude`, `double? longitude`
- `String address` (the text, whether typed or auto-filled)
- `bool isLocating` — true while GPS or the lookup is in flight
- `String? errorMessage` — plain-language failure reason, or `null`
- `bool isSet`

New behaviour: `useCurrentLocation()` becomes `Future`-returning, sets
`isLocating`, requests permission, gets coordinates, reverse-geocodes, and sets
text. On any failure it sets `errorMessage` and leaves the customer able to type
manually.

This preserves the existing `locationProvider` / `LocationNotifier` /
`LocationState` public names, so `home_screen.dart` (`:65`, `:165`) and
`shared_components.dart` keep compiling.

### 5.3 `addresses_screen.dart`

- Add a **"Use current location"** button wired to the provider.
- **Remove** the manual latitude (`:110`) and longitude (`:127`) text fields, and
  their controllers (`:21-22`) and parsing (`:178-179`).
- `addAddress` in `profile_repository.dart:36` keeps accepting the coordinates;
  they now come from GPS instead of typing.

### 5.4 `LocationSelectionDialog` (`shared_components.dart:1270`)

Its `_savedLocations` list (`:1284`) is hardcoded fake data. Replace with the
customer's real saved addresses from the `addresses` table, plus the new
"Use current location" action.

---

## 6. Platform permissions

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

`ACCESS_COARSE_LOCATION` is listed alongside `FINE` because requesting only `FINE`
can be rejected on some Android versions, and coarse is sufficient for the
5 km-scale precision this app needs.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Mr Pizza uses your location to find the nearest branch and deliver your order.</string>
```

iOS aborts the app if this key is missing while permission is requested.

### `pubspec.yaml`

```yaml
geolocator: ^14.0.3
http: ^1.2.0
```

`geolocator` 14.0.3 requires Dart `^3.5.0`; this project is `>=3.5.0 <4.0.0` on
Flutter 3.44.6, so it is compatible. `http` is declared explicitly rather than
relied upon as a transitive dependency of `supabase_flutter`.

---

## 7. The honesty fix

Today a branch chosen by alphabetical fallback is still labelled *"nearest
branch"*. Change `nearestBranch()` to report **how** the branch was chosen, and
have `checkout_screen.dart:819` render that:

- distance computed → *"Delivering from Abbottabad (nearest branch)"*
- no branch had coordinates → *"Delivering from Abbottabad (default branch)"*

This is a text-only change, but it stops the app asserting something it did not
actually compute.

---

## 8. Error handling

Location is **never mandatory**. Every failure path ends with the customer able to
type their address.

| Failure | Message | Fallback |
|---|---|---|
| Permission denied | "Location permission is off" | Type address manually |
| Permission denied forever | "Enable location in Settings" + deep-link to app settings | Type address manually |
| Location services off | "Turn on location services" | Type address manually |
| Timeout (GPS indoors) | "Could not get your location — try again" | Type address manually |
| Reverse lookup failed | *(silent)* | Coordinates saved, text left empty for manual entry |

The lookup failure being silent is intentional: the coordinates are the part that
matters for nearest-branch, and an error banner for a cosmetic text field would be
noise.

---

## 9. Testing

**Unit tests (no device required):**

- `Branch.haversineKm()` — known distances; Abbottabad→Mansehra is ~30 km, and
  identical points return 0.
- `nearestBranch()` — given branches with coordinates, picks the closer one;
  given branches without, returns the default and reports it as a default.
- Reverse-geocode URL construction and response parsing, against a fake client.
- Error mapping: each `GeolocatorException` maps to the right message and the
  provider stays usable afterwards.

**Widget test:** the permission-denied path leaves the manual address field
enabled and shows the correct message.

**Manual verification (device required):** real GPS accuracy and the permission
prompt. An emulator reports a simulated position and will not catch a
misconfigured manifest or plist entry.

---

## 10. Verification before completion

1. `flutter analyze` → No issues found
2. `flutter test` → all green
3. On a physical Android device: grant permission, confirm the picked coordinate
   matches the real location, confirm checkout labels the branch correctly
4. On a physical iOS device: same, confirming the plist string is present
5. Confirm a second customer address nearer Mansehra selects the Mansehra branch

---

## 11. Open items

- **Mansehra's real address and coordinates.** The stored value is the city
  centroid. Until it is replaced, customers near the real Mansehra shop may be
  routed to Abbottabad. The `TODO` placeholder in the `address` column must be
  replaced at the same time.
- **Nominatim contact address** to embed in the `User-Agent` before release.
- **`is_owner` / `is_staff` RPC exposure** — a pre-existing, unrelated security
  advisory. Deliberately not touched here.
- **The 10 tables with RLS disabled** — deliberately untouched, to be locked one
  at a time as each feature is built.
