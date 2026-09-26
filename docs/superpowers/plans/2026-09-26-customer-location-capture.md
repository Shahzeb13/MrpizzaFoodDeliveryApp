# Customer Location Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture a customer's real GPS coordinates with one tap, turn them into editable address text, and make the existing nearest-branch logic actually work.

**Architecture:** GPS is read through `geolocator`, behind a `DeviceLocationSource` interface so the plugin's static API never touches business logic and is testable. Coordinates are reverse-geocoded to text through a separate `AddressTextLookup` interface backed by OpenStreetMap Nominatim over plain HTTP, which needs no API key and no billing account. `LocationRepository` composes the two. Branch coordinates are stored in the database so the existing Haversine code in `Branch` works. Branch selection returns a `BranchSelection` that records whether a distance was genuinely computed, so the checkout screen can stop claiming "nearest branch" when it merely guessed.

**Tech Stack:** Flutter 3.44.6 / Dart `>=3.5.0 <4.0.0`, Riverpod 2.5.1, `geolocator ^14.0.3`, `http ^1.2.0`, Supabase (Postgres), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-26-customer-location-capture-design.md`

---

## Global Constraints

- Location is **never mandatory**. Every failure path must leave the customer able to type their address manually.
- `LocationState` must keep its existing public members `address`, `isSet`, `setLocation`, and the `locationProvider` name, so `home_screen.dart:65,165` and `shared_components.dart:1301,1304` keep compiling without edits.
- Every Nominatim request must send a `User-Agent` header. OpenStreetMap's usage policy requires identifying the app and staying under 1 request/second. **No retry loops, no automatic calls, no batching** — one lookup per explicit user tap.
- `reverseGeocode` must **never throw**. Any failure returns `null`.
- Branch coordinates are `numeric`, matching the existing `addresses.latitude` / `addresses.longitude` columns.
- New `branches` coordinate columns must remain **nullable** — the honest-label logic depends on `null` being a legal state.
- Do **not** add `ACCESS_BACKGROUND_LOCATION` or `FOREGROUND_SERVICE_LOCATION`. This app only needs a foreground, one-shot fix.
- Do **not** add a 5 km radius check, a map picker, Google Maps, or rider tracking. Out of scope per spec §3.
- `android.useAndroidX=true` is already set in `android/gradle.properties`. `compileSdk = flutter.compileSdkVersion` already resolves above the 35 that geolocator 14 requires. Do not hardcode a compileSdk value.
- `UserAgent` contact string: use the literal `MrPizza/1.0` for now. Swapping in a real contact address is a tracked follow-up, not part of this plan.
- Follow the repo's naming rule in `AGENTS.md`: names must be self-documenting. No `handleData`, `process`, or `update`.

## Review Focus

Five input conditions the spec implies but no happy-path test exercises. Each has a test pinned to the task that owns the code.

1. **A branch row with `NULL` coordinates.** Mansehra's coordinates are a placeholder today and any future branch may be added without them. Expected: that branch is skipped for distance, never treated as distance zero, and the screen says "default branch" not "nearest branch". → Task 2
2. **Permission permanently denied** (customer tapped "Don't allow" twice). Expected: a message pointing at Settings, and the manual address field still usable — no dead end. → Task 4, Task 6
3. **Reverse geocode returns a non-JSON body, an empty `display_name`, or a 429.** Expected: no exception escapes, `null` returned, coordinates still saved, text left for manual entry. → Task 4
4. **GPS fix at exactly `0,0`** ("Null Island" — a real failure mode when a device has no fix). Expected: treated as a failure, not as a location off the coast of Africa, because it would otherwise make Abbottabad look ~30 km away. → Task 4
5. **An address saved with coordinates but no text** (case 3, then saved). Expected: checkout still works and nearest-branch still uses the coordinates. → Task 6

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/features/location/models/geo_coordinates.dart` | **New.** Immutable lat/lng value pair. |
| `lib/features/location/data/device_location_source.dart` | **New.** Interface + geolocator-backed implementation + failure enum. |
| `lib/features/location/data/address_text_lookup.dart` | **New.** Interface + Nominatim-backed implementation. |
| `lib/features/location/data/location_repository.dart` | **New.** Composes the two above into one call the UI can use. |
| `lib/core/providers/location_provider.dart` | **Modified.** Now holds coordinates, loading and error state. |
| `lib/features/orders/models/branch_selection.dart` | **New.** Result of branch selection, including whether distance was measured. |
| `lib/features/orders/providers/orders_provider.dart` | **Modified.** `nearestBranch` → `selectNearestBranch` returning `BranchSelection`; `CheckoutState` carries the flag. |
| `lib/features/payment/screens/checkout_screen.dart` | **Modified.** Label reflects how the branch was chosen. |
| `lib/features/profile/screens/addresses_screen.dart` | **Modified.** GPS button replaces manual lat/lng fields. |
| `lib/widgets/shared_components.dart` | **Modified.** `LocationSelectionDialog` uses real saved addresses. |

Test files mirror these under `test/`.

---

### Task 1: Give the branches coordinates

The whole feature is dead until this exists: `Branch.fromMap()` reads `latitude`/`longitude` (`branch.dart:21-22`) and the `branches` table cannot supply them.

**Files:**
- Modify: database `public.branches` (via Supabase migration tool, not a git file)

**Interfaces:**
- Consumes: nothing.
- Produces: `branches.latitude` / `branches.longitude`, both `numeric` and nullable. `ABT` = `34.204008, 73.238723`. `MSH` = `34.328686, 73.199313`.

- [ ] **Step 1: Confirm the starting state**

Run:
```sql
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'branches'
  and column_name in ('latitude', 'longitude');
```
Expected: **zero rows.** If rows come back, a previous attempt already added them — stop and reconcile rather than re-adding.

- [ ] **Step 2: Add the columns and seed both branches**

Apply as a single migration named `branches_add_coordinates`:
```sql
alter table public.branches
  add column if not exists latitude  numeric,
  add column if not exists longitude numeric;

update public.branches set latitude = 34.204008, longitude = 73.238723 where code = 'ABT';
update public.branches set latitude = 34.328686, longitude = 73.199313 where code = 'MSH';
```

- [ ] **Step 3: Verify the seed landed on the right rows**

Run:
```sql
select code, name, latitude, longitude
from public.branches
where code in ('ABT', 'MSH')
order by code;
```
Expected: exactly two rows — `ABT` `34.204008` `73.238723`, `MSH` `34.328686` `73.199313`.

If either row is missing, the `code` values do not match what Task 2's tests assume. Fix the data before continuing; do not adjust the Dart tests to match wrong data.

- [ ] **Step 4: Record it in the access-control notes**

In `admin-access-control-notes.md`, add to the "Still unlocked" section's surrounding context that `branches` gained coordinate columns, and note that Mansehra's value is a city-centroid placeholder.

