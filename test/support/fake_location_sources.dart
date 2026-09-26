import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';

/// Stands in for the device GPS so location behaviour can be tested without a
/// real phone or the geolocator plugin.
class FakeDeviceLocationSource implements DeviceLocationSource {
  LocationPermissionOutcome permission;
  CapturedCoordinates? fix;
  Object? fixError;
  bool settingsOpened = false;

  FakeDeviceLocationSource({
    this.permission = LocationPermissionOutcome.granted,
    this.fix,
    this.fixError,
  });

  @override
  Future<LocationPermissionOutcome> ensurePermission() async => permission;

  @override
  Future<void> openAppSettings() async => settingsOpened = true;

  @override
  Future<CapturedCoordinates> readCurrentCoordinates() async {
    final error = fixError;
    if (error != null) throw error;
    return fix!;
  }
}

/// Stands in for OpenStreetMap reverse geocoding.
class FakeAddressTextLookup implements AddressTextLookup {
  String? result;
  Object? error;

  FakeAddressTextLookup({this.result, this.error});

  @override
  Future<String?> lookupAddressText(CapturedCoordinates coordinates) async {
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}
