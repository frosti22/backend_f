import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/clinic_directory_models.dart';
import '../services/api_service.dart';
import 'clinic_navigation_screen.dart';

enum _ClinicMapMode { street, terrain, satellite }

class ClinicDirectoryScreen extends StatefulWidget {
  const ClinicDirectoryScreen({super.key});

  @override
  State<ClinicDirectoryScreen> createState() => _ClinicDirectoryScreenState();
}

class _ClinicDirectoryScreenState extends State<ClinicDirectoryScreen> {
  static const Color _teal = Color(0xFF006A8E);
  static const Color _softTeal = Color(0xFFE7F4F7);
  static const String _streetMapStyle =
      'https://tiles.openfreemap.org/styles/bright';

  // Pass your free MapTiler key with:
  // flutter run --dart-define=MAPTILER_KEY=YOUR_KEY
  //
  // The key is intentionally not hard-coded in source control.
  static const String _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

  static const LatLng _philippinesCenter = LatLng(12.8797, 121.7740);

  final ApiService _api = ApiService();
  final TextEditingController _clinicSearchController = TextEditingController();
  final GlobalKey _mapSectionKey = GlobalKey();

  List<ClinicRegionOption> _regions = const [];
  List<ClinicAreaOption> _areas = const [];
  List<ClinicLocalityOption> _localities = const [];

  ClinicRegionOption? _selectedRegion;
  ClinicAreaOption? _selectedArea;
  ClinicLocalityOption? _selectedLocality;
  ClinicMatchResult? _result;
  AccreditedClinic? _selectedClinic;

  MapLibreMapController? _mapController;
  bool _mapStyleLoaded = false;
  bool _mapExpanded = false;
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