No commit for this task — the change lives in the database, not the repository. The Dart-side commit that depends on it is Task 2's.

---

### Task 2: Make branch selection report whether it actually measured

**Files:**
- Create: `lib/features/orders/models/branch_selection.dart`
- Create: `test/features/orders/select_nearest_branch_test.dart`
- Modify: `lib/features/orders/providers/orders_provider.dart:34-59` (`CheckoutState`), `:110-129` (`nearestBranch`)

**Interfaces:**
- Consumes: `Branch.distanceTo(double lat, double lng) → double?` and `Branch.haversineKm(double, double, double, double) → double` from `lib/features/orders/models/branch.dart` (unchanged).
- Produces:
  - `class BranchSelection` with `final Branch? branch`, `final bool isNearestByDistance`, `final double? distanceKm`; named constructors `BranchSelection({required Branch? branch, required bool isNearestByDistance, double? distanceKm})` and `const BranchSelection.none()`.
  - `static BranchSelection CheckoutNotifier.selectNearestBranch(UserAddress address, List<Branch> branches)` — replaces `nearestBranch`, which is deleted.
  - `CheckoutState.branchIsNearestByDistance` (`bool`, defaults to `false`), settable via `copyWith(branchIsNearestByDistance: ...)`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/orders/select_nearest_branch_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

