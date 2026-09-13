import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocationState {
  final String address;
  final bool isSet;

  const LocationState({
    required this.address,
    required this.isSet,
  });

  LocationState copyWith({
    String? address,
    bool? isSet,
  }) {
    return LocationState(
      address: address ?? this.address,
      isSet: isSet ?? this.isSet,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier()
      : super(const LocationState(
          address: 'COMSATS Abbottabad, Phase 2',
          isSet: false,
        ));

  void setLocation(String newAddress) {
    state = LocationState(address: newAddress, isSet: true);
  }

  void useCurrentLocation() {
    state = const LocationState(
      address: 'COMSATS University, Abbottabad Campus',
      isSet: true,
    );
  }
}

final locationProvider = StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier();
});