  bool _loadingRegions = true;
  bool _loadingAreas = false;
  bool _loadingLocalities = false;
  bool _searching = false;
  String _clinicSearchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    _clinicSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _error = null;
    });

    try {
      final regions = await _api.getClinicRegions();

      if (!mounted) {
        return;
      }

      final uniqueRegions = <String, ClinicRegionOption>{};

      for (final region in regions) {
        uniqueRegions.putIfAbsent(region.name.trim(), () => region);
      }

      setState(() {
        _regions = uniqueRegions.values.toList(growable: false);
        _selectedRegion = null;
        _selectedArea = null;
        _selectedLocality = null;
        _areas = const [];
        _localities = const [];
        _result = null;
        _selectedClinic = null;
        _mapExpanded = false;
        _mapController = null;
        _mapStyleLoaded = false;
        _loadingRegions = false;
      });

      _resetClinicSearch();
      await _clearClinicPin();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRegions = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _onRegionChanged(ClinicRegionOption? region) async {
    setState(() {
      _selectedRegion = region;
      _selectedArea = null;
      _selectedLocality = null;
      _areas = const [];
      _localities = const [];
      _result = null;
      _selectedClinic = null;
      _mapExpanded = false;
      _mapController = null;
      _mapStyleLoaded = false;
      _error = null;
    });

    _resetClinicSearch();

    if (region == null) {
      return;
    }

    setState(() => _loadingAreas = true);

    try {
      final result = await _api.getClinicAreas(region.name);

      var loadedAreas = result.combinedAreas.isNotEmpty
          ? List<ClinicAreaOption>.from(result.combinedAreas)
          : <ClinicAreaOption>[
              ...result.provinces,
              ...result.regionLevelLocalities,
              ...result.specialAreas,
            ];

      if (loadedAreas.isEmpty && region.hasRegionLevelLocalities) {
        final regionLocalities = await _api.getClinicLocalities(
          region: region.name,
        );

        loadedAreas = regionLocalities
            .map(
              (locality) => ClinicAreaOption(
                name: locality.name,
                type: 'region_level_locality',
                localityType: locality.type,
              ),
            )
            .toList();
      }

      loadedAreas.sort(
        (first, second) =>
            first.name.toLowerCase().compareTo(second.name.toLowerCase()),
      );

      final uniqueAreas = <String, ClinicAreaOption>{};

      for (final area in loadedAreas) {
        uniqueAreas.putIfAbsent(_areaKey(area), () => area);
      }

      final areas = uniqueAreas.values.toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _areas = areas;
        _loadingAreas = false;
        if (areas.isEmpty) {
          _error =
              'No Province entries were returned for ${region.name}. '
              'Restart the updated backend and try again.';
        }
      });

      if (areas.length == 1) {
        await _onAreaChanged(areas.first);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingAreas = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _onAreaChanged(ClinicAreaOption? area) async {
    setState(() {
      _selectedArea = area;
      _selectedLocality = null;
      _localities = const [];
      _result = null;
      _selectedClinic = null;
      _mapExpanded = false;
      _mapController = null;
      _mapStyleLoaded = false;
      _error = null;
    });

    _resetClinicSearch();

    final region = _selectedRegion;

    if (region == null || area == null) {
      return;
    }

    if (area.type == 'region_level_locality') {
      final locality = ClinicLocalityOption(
        name: area.name,
        type: area.localityType ?? 'locality',
      );

      setState(() {
        _selectedLocality = locality;
        _localities = [locality];
        _loadingLocalities = false;
      });
      return;
    }

    setState(() => _loadingLocalities = true);

    try {
      final localities = await _api.getClinicLocalities(
        region: region.name,
        area: area,
      );

      if (!mounted) {
        return;
      }

      final uniqueLocalities = <String, ClinicLocalityOption>{};

      for (final locality in localities) {
        uniqueLocalities.putIfAbsent(locality.name.trim(), () => locality);
      }

      setState(() {
        _localities = uniqueLocalities.values.toList(growable: false);
        _selectedLocality = null;
        _loadingLocalities = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingLocalities = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _findClinics() async {
    final region = _selectedRegion;
    final locality = _selectedLocality;

    if (region == null || locality == null) {
      setState(() {
        _error = 'Select your region and location.';
      });
      return;
    }

    final area = _selectedArea;
    final province = area?.type == 'province' ? area?.name : null;

    setState(() {
      _searching = true;
      _result = null;
      _selectedClinic = null;
      _mapExpanded = false;
      _mapController = null;
      _mapStyleLoaded = false;
      _error = null;
    });

    _resetClinicSearch();

    try {
      final result = await _api.matchAccreditedClinics(
        region: region.name,
        province: province,
        cityMunicipality: locality.name,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _searching = false;
        _error = error.toString();
      });
    }
  }

  void _resetClinicSearch() {
    _clinicSearchController.clear();
    _clinicSearchQuery = '';
  }

  Future<void> _selectClinic(AccreditedClinic clinic) async {
    setState(() {
      _selectedClinic = clinic;
      _mapExpanded = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapContext = _mapSectionKey.currentContext;
      if (mapContext != null) {
        Scrollable.ensureVisible(
          mapContext,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }
    });

    await _showSelectedClinicOnMap();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    _mapStyleLoaded = false;
  }

  Future<void> _onMapStyleLoaded() async {
    _mapStyleLoaded = true;

    // Street keeps the original OpenFreeMap Bright appearance.
    // Terrain adds the CKD natural land-cover + DEM hillshade.
    // Satellite uses MapTiler Satellite Hybrid, which already includes
    // imagery, roads, labels and boundaries.
    if (_mapMode == _ClinicMapMode.terrain) {
      await _applyGoogleLikeTerrainPalette();
    }

    await _showSelectedClinicOnMap();
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

      // Recreate only the native map when changing basemaps. Clinic/filter
      // state stays intact and the verified clinic pin is redrawn after the
      // new style finishes loading.
      _mapController = null;
      _mapStyleLoaded = false;
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
          const HillshadeLayerProperties(
            hillshadeExaggeration: 0.28,
            hillshadeIlluminationDirection: 315.0,
            hillshadeIlluminationAnchor: 'map',
            hillshadeShadowColor: '#929D8D',
            hillshadeHighlightColor: '#FCFDFB',
            hillshadeAccentColor: '#AAB6A5',
          ),
          belowLayerId: belowLayerId,
        );
      }

      debugPrint('NATURAL TERRAIN HILLSHADE: enabled');
    } catch (error, stackTrace) {
      debugPrint('NATURAL TERRAIN HILLSHADE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _showSelectedClinicOnMap() async {
    final controller = _mapController;
    final clinic = _selectedClinic;

    if (controller == null || !_mapStyleLoaded) {
      return;
    }

    try {
      await controller.clearCircles();

      if (clinic == null || !clinic.hasVerifiedCoordinates) {
        return;
      }

      final point = LatLng(clinic.latitude!, clinic.longitude!);

      await controller.addCircle(
        CircleOptions(
          geometry: point,
          circleRadius: 10,
          circleColor: '#006A8E',
          circleOpacity: 1,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
          circleStrokeOpacity: 1,
        ),
      );

      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(point, 15.5),
        duration: const Duration(milliseconds: 700),
      );
    } catch (_) {
      if (mounted) {
        _showMessage('The clinic map pin could not be displayed right now.');
      }
    }
  }

  Future<void> _clearClinicPin() async {
    final controller = _mapController;

    if (controller == null || !_mapStyleLoaded) {
      return;
    }

    try {
      await controller.clearCircles();
    } catch (_) {
      // The style can be rebuilding while the location filters are changing.
    }
  }

  Future<void> _openClinicNavigation(AccreditedClinic clinic) async {
    if (!clinic.hasVerifiedCoordinates) {
      _showMessage('A verified map pin is required for navigation.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClinicNavigationScreen(clinic: clinic),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _areaKey(ClinicAreaOption area) {
    return '${area.type}::${area.name.trim()}';
  }

  String? get _regionInitialValue {
    final selectedName = _selectedRegion?.name.trim();

    if (selectedName == null) {
      return null;
    }

    final matches = _regions.where(
      (region) => region.name.trim() == selectedName,
    );

    return matches.length == 1 ? selectedName : null;
  }

  String? get _areaInitialValue {
    final selectedArea = _selectedArea;

    if (selectedArea == null) {
      return null;
    }

    final selectedKey = _areaKey(selectedArea);
    final matches = _areas.where((area) => _areaKey(area) == selectedKey);

    return matches.length == 1 ? selectedKey : null;
  }

  String? get _localityInitialValue {
    final selectedName = _selectedLocality?.name.trim();

    if (selectedName == null) {
      return null;
    }

    final matches = _localities.where(
      (locality) => locality.name.trim() == selectedName,
    );

    return matches.length == 1 ? selectedName : null;
  }

  List<AccreditedClinic> get _visibleClinics {
    final facilities = _result?.facilities ?? const <AccreditedClinic>[];
    final query = _clinicSearchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return facilities;
    }

    return facilities
        .where((clinic) {
          return clinic.name.toLowerCase().contains(query) ||
              clinic.displayAddress.toLowerCase().contains(query) ||
              clinic.facilityTypeLabel.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final visibleClinics = _visibleClinics;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Healthcare Facilities'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRegions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _buildLocationSearchCard(context),
            if (_loadingRegions || _loadingAreas || _loadingLocalities) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(color: _teal),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MessageCard(
                icon: Icons.error_outline,
                message: _error!,
                accentColor: Colors.redAccent,
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _MessageCard(
                icon: _resultIcon(result.matchLevel),
                message: result.message,
                accentColor: _teal,
              ),
              const SizedBox(height: 16),
              _buildClinicSearchBar(),
              const SizedBox(height: 12),
              _buildClinicList(context, visibleClinics),
              const SizedBox(height: 18),
              _buildMapSection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSearchCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14006A8E),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: _softTeal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_hospital_outlined, color: _teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find accredited facilities',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Results are based on your selected location.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5E6D72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _regionInitialValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Region',
              prefixIcon: Icon(Icons.public, color: _teal),
            ),
            items: _regions
                .map(
                  (region) => DropdownMenuItem<String>(
                    value: region.name.trim(),
                    child: Text(region.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _loadingRegions
                ? null
                : (value) {
                    if (value == null) {
                      _onRegionChanged(null);
                      return;
                    }

                    final region = _regions.firstWhere(
                      (item) => item.name.trim() == value,
                    );

                    _onRegionChanged(region);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _areaInitialValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Province',
              prefixIcon: Icon(Icons.map_outlined, color: _teal),
            ),
            items: _areas
                .map(
                  (area) => DropdownMenuItem<String>(
                    value: _areaKey(area),
                    child: Text(area.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _loadingAreas || _selectedRegion == null
                ? null
                : (value) {
                    if (value == null) {
                      _onAreaChanged(null);
                      return;
                    }

                    final area = _areas.firstWhere(
                      (item) => _areaKey(item) == value,
                    );

                    _onAreaChanged(area);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _localityInitialValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'City/Municipality',
              prefixIcon: Icon(Icons.location_city, color: _teal),
            ),
            items: _localities
                .map(
                  (locality) => DropdownMenuItem<String>(
                    value: locality.name.trim(),
                    child: Text(locality.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _loadingLocalities
                ? null
                : (value) {
                    setState(() {
                      _selectedLocality = value == null
                          ? null
                          : _localities.firstWhere(
                              (item) => item.name.trim() == value,
                            );
                      _result = null;
                      _selectedClinic = null;
                      _mapExpanded = false;
                      _mapController = null;
                      _mapStyleLoaded = false;
                      _error = null;
                    });
                    _resetClinicSearch();
                  },
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: _searching ? null : _findClinics,
            icon: _searching
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: const Text('Show healthcare facilities'),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicSearchBar() {
    return TextField(
      controller: _clinicSearchController,
      onChanged: (value) {
        setState(() => _clinicSearchQuery = value);
      },
      decoration: InputDecoration(
        hintText: 'Search facility name',
        prefixIcon: const Icon(Icons.search, color: _teal),
        suffixIcon: _clinicSearchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _clinicSearchController.clear();
                  setState(() => _clinicSearchQuery = '');
                },
                icon: const Icon(Icons.close),
              ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildClinicList(
    BuildContext context,
    List<AccreditedClinic> clinics,
  ) {
    final total = _result?.facilities.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Healthcare facilities',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${clinics.length}/$total',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: const Color(0xFF617176)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tap a facility to expand the map and display its verified pin.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF617176)),
        ),
        const SizedBox(height: 10),
        if (clinics.isEmpty)
          const _MessageCard(
            icon: Icons.search_off,
            message: 'No facility matches your search.',
            accentColor: _teal,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 270),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: clinics.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final clinic = clinics[index];
                final isSelected =
                    clinic.facilityNumber == _selectedClinic?.facilityNumber;

                return _ClinicListTile(
                  clinic: clinic,
                  isSelected: isSelected,
                  onTap: () => _selectClinic(clinic),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMapSection(BuildContext context) {
    final selectedClinic = _selectedClinic;

    return Container(
      key: _mapSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Map',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selectedClinic != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() => _mapExpanded = !_mapExpanded);
                  },
                  icon: Icon(
                    _mapExpanded ? Icons.close_fullscreen : Icons.open_in_full,
                  ),
                  label: Text(_mapExpanded ? 'Collapse' : 'Expand'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            height: _mapExpanded ? 430 : 235,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A006A8E),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MapLibreMap(
                      key: ValueKey('clinic-directory-map-${_mapMode.name}'),
                      styleString: _activeMapStyle,
                      initialCameraPosition: const CameraPosition(
                        target: _philippinesCenter,
                        zoom: 4.8,
                      ),
                      onMapCreated: _onMapCreated,
                      onStyleLoadedCallback: _onMapStyleLoaded,
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      myLocationEnabled: false,
                      logoEnabled: false,
                      attributionButtonPosition:
                          AttributionButtonPosition.topRight,
                      foregroundLoadColor: _softTeal,
                    ),
                  ),
                  Positioned(
                    top: 48,
                    right: 12,
                    child: _MapStyleSwitcher(
                      mode: _mapMode,
                      onChanged: _changeMapMode,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              size: 17,
                              color: _teal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedClinic == null
                                  ? 'Select a facility'
                                  : selectedClinic.cityMunicipality,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (selectedClinic == null)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: _MapNotice(
                        icon: Icons.touch_app_outlined,
                        message:
                            'Tap a facility from the list to expand this map.',
                      ),
                    )
                  else if (!selectedClinic.hasVerifiedCoordinates)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: const _MapNotice(
                        icon: Icons.location_off_outlined,
                        message:
                            'Verified map pin not yet available for this facility.',
                      ),
                    )
                  else if (_mapExpanded)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _SelectedClinicMapCard(
                        clinic: selectedClinic,
                        onDirections: () =>
                            _openClinicNavigation(selectedClinic),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _mapMode == _ClinicMapMode.satellite
                ? 'Satellite Hybrid imagery is displayed through MapLibre. '
                      'Only manually verified clinic coordinates are displayed.'
                : 'The map uses OpenStreetMap-based street data through '
                      'MapLibre. Only manually verified clinic coordinates are '
                      'displayed.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF617176)),
          ),
        ],
      ),
    );
  }

  IconData _resultIcon(String matchLevel) {
    switch (matchLevel) {
      case 'same_city_municipality':
        return Icons.location_on_outlined;
      case 'same_province':
        return Icons.map_outlined;
      case 'same_region':
        return Icons.public;
      default:
        return Icons.info_outline;
    }
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    required this.accentColor,
  });

  final IconData icon;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accentColor),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ClinicListTile extends StatelessWidget {
  const _ClinicListTile({
    required this.clinic,
    required this.isSelected,
    required this.onTap,
  });

  static const Color _teal = Color(0xFF006A8E);

  final AccreditedClinic clinic;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFE0F2F6) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? _teal : const Color(0xFFE1E9EB),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: clinic.hasVerifiedCoordinates
                      ? const Color(0xFFD9F0F4)
                      : const Color(0xFFF0F2F3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  clinic.hasVerifiedCoordinates
                      ? Icons.location_on
                      : Icons.local_hospital_outlined,
                  color: clinic.hasVerifiedCoordinates
                      ? _teal
                      : const Color(0xFF728086),
                ),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      clinic.facilityTypeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (clinic.displayAddress.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        clinic.displayAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF617176),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(isSelected ? Icons.map : Icons.chevron_right, color: _teal),
            ],
          ),
        ),
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

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF006A8E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedClinicMapCard extends StatelessWidget {
  const _SelectedClinicMapCard({
    required this.clinic,
    required this.onDirections,
  });

  final AccreditedClinic clinic;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFD9F0F4),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  clinic.displayAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Open in-app navigation',
            onPressed: onDirections,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF006A8E),
            ),
            icon: const Icon(Icons.directions, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
