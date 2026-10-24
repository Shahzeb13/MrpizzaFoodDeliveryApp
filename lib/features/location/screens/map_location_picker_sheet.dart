import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;
// Flutter ships its own `Position` widget, which collides with the geometry
// type of the same name the SDK re-exports, so geometry is imported from `turf`.
import 'package:turf/turf.dart' as turf;

import '../../../core/config/mapbox_config.dart';
import '../../../core/geo/geo.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/providers/address_selection_provider.dart';
import '../data/delivery_area_options.dart';
import '../data/location_repository.dart';
import '../models/captured_location.dart';

/// Opens the delivery map as a modal sheet.
///
/// Returns true when the customer confirmed a location (which has already been
/// applied to the app's location state and stored), and null/false when they
/// backed out.
Future<bool?> showMapLocationPicker(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Critical: a draggable sheet wraps itself in a VerticalDragGestureRecognizer
    // that competes with the map's own pan/pinch recognisers in the gesture
    // arena. The map is a platform view, so it loses — the customer could drag
    // the sheet around but could not move the map. The sheet has its own
    // grabber and close button, so it does not need to be draggable.
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => const MapLocationPickerSheet(),
  );
}

/// The Mapbox delivery map, as a sheet over whatever asked for it.
///
/// The pin is a plain Flutter overlay sitting in the middle of the map area —
/// not an annotation attached to a coordinate — so it never moves while the map
/// does. Because the panel lives *below* the map rather than on top of it, the
/// map's own geometric centre is its camera centre, which is what makes "what
/// the pin is over" and "what gets confirmed" the same point with no padding
/// arithmetic to get wrong.
///
/// The customer can press "Locate me" or simply move the map by hand. Location
/// permission is never needed to use the map manually.
class MapLocationPickerSheet extends ConsumerStatefulWidget {
  const MapLocationPickerSheet({super.key});

  @override
  ConsumerState<MapLocationPickerSheet> createState() =>
      _MapLocationPickerSheetState();
}

