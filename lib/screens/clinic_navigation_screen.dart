import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/clinic_directory_models.dart';

enum _ClinicMapMode { street, terrain, satellite }

class ClinicNavigationScreen extends StatefulWidget {
  const ClinicNavigationScreen({super.key, required this.clinic});

  final AccreditedClinic clinic;

  @override
  State<ClinicNavigationScreen> createState() => _ClinicNavigationScreenState();
}

class _ClinicNavigationScreenState extends State<ClinicNavigationScreen> {
  static const Color _teal = Color(0xFF006A8E);
  static const Color _softTeal = Color(0xFFE7F4F7);
  static const String _streetMapStyle =
      'https://tiles.openfreemap.org/styles/bright';

  // Pass your free MapTiler key with:
  // flutter run --dart-define=MAPTILER_KEY=YOUR_KEY
  //
  // The key is intentionally not hard-coded in source control.
  static const String _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

  static const String _osrmBaseUrl = 'https://router.project-osrm.org';

  MapLibreMapController? _mapController;
  bool _styleLoaded = false;
  bool _permissionChecked = false;
  bool _locationPermissionGranted = false;
  bool _permissionPermanentlyDenied = false;
  bool _routeLoading = false;
  bool _routeLoaded = false;
  bool _routeRequestStarted = false;
  bool _cameraFollowingUser = false;

  // Turn-by-turn navigation state.
  bool _navigationActive = false;
  bool _arrived = false;
  int _activeInstructionIndex = 0;
  double? _distanceToNextManeuver;
  double? _remainingDistanceMeters;
  double? _remainingDurationSeconds;
  double _navigationBearing = 0;
  int _offRouteSamples = 0;
  DateTime? _lastRerouteAt;
  String? _navigationNotice;
  geo.Position? _lastPosition;
  List<double> _remainingRouteDistanceByPoint = const [];

  _ClinicMapMode _mapMode = _ClinicMapMode.terrain;

  String get _activeMapStyle {
    switch (_mapMode) {
      case _ClinicMapMode.street:
      case _ClinicMapMode.terrain:
        return _streetMapStyle;
      case _ClinicMapMode.satellite:
        return 'https://api.maptiler.com/maps/hybrid/style.json'
            '?key=$_mapTilerKey';
    }
  }

  Timer? _locationWaitTimer;
  StreamSubscription<geo.Position>? _positionSubscription;
  bool _acquiringLocation = false;

  LatLng? _userLocation;
  List<LatLng> _routePoints = const [];
  List<_RouteInstruction> _instructions = const [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  String? _error;

  LatLng get _clinicPoint =>
      LatLng(widget.clinic.latitude!, widget.clinic.longitude!);

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _locationWaitTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    _locationWaitTimer?.cancel();

    final current = await Permission.locationWhenInUse.status;
    final result = current.isGranted
        ? current
        : await Permission.locationWhenInUse.request();

    if (!mounted) {
      return;
    }

    setState(() {
      _permissionChecked = true;
      _locationPermissionGranted = result.isGranted;
      _permissionPermanentlyDenied = result.isPermanentlyDenied;
      _error = result.isGranted
          ? null
          : 'Location permission is needed to calculate a route from your '
                'current position.';
    });

    if (result.isGranted) {
      await _acquireCurrentLocation();
    }
  }

  Future<void> _acquireCurrentLocation({bool forceFresh = false}) async {
    if (_acquiringLocation) {
      return;
    }

    _locationWaitTimer?.cancel();

    if (mounted) {
      setState(() {
        _acquiringLocation = true;
        _error = null;
      });
    }

    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      debugPrint('LOCATION SERVICE ENABLED: $serviceEnabled');

      if (!serviceEnabled) {
        throw Exception(
          'Location services are disabled. Turn on device location, then '
          'press Try again.',
        );
      }

      final geolocatorPermission = await geo.Geolocator.checkPermission();
      debugPrint('GEOLOCATOR PERMISSION: $geolocatorPermission');

      if (geolocatorPermission == geo.LocationPermission.denied ||
          geolocatorPermission == geo.LocationPermission.deniedForever) {
        throw Exception(
          'The app does not have location permission. Open app settings and '
          'allow precise location while the app is in use.',
        );
      }

      if (!forceFresh) {
        final lastKnown = await geo.Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint(
            'LAST KNOWN LOCATION: '
            '${lastKnown.latitude}, ${lastKnown.longitude}',
          );
          _acceptPosition(lastKnown, source: 'last known', startRoute: false);
        }
      }