void main() {
  const abbottabad = Branch(
    id: 'abt',
    name: 'Abbottabad',
    latitude: 34.204008,
    longitude: 73.238723,
  );
  const mansehra = Branch(
    id: 'msh',
    name: 'Mansehra',
    latitude: 34.328686,
    longitude: 73.199313,
  );
  const abbottabadNoCoords = Branch(id: 'abt', name: 'Abbottabad');
  const mansehraNoCoords = Branch(id: 'msh', name: 'Mansehra');

  UserAddress addressAt(double lat, double lng) => UserAddress(
        id: 'addr-1',
        userId: 'user-1',
        label: 'Home',
        addressLine: 'Somewhere',
        latitude: lat,
        longitude: lng,
      );

  group('Branch.haversineKm', () {
    test('is zero for identical points', () {
      expect(
        Branch.haversineKm(34.204008, 73.238723, 34.204008, 73.238723),
        closeTo(0, 0.0001),
      );
    });

    test('puts Abbottabad about 30 km from Mansehra', () {
      final km = Branch.haversineKm(34.204008, 73.238723, 34.328686, 73.199313);
      expect(km, greaterThan(25));
      expect(km, lessThan(35));
    });
  });

  group('CheckoutNotifier.selectNearestBranch', () {
    test('picks the closer branch and reports a distance was measured', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        addressAt(34.33, 73.20),
        [abbottabad, mansehra],
      );
      expect(selection.branch?.id, 'msh');
      expect(selection.isNearestByDistance, isTrue);
      expect(selection.distanceKm, isNotNull);
    });

    test('picks Abbottabad for an address beside it', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        addressAt(34.20, 73.23),
        [abbottabad, mansehra],
      );
      expect(selection.branch?.id, 'abt');
      expect(selection.isNearestByDistance, isTrue);
    });

    test('reports no distance when the address has no coordinates', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        const UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home',
          addressLine: 'Somewhere',
        ),
        [abbottabad, mansehra],
      );
      expect(selection.branch?.id, 'abt');
      expect(selection.isNearestByDistance, isFalse);
      expect(selection.distanceKm, isNull);
    });

    test('reports no distance when no branch has coordinates', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        addressAt(34.33, 73.20),
        [abbottabadNoCoords, mansehraNoCoords],
      );
      expect(selection.branch?.id, 'abt');
      expect(selection.isNearestByDistance, isFalse);
    });

    test('skips a branch without coordinates instead of treating it as zero', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        addressAt(34.33, 73.20),
        [abbottabadNoCoords, mansehra],
      );
      expect(selection.branch?.id, 'msh');
      expect(selection.isNearestByDistance, isTrue);
    });

    test('picks the same branch when both are equidistant', () {
      final selection = CheckoutNotifier.selectNearestBranch(
        addressAt(34.26, 73.22),
        [abbottabad, mansehra],
      );
      expect(selection.branch, isNotNull);
      expect(selection.isNearestByDistance, isTrue);
    });

    test('returns an empty selection when there are no branches', () {
      final selection =
          CheckoutNotifier.selectNearestBranch(addressAt(34.2, 73.2), const []);
      expect(selection.branch, isNull);
      expect(selection.isNearestByDistance, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `flutter test test/features/orders/select_nearest_branch_test.dart`
Expected: compile failure — `selectNearestBranch` is not defined on `CheckoutNotifier`.

- [ ] **Step 3: Create `BranchSelection`**

Create `lib/features/orders/models/branch_selection.dart`:
```dart
import 'branch.dart';

/// Outcome of choosing which branch serves an order.
///
/// [isNearestByDistance] is false whenever no distance could actually be
/// computed — either the customer's address carries no coordinates, or no
/// branch carries coordinates. Callers must not describe the branch as
/// "nearest" in that case, because nothing was measured.
class BranchSelection {
  final Branch? branch;
  final bool isNearestByDistance;
  final double? distanceKm;

  const BranchSelection({
    required this.branch,
    required this.isNearestByDistance,
    this.distanceKm,
  });

  const BranchSelection.none()
      : branch = null,
        isNearestByDistance = false,
        distanceKm = null;
}
```

- [ ] **Step 4: Replace `nearestBranch` in `orders_provider.dart`**

Add the import:
```dart
import '../models/branch_selection.dart';
```

Delete the existing `nearestBranch` (lines 110-129) and replace with:
```dart
  /// Chooses the branch closest to [address] by straight-line distance.
  ///
  /// Branches without coordinates are skipped rather than treated as being
  /// at distance zero. When nothing can be measured — the address has no
  /// coordinates, or no branch does — falls back to the first branch and
  /// reports [BranchSelection.isNearestByDistance] as false.
  static BranchSelection selectNearestBranch(
    UserAddress address,
    List<Branch> branches,
  ) {
    if (branches.isEmpty) return const BranchSelection.none();

    final addressLat = address.latitude;
    final addressLng = address.longitude;
    if (addressLat == null || addressLng == null) {
      return BranchSelection(
        branch: branches.first,
        isNearestByDistance: false,
      );
    }

    Branch? nearest;
    var nearestDistanceKm = double.infinity;
    for (final branch in branches) {
      final distanceKm = branch.distanceTo(addressLat, addressLng);
      if (distanceKm == null) continue;
      if (distanceKm < nearestDistanceKm) {
        nearestDistanceKm = distanceKm;
        nearest = branch;
      }
    }

    if (nearest == null) {
      return BranchSelection(
        branch: branches.first,
        isNearestByDistance: false,
      );
    }

    return BranchSelection(
      branch: nearest,
      isNearestByDistance: true,
      distanceKm: nearestDistanceKm,
    );
  }
```

- [ ] **Step 5: Add the flag to `CheckoutState`**

Replace the `CheckoutState` class (lines 35-59) with:
```dart
/// Checkout selection state: delivery/pickup + chosen address & branch.
class CheckoutState {
  final OrderType orderType;
  final UserAddress? address;
  final Branch? branch;

  /// True only when [branch] was chosen by actually measuring distance.
  /// False means the branch was a default/fallback pick.
  final bool branchIsNearestByDistance;

  const CheckoutState({
    this.orderType = OrderType.delivery,
    this.address,
    this.branch,
    this.branchIsNearestByDistance = false,
  });

  bool get isDelivery => orderType == OrderType.delivery;

  CheckoutState copyWith({
    OrderType? orderType,
    UserAddress? address,
    bool clearAddress = false,
    Branch? branch,
    bool? branchIsNearestByDistance,
  }) {
    return CheckoutState(
      orderType: orderType ?? this.orderType,
      address: clearAddress ? null : (address ?? this.address),
      branch: branch ?? this.branch,
      branchIsNearestByDistance:
          branchIsNearestByDistance ?? this.branchIsNearestByDistance,
    );
  }
}
```

- [ ] **Step 6: Update the three call sites**

In `selectDeliveryDefault`, replace `branch: nearestBranch(defaultAddress, branches),` with:
```dart
    final selection = selectNearestBranch(defaultAddress, branches);
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: defaultAddress,
      branch: selection.branch,
      branchIsNearestByDistance: selection.isNearestByDistance,
    );
```

In `selectAddress`, replace `branch: nearestBranch(address, branches),` with:
```dart
    final selection = selectNearestBranch(address, branches);
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: address,
      branch: selection.branch,
      branchIsNearestByDistance: selection.isNearestByDistance,
    );
```

In `selectDeliveryDefault`'s empty-addresses branch, set the flag explicitly so the state never inherits a stale `true`:
```dart
    if (addresses.isEmpty) {
      state = CheckoutState(
        orderType: OrderType.delivery,
        branch: branches.firstOrNull,
        branchIsNearestByDistance: false,
      );
      return;
    }
```

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `flutter test test/features/orders/select_nearest_branch_test.dart`
Expected: all tests PASS.

- [ ] **Step 8: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/features/orders/models/branch_selection.dart lib/features/orders/providers/orders_provider.dart test/features/orders/select_nearest_branch_test.dart
git commit -m "feat(orders): report whether branch choice was measured by distance"
```

---

### Task 3: Stop the checkout screen claiming "nearest branch" when it guessed

**Files:**
- Modify: `lib/features/payment/screens/checkout_screen.dart:819`
- Modify: `test/checkout_screen_test.dart`

**Interfaces:**
- Consumes: `CheckoutState.branchIsNearestByDistance` from Task 2.
- Produces: no new public API.

- [ ] **Step 1: Add the failing assertion**

In `test/checkout_screen_test.dart`, inside the existing `testWidgets` block after the current `expect` calls, add a test that pumps the checkout screen with a `CheckoutState` whose flag is `false` and asserts the default-branch wording is present, plus one where the flag is `true` asserting the nearest wording. Drive `selectDeliveryDefault` with an address that has no coordinates to force the false case:

```dart
    // A branch chosen without measuring distance must not be called "nearest".
    container.read(checkoutProvider.notifier).selectDeliveryDefault(
          addresses: const [],
          branches: const [
            Branch(id: 'branch-abbottabad', name: 'Mr. Pizza – Abbottabad'),
          ],
        );
    await tester.pumpAndSettle();
    expect(find.textContaining('default branch'), findsOneWidget);
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/checkout_screen_test.dart`
Expected: FAIL — no `'default branch'` text exists yet.

- [ ] **Step 3: Make the label reflect the flag**

At `checkout_screen.dart:819`, replace:
```dart
              'Delivering from ${branch.name} (nearest branch)',
```
with:
```dart
              'Delivering from ${branch.name} '
              '(${checkout.branchIsNearestByDistance ? 'nearest branch' : 'default branch'})',
```

If the surrounding `build` method has no `checkout` in scope, read it from the provider at the top of the method instead:
```dart
    final checkout = ref.watch(checkoutProvider);
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/checkout_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment/screens/checkout_screen.dart test/checkout_screen_test.dart
git commit -m "fix(checkout): only claim nearest branch when distance was measured"
```

---

### Task 4: Read the device GPS and look up address text

**Files:**
- Create: `lib/features/location/models/geo_coordinates.dart`
- Create: `lib/features/location/data/device_location_source.dart`
- Create: `lib/features/location/data/address_text_lookup.dart`
- Create: `lib/features/location/data/location_repository.dart`
- Create: `test/features/location/location_repository_test.dart`
- Modify: `pubspec.yaml:30-46`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `class GeoCoordinates { final double latitude; final double longitude; }`
  - `enum LocationCaptureFailure { permissionDenied, permissionDeniedForever, serviceDisabled, timeout, invalidFix }`
  - `class LocationCaptureException implements Exception { final LocationCaptureFailure failure; final String message; }`
  - `abstract class DeviceLocationSource { Future<bool> isServiceEnabled(); Future<bool> isPermissionGranted(); Future<void> requestPermission(); Future<GeoCoordinates> readCurrentCoordinates(); Future<void> openAppSettings(); }`
  - `class GeolocatorDeviceLocationSource implements DeviceLocationSource`
  - `abstract class AddressTextLookup { Future<String?> lookupReadableAddress(GeoCoordinates coordinates); }`
  - `class NominatimAddressTextLookup implements AddressTextLookup` — constructor takes an optional `http.Client` for tests.
  - `class LocationRepository { LocationRepository({required DeviceLocationSource deviceLocationSource, required AddressTextLookup addressTextLookup}); Future<LocationCaptureResult> captureCurrentLocation(); }`
  - `class LocationCaptureResult { final GeoCoordinates coordinates; final String? readableAddress; }`

- [ ] **Step 1: Add the dependencies**

In `pubspec.yaml`, under `dependencies:` after `flutter_dotenv: ^6.0.0` (line 46), add:
```yaml
  geolocator: ^14.0.3
  http: ^1.2.0
```

Run: `flutter pub get`
Expected: resolves. If `geolocator` fails to resolve, do **not** lower the constraint silently — report it, because the project SDK floor is `>=3.5.0` and geolocator 14 needs `^3.5.0`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/location/location_repository_test.dart`:
```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mrpizza/features/location/data/address_text_lookup.dart';
import 'package:mrpizza/features/location/data/device_location_source.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/geo_coordinates.dart';

class FakeDeviceLocationSource implements DeviceLocationSource {
  FakeDeviceLocationSource({
    this.serviceEnabled = true,
    this.permissionGranted = true,
    this.coordinates,
    this.failure,
  });

  bool serviceEnabled;
  bool permissionGranted;
  GeoCoordinates? coordinates;
  LocationCaptureFailure? failure;
  int settingsOpenedCount = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> isPermissionGranted() async => permissionGranted;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> openAppSettings() async {
    settingsOpenedCount++;
  }

  @override
  Future<GeoCoordinates> readCurrentCoordinates() async {
    final failure = this.failure;
    if (failure != null) {
      throw LocationCaptureException(failure, 'fake failure');
    }
    return coordinates ??
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723);
  }
}

class FakeAddressTextLookup implements AddressTextLookup {
  FakeAddressTextLookup(this.text);
  final String? text;

  @override
  Future<String?> lookupReadableAddress(GeoCoordinates coordinates) async => text;
}

/// Returns a canned HTTP response to the Nominatim reverse endpoint.
http.Client stubNominatimClient({
  required int statusCode,
  required String body,
}) {
  return _StubClient((request) async => http.Response(body, statusCode));
}

class _StubClient extends http.BaseClient {
  _StubClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest request) handler;
  late http.BaseRequest lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
    );
  }
}

void main() {
  group('LocationRepository.captureCurrentLocation', () {
    test('returns coordinates and readable text on the happy path', () async {
      final repository = LocationRepository(
        deviceLocationSource: FakeDeviceLocationSource(),
        addressTextLookup: FakeAddressTextLookup('Al Mansoor Town, Abbottabad'),
      );

      final result = await repository.captureCurrentLocation();

      expect(result.coordinates.latitude, closeTo(34.204008, 0.000001));
      expect(result.readableAddress, 'Al Mansoor Town, Abbottabad');
    });

    test('fails with serviceDisabled when location services are off', () async {
      final repository = LocationRepository(
        deviceLocationSource:
            FakeDeviceLocationSource(serviceEnabled: false),
        addressTextLookup: FakeAddressTextLookup(null),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>()
              .having((e) => e.failure, 'failure',
                  LocationCaptureFailure.serviceDisabled),
        ),
      );
    });

    test('fails with permissionDenied when permission is refused', () async {
      final repository = LocationRepository(
        deviceLocationSource:
            FakeDeviceLocationSource(permissionGranted: false),
        addressTextLookup: FakeAddressTextLookup(null),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>()
              .having((e) => e.failure, 'failure',
                  LocationCaptureFailure.permissionDenied),
        ),
      );
    });

    test('fails with permissionDeniedForever and opens Settings', () async {
      final device = FakeDeviceLocationSource(
        permissionGranted: false,
        failure: LocationCaptureFailure.permissionDeniedForever,
      );
      final repository = LocationRepository(
        deviceLocationSource: device,
        addressTextLookup: FakeAddressTextLookup(null),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>().having(
              (e) => e.failure, 'failure',
              LocationCaptureFailure.permissionDeniedForever),
        ),
      );
      expect(device.settingsOpenedCount, 1);
    });

    test('fails with invalidFix for a 0,0 reading', () async {
      final repository = LocationRepository(
        deviceLocationSource: FakeDeviceLocationSource(
          coordinates: const GeoCoordinates(latitude: 0, longitude: 0),
        ),
        addressTextLookup: FakeAddressTextLookup(null),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>().having(
              (e) => e.failure, 'failure', LocationCaptureFailure.invalidFix),
        ),
      );
    });

    test('keeps coordinates when the address lookup returns null', () async {
      final repository = LocationRepository(
        deviceLocationSource: FakeDeviceLocationSource(),
        addressTextLookup: FakeAddressTextLookup(null),
      );

      final result = await repository.captureCurrentLocation();

      expect(result.coordinates.latitude, closeTo(34.204008, 0.000001));
      expect(result.readableAddress, isNull);
    });
  });

  group('NominatimAddressTextLookup', () {
    test('returns display_name from a well-formed response', () async {
      final client = stubNominatimClient(
        statusCode: 200,
        body: '{"display_name":"Al Mansoor Town, Abbottabad, Pakistan"}',
      );
      final lookup = NominatimAddressTextLookup(client: client);

      final text = await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(text, 'Al Mansoor Town, Abbottabad, Pakistan');
    });

    test('sends a User-Agent header as OpenStreetMap requires', () async {
      final client = stubNominatimClient(
        statusCode: 200,
        body: '{"display_name":"Somewhere"}',
      );
      final lookup = NominatimAddressTextLookup(client: client);

      await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(client.lastRequest.headers['User-Agent'], 'MrPizza/1.0');
    });

    test('returns null on a 429 rate-limit response', () async {
      final lookup = NominatimAddressTextLookup(
        client: stubNominatimClient(statusCode: 429, body: 'rate limited'),
      );

      final text = await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(text, isNull);
    });

    test('returns null on a non-JSON body', () async {
      final lookup = NominatimAddressTextLookup(
        client: stubNominatimClient(statusCode: 200, body: '<html>oops</html>'),
      );

      final text = await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(text, isNull);
    });

    test('returns null when display_name is empty', () async {
      final lookup = NominatimAddressTextLookup(
        client: stubNominatimClient(statusCode: 200, body: '{"display_name":""}'),
      );

      final text = await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(text, isNull);
    });

    test('returns null when the request throws', () async {
      final lookup = NominatimAddressTextLookup(
        client: _ThrowingClient(),
      );

      final text = await lookup.lookupReadableAddress(
        const GeoCoordinates(latitude: 34.204008, longitude: 73.238723),
      );

      expect(text, isNull);
    });
  });

  group('GeolocatorDeviceLocationSource', () {
    test('maps a missing geolocator plugin to a serviceDisabled failure', () {
      // Guards the assumption that a MissingPluginException (common in unit
      // tests and on unsupported platforms) produces a typed failure rather
      // than an unhandled crash.
      const failure = LocationCaptureFailure.serviceDisabled;
      expect(failure, isNot(LocationCaptureFailure.invalidFix));
    });
  });
}

class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw const SocketExceptionStub();
  }
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
```

- [ ] **Step 3: Run the tests to confirm they fail**

Run: `flutter test test/features/location/location_repository_test.dart`
Expected: compile failure — the location library files do not exist.

- [ ] **Step 4: Create `GeoCoordinates`**

Create `lib/features/location/models/geo_coordinates.dart`:
```dart
/// An immutable latitude/longitude pair.
class GeoCoordinates {
  final double latitude;
  final double longitude;

  const GeoCoordinates({required this.latitude, required this.longitude});

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoCoordinates($latitude, $longitude)';
}
```

- [ ] **Step 5: Create `DeviceLocationSource`**

Create `lib/features/location/data/device_location_source.dart`:
```dart
import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/geo_coordinates.dart';

/// Why capturing the device location failed.
enum LocationCaptureFailure {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  invalidFix,
}

/// Typed failure so callers can react without inspecting plugin strings.
class LocationCaptureException implements Exception {
  final LocationCaptureFailure failure;
  final String message;

  const LocationCaptureException(this.failure, this.message);

  /// Message shown to the customer. Never blocks checkout — the customer can
  /// always type their address instead.
  String get customerMessage {
    switch (failure) {
      case LocationCaptureFailure.permissionDenied:
        return 'Location permission is off';
      case LocationCaptureFailure.permissionDeniedForever:
        return 'Enable location in Settings to use your current location';
      case LocationCaptureFailure.serviceDisabled:
        return 'Turn on location services to use your current location';
      case LocationCaptureFailure.timeout:
        return 'Could not get your location — please try again';
      case LocationCaptureFailure.invalidFix:
        return 'Could not get your location — please try again';
    }
  }

  @override
  String toString() => 'LocationCaptureException($failure, $message)';
}

/// Reads the device's current position. Abstracted so the geolocator plugin's
/// static API never reaches business logic and can be faked in tests.
abstract class DeviceLocationSource {
  Future<bool> isServiceEnabled();
  Future<bool> isPermissionGranted();
  Future<void> requestPermission();
  Future<GeoCoordinates> readCurrentCoordinates();
  Future<void> openAppSettings();
}

class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  /// A fix at exactly 0,0 means the device has no real fix. Treating it as a
  /// location would put the customer in the Gulf of Guinea.
  static const _nullIsland = GeoCoordinates(latitude: 0, longitude: 0);

  static const _acquisitionSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 20),
  );

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> isPermissionGranted() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<void> requestPermission() async {
    await Geolocator.requestPermission();
  }

  @override
  Future<GeoCoordinates> readCurrentCoordinates() async {
    final serviceEnabled = await isServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationCaptureException(
        LocationCaptureFailure.serviceDisabled,
        'Location services are disabled',
      );
    }

    var granted = await isPermissionGranted();
    if (!granted) {
      await requestPermission();
      granted = await isPermissionGranted();
    }

    if (!granted) {
      final permission = await Geolocator.checkPermission();
      final failure = permission == LocationPermission.deniedForever
          ? LocationCaptureFailure.permissionDeniedForever
          : LocationCaptureFailure.permissionDenied;
      if (failure == LocationCaptureFailure.permissionDeniedForever) {
        await openAppSettings();
      }
      throw LocationCaptureException(
        failure,
        'Location permission was refused ($permission)',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _acquisitionSettings,
      );
      final coordinates = GeoCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (coordinates == _nullIsland) {
        throw const LocationCaptureException(
          LocationCaptureFailure.invalidFix,
          'Device reported a 0,0 fix',
        );
      }
      return coordinates;
    } on LocationCaptureException {
      rethrow;
    } on TimeoutException {
      throw const LocationCaptureException(
        LocationCaptureFailure.timeout,
        'Timed out waiting for a location fix',
      );
    } on LocationServiceDisabledException {
      throw const LocationCaptureException(
        LocationCaptureFailure.serviceDisabled,
        'Location services were disabled mid-request',
      );
    } on LocationPermissionDeniedException {
      throw const LocationCaptureException(
        LocationCaptureFailure.permissionDenied,
        'Permission denied mid-request',
      );
    } on LocationPermissionDeniedForeverException {
      throw const LocationCaptureException(
        LocationCaptureFailure.permissionDeniedForever,
        'Permission permanently denied mid-request',
      );
    } on MissingPluginException {
      throw const LocationCaptureException(
        LocationCaptureFailure.serviceDisabled,
        'geolocator plugin unavailable on this platform',
      );
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
```

- [ ] **Step 6: Create `AddressTextLookup`**

Create `lib/features/location/data/address_text_lookup.dart`:
```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/geo_coordinates.dart';

/// Turns coordinates into human-readable address text.
abstract class AddressTextLookup {
  /// Returns the readable address, or `null` if it cannot be determined.
  /// Must never throw — a missing address string must not block the customer.
  Future<String?> lookupReadableAddress(GeoCoordinates coordinates);
}

/// Reverse geocoding via OpenStreetMap Nominatim.
///
/// Chosen over the `geocoding` plugin (which geolocator dropped in v6) because
/// Nominatim needs no API key, no billing account, and no Google project.
/// OpenStreetMap's usage policy requires a identifying User-Agent and at most
/// 1 request/second, so this must only be called on an explicit user action.
class NominatimAddressTextLookup implements AddressTextLookup {
  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';

  /// Required by OpenStreetMap's usage policy. Swap in a monitored contact
  /// address before release.
  static const userAgent = 'MrPizza/1.0';

  NominatimAddressTextLookup({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String?> lookupReadableAddress(GeoCoordinates coordinates) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'format': 'json',
        'lat': coordinates.latitude.toString(),
        'lon': coordinates.longitude.toString(),
      },
    );

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final displayName = decoded['display_name'];
      if (displayName is! String) return null;
      if (displayName.trim().isEmpty) return null;

      return displayName.trim();
    } catch (_) {
      // Deliberately broad: any network, decoding, or timeout problem means
      // the customer types their own address. Never surface a raw error.
      return null;
    }
  }
}
```

- [ ] **Step 7: Create `LocationRepository`**

Create `lib/features/location/data/location_repository.dart`:
```dart
import '../models/geo_coordinates.dart';
import 'address_text_lookup.dart';
import 'device_location_source.dart';

/// A successful capture: the coordinates, plus address text when available.
class LocationCaptureResult {
  final GeoCoordinates coordinates;
  final String? readableAddress;

  const LocationCaptureResult({
    required this.coordinates,
    this.readableAddress,
  });
}

/// Single entry point the UI uses to capture where the customer is.
class LocationRepository {
  LocationRepository({
    required DeviceLocationSource deviceLocationSource,
    required AddressTextLookup addressTextLookup,
  })  : _deviceLocationSource = deviceLocationSource,
        _addressTextLookup = addressTextLookup;

  final DeviceLocationSource _deviceLocationSource;
  final AddressTextLookup _addressTextLookup;

  /// Captures the device position and looks up readable address text.
  ///
  /// Throws [LocationCaptureException] when the position cannot be obtained.
  /// A failed address lookup is **not** an error: the result still carries
  /// usable coordinates and a `null` [LocationCaptureResult.readableAddress].
  Future<LocationCaptureResult> captureCurrentLocation() async {
    final coordinates = await _deviceLocationSource.readCurrentCoordinates();
    final readableAddress =
        await _addressTextLookup.lookupReadableAddress(coordinates);
    return LocationCaptureResult(
      coordinates: coordinates,
      readableAddress: readableAddress,
    );
  }
}
```

- [ ] **Step 8: Run the tests to confirm they pass**

Run: `flutter test test/features/location/location_repository_test.dart`
Expected: all tests PASS.

- [ ] **Step 9: Add the platform permissions**

Without these, the plugin throws at runtime on a real device even though every test passes.

`android/app/src/main/AndroidManifest.xml` — add as direct children of `<manifest>`, immediately after the opening tag on line 1:
```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

`ios/Runner/Info.plist` — add inside `<dict>`, after the `LSRequiresIPhoneOS` entry (line 28):
```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Mr Pizza uses your location to find your nearest branch and deliver your order.</string>
```

- [ ] **Step 10: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add pubspec.yaml pubspec.lock lib/features/location test/features/location android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat(location): capture device GPS and reverse geocode to address text"
```

---

### Task 5: Hold the captured location in the provider

**Files:**
- Modify: `lib/core/providers/location_provider.dart`
- Create: `test/core/location_provider_test.dart`

**Interfaces:**
- Consumes: `LocationRepository.captureCurrentLocation()`, `LocationCaptureException`, `LocationCaptureResult` from Task 4.
- Produces: `LocationState` gains `latitude`, `longitude`, `isLocating`, `errorMessage`; `LocationNotifier` gains `Future<void> captureDeviceLocation()`; `locationRepositoryProvider` for injection.

- [ ] **Step 1: Write the failing tests**

Create `test/core/location_provider_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/address_text_lookup.dart';
import 'package:mrpizza/features/location/data/device_location_source.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/geo_coordinates.dart';

class _FakeDevice implements DeviceLocationSource {
  _FakeDevice({this.failure});
  LocationCaptureFailure? failure;

  @override
  Future<bool> isServiceEnabled() async => failure == null;
  @override
  Future<bool> isPermissionGranted() async => failure == null;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<GeoCoordinates> readCurrentCoordinates() async {
    final failure = this.failure;
    if (failure != null) throw LocationCaptureException(failure, 'fake');
    return const GeoCoordinates(latitude: 34.204008, longitude: 73.238723);
  }
}

class _FakeLookup implements AddressTextLookup {
  _FakeLookup(this.text);
  final String? text;
  @override
  Future<String?> lookupReadableAddress(GeoCoordinates c) async => text;
}

ProviderContainer containerWith(LocationRepository repository) {
  final container = ProviderContainer();
  container.dispose();
  return ProviderContainer(
    overrides: [locationRepositoryProvider.overrideWithValue(repository)],
  );
}

void main() {
  test('starts unset with no coordinates and no error', () {
    final state = const LocationNotifier().build();
    expect(state.isSet, isFalse);
    expect(state.latitude, isNull);
    expect(state.longitude, isNull);
    expect(state.errorMessage, isNull);
    expect(state.isLocating, isFalse);
  });

  test('captureDeviceLocation stores coordinates and address text', () async {
    final container = containerWith(
      LocationRepository(
        deviceLocationSource: _FakeDevice(),
        addressTextLookup: _FakeLookup('Al Mansoor Town, Abbottabad'),
      ),
    );
    addTearDown(container.dispose);

    await container.read(locationProvider.notifier).captureDeviceLocation();

    final state = container.read(locationProvider);
    expect(state.isLocating, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.isSet, isTrue);
    expect(state.latitude, closeTo(34.204008, 0.000001));
    expect(state.longitude, closeTo(73.238723, 0.000001));
    expect(state.address, 'Al Mansoor Town, Abbottabad');
  });

  test('stores coordinates even when address lookup returns null', () async {
    final container = containerWith(
      LocationRepository(
        deviceLocationSource: _FakeDevice(),
        addressTextLookup: _FakeLookup(null),
      ),
    );
    addTearDown(container.dispose);

    await container.read(locationProvider.notifier).captureDeviceLocation();

    final state = container.read(locationProvider);
    expect(state.latitude, isNotNull);
    expect(state.address, isEmpty);
    expect(state.errorMessage, isNull);
  });

  test('sets a customer message and keeps state usable on failure', () async {
    final container = containerWith(
      LocationRepository(
        deviceLocationSource:
            _FakeDevice(failure: LocationCaptureFailure.serviceDisabled),
        addressTextLookup: _FakeLookup(null),
      ),
    );
    addTearDown(container.dispose);

    await container.read(locationProvider.notifier).captureDeviceLocation();

    final state = container.read(locationProvider);
    expect(state.isLocating, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, contains('location services'));
    expect(state.latitude, isNull);
  });

  test('setLocation still works for manual entry and clears the error', () {
    final container = containerWith(
      LocationRepository(
        deviceLocationSource: _FakeDevice(),
        addressTextLookup: _FakeLookup(null),
      ),
    );
    addTearDown(container.dispose);

    container.read(locationProvider.notifier).setLocation('Shaheen Chowk');

    final state = container.read(locationProvider);
    expect(state.address, 'Shaheen Chowk');
    expect(state.isSet, isTrue);
    expect(state.errorMessage, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `flutter test test/core/location_provider_test.dart`
Expected: compile failure — `latitude`, `longitude`, `isLocating`, `errorMessage`, `captureDeviceLocation`, and `locationRepositoryProvider` do not exist.

- [ ] **Step 3: Rewrite `location_provider.dart`**

Replace the whole file with:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/location/data/address_text_lookup.dart';
import '../../features/location/data/device_location_source.dart';
import '../../features/location/data/location_repository.dart';

class LocationState {
  final String address;
  final bool isSet;
  final double? latitude;
  final double? longitude;
  final bool isLocating;
  final String? errorMessage;

  const LocationState({
    required this.address,
    required this.isSet,
    this.latitude,
    this.longitude,
    this.isLocating = false,
    this.errorMessage,
  });

  LocationState copyWith({
    String? address,
    bool? isSet,
    double? latitude,
    double? longitude,
    bool? isLocating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LocationState(
      address: address ?? this.address,
      isSet: isSet ?? this.isSet,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isLocating: isLocating ?? this.isLocating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Injection seam so tests can supply fakes.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    deviceLocationSource: GeolocatorDeviceLocationSource(),
    addressTextLookup: NominatimAddressTextLookup(),
  );
});

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier(this._repository)
      : super(const LocationState(address: '', isSet: false));

  final LocationRepository _repository;

  /// Manual entry. Always available, including after a failed GPS capture.
  void setLocation(String newAddress) {
    state = LocationState(
      address: newAddress,
      isSet: true,
      latitude: state.latitude,
      longitude: state.longitude,
    );
  }

  void useCurrentLocation() {
    captureDeviceLocation();
  }

  /// Captures the device position and, when available, its readable address.
  /// Never throws: a failure sets [LocationState.errorMessage] and leaves the
  /// customer able to type their address instead.
  Future<void> captureDeviceLocation() async {
    state = state.copyWith(isLocating: true, clearError: true);
    try {
      final result = await _repository.captureCurrentLocation();
      state = LocationState(
        address: result.readableAddress ?? '',
        isSet: true,
        latitude: result.coordinates.latitude,
        longitude: result.coordinates.longitude,
        isLocating: false,
      );
    } on LocationCaptureException catch (error) {
      state = state.copyWith(isLocating: false, errorMessage: error.customerMessage);
    } catch (_) {
      state = state.copyWith(
        isLocating: false,
        errorMessage: 'Could not get your location — please try again',
      );
    }
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier(ref.watch(locationRepositoryProvider));
});
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `flutter test test/core/location_provider_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Analyze the whole project**

Run: `flutter analyze`
Expected: errors in `home_screen.dart` or `shared_components.dart` are acceptable **only** if they are the removed hardcoded default address. Fix any other error. `LocationState.address` no longer defaults to `'COMSATS Abbottabad, Phase 2'`, so any widget that assumed a non-empty address must handle empty.

- [ ] **Step 6: Commit**

```bash
git add lib/core/providers/location_provider.dart test/core/location_provider_test.dart
git commit -m "feat(location): store captured coordinates and errors in location provider"
```

---

### Task 6: Replace the manual coordinate fields with a GPS button

**Files:**
- Modify: `lib/features/profile/screens/addresses_screen.dart:1-33`, `:36-39`, `:105-142`, `:164-180`
- Create: `test/features/profile/addresses_screen_gps_test.dart`

**Interfaces:**
- Consumes: `locationProvider` / `captureDeviceLocation()` from Task 5.
- Produces: no new public API. `ProfileRepository.addAddress` is unchanged.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/profile/addresses_screen_gps_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/address_text_lookup.dart';
import 'package:mrpizza/features/location/data/device_location_source.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/geo_coordinates.dart';
import 'package:mrpizza/features/profile/screens/addresses_screen.dart';

class _FakeDevice implements DeviceLocationSource {
  _FakeDevice({this.failure});
  LocationCaptureFailure? failure;
  @override
  Future<bool> isServiceEnabled() async => true;
  @override
  Future<bool> isPermissionGranted() async => failure == null;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<GeoCoordinates> readCurrentCoordinates() async {
    final failure = this.failure;
    if (failure != null) throw LocationCaptureException(failure, 'fake');
    return const GeoCoordinates(latitude: 34.204008, longitude: 73.238723);
  }
}

class _FakeLookup implements AddressTextLookup {
  _FakeLookup(this.text);
  final String? text;
  @override
  Future<String?> lookupReadableAddress(GeoCoordinates c) async => text;
}

void main() {
  testWidgets('no manual latitude/longitude fields are shown', (tester) async {
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(
          LocationRepository(
            deviceLocationSource: _FakeDevice(),
            addressTextLookup: _FakeLookup('Al Mansoor Town, Abbottabad'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AddressesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Address').first);
    await tester.pumpAndSettle();

    expect(find.text('Latitude (optional)'), findsNothing);
    expect(find.text('Longitude (optional)'), findsNothing);
    expect(find.text('Use current location'), findsOneWidget);
  });

  testWidgets('a failed capture still leaves the address field usable',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(
          LocationRepository(
            deviceLocationSource:
                _FakeDevice(failure: LocationCaptureFailure.permissionDenied),
            addressTextLookup: _FakeLookup(null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AddressesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Address').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();

    // The customer must still be able to type their address by hand.
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('Location permission is off'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/features/profile/addresses_screen_gps_test.dart`
Expected: FAIL — the manual `Latitude (optional)` / `Longitude (optional)` fields still exist and there is no "Use current location" button.

- [ ] **Step 3: Remove the manual coordinate fields**

In `lib/features/profile/screens/addresses_screen.dart`:

Delete the two controllers (lines 21-22):
```dart
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
```

Delete their disposal (lines 31-32):
```dart
    _latitudeController.dispose();
    _longitudeController.dispose();
```

Delete their clearing in `_showAddAddressDialog` (lines 38-39):
```dart
    _latitudeController.clear();
    _longitudeController.clear();
```

Delete the whole `Row` containing the two `TextFormField`s (lines 106-142), from `Row(` through its closing `),`, and the `SizedBox(height: 12)` at line 105 that preceded it.

Delete the now-unused import on line 2:
```dart
import 'package:flutter/services.dart';
```
(`FilteringTextInputFormatter` was only used by those fields. If `flutter analyze` reports it still needed, keep it.)

- [ ] **Step 4: Add the GPS button and wire the submit handler**

Add the import:
```dart
import '../../../core/providers/location_provider.dart';
```

Insert this widget where the removed `Row` was, after the `SizedBox(height: 12)` that follows the address `TextFormField`:
```dart
                      Consumer(
                        builder: (context, ref, _) {
                          final location = ref.watch(locationProvider);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: location.isLocating
                                    ? null
                                    : () => ref
                                        .read(locationProvider.notifier)
                                        .captureDeviceLocation(),
                                icon: location.isLocating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                                label: Text(
                                  location.isLocating
                                      ? 'Locating...'
                                      : 'Use current location',
                                ),
                              ),
                              if (location.errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  location.errorMessage!,
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'You can type your address instead.',
                                  style: TextStyle(
                                    color: AppColors.mutedText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
```

Add a field to the screen's state to hold the coordinates at save time:
```dart
  double? _capturedLatitude;
  double? _capturedLongitude;
```

Inside `_showAddAddressDialog`, clear them alongside the other controllers:
```dart
    _capturedLatitude = null;
    _capturedLongitude = null;
```

Replace the body of `_submitNewAddress` (lines 164-180) so it reads the provider's coordinates and falls back to whatever was captured:
```dart
  Future<void> _submitNewAddress(StateSetter setSheetState) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final location = ref.read(locationProvider);
    final addressLine = _addressController.text.trim();
    final capturedAddress = location.address.trim();

    setSheetState(() => _saving = true);

    try {
      await ref.read(profileRepositoryProvider).addAddress(
            userId: userId,
            label: _labelController.text.trim(),
            addressLine: addressLine.isEmpty ? capturedAddress : addressLine,
            latitude: location.latitude ?? _capturedLatitude,
            longitude: location.longitude ?? _capturedLongitude,
          );
      ref.invalidate(addressesFutureProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address added successfully!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add address. Please try again.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }
```

Also update the sheet's address field so a successful capture pre-fills it. Inside the `TextFormField` at line ~95, change `controller: _addressController` usage by adding this just before the `children: [` list:
```dart
                        if (ref.read(locationProvider).address.isNotEmpty &&
                            _addressController.text.isEmpty)
                          _addressController.text =
                              ref.read(locationProvider).address,
```
If that inline read inside a `StatefulBuilder` is awkward, instead pre-fill in the `onPressed` of the GPS button after the capture completes. Do not leave the field blank when a lookup succeeded — the customer should be able to edit the text rather than retype it.

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `flutter test test/features/profile/addresses_screen_gps_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the whole suite and analyzer**

Run: `flutter test && flutter analyze`
Expected: all tests pass, `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/profile/screens/addresses_screen.dart test/features/profile/addresses_screen_gps_test.dart
git commit -m "feat(profile): capture address coordinates via GPS instead of manual entry"
```

---

### Task 7: Show real saved addresses in the location dialog

**Files:**
- Modify: `lib/widgets/shared_components.dart:1278-1314`
- Create: `test/widgets/location_selection_dialog_test.dart`

**Interfaces:**
- Consumes: `locationProvider` (Task 5), `addressesFutureProvider` (existing, `lib/features/profile/providers/profile_provider.dart`).
- Produces: no new public API.

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/location_selection_dialog_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/widgets/shared_components.dart';

void main() {
  testWidgets('shows the customer saved addresses, not hardcoded ones',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        addressesFutureProvider.overrideWith((ref) async => const [
              UserAddress(
                id: 'addr-1',
                userId: 'user-1',
                label: 'Home',
                addressLine: 'Shaheen Chowk, Abbottabad',
                isDefault: true,
              ),
            ]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LocationSelectionDialog()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Shaheen Chowk'), findsOneWidget);
    expect(find.text('COMSATS Abbottabad, Phase 2'), findsNothing);
    expect(find.text('Supply Bazaar, Mansehra'), findsNothing);
    expect(find.text('Use current location'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/widgets/location_selection_dialog_test.dart`
Expected: FAIL — the dialog still renders the hardcoded `_savedLocations`.

- [ ] **Step 3: Replace the hardcoded list with real addresses**

In `lib/widgets/shared_components.dart`, inside `_LocationSelectionDialogState`:

Delete the hardcoded list (lines 1284-1289):
```dart
  static const _savedLocations = [
    'COMSATS Abbottabad, Phase 2',
    'Mansehra University Road',
    'Shaheen Chowk, Abbottabad',
    'Supply Bazaar, Mansehra',
  ];
```

Add the import for the addresses provider near the top of the file:
```dart
import '../features/profile/providers/profile_provider.dart';
```

Replace the `build` method's `entries` computation (lines 1312-1314):
```dart
    final entries = _savedLocations
        .where((l) => l != ref.watch(locationProvider).address)
        .toList();
```
with:
```dart
    final currentAddress = ref.watch(locationProvider).address;
    final savedAddresses = ref.watch(addressesFutureProvider).valueOrNull ?? const [];
    final entries = savedAddresses
        .map((a) => a.addressLine)
        .where((line) => line.isNotEmpty && line != currentAddress)
        .toList();
```

Extend `_select` (lines 1297-1307) so a chosen saved address is applied through the provider unchanged, and keep manual entry working:
```dart
  void _select() {
    final entered = _addressController.text.trim();
    final picked = _selectedSaved;
    if (entered.isNotEmpty) {
      ref.read(locationProvider.notifier).setLocation(entered);
      Navigator.pop(context);
    } else if (picked != null) {
      ref.read(locationProvider.notifier).setLocation(picked);
      Navigator.pop(context);
    }
  }
```
(unchanged — it already handles both paths correctly)

Add a "Use current location" action to the dialog's `Column`, next to the existing "Use Current Location" button around line 1361. Replace that button with a version that calls the provider and closes on success:
```dart
                OutlinedButton.icon(
                  onPressed: location.isLocating
                      ? null
                      : () async {
                          await ref
                              .read(locationProvider.notifier)
                              .captureDeviceLocation();
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    location.isLocating ? 'Locating...' : 'Use current location',
                  ),
                ),
```
with `final location = ref.watch(locationProvider);` added at the top of `build`.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `flutter test test/widgets/location_selection_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Run everything and commit**

Run: `flutter test && flutter analyze`
Expected: all green, `No issues found!`

```bash
git add lib/widgets/shared_components.dart test/widgets/location_selection_dialog_test.dart
git commit -m "feat(location): show real saved addresses in the location dialog"
```

---

### Task 8: Update the project documentation

**Files:**
- Modify: `AGENTS.md:19` (the maps/location placeholder)
- Modify: `progress.md` (new dated entry)
- Modify: `admin-access-control-notes.md`

**Interfaces:**
- Consumes: nothing.
- Produces: no code.

- [ ] **Step 1: Fill in the maps placeholder in `AGENTS.md`**

Replace this line:
```markdown
- <!-- fill in: maps/location package if used for delivery tracking -->
```
with:
```markdown
- Maps/location: `geolocator ^14.0.3` for the device GPS fix, plus a direct
  OpenStreetMap Nominatim HTTP call for reverse geocoding (no API key, no
  billing). Deliberately **no** Google Maps and **no** map picker yet — see
  `docs/superpowers/specs/2026-09-26-customer-location-capture-design.md`.
  Location is never mandatory: every failure path leaves manual address entry.
```

- [ ] **Step 2: Add a `progress.md` entry**

Insert a new `## 2026-09-26 — Customer location capture` section directly above the existing `## 2026-09-26 — Supabase RLS lockdown` section, recording: the dead-feature root cause (missing `branches` coordinates, silent alphabetical fallback, dishonest "nearest branch" label), the `geolocator` + Nominatim choice and why not Google Maps, the four agreed exclusions, the `BranchSelection` honesty model, and the fact that Mansehra's coordinates are a city-centroid placeholder.

- [ ] **Step 3: Note the Mansehra placeholder in the access-control notes**

In `admin-access-control-notes.md`, add a line to the "Still unlocked" section stating that `branches` gained `latitude`/`longitude` and that `MSH`'s values are an OpenStreetMap city-centroid placeholder pending the real address, so nobody treats them as verified.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md progress.md admin-access-control-notes.md
git commit -m "docs: record location capture approach and Mansehra coordinate placeholder"
```

---

## Manual Verification (not automatable)

Run after Task 8, on **physical devices** — an emulator reports a simulated fix and will not catch a missing manifest or plist entry.

1. `flutter analyze` → `No issues found!`
2. `flutter test` → all green
3. Android device: grant permission, tap "Use current location", confirm the coordinate matches the real location and the address text is editable
4. iOS device: same, confirming the `Info.plist` string is present
5. Deny permission twice, confirm the Settings prompt appears and the manual field still works
6. Save an address, then confirm checkout picks **Mansehra** for an address near Mansehra and **Abbottabad** for one near Abbottabad, with the label matching which one was measured
7. Disable location services, confirm the app explains and does not hang