class _MapLocationPickerSheetState
    extends ConsumerState<MapLocationPickerSheet> {
  /// Drives the animated camera moves (Locate me, saved places, cities).
  final _viewportController = ViewportController();

  final _landmarkController = TextEditingController();

  /// The point under the pin.
  ///
  /// In a [ValueNotifier] rather than [setState] because the camera reports a
  /// new centre on every frame of a drag. Only the pin, the summary line and
  /// the confirm button listen to it, so dragging the map never rebuilds the
  /// rest of the sheet.
  final ValueNotifier<CapturedCoordinates?> _point =
      ValueNotifier<CapturedCoordinates?>(null);

  /// True once the customer has typed in the address field, which stops the
  /// automatic fill from ever overwriting their own words.
  bool _landmarkEdited = false;

  /// The last address the lookup put in the field, so the next lookup knows
  /// whether the current text is ours to replace or belongs to the customer.
  String? _lastAutoFilledAddress;

  /// The name of the place the pin is currently on, or null before the first
  /// answer arrives and whenever the lookup found nothing.
  ///
  /// Display only and never stored: it describes the pin as it is right now, so
  /// keeping it past the next move would be showing a lie.
  String? _placeName;

  /// True once a lookup for the current pin has come back, whatever it said.
  ///
  /// Without it, the gap before the first lookup would be indistinguishable
  /// from a lookup that found nothing, and the card would claim "Unknown place"
  /// about a place nobody had asked about yet.
  bool _placeNameResolved = false;

  /// The pin the displayed name actually belongs to.
  ///
  /// The map reports a new centre as floating point on every idle, so two
  /// readings of an unmoved pin are never byte-identical. Comparing against this
  /// rather than against the last lookup is what stops a map that has stopped
  /// moving from starting a fresh lookup each time.
  CapturedCoordinates? _namedPoint;

  /// How far the pin must move before the name is looked up again.
  ///
  /// Mapbox answers "the shop at this point" for a whole neighbourhood of
  /// coordinates, so re-asking after a nudge spends requests to relearn the same
  /// answer — and made the card flicker between the name and "Finding
  /// location…". About a house front, which is the throttle this picker carried
  /// before the geocoder moved.
  static const double _minimumNameLookupMoveMetres = 30;

  /// The pin a place-name lookup is currently running for, or null.
  ///
  /// This doubles as the "Finding location…" flag and as the guard that a slow
  /// answer cannot overwrite a newer one — so it is compared against the pin
  /// rather than being a plain bool that has to be remembered to be cleared.
  CapturedCoordinates? _placeNameLookupInFlight;

  bool _isMapReady = false;
  bool _isLocating = false;
  bool _isSaving = false;
  String? _gpsErrorMessage;
  bool _gpsNeedsSettings = false;

  bool get _mapIsUsable => MapboxConfig.isUsable;

  @override
  void initState() {
    super.initState();
    // Open on whatever the customer already delivers to, so coming back to the
    // picker does not throw the view around. Their own description of the place
    // is carried over too — it is the text they typed for roughly this spot,
    // and re-typing it every time would be pointless.
    final existing = ref.read(locationProvider);
    if (existing.hasCoordinates) {
      _point.value = CapturedCoordinates(
        latitude: existing.latitude!,
        longitude: existing.longitude!,
      );
    }
    if (existing.address.trim().isNotEmpty) {
      _landmarkController.text = existing.address.trim();
    }
  }

  @override
  void dispose() {
    _viewportController.dispose();
    _landmarkController.dispose();
    _point.dispose();
    super.dispose();
  }

  /// Records the point under the pin without rebuilding the sheet.
  void _setPoint(double latitude, double longitude) {
    if (!CapturedCoordinates.isPlausibleEarth(latitude, longitude)) return;
    final current = _point.value;
    if (current != null &&
        current.latitude == latitude &&
        current.longitude == longitude) {
      return;
    }
    _point.value = CapturedCoordinates(
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// The address line that will be stored for this pick.
  String get _addressText => _landmarkController.text.trim();

  /// The place name to show under the pin.
  ///
  /// Says what is happening rather than hiding it: a lookup in progress reads as
  /// "Finding location…", and a lookup that came back with nothing says
  /// "Unknown place" instead of leaving an empty gap the customer cannot tell
  /// apart from a finished one.
  String get _placeNameText {
    final name = _placeName?.trim();

    // A name already on screen beats a loading message flashing over it. It
    // stays until the new answer replaces it — blanking it here is what made
    // the card strobe between "Finding location…" and the name.
    if (name != null && name.isNotEmpty) return name;

    if (_placeNameLookupInFlight != null) return 'Finding location…';

    return 'Unknown place';
  }

  /// Whether there is a name worth showing yet.
  ///
  /// Nothing is drawn while the map has never reported idle, so the card does
  /// not open already saying "Unknown place" about a pin nobody has looked up.
  bool get _hasPlaceNameToShow =>
      _placeNameLookupInFlight != null || _placeNameResolved;

  /// Names the place under the pin and offers it as the address text.
  ///
  /// Called once the customer lets go of the map — the end of a drag, a tap
  /// that moved the camera, the end of a long press — and never on the frames
  /// in between, because a camera reports a new centre on every one of them and
  /// a lookup per frame would be both slow and expensive.
  ///
  /// One lookup does both jobs. Reverse geocoding is the same question whether
  /// it is asked for the label under the pin or for the address the customer
  /// ends up saving, so asking twice spent two requests to learn one thing.
  ///
  /// The pin can move again while this is running, so the answer is applied
  /// only when it is still the one the map is waiting on.
  Future<void> _refreshPlaceNameForPin() async {
    final point = _point.value;
    if (point == null) return;

    // A second gesture on the same spot while the first is still running must
    // not spend another request.
    if (_placeNameLookupInFlight == point) return;

    // A pin that has barely moved is on the same shop, and the answer for it has
    // already been paid for. Skipping here is what stops a settled map from
    // firing a lookup — and flickering the card — over float noise.
    final named = _namedPoint;
    if (named != null &&
        Geo.haversineMetres(
          named.latitude,
          named.longitude,
          point.latitude,
          point.longitude,
        ) <
            _minimumNameLookupMoveMetres) {
      return;
    }

    _placeNameLookupInFlight = point;
    if (mounted) {
      setState(() => _placeNameResolved = false);
    }

    final name = await ref
        .read(geocodingServiceProvider)
        .getPlaceName(point.latitude, point.longitude);

    // A newer lookup may have taken over while this one was in flight. Then this
    // answer belongs to a pin the customer has already moved away from.
    final isNewest = _placeNameLookupInFlight == point;
    if (isNewest) {
      _placeNameLookupInFlight = null;
      _namedPoint = point;
    }
    if (!mounted || !isNewest) return;

    setState(() {
      // A miss clears the old name: it belonged to a spot the pin has left, and
      // showing the wrong shop is worse than showing nothing.
      _placeName = name;
      _placeNameResolved = true;
    });

    // Drop the address into the field too, when the customer has not written
    // their own. This is what stops a pin-only confirm from saving a row called
    // "Pinned location" with nothing a rider could work with. It is a
    // convenience, never a requirement: no lookup, no harm, the customer types
    // instead. Their own words always win, whenever they were typed.
    if (name == null || name.isEmpty) return;
    if (_landmarkEdited) return;

    // The field may only be replaced when it still holds what *we* put there.
    // Anything else is either the customer's own words or the address they came
    // back to, and overwriting it would drop the place they were standing at.
    final current = _landmarkController.text.trim();
    if (current.isNotEmpty && current != _lastAutoFilledAddress) return;

    _lastAutoFilledAddress = name;
    _landmarkController.text = name;
    if (mounted) setState(() {});
  }

  /// A pin on its own is a complete answer.
  ///
  /// Requiring typed text as well was what made "Confirm" a dead button for a
  /// customer who simply dropped a pin — the coordinates alone are a real
  /// delivery location and are stored alongside the address text.
  bool get _canConfirm => canConfirmMapPick(
      latitude: _point.value?.latitude,
      longitude: _point.value?.longitude,
      hasUsableAddressText: true);

  Future<void> _locateMe() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _gpsErrorMessage = null;
      _gpsNeedsSettings = false;
    });

    try {
      final fix =
          await ref.read(locationRepositoryProvider).captureCurrentLocation();
      if (!mounted) return;
      setState(() => _isLocating = false);
      _setPoint(fix.latitude, fix.longitude);
      _flyTo(fix.latitude, fix.longitude);

      // A GPS fix usually comes back with a street address, so put it straight
      // into the field rather than making the customer read it off a banner.
      if (fix.hasAddressText &&
          !_landmarkEdited &&
          _landmarkController.text.trim().isEmpty) {
        _landmarkController.text = fix.addressLine;
        if (mounted) setState(() {});
      }
    } on LocationCaptureException catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _gpsErrorMessage = failure.message;
        _gpsNeedsSettings = failure.settingsMustBeOpened;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _gpsErrorMessage = 'We could not read your location. You can still '
            'move the map by hand and drop the pin yourself.';
      });
    }
  }

  void _flyTo(double latitude, double longitude) {
    _viewportController.moveTo(
      CameraViewportState(
        center: turf.Point(coordinates: turf.Position(longitude, latitude)),
        zoom: _focusZoom,
      ),
      transition: const FlyViewportTransition(
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  /// Applies the pick to the app and stores it, exactly like a GPS capture.
  Future<void> _confirm() async {
    final point = _point.value;
    if (point == null || !_canConfirm || _isSaving) return;

    setState(() => _isSaving = true);

    ref.read(locationProvider.notifier).applyMapPick(
          latitude: point.latitude,
          longitude: point.longitude,
          addressText: _addressText,
        );

    try {
      await ref.read(saveCurrentLocationProvider)();
    } catch (_) {
      // Storing the address must never block ordering. The pin is applied and
      // the branch is worked out from it; My Addresses can retry later.
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapRef = mapboxMap;

    // The panel sits below the map rather than over it, so no camera padding
    // is needed: the camera centre is already the middle of the map area, which
    // is exactly where the pin is drawn.
    await _applyMapSettings(mapboxMap);
    if (!mounted) return;

    setState(() => _isMapReady = true);

    if (_point.value == null) {
      await _readCameraCentre(mapboxMap);
    } else {
      final existing = _point.value!;
      _flyTo(existing.latitude, existing.longitude);
    }
  }

  Future<void> _readCameraCentre(MapboxMap mapboxMap) async {
    try {
      final camera = await mapboxMap.getCameraState();
      final coordinates = camera.center.coordinates;
      if (!mounted) return;
      _setPoint(coordinates.lat.toDouble(), coordinates.lng.toDouble());
    } catch (_) {
      // No point yet. The customer moves the map and it fills in.
    }
  }

  /// Ornaments and gesture rules, tolerating a platform that lacks one.
  ///
  /// Attribution and the Mapbox logo stay **on** — Mapbox's terms require the
  /// map to carry them — and sit at the top of the map, which is always
  /// visible here because the controls are below it, not on it.
  Future<void> _applyMapSettings(MapboxMap mapboxMap) async {
    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        // A decoration failure must never stop the map being usable.
      }
    }

    await guard(() => mapboxMap.gestures.updateSettings(
          GesturesSettings(rotateEnabled: false, pitchEnabled: false),
        ));
    await guard(() => mapboxMap.attribution.updateSettings(
          AttributionSettings(
            enabled: true,
            position: OrnamentPosition.TOP_RIGHT,
          ),
        ));
    await guard(() => mapboxMap.logo.updateSettings(
          LogoSettings(
            enabled: true,
            position: OrnamentPosition.TOP_RIGHT,
          ),
        ));
    await guard(() => mapboxMap.scaleBar.updateSettings(
          ScaleBarSettings(
            enabled: true,
            position: OrnamentPosition.TOP_RIGHT,
            distanceUnits: DistanceUnits.METRIC,
          ),
        ));
    await guard(() => mapboxMap.compass.updateSettings(
          CompassSettings(enabled: false),
        ));
  }

  // --- Layout --------------------------------------------------------------

  /// Zoom used when the map jumps somewhere the customer asked for.
  static const double _focusZoom = 15.5;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final sheetHeight = ((media.size.height - keyboard) * 0.92)
        .clamp(280.0, media.size.height)
        .toDouble();

    return Padding(
      padding: EdgeInsets.only(
          top: (media.size.height - sheetHeight).clamp(0, media.size.height)),
      child: Container(
        height: sheetHeight,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMap()),
            _buildBottomBar(keyboard),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.borderDeep,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 10, 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pick your location',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Move the map until the pin is on your door',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        if (_mapIsUsable)
          Positioned.fill(
            child: MapWidget(
              key: const ValueKey('mrpizza-delivery-map'),
              // Streets, not Standard. Standard is a 3D style that fades
              // buildings away and washes the land out to near-white, which read
              // as an empty canvas rather than a map. Streets v12 is the
              // familiar road map: light land, white roads with grey casing,
              // filled building footprints, green parks and blue water — the
              // thing a customer already knows how to read. It also ships far
              // fewer glyphs and layers than Standard, which is what makes it
              // usable on a budget phone.
              styleUri: MapboxStyles.MAPBOX_STREETS,
              viewportController: _viewportController,
              viewport: CameraViewportState(
                center: turf.Point(
                  coordinates: turf.Position(
                    _point.value?.longitude ?? _fallbackLongitude,
                    _point.value?.latitude ?? _fallbackLatitude,
                  ),
                ),
                zoom: _focusZoom,
              ),
              onMapCreated: _onMapCreated,
              onCameraChangeListener: (event) {
                final center = event.cameraState.center.coordinates;
                _setPoint(center.lat.toDouble(), center.lng.toDouble());
              },
              // Safety net: re-read the centre once the map settles, so the
              // confirmed point is right even if a camera-change frame was
              // dropped while the gesture was in flight — and the moment to name
              // the place and fill in the address, because the customer has
              // stopped moving the map. Idle is the one event that means "they
              // let go", so this fires on drag end, on a tap that moved the
              // camera and on the end of a long press alike.
              onMapIdleListener: (_) async {
                final map = _mapRef;
                if (map == null) return;
                await _readCameraCentre(map);
                await _refreshPlaceNameForPin();
              },
              onMapLoadErrorListener: (event) {
                if (!mounted) return;
                debugPrint(
                  'Mapbox resource failed to load: ${event.type.name} '
                  '${event.message}',
                );
              },
            ),
          )
        else
          Positioned.fill(child: _buildMapUnavailable()),

        // The pin: dead centre of the map area, which is the camera centre.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(child: _buildPin()),
          ),
        ),

        if (_mapIsUsable)
          Positioned(
            right: 14,
            bottom: 14,
            child: _MapFloatingButton(
              icon: Icons.my_location_rounded,
              tooltip: 'Locate me',
              busy: _isLocating,
              onPressed: _isLocating ? null : _locateMe,
            ),
          ),
      ],
    );
  }

  /// The pin itself.
  ///
  /// Deliberately *not* listening to the point: its geometry never changes, and
  /// rebuilding an icon stack on every frame of a drag is exactly the kind of
  /// work that makes a map feel sticky on a budget phone. The live coordinates
  /// are spelled out in the summary strip below the map, which is where a screen
  /// reader user gets them from too.
  Widget _buildPin() {
    return Transform.translate(
      // Only half the graphic: the widget is *centred* on the camera centre, so
      // the tip — which is its bottom edge — is already half a height below it.
      // Shifting by the full height left the pin floating above the point it
      // was supposed to be marking.
      offset: const Offset(0, -(_pinHeight / 2)),
      child: Semantics(
        label: 'Delivery pin. Move the map to change your address.',
        child: const _DeliveryPinGraphic(),
      ),
    );
  }

  Widget _buildMapUnavailable() {
    return Container(
      color: AppColors.sand,
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _UnavailableMapBadge(),
          SizedBox(height: 16),
          Text(
            MapboxConfig.unavailableMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double keyboard) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + keyboard * 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_gpsErrorMessage != null) ...[
            _NoticeCard(
              message: _gpsErrorMessage!,
              actionLabel: _gpsNeedsSettings ? 'Settings' : null,
              onAction: _gpsNeedsSettings
                  ? () => ref.read(locationProvider.notifier).openAppSettings()
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          ValueListenableBuilder<CapturedCoordinates?>(
            valueListenable: _point,
            builder: (context, point, _) => _buildSummary(point),
          ),
          const SizedBox(height: 4),
          const Text(
            'Address & what the rider should look for',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _landmarkController,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            // One flag, not a diff: once the customer has typed, the automatic
            // street lookup never touches this field again.
            onChanged: (_) {
              _landmarkEdited = true;
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: _landmarkController.text.isEmpty
                  ? 'Move the map and we fill this in — '
                      'then add a gate colour, floor or landmark'
                  : null,
              isDense: true,
              prefixIcon: const Icon(Icons.edit_location_alt_rounded, size: 19),
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<CapturedCoordinates?>(
            valueListenable: _point,
            builder: (context, point, _) => SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('map-picker-confirm'),
                onPressed: point != null && _canConfirm && !_isSaving
                    ? _confirm
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        point == null
                            ? (_isMapReady
                                ? 'Move the map to choose a spot'
                                : 'Loading the map…')
                            : 'Confirm Location',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The pick, stated plainly: coordinates and whatever text was added.
  Widget _buildSummary(CapturedCoordinates? point) {
    final address = _addressText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            point == null
                ? (_isMapReady ? 'No spot chosen yet' : 'Waiting for the map…')
                : formatPickedCoordinates(
                    latitude: point.latitude,
                    longitude: point.longitude,
                  ),
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: address.isEmpty ? 12.5 : 14,
              height: 1.3,
              fontWeight: point == null ? FontWeight.w500 : FontWeight.w800,
              color: point == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          if (point != null && _hasPlaceNameToShow) ...[
            const SizedBox(height: 3),
            Text(
              _placeNameText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: _placeNameLookupInFlight != null
                    ? AppColors.textSecondary
                    : AppColors.primary,
              ),
            ),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                height: 1.3,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            address.isEmpty
                ? 'Move the map and we look up the street for you. Add a '
                    'landmark so the rider can find the door.'
                : 'Confirming saves this to My Addresses and checks out with '
                    'it. The pin is the spot you chose; the text is what the '
                    'lookup found plus anything you added.',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10.5,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Kept so the map can be re-read on idle without rebuilding the widget.
  MapboxMap? _mapRef;
}

/// Height of the pin graphic, measured from the top of the teardrop to the
/// middle of the dot that marks its tip.
const double _pinIconSize = 44;
const double _pinDotSize = 10;
const double _pinHeight = _pinIconSize + (_pinDotSize / 2);

/// Where the map opens before anything is chosen. A viewport only — never the
/// customer's selection.
const double _fallbackLatitude = 34.1688; // Abbottabad
const double _fallbackLongitude = 73.2215;

/// The pin's artwork, on its own so it can be a single const subtree.
///
/// A teardrop with a dot exactly on its tip, so there is never any doubt about
/// which pixel is about to be confirmed.
class _DeliveryPinGraphic extends StatelessWidget {
  const _DeliveryPinGraphic();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _pinIconSize,
      height: _pinHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: _pinIconSize,
            color: AppColors.primaryDark,
            shadows: [Shadow(color: Color(0x59000000), blurRadius: 5)],
          ),
          Positioned(
            top: _pinIconSize - (_pinDotSize / 2),
            left: (_pinIconSize - _pinDotSize) / 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: SizedBox(height: _pinDotSize, width: _pinDotSize),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableMapBadge extends StatelessWidget {
  const _UnavailableMapBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        color: AppColors.primaryTint,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.map_outlined,
        size: 32,
        color: AppColors.primary,
      ),
    );
  }
}

/// Inline warning with an optional action.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Color(0xFF9A6B1F),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF7A5414),
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7A5414),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// The round map control used for "Locate me".
class _MapFloatingButton extends StatelessWidget {
  const _MapFloatingButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: AppColors.shadow,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: busy
                ? const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : Icon(icon, size: 21, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