      final current = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 25),
        ),
      );

      debugPrint(
        'CURRENT LOCATION: ${current.latitude}, ${current.longitude} '
        '(accuracy ${current.accuracy.toStringAsFixed(1)} m)',
      );
      _acceptPosition(current, source: 'current');
      _startPositionStream();
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('LOCATION TIMEOUT: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (_userLocation != null && !_routeRequestStarted) {
        debugPrint(
          'Using the last known location after the fresh GPS timeout.',
        );
        await _loadRoute();
      } else if (mounted) {
        setState(() {
          _error =
              'No GPS position was received after 25 seconds. In the '
              'Android emulator, open Extended controls → Location, choose a '
              'Pampanga point, press Set location, then press Try again.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('LOCATION ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && _userLocation == null) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _acquiringLocation = false;
        });
      }
    }
  }

  void _acceptPosition(
    geo.Position position, {
    required String source,
    bool startRoute = true,
  }) {
    final point = LatLng(position.latitude, position.longitude);
    debugPrint(
      'LOCATION ACCEPTED ($source): '
      '${point.latitude}, ${point.longitude}',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _userLocation = point;
      _lastPosition = position;

      if (_error != null && !_routeLoading) {
        _error = null;
      }
    });

    _locationWaitTimer?.cancel();

    // MapLibre already renders the native user-location dot, so avoid
    // clearing/redrawing the entire route for every GPS update. During active
    // navigation we only update progress and the camera.
    if (_navigationActive && _routeLoaded) {
      unawaited(_updateNavigationProgress(position));
    }

    if (startRoute &&
        !_routeLoaded &&
        !_routeLoading &&
        !_routeRequestStarted) {
      _loadRoute();
    }
  }

  void _startPositionStream() {
    if (_positionSubscription != null) {
      return;
    }

    const settings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _positionSubscription =
        geo.Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) {
            _acceptPosition(position, source: 'stream');
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('LOCATION STREAM ERROR: $error');
            debugPrintStack(stackTrace: stackTrace);
          },
        );
  }

  void _startLocationWaitTimeout() {
    _locationWaitTimer?.cancel();
    _locationWaitTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _userLocation != null || _routeLoading || _routeLoaded) {
        return;
      }

      setState(() {
        _error =
            'No current location was received after 20 seconds. Turn on '
            'the emulator or phone location service, set a test location, '
            'then press Try again.';
      });

      debugPrint('ROUTE ERROR: No user location received after 20 seconds.');
    });
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;

    // Street keeps the original OpenFreeMap Bright appearance.
    // Terrain adds the CKD natural land-cover + DEM hillshade.
    // Satellite uses MapTiler Satellite Hybrid.
    if (_mapMode == _ClinicMapMode.terrain) {
      await _applyGoogleLikeTerrainPalette();
    }

    // Clinic pin and the existing OSRM route are redrawn on top of whichever
    // basemap the user selected.
    await _drawClinicAndRoute();

    if (_navigationActive && _lastPosition != null) {
      await _updateNavigationProgress(
        _lastPosition!,
        allowAutomaticReroute: false,
      );
    }
  }

  void _changeMapMode(_ClinicMapMode mode) {
    if (mode == _mapMode) {
      return;
    }

    if (mode == _ClinicMapMode.satellite && _mapTilerKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Satellite needs a MapTiler API key. Run Flutter with '
            '--dart-define=MAPTILER_KEY=YOUR_KEY.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _mapMode = mode;

      // Recreate the native map only. Route/location state is kept in this
      // screen and is redrawn when the replacement style is ready.
      _mapController = null;
      _styleLoaded = false;
    });
  }

  Future<void> _applyGoogleLikeTerrainPalette() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    const terrainSourceId = 'ckd-terrain-dem';
    const terrainHillshadeLayerId = 'ckd-terrain-hillshade';

    const customGrassLayerId = 'ckd-landcover-grass';
    const customFarmlandLayerId = 'ckd-landcover-farmland';
    const customWetlandLayerId = 'ckd-landcover-wetland';
    const customWoodLayerId = 'ckd-landcover-wood';

    Future<void> setFill(
      String layerId,
      String color, {
      double? opacity,
    }) async {
      try {
        await controller.setLayerProperties(
          layerId,
          FillLayerProperties(fillColor: color, fillOpacity: opacity),
        );
      } catch (_) {
        // Ignore layers that do not exist or are not fill layers.
      }
    }

    Future<void> setLine(
      String layerId,
      String color, {
      double? opacity,
    }) async {
      try {
        await controller.setLayerProperties(
          layerId,
          LineLayerProperties(lineColor: color, lineOpacity: opacity),
        );
      } catch (_) {
        // Ignore layers that do not exist or are not line layers.
      }
    }

    List<String> layerIds = const [];

    try {
      layerIds = (await controller.getLayerIds())
          .map((id) => id.toString())
          .toList(growable: false);
    } catch (error) {
      debugPrint('MAP STYLE LAYER READ ERROR: $error');
    }

    // -----------------------------------------------------------------------
    // EXISTING OPENFREEMAP BRIGHT NATURAL LAYERS
    //
    // Keep streets, buildings, residential, commercial and industrial areas
    // exactly as OpenFreeMap Bright renders them.
    // -----------------------------------------------------------------------
    await setFill('landcover-grass', '#CDE6C6', opacity: 0.96);
    await setFill('landcover-grass-park', '#CDE6C6', opacity: 0.92);
    await setFill('landcover-wood', '#BDDDBB', opacity: 0.88);
    await setFill('park', '#D2E8CC', opacity: 0.82);

    for (final layerId in layerIds) {
      final id = layerId.toLowerCase();

      if (id.contains('water')) {
        await setFill(layerId, '#A7DDF2', opacity: 1.0);
        await setLine(layerId, '#78CDEB', opacity: 0.95);
      }
    }

    // -----------------------------------------------------------------------
    // MISSING NATURAL LAND-COVER CLASSES
    //
    // OpenFreeMap Bright has layers for wood and grass, but its Bright style
    // does not render every landcover class such as farmland. We add those
    // directly from the existing "openmaptiles" vector source.
    //
    // These layers are inserted below waterways/roads, so roads and streets
    // remain white/gray/yellow and are NOT tinted green.
    // -----------------------------------------------------------------------
    try {
      final currentLayerIds = (await controller.getLayerIds())
          .map((id) => id.toString())
          .toList(growable: false);

      String? belowNaturalLayer;

      if (currentLayerIds.contains('waterway_tunnel')) {
        belowNaturalLayer = 'waterway_tunnel';
      } else {
        // Fallback: find the first waterway/transportation layer.
        for (final id in currentLayerIds) {
          final lower = id.toLowerCase();
          if (lower.contains('waterway') ||
              lower.contains('road') ||
              lower.contains('highway') ||
              lower.contains('transportation')) {
            belowNaturalLayer = id;
            break;
          }
        }
      }

      Future<void> addLandcoverLayer({
        required String layerId,
        required String landcoverClass,
        required String color,
        required double opacity,
      }) async {
        final ids = (await controller.getLayerIds())
            .map((id) => id.toString())
            .toList(growable: false);

        if (ids.contains(layerId)) {
          return;
        }

        await controller.addFillLayer(
          'openmaptiles',
          layerId,
          FillLayerProperties(fillColor: color, fillOpacity: opacity),
          sourceLayer: 'landcover',
          filter: <dynamic>[
            '==',
            <dynamic>['get', 'class'],
            landcoverClass,
          ],
          belowLayerId: belowNaturalLayer,
        );
      }

      // Grass is added explicitly as an overlay so it stays visibly green
      // even if the base Bright style changes its own grass paint later.
      await addLandcoverLayer(
        layerId: customGrassLayerId,
        landcoverClass: 'grass',
        color: '#CBE5C4',
        opacity: 0.92,
      );

      // Agricultural fields are a major part of the pale-green appearance
      // seen in Google Terrain in rural Pampanga.
      await addLandcoverLayer(
        layerId: customFarmlandLayerId,
        landcoverClass: 'farmland',
        color: '#D6E9CF',
        opacity: 0.90,
      );

      await addLandcoverLayer(
        layerId: customWetlandLayerId,
        landcoverClass: 'wetland',
        color: '#D4E9D6',
        opacity: 0.86,
      );

      await addLandcoverLayer(
        layerId: customWoodLayerId,
        landcoverClass: 'wood',
        color: '#BDDDBB',
        opacity: 0.88,
      );

      debugPrint('GRASS/FARMLAND TERRAIN LAYERS: enabled');
    } catch (error, stackTrace) {
      debugPrint('GRASS/FARMLAND TERRAIN LAYER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    // -----------------------------------------------------------------------
    // ELEVATION / HILLSHADE
    //
    // Adds relief to hills and mountains without applying a green tint to
    // streets or developed land.
    // -----------------------------------------------------------------------
    try {
      final sourceIds = await controller.getSourceIds();

      if (!sourceIds.contains(terrainSourceId)) {
        await controller.addSource(
          terrainSourceId,
          const RasterDemSourceProperties(
            tiles: [
              'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/'
                  '{z}/{x}/{y}.png',
            ],
            tileSize: 256.0,
            minzoom: 0.0,
            maxzoom: 15.0,
            encoding: 'terrarium',
            attribution: 'Terrain data: Mapzen / AWS Open Data',
          ),
        );
      }

      final refreshedLayerIds = (await controller.getLayerIds())
          .map((id) => id.toString())
          .toList(growable: false);

      if (!refreshedLayerIds.contains(terrainHillshadeLayerId)) {
        String? belowLayerId;

        for (final id in refreshedLayerIds) {
          final lower = id.toLowerCase();

          if (lower.contains('road') ||
              lower.contains('highway') ||
              lower.contains('transportation') ||
              lower.contains('bridge') ||
              lower.contains('tunnel')) {
            belowLayerId = id;
            break;
          }
        }

        await controller.addHillshadeLayer(
          terrainSourceId,
          terrainHillshadeLayerId,
          const HillshadeLayerProperties(hillshadeExaggeration: 0.28),
          belowLayerId: belowLayerId,
        );
      }

      debugPrint('NATURAL TERRAIN HILLSHADE: enabled');
    } catch (error, stackTrace) {
      debugPrint('NATURAL TERRAIN HILLSHADE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _onUserLocationUpdated(UserLocation location) {
    _userLocation = location.position;
    _locationWaitTimer?.cancel();

    // Start only one automatic request. Without this guard, a failed request
    // would immediately be started again on every location update, making the
    // screen appear permanently stuck on "Calculating route".
    if (!_routeLoaded && !_routeLoading && !_routeRequestStarted) {
      _loadRoute();
    }
  }

  Future<void> _retryRoute() async {
    _locationWaitTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _routeRequestStarted = false;
      _routeLoaded = false;
      _routePoints = const [];
      _instructions = const [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _remainingRouteDistanceByPoint = const [];
      _remainingDistanceMeters = null;
      _remainingDurationSeconds = null;
      _navigationActive = false;
      _arrived = false;
      _activeInstructionIndex = 0;
      _distanceToNextManeuver = null;
      _navigationNotice = null;
      _offRouteSamples = 0;
      _error = null;
    });

    await _acquireCurrentLocation(forceFresh: true);

    if (_userLocation != null &&
        !_routeLoading &&
        !_routeRequestStarted &&
        !_routeLoaded) {
      await _loadRoute();
    }
  }

  Future<void> _loadRoute({bool navigationReroute = false}) async {
    final start = _userLocation;

    if (_routeLoading) {
      return;
    }

    if (_routeRequestStarted && !navigationReroute) {
      return;
    }

    if (start == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'Your current location is not available yet. Turn on the '
            'device location service, set an emulator location, and try again.';
      });
      _startLocationWaitTimeout();
      return;
    }

    _routeRequestStarted = true;

    setState(() {
      _routeLoading = true;

      // When automatically rerouting, keep the previous route visible until
      // the replacement route is ready.
      if (!navigationReroute) {
        _routeLoaded = false;
        _error = null;
      } else {
        _navigationNotice = 'Rerouting…';
      }
    });

    final destination = _clinicPoint;
    final coordinates =
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.parse(
      '$_osrmBaseUrl/route/v1/driving/$coordinates'
      '?overview=full&geometries=geojson&steps=true',
    );

    debugPrint('========== CLINIC ROUTING REQUEST ==========');
    debugPrint('Start: ${start.latitude}, ${start.longitude}');
    debugPrint(
      'Destination: ${destination.latitude}, ${destination.longitude}',
    );
    debugPrint('OSRM URL: $uri');

    try {
      final response = await _requestRouteWithRetry(uri);

      final responsePreview = response.body.length > 1000
          ? '${response.body.substring(0, 1000)}...'
          : response.body;

      debugPrint('OSRM status: ${response.statusCode}');
      debugPrint('OSRM response: $responsePreview');

      if (response.statusCode == 429) {
        throw Exception(
          'The public routing server is temporarily rate-limiting requests '
          '(HTTP 429). Wait a moment, then try again.',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'The routing request was refused by the server (HTTP 403).',
        );
      }

      if (response.statusCode >= 500) {
        throw Exception(
          'The routing server is temporarily unavailable '
          '(HTTP ${response.statusCode}).',
        );
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Routing service returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final code = decoded['code']?.toString();

      if (code != null && code != 'Ok') {
        final message = decoded['message']?.toString();
        throw Exception(
          message == null || message.isEmpty
              ? 'Routing server result: $code.'
              : 'Routing server result: $code — $message',
        );
      }

      final routes = decoded['routes'] as List<dynamic>? ?? const [];

      if (routes.isEmpty) {
        throw Exception(
          'No driving route was found. The start or clinic coordinate may be '
          'too far from a routable road.',
        );
      }

      final route = Map<String, dynamic>.from(routes.first as Map);
      final rawGeometry = route['geometry'];

      if (rawGeometry is! Map) {
        throw const FormatException(
          'The routing response did not contain route geometry.',
        );
      }

      final geometry = Map<String, dynamic>.from(rawGeometry);
      final rawCoordinates = geometry['coordinates'];

      if (rawCoordinates is! List || rawCoordinates.isEmpty) {
        throw const FormatException(
          'The routing response contained an empty route geometry.',
        );
      }

      final points = rawCoordinates
          .map((coordinate) {
            if (coordinate is! List || coordinate.length < 2) {
              throw const FormatException('Invalid route coordinate received.');
            }

            return LatLng(
              (coordinate[1] as num).toDouble(),
              (coordinate[0] as num).toDouble(),
            );
          })
          .toList(growable: false);

      final instructions = _readInstructions(route);
      final distance = (route['distance'] as num?)?.toDouble() ?? 0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0;
      final remainingByPoint = _buildRemainingRouteDistances(points);

      if (!mounted) {
        return;
      }

      setState(() {
        _routePoints = points;
        _instructions = instructions;
        _routeDistanceMeters = distance;
        _routeDurationSeconds = duration;
        _remainingRouteDistanceByPoint = remainingByPoint;
        _remainingDistanceMeters = distance;
        _remainingDurationSeconds = duration;
        _routeLoading = false;
        _routeLoaded = true;
        _routeRequestStarted = true;
        _error = null;
        _navigationNotice = null;
        _offRouteSamples = 0;

        if (_navigationActive) {
          _activeInstructionIndex = _firstGuidanceInstructionIndex();
          _arrived = false;
        }
      });

      debugPrint(
        'ROUTE SUCCESS: ${points.length} points, '
        '${_routeDistanceMeters?.toStringAsFixed(0)} meters, '
        '${_routeDurationSeconds?.toStringAsFixed(0)} seconds.',
      );
      debugPrint('============================================');

      await _drawClinicAndRoute();

      if (_navigationActive) {
        final position = _lastPosition;
        if (position != null) {
          await _updateNavigationProgress(
            position,
            allowAutomaticReroute: false,
          );
        }
      } else {
        await _showRouteOverview();
      }
    } on TimeoutException catch (error, stackTrace) {
      if (navigationReroute && _routeLoaded) {
        _handleNavigationRerouteFailure(
          'Could not reroute yet. Continuing on the previous route.',
          error,
          stackTrace,
        );
      } else {
        _handleRouteFailure(
          'The routing request timed out. Check the device internet '
          'connection and try again.',
          error,
          stackTrace,
        );
      }
    } on FormatException catch (error, stackTrace) {
      if (navigationReroute && _routeLoaded) {
        _handleNavigationRerouteFailure(
          'Could not reroute yet. Continuing on the previous route.',
          error,
          stackTrace,
        );
      } else {
        _handleRouteFailure(
          'The routing server returned an invalid response: ${error.message}',
          error,
          stackTrace,
        );
      }
    } on http.ClientException catch (error, stackTrace) {
      if (navigationReroute && _routeLoaded) {
        _handleNavigationRerouteFailure(
          'Could not reroute yet. Continuing on the previous route.',
          error,
          stackTrace,
        );
      } else {
        _handleRouteFailure(
          'The app could not connect to the routing server: ${error.message}',
          error,
          stackTrace,
        );
      }
    } catch (error, stackTrace) {
      if (navigationReroute && _routeLoaded) {
        _handleNavigationRerouteFailure(
          'Could not reroute yet. Continuing on the previous route.',
          error,
          stackTrace,
        );
      } else {
        _handleRouteFailure(
          error.toString().replaceFirst('Exception: ', ''),
          error,
          stackTrace,
        );
      }
    }
  }

  Future<http.Response> _requestRouteWithRetry(Uri uri) async {
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http
            .get(
              uri,
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'log.CKD-clinic-directory/1.0',
              },
            )
            .timeout(const Duration(seconds: 20));

        if ((response.statusCode == 429 || response.statusCode >= 500) &&
            attempt < 3) {
          debugPrint(
            'ROUTE ATTEMPT $attempt/3 returned '
            'HTTP ${response.statusCode}. Retrying…',
          );

          await Future.delayed(Duration(seconds: attempt * 2));

          continue;
        }

        return response;
      } catch (error) {
        lastError = error;

        debugPrint('ROUTE ATTEMPT $attempt/3 FAILED: $error');

        if (attempt >= 3) {
          rethrow;
        }

        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    if (lastError != null) {
      throw Exception('Routing request failed: $lastError');
    }

    throw StateError('Routing request failed unexpectedly.');
  }

  void _handleNavigationRerouteFailure(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('NAVIGATION REROUTE ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);

    if (!mounted) {
      return;
    }

    setState(() {
      _routeLoading = false;
      _routeRequestStarted = true;
      _navigationNotice = message;
    });
  }

  void _handleRouteFailure(
    String userMessage,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('ROUTE ERROR: $error');
    debugPrintStack(stackTrace: stackTrace);
    debugPrint('============================================');

    if (!mounted) {
      return;
    }

    setState(() {
      _routeLoading = false;
      _routeLoaded = false;
      _error = userMessage;
    });
  }

  List<_RouteInstruction> _readInstructions(Map<String, dynamic> route) {
    final legs = route['legs'] as List<dynamic>? ?? const [];
    if (legs.isEmpty) {
      return const [];
    }

    final firstLeg = Map<String, dynamic>.from(legs.first as Map);
    final steps = firstLeg['steps'] as List<dynamic>? ?? const [];

    var distanceFromStart = 0.0;
    final instructions = <_RouteInstruction>[];

    for (final rawStep in steps) {
      final step = Map<String, dynamic>.from(rawStep as Map);
      final maneuver = Map<String, dynamic>.from(
        step['maneuver'] as Map? ?? const <String, dynamic>{},
      );

      final type = maneuver['type']?.toString() ?? 'continue';
      final modifier = maneuver['modifier']?.toString();
      final roadName = step['name']?.toString().trim() ?? '';
      final distance = (step['distance'] as num?)?.toDouble() ?? 0;
      final duration = (step['duration'] as num?)?.toDouble() ?? 0;

      final rawLocation = maneuver['location'];
      LatLng maneuverPoint = _clinicPoint;

      if (rawLocation is List && rawLocation.length >= 2) {
        maneuverPoint = LatLng(
          (rawLocation[1] as num).toDouble(),
          (rawLocation[0] as num).toDouble(),
        );
      }

      instructions.add(
        _RouteInstruction(
          text: _instructionText(
            type: type,
            modifier: modifier,
            roadName: roadName,
          ),
          distanceMeters: distance,
          durationSeconds: duration,
          maneuverPoint: maneuverPoint,
          distanceFromStartMeters: distanceFromStart,
          type: type,
          modifier: modifier,
        ),
      );

      distanceFromStart += distance;
    }

    return instructions;
  }

  String _instructionText({
    required String type,
    required String? modifier,
    required String roadName,
  }) {
    final direction = modifier
        ?.replaceAll('_', ' ')
        .replaceAll('slight ', 'slightly ');
    final road = roadName.isEmpty ? '' : ' onto $roadName';

    switch (type) {
      case 'depart':
        return roadName.isEmpty ? 'Start your route' : 'Start on $roadName';
      case 'arrive':
        return 'Arrive at ${widget.clinic.name}';
      case 'turn':
        return 'Turn ${direction ?? ''}$road'.replaceAll('  ', ' ').trim();
      case 'continue':
      case 'new name':
        return 'Continue ${direction ?? ''}$road'.replaceAll('  ', ' ').trim();
      case 'merge':
        return 'Merge ${direction ?? ''}$road'.replaceAll('  ', ' ').trim();
      case 'fork':
        return 'Keep ${direction ?? ''}$road'.replaceAll('  ', ' ').trim();
      case 'end of road':
        return 'At the end of the road, turn ${direction ?? ''}$road'
            .replaceAll('  ', ' ')
            .trim();
      case 'roundabout':
      case 'rotary':
        return roadName.isEmpty
            ? 'Enter the roundabout'
            : 'Enter the roundabout toward $roadName';
      default:
        final action = type.replaceAll('_', ' ');
        return '${_capitalize(action)} ${direction ?? ''}$road'
            .replaceAll('  ', ' ')
            .trim();
    }
  }

  Future<void> _drawClinicAndRoute() async {
    final controller = _mapController;

    if (controller == null || !_styleLoaded) {
      return;
    }

    try {
      await controller.clearCircles();
      await controller.clearLines();

      if (_routePoints.isNotEmpty) {
        await controller.addLine(
          LineOptions(
            geometry: _routePoints,
            lineColor: '#006A8E',
            lineWidth: 6,
            lineOpacity: 0.9,
            lineJoin: 'round',
          ),
        );
      }

      await controller.addCircle(
        CircleOptions(
          geometry: _clinicPoint,
          circleRadius: 10,
          circleColor: '#006A8E',
          circleOpacity: 1,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
          circleStrokeOpacity: 1,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('MAP DRAW ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _error =
              'The route was calculated, but it could not be drawn on '
              'the map: $error';
        });
      }
    }
  }

  Future<void> _showRouteOverview() async {
    final controller = _mapController;
    if (controller == null || _routePoints.isEmpty) {
      return;
    }

    setState(() => _cameraFollowingUser = false);
    await controller.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        _boundsFor(_routePoints),
        left: 44,
        top: 90,
        right: 44,
        bottom: 230,
      ),
      duration: const Duration(milliseconds: 800),
    );
  }

  Future<void> _followUser() async {
    final controller = _mapController;
    final user = _userLocation;

    if (controller == null || user == null) {
      setState(() {
        _error = 'Waiting for your current location.';
      });
      return;
    }

    setState(() => _cameraFollowingUser = true);

    // Turn-by-turn uses its own camera updates so we can rotate toward the
    // phone/GPS heading and apply a navigation-style tilt.
    await controller.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

    final position = _lastPosition;
    if (_navigationActive && position != null) {
      await _updateNavigationCamera(position);
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(user, 16.5),
      duration: const Duration(milliseconds: 650),
    );
  }

  Future<void> _startNavigation() async {
    if (!_routeLoaded || _routePoints.isEmpty || _userLocation == null) {
      setState(() {
        _error = 'A route and current location are required before starting.';
      });
      return;
    }

    setState(() {
      _navigationActive = true;
      _arrived = false;
      _cameraFollowingUser = true;
      _activeInstructionIndex = _firstGuidanceInstructionIndex();
      _remainingDistanceMeters = _routeDistanceMeters;
      _remainingDurationSeconds = _routeDurationSeconds;
      _navigationNotice = null;
      _offRouteSamples = 0;
    });

    final controller = _mapController;
    if (controller != null) {
      await controller.updateMyLocationTrackingMode(
        MyLocationTrackingMode.none,
      );
    }

    final position = _lastPosition;
    if (position != null) {
      await _updateNavigationProgress(position, allowAutomaticReroute: false);
    }
  }

  Future<void> _stopNavigation() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _navigationActive = false;
      _arrived = false;
      _cameraFollowingUser = false;
      _navigationNotice = null;
      _offRouteSamples = 0;
      _distanceToNextManeuver = null;
      _remainingDistanceMeters = _routeDistanceMeters;
      _remainingDurationSeconds = _routeDurationSeconds;
    });

    await _showRouteOverview();
  }

  int _firstGuidanceInstructionIndex() {
    if (_instructions.isEmpty) {
      return 0;
    }

    if (_instructions.length > 1 &&
        _instructions.first.type.toLowerCase() == 'depart') {
      return 1;
    }

    return 0;
  }

  _RouteInstruction? get _activeInstruction {
    if (_instructions.isEmpty) {
      return null;
    }

    final index = _activeInstructionIndex
        .clamp(0, _instructions.length - 1)
        .toInt();

    return _instructions[index];
  }

  _RouteInstruction? get _nextInstruction {
    if (_instructions.isEmpty ||
        _activeInstructionIndex + 1 >= _instructions.length) {
      return null;
    }

    return _instructions[_activeInstructionIndex + 1];
  }

  Future<void> _updateNavigationProgress(
    geo.Position position, {
    bool allowAutomaticReroute = true,
  }) async {
    if (!_navigationActive || !_routeLoaded || _routePoints.isEmpty) {
      return;
    }

    final user = LatLng(position.latitude, position.longitude);

    final distanceToClinic = geo.Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      _clinicPoint.latitude,
      _clinicPoint.longitude,
    );

    if (distanceToClinic <= 35) {
      if (mounted) {
        setState(() {
          _arrived = true;
          _activeInstructionIndex = _instructions.isEmpty
              ? 0
              : _instructions.length - 1;
          _distanceToNextManeuver = 0;
          _remainingDistanceMeters = 0;
          _remainingDurationSeconds = 0;
          _navigationNotice = null;
          _offRouteSamples = 0;
        });
      }

      if (_cameraFollowingUser) {
        await _updateNavigationCamera(position);
      }
      return;
    }

    final proximity = _routeProximity(user);

    final remainingByIndex = _remainingRouteDistanceByPoint;
    var remaining = _routeDistanceMeters ?? 0;

    if (remainingByIndex.isNotEmpty) {
      final index = proximity.routePointIndex
          .clamp(0, remainingByIndex.length - 1)
          .toInt();

      remaining = remainingByIndex[index];
    }

    final totalDistance = _routeDistanceMeters ?? 0;
    final progress = (totalDistance - remaining)
        .clamp(0.0, totalDistance)
        .toDouble();

    // Pick the next maneuver based on along-route progress rather than only
    // straight-line distance. This avoids skipping turns when GPS drifts.
    var upcomingIndex = _instructions.isEmpty ? 0 : _instructions.length - 1;

    for (
      var i = _firstGuidanceInstructionIndex();
      i < _instructions.length;
      i++
    ) {
      if (_instructions[i].distanceFromStartMeters > progress + 4) {
        upcomingIndex = i;
        break;
      }
    }

    final active = _instructions.isEmpty ? null : _instructions[upcomingIndex];

    final distanceToManeuver = active == null
        ? distanceToClinic
        : (active.distanceFromStartMeters - progress)
              .clamp(0.0, double.infinity)
              .toDouble();

    final totalDuration = _routeDurationSeconds ?? 0;
    final remainingDuration = totalDistance <= 0
        ? 0.0
        : totalDuration * (remaining / totalDistance);

    if (mounted) {
      setState(() {
        _activeInstructionIndex = upcomingIndex;
        _distanceToNextManeuver = distanceToManeuver;
        _remainingDistanceMeters = remaining;
        _remainingDurationSeconds = remainingDuration;
      });
    }

    // Use a threshold that accounts for GPS accuracy. We require several
    // consecutive off-route samples before requesting a replacement route.
    final offRouteThreshold = (45.0 + position.accuracy)
        .clamp(55.0, 110.0)
        .toDouble();

    if (proximity.distanceMeters > offRouteThreshold) {
      _offRouteSamples++;
    } else {
      _offRouteSamples = 0;

      if (_navigationNotice == 'You appear to be off route.') {
        if (mounted) {
          setState(() {
            _navigationNotice = null;
          });
        }
      }
    }

    if (allowAutomaticReroute &&
        _offRouteSamples >= 3 &&
        !_routeLoading &&
        _canRerouteNow()) {
      _offRouteSamples = 0;
      _lastRerouteAt = DateTime.now();

      if (mounted) {
        setState(() {
          _navigationNotice = 'You appear to be off route. Rerouting…';
          _routeRequestStarted = false;
        });
      }

      await _loadRoute(navigationReroute: true);
    }

    if (_cameraFollowingUser) {
      await _updateNavigationCamera(position);
    }
  }

  bool _canRerouteNow() {
    final last = _lastRerouteAt;
    if (last == null) {
      return true;
    }

    return DateTime.now().difference(last) >= const Duration(seconds: 15);
  }

  Future<void> _updateNavigationCamera(geo.Position position) async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) {
      return;
    }

    if (position.speed > 0.8 &&
        position.heading.isFinite &&
        position.heading >= 0 &&
        position.heading <= 360) {
      _navigationBearing = position.heading;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 17.3,
            bearing: _navigationBearing,
            tilt: 48,
          ),
        ),
        duration: const Duration(milliseconds: 550),
      );
    } catch (error) {
      debugPrint('NAVIGATION CAMERA ERROR: $error');
    }
  }

  List<double> _buildRemainingRouteDistances(List<LatLng> points) {
    if (points.isEmpty) {
      return const [];
    }

    final result = List<double>.filled(points.length, 0);
    var running = 0.0;

    for (var i = points.length - 2; i >= 0; i--) {
      running += geo.Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );

      result[i] = running;
    }

    return result;
  }

  _RouteProximity _routeProximity(LatLng point) {
    if (_routePoints.length < 2) {
      return const _RouteProximity(
        distanceMeters: double.infinity,
        routePointIndex: 0,
      );
    }

    var bestDistance = double.infinity;
    var bestIndex = 0;

    for (var i = 0; i < _routePoints.length - 1; i++) {
      final result = _distanceToSegmentMeters(
        point,
        _routePoints[i],
        _routePoints[i + 1],
      );

      if (result.distanceMeters < bestDistance) {
        bestDistance = result.distanceMeters;
        bestIndex = result.t < 0.5 ? i : i + 1;
      }
    }

    return _RouteProximity(
      distanceMeters: bestDistance,
      routePointIndex: bestIndex,
    );
  }

  _SegmentDistance _distanceToSegmentMeters(LatLng point, LatLng a, LatLng b) {
    const metersPerDegreeLat = 110540.0;
    final referenceLatRadians =
        ((point.latitude + a.latitude + b.latitude) / 3) *
        3.141592653589793 /
        180;
    final metersPerDegreeLng = 111320.0 * math.cos(referenceLatRadians);

    final px = point.longitude * metersPerDegreeLng;
    final py = point.latitude * metersPerDegreeLat;
    final ax = a.longitude * metersPerDegreeLng;
    final ay = a.latitude * metersPerDegreeLat;
    final bx = b.longitude * metersPerDegreeLng;
    final by = b.latitude * metersPerDegreeLat;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final denominator = abx * abx + aby * aby;

    var t = denominator <= 0 ? 0.0 : (apx * abx + apy * aby) / denominator;

    t = t.clamp(0.0, 1.0).toDouble();

    final closestX = ax + abx * t;
    final closestY = ay + aby * t;
    final dx = px - closestX;
    final dy = py - closestY;

    return _SegmentDistance(distanceMeters: math.sqrt(dx * dx + dy * dy), t: t);
  }

  IconData _maneuverIcon(_RouteInstruction instruction) {
    final type = instruction.type.toLowerCase();
    final modifier = instruction.modifier?.toLowerCase() ?? '';

    if (type == 'arrive') {
      return Icons.flag;
    }

    if (type == 'roundabout' || type == 'rotary') {
      return Icons.roundabout_right;
    }

    if (modifier.contains('left')) {
      return Icons.turn_left;
    }

    if (modifier.contains('right')) {
      return Icons.turn_right;
    }

    if (type == 'merge') {
      return Icons.merge;
    }

    if (type == 'fork') {
      return Icons.fork_right;
    }

    return Icons.straight;
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _showRouteSteps() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Route steps',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _instructions.length,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final instruction = _instructions[index];
                      final isActive =
                          _navigationActive && index == _activeInstructionIndex;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? _softTeal : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: _softTeal,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: _teal,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    instruction.text,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatDistance(instruction.distanceMeters),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF617176),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic navigation'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              key: ValueKey('clinic-navigation-map-${_mapMode.name}'),
              styleString: _activeMapStyle,
              initialCameraPosition: CameraPosition(
                target: _clinicPoint,
                zoom: 15,
              ),
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              onUserLocationUpdated: _onUserLocationUpdated,
              myLocationEnabled: _locationPermissionGranted,
              myLocationRenderMode: _locationPermissionGranted
                  ? MyLocationRenderMode.compass
                  : MyLocationRenderMode.normal,
              myLocationTrackingMode: MyLocationTrackingMode.none,
              compassEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              attributionButtonPosition: AttributionButtonPosition.topRight,
              logoEnabled: false,
              foregroundLoadColor: _softTeal,
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _navigationActive
                ? _NavigationManeuverCard(
                    instruction: _activeInstruction,
                    nextInstruction: _nextInstruction,
                    distanceMeters: _distanceToNextManeuver,
                    arrived: _arrived,
                    clinicName: widget.clinic.name,
                    icon: _activeInstruction == null
                        ? Icons.navigation
                        : _maneuverIcon(_activeInstruction!),
                  )
                : _ClinicDestinationCard(clinic: widget.clinic),
          ),
          Positioned(
            top: _navigationActive ? 142.0 : 94.0,
            right: 14,
            child: _MapStyleSwitcher(mode: _mapMode, onChanged: _changeMapMode),
          ),
          Positioned(
            right: 14,
            bottom: _navigationActive ? 222.0 : 238.0,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'route-overview',
                  tooltip: 'Show whole route',
                  backgroundColor: Colors.white,
                  foregroundColor: _teal,
                  onPressed: _routeLoaded ? _showRouteOverview : null,
                  child: const Icon(Icons.route_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'follow-location',
                  tooltip: 'Follow my location',
                  backgroundColor: _cameraFollowingUser ? _teal : Colors.white,
                  foregroundColor: _cameraFollowingUser ? Colors.white : _teal,
                  onPressed: _locationPermissionGranted ? _followUser : null,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildBottomPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    if (!_permissionChecked) {
      return const _NavigationStatusCard(
        icon: Icons.location_searching,
        title: 'Preparing your location',
        message: 'Waiting for the location permission request.',
        loading: true,
      );
    }

    if (!_locationPermissionGranted) {
      return _NavigationStatusCard(
        icon: Icons.location_off_outlined,
        title: 'Location permission required',
        message:
            _error ??
            'Allow location access to calculate a road route to this clinic.',
        buttonLabel: _permissionPermanentlyDenied
            ? 'Open app settings'
            : 'Allow location',
        onPressed: _permissionPermanentlyDenied
            ? openAppSettings
            : _requestLocationPermission,
      );
    }

    if (_error != null && !_routeLoaded && !_routeLoading) {
      return _NavigationStatusCard(
        icon: Icons.error_outline,
        title: 'Route unavailable',
        message: _error!,
        buttonLabel: 'Try again',
        onPressed: _retryRoute,
      );
    }

    if (_acquiringLocation) {
      return const _NavigationStatusCard(
        icon: Icons.location_searching,
        title: 'Getting your location',
        message: 'Requesting a GPS position from the device.',
        loading: true,
      );
    }

    if (_routeLoading) {
      return const _NavigationStatusCard(
        icon: Icons.route_outlined,
        title: 'Calculating route',
        message: 'Requesting a driving route from the routing server.',
        loading: true,
      );
    }

    if (_userLocation == null) {
      return const _NavigationStatusCard(
        icon: Icons.location_searching,
        title: 'Waiting for your location',
        message:
            'Turn on location services or set a location in the Android '
            'Emulator controls.',
        loading: true,
      );
    }

    if (_navigationActive && _routeLoaded) {
      return _buildActiveNavigationPanel(context);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _RouteMetric(
                  icon: Icons.route,
                  label: 'Distance',
                  value: _formatDistance(_routeDistanceMeters ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteMetric(
                  icon: Icons.schedule,
                  label: 'Estimated time',
                  value: _formatDuration(_routeDurationSeconds ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _instructions.isEmpty ? null : _showRouteSteps,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Route steps'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _teal),
                  onPressed: _routeLoaded ? _startNavigation : null,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Route guidance is informational. Follow road signs and local '
            'traffic rules.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF617176)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveNavigationPanel(BuildContext context) {
    final remainingDistance =
        _remainingDistanceMeters ?? _routeDistanceMeters ?? 0;
    final remainingDuration =
        _remainingDurationSeconds ?? _routeDurationSeconds ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_navigationNotice != null) ...[
            Row(
              children: [
                if (_routeLoading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _teal,
                    ),
                  )
                else
                  const Icon(Icons.info_outline, size: 18, color: _teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _navigationNotice!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF485A60),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _RouteMetric(
                  icon: Icons.route,
                  label: _arrived ? 'Status' : 'Remaining',
                  value: _arrived
                      ? 'Arrived'
                      : _formatDistance(remainingDistance),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteMetric(
                  icon: Icons.schedule,
                  label: 'Time left',
                  value: _arrived
                      ? '0 min'
                      : _formatDuration(remainingDuration),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _instructions.isEmpty ? null : _showRouteSteps,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Steps'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _arrived
                        ? const Color(0xFF39484D)
                        : const Color(0xFFD32F2F),
                  ),
                  onPressed: _stopNavigation,
                  icon: Icon(_arrived ? Icons.check : Icons.close),
                  label: Text(_arrived ? 'Done' : 'End'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
  }

  String _capitalize(String text) {
    if (text.isEmpty) {
      return text;
    }
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

class _RouteInstruction {
  const _RouteInstruction({
    required this.text,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuverPoint,
    required this.distanceFromStartMeters,
    required this.type,
    required this.modifier,
  });

  final String text;
  final double distanceMeters;
  final double durationSeconds;
  final LatLng maneuverPoint;
  final double distanceFromStartMeters;
  final String type;
  final String? modifier;
}

class _RouteProximity {
  const _RouteProximity({
    required this.distanceMeters,
    required this.routePointIndex,
  });

  final double distanceMeters;
  final int routePointIndex;
}

class _SegmentDistance {
  const _SegmentDistance({required this.distanceMeters, required this.t});

  final double distanceMeters;
  final double t;
}

class _NavigationManeuverCard extends StatelessWidget {
  const _NavigationManeuverCard({
    required this.instruction,
    required this.nextInstruction,
    required this.distanceMeters,
    required this.arrived,
    required this.clinicName,
    required this.icon,
  });

  final _RouteInstruction? instruction;
  final _RouteInstruction? nextInstruction;
  final double? distanceMeters;
  final bool arrived;
  final String clinicName;
  final IconData icon;

  String _distanceLabel(double? meters) {
    if (meters == null) {
      return '';
    }

    if (meters < 1000) {
      return 'In ${meters.round()} m';
    }

    return 'In ${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final primary = arrived
        ? 'You have arrived'
        : instruction?.text ?? 'Continue on the route';
    final distance = arrived ? clinicName : _distanceLabel(distanceMeters);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF006A8E),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Icon(
              arrived ? Icons.flag : icon,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (distance.isNotEmpty)
                  Text(
                    distance,
                    style: const TextStyle(
                      color: Color(0xFFD8F1F6),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  primary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!arrived && nextInstruction != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Then ${nextInstruction!.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD8F1F6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStyleSwitcher extends StatelessWidget {
  const _MapStyleSwitcher({required this.mode, required this.onChanged});

  final _ClinicMapMode mode;
  final ValueChanged<_ClinicMapMode> onChanged;

  String get _label {
    switch (mode) {
      case _ClinicMapMode.street:
        return 'Street';
      case _ClinicMapMode.terrain:
        return 'Terrain';
      case _ClinicMapMode.satellite:
        return 'Satellite';
    }
  }

  IconData get _icon {
    switch (mode) {
      case _ClinicMapMode.street:
        return Icons.map_outlined;
      case _ClinicMapMode.terrain:
        return Icons.terrain_outlined;
      case _ClinicMapMode.satellite:
        return Icons.satellite_alt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: PopupMenuButton<_ClinicMapMode>(
        tooltip: 'Change map style',
        initialValue: mode,
        onSelected: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ClinicMapMode.street,
            child: Row(
              children: [
                Icon(Icons.map_outlined),
                SizedBox(width: 10),
                Text('Street'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _ClinicMapMode.terrain,
            child: Row(
              children: [
                Icon(Icons.terrain_outlined),
                SizedBox(width: 10),
                Text('Terrain'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _ClinicMapMode.satellite,
            child: Row(
              children: [
                Icon(Icons.satellite_alt_outlined),
                SizedBox(width: 10),
                Text('Satellite'),
              ],
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 18, color: const Color(0xFF006A8E)),
              const SizedBox(width: 6),
              Text(
                _label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF243238),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: Color(0xFF617176),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicDestinationCard extends StatelessWidget {
  const _ClinicDestinationCard({required this.clinic});

  final AccreditedClinic clinic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE7F4F7),
            child: Icon(Icons.local_hospital, color: Color(0xFF006A8E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clinic.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  clinic.displayAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationStatusCard extends StatelessWidget {
  const _NavigationStatusCard({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF006A8E),
              ),
            )
          else
            Icon(icon, color: const Color(0xFF006A8E), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF617176),
                  ),
                ),
                if (buttonLabel != null) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF006A8E),
                    ),
                    onPressed: onPressed,
                    child: Text(buttonLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F4F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF006A8E), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF617176),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
