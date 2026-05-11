import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../models/pharmacy.dart';
import '../theme/app_theme.dart';
import 'pharmacy_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // ── Map controller ──────────────────────────────────────────
  final MapController _mapController = MapController();

  // ── User location (default: Beirut downtown) ────────────────
  static const LatLng _defaultUserLocation = LatLng(33.8938, 35.5018);
  LatLng _userLocation = _defaultUserLocation;
  bool _locatingUser = true;
  bool _locationAvailable = false;

  // ── State ───────────────────────────────────────────────────
  Pharmacy? _selectedPharmacy;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _showSuggestions = false;
  bool _showList = false;
  String _sortBy = 'proximity';
  double _currentZoom = 10.0;

  @override
  @override
  void initState() {
    super.initState();
    _acquireUserLocation();
    _logPharmacyCoordinates();
  }

  void _logPharmacyCoordinates() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
      final pharmacies = appState.pharmacies.take(5).toList();
      for (final p in pharmacies) {
        debugPrint(
          '📍 ${p.name}: lat=${p.latitude.toStringAsFixed(4)}, lng=${p.longitude.toStringAsFixed(4)}',
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Top suggestions for the current query: pharmacies whose name, location,
  /// or any stocked medication matches. Capped at 6 so the dropdown stays
  /// compact.
  List<Pharmacy> _suggestionsFor(List<Pharmacy> all) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.location.toLowerCase().contains(q) ||
          p.region.toLowerCase().contains(q) ||
          p.stock.any((s) => s.medicationName.toLowerCase().contains(q));
    }).toList();
    // Prefer name matches first, then location, then medication.
    int score(Pharmacy p) {
      if (p.name.toLowerCase().contains(q)) return 0;
      if (p.location.toLowerCase().contains(q)) return 1;
      if (p.region.toLowerCase().contains(q)) return 2;
      return 3;
    }
    results.sort((a, b) => score(a).compareTo(score(b)));
    return results.take(6).toList();
  }

  /// Pick a pharmacy from the search suggestions: dismiss the dropdown,
  /// center the map on the pharmacy, and surface the bottom detail card.
  /// Keeps the typed query in the field so the user can quickly pick a
  /// different match.
  void _pickFromSearch(Pharmacy pharmacy) {
    _searchFocus.unfocus();
    setState(() {
      _showSuggestions = false;
      _selectedPharmacy = pharmacy;
    });
    _animatedMapMove(LatLng(pharmacy.latitude, pharmacy.longitude), 15.0);
  }

  // ── Acquire real GPS location ───────────────────────────────
  Future<void> _acquireUserLocation() async {
    // Wait until the location permission popup has been seen,
    // so we don't trigger the native browser prompt too early.
    bool promptSeen = false;
    while (!promptSeen) {
      final prefs = await SharedPreferences.getInstance();
      promptSeen = prefs.getBool('location_prompt_seen') ?? false;
      if (!promptSeen) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _fallbackToDefault('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _fallbackToDefault('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _fallbackToDefault('Location permission permanently denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _locatingUser = false;
        _locationAvailable = true;
      });
      context.read<AppState>().setUserLocation(
        position.latitude,
        position.longitude,
      );
      _animatedMapMove(_userLocation, 14.0);
    } catch (e) {
      _fallbackToDefault('Could not get location');
    }
  }

  void _fallbackToDefault(String reason) {
    if (!mounted) return;
    setState(() {
      _userLocation = _defaultUserLocation;
      _locatingUser = false;
      _locationAvailable = false;
    });
    context.read<AppState>().setUserLocation(
      _defaultUserLocation.latitude,
      _defaultUserLocation.longitude,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$reason — showing Beirut'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Animated map move ───────────────────────────────────────
  void _animatedMapMove(LatLng dest, double zoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: dest.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: dest.longitude,
    );
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) controller.dispose();
    });

    controller.forward();
  }

  // ── Filter pharmacies by search ─────────────────────────────
  List<Pharmacy> _filteredPharmacies(List<Pharmacy> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((p) {
      final nameMatch = p.name.toLowerCase().contains(q);
      final locationMatch = p.location.toLowerCase().contains(q);
      final medMatch = p.stock.any(
        (s) => s.medicationName.toLowerCase().contains(q),
      );
      return nameMatch || locationMatch || medMatch;
    }).toList();
  }

  // ── Sort pharmacies ─────────────────────────────────────────
  List<Pharmacy> _sortPharmacies(List<Pharmacy> list) {
    final sorted = List<Pharmacy>.from(list);
    switch (_sortBy) {
      case 'proximity':
        sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case 'rating':
        sorted.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'name':
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    return sorted;
  }

  // ── Select marker ───────────────────────────────────────────
  void _onMarkerTap(Pharmacy pharmacy) {
    setState(() => _selectedPharmacy = pharmacy);
    _animatedMapMove(LatLng(pharmacy.latitude, pharmacy.longitude), 15.0);
  }

  // ── Center on user ──────────────────────────────────────────
  void _centerOnUser() {
    if (_locationAvailable) {
      _animatedMapMove(_userLocation, 14.0);
      setState(() => _selectedPharmacy = null);
    } else {
      // Re-try getting location
      setState(() => _locatingUser = true);
      _acquireUserLocation();
    }
  }

  // ── Fit all pharmacies in view ──────────────────────────────
  void _fitAllPharmacies(List<Pharmacy> pharmacies) {
    if (pharmacies.isEmpty) return;
    final points =
        pharmacies.map((p) => LatLng(p.latitude, p.longitude)).toList()
          ..add(_userLocation);
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
    setState(() => _selectedPharmacy = null);
  }

  // ── User marker size (bigger when zoomed out) ───────────────
  double get _userMarkerSize {
    // At zoom 8 → 80px, at zoom 15+ → 44px
    return (120 - _currentZoom * 5).clamp(44.0, 100.0);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allPharmacies = appState.pharmacies;
    final filtered = _filteredPharmacies(allPharmacies);
    final sorted = _sortPharmacies(filtered);

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ─────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultUserLocation,
              initialZoom: _currentZoom,
              minZoom: 8,
              maxZoom: 18,
              onTap: (_, __) => setState(() => _selectedPharmacy = null),
              onPositionChanged: (pos, _) {
                setState(() => _currentZoom = pos.zoom);
              },
            ),
            children: [
              // ── Tile layer — CartoDB Voyager (clean, muted, professional)
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.medtrack360.app',
                maxZoom: 20,
                // Attribution overlay handled below
              ),

              // ── Pharmacy markers ────────────────────────────
              MarkerLayer(
                markers: [
                  // User location marker — scales with zoom
                  Marker(
                    point: _userLocation,
                    width: _userMarkerSize,
                    height: _userMarkerSize,
                    child: _UserLocationDot(size: _userMarkerSize),
                  ),

                  // Pharmacy markers
                  ...filtered.map((pharmacy) {
                    final isSelected = _selectedPharmacy?.id == pharmacy.id;
                    return Marker(
                      point: LatLng(pharmacy.latitude, pharmacy.longitude),
                      width: isSelected ? 52 : 44,
                      height: isSelected ? 62 : 54,
                      child: GestureDetector(
                        onTap: () => _onMarkerTap(pharmacy),
                        child: _PharmacyMarker(
                          pharmacy: pharmacy,
                          isSelected: isSelected,
                        ),
                      ),
                    );
                  }),
                ],
              ),

              // ── Map attribution (bottom-right, subtle) ──────
              const RichAttributionWidget(
                animationConfig: ScaleRAWA(),
                showFlutterMapAttribution: false,
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                  TextSourceAttribution('© CARTO'),
                ],
              ),
            ],
          ),

          // ── Top bar: search + sort ──────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  // Search field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onTap: () {
                          if (_searchQuery.trim().isNotEmpty) {
                            setState(() => _showSuggestions = true);
                          }
                        },
                        onChanged: (v) => setState(() {
                          _searchQuery = v;
                          _showSuggestions = v.trim().isNotEmpty;
                        }),
                        onSubmitted: (_) {
                          // Hitting "Search" jumps to the top suggestion.
                          final matches = _suggestionsFor(
                            context.read<AppState>().pharmacies,
                          );
                          if (matches.isNotEmpty) _pickFromSearch(matches.first);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search pharmacy or medication…',
                          hintStyle: const TextStyle(
                            color: MedTrackColors.textHint,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF546E7A),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                      _showSuggestions = false;
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Sort button
                  _MapActionButton(
                    icon: Icons.sort,
                    tooltip: 'Sort',
                    onTap: () => _showSortMenu(context),
                  ),
                ],
              ),
            ),
          ),

          // ── Search suggestions dropdown ─────────────────────
          if (_showSuggestions && _searchQuery.trim().isNotEmpty)
            _SuggestionsOverlay(
              suggestions: _suggestionsFor(allPharmacies),
              query: _searchQuery,
              onPick: _pickFromSearch,
            ),

          // ── Right-side action buttons ───────────────────────
          Positioned(
            right: 12,
            bottom: _selectedPharmacy != null ? 215 : (_showList ? 320 : 135),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapActionButton(
                  icon: Icons.my_location,
                  tooltip: 'My location',
                  onTap: _centerOnUser,
                ),
                const SizedBox(height: 8),
                _MapActionButton(
                  icon: Icons.zoom_out_map,
                  tooltip: 'Fit all',
                  onTap: () => _fitAllPharmacies(filtered),
                ),
                const SizedBox(height: 8),
                _MapActionButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onTap: () {
                    final z = (_currentZoom + 1).clamp(8.0, 18.0);
                    _mapController.move(_mapController.camera.center, z);
                  },
                ),
                const SizedBox(height: 8),
                _MapActionButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onTap: () {
                    final z = (_currentZoom - 1).clamp(8.0, 18.0);
                    _mapController.move(_mapController.camera.center, z);
                  },
                ),
              ],
            ),
          ),

          // ── Bottom: selected pharmacy card OR list toggle ───
          if (_selectedPharmacy != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: _SelectedPharmacyCard(
                pharmacy: _selectedPharmacy!,
                onClose: () => setState(() => _selectedPharmacy = null),
                onTap: () => _navigateToPharmacy(context, _selectedPharmacy!),
              ),
            ),

          // ── Bottom list toggle pill ─────────────────────────
          if (_selectedPharmacy == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomPharmacySheet(
                pharmacies: sorted,
                showList: _showList,
                onToggle: () => setState(() => _showList = !_showList),
                onPharmacyTap: (p) {
                  _onMarkerTap(p);
                  setState(() => _showList = false);
                },
                onNavigate: (p) => _navigateToPharmacy(context, p),
              ),
            ),

          // ── Locating indicator ──────────────────────────────
          if (_locatingUser)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MedTrackColors.info,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Getting your location…',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: MedTrackColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Location badge (bottom-left) ────────────────────
          if (!_locatingUser)
            Positioned(
              left: 12,
              bottom: _selectedPharmacy != null ? 210 : (_showList ? 220 : 75),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _locationAvailable ? Icons.gps_fixed : Icons.gps_off,
                      size: 14,
                      color: _locationAvailable
                          ? MedTrackColors.info
                          : MedTrackColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _locationAvailable
                          ? '${_userLocation.latitude.toStringAsFixed(4)}, ${_userLocation.longitude.toStringAsFixed(4)}'
                          : 'Default: Beirut',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _locationAvailable
                            ? MedTrackColors.textPrimary
                            : MedTrackColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: MedTrackColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Sort Pharmacies',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              _SortOption(
                icon: Icons.near_me,
                label: 'Nearest First',
                value: 'proximity',
                current: _sortBy,
                onTap: () {
                  setState(() => _sortBy = 'proximity');
                  Navigator.pop(context);
                },
              ),
              _SortOption(
                icon: Icons.star,
                label: 'Highest Rated',
                value: 'rating',
                current: _sortBy,
                onTap: () {
                  setState(() => _sortBy = 'rating');
                  Navigator.pop(context);
                },
              ),
              _SortOption(
                icon: Icons.sort_by_alpha,
                label: 'Name (A – Z)',
                value: 'name',
                current: _sortBy,
                onTap: () {
                  setState(() => _sortBy = 'name');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToPharmacy(BuildContext context, Pharmacy pharmacy) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PharmacyDetailScreen(pharmacy: pharmacy),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ── PRIVATE WIDGETS ──────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

/// Pulsing blue dot for user's location — scales with zoom
class _UserLocationDot extends StatefulWidget {
  final double size;
  const _UserLocationDot({required this.size});

  @override
  State<_UserLocationDot> createState() => _UserLocationDotState();
}

class _UserLocationDotState extends State<_UserLocationDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.28, end: 0.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final coreSize = (s * 0.34).clamp(14.0, 32.0);
    final ringSize = (s * 0.58).clamp(24.0, 54.0);

    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse halo
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF1976D2,
                  ).withValues(alpha: _pulseAnimation.value),
                ),
              ),
              // Mid ring
              Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1976D2).withValues(alpha: 0.18),
                ),
              ),
              // Core dot
              Container(
                width: coreSize,
                height: coreSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                  ),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1976D2).withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom pharmacy map marker — refined, professional pin
class _PharmacyMarker extends StatelessWidget {
  final Pharmacy pharmacy;
  final bool isSelected;
  const _PharmacyMarker({required this.pharmacy, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final baseColor = pharmacy.isOpen
        ? const Color(0xFF1B6E4F) // MedTrack primary green for open
        : const Color(0xFF90A4AE); // Muted blue-grey for closed

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(isSelected ? 7 : 5),
          decoration: BoxDecoration(
            color: isSelected ? baseColor : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: baseColor, width: isSelected ? 2.5 : 1.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isSelected ? 0.25 : 0.12),
                blurRadius: isSelected ? 10 : 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.local_pharmacy_rounded,
            size: isSelected ? 20 : 16,
            color: isSelected ? Colors.white : baseColor,
          ),
        ),
        // Pin tail triangle
        CustomPaint(
          size: const Size(10, 6),
          painter: _PinTailPainter(color: baseColor),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTailPainter old) => old.color != color;
}

/// Circular action button — frosted glass style
class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: const Color(0xFF37474F)),
          ),
        ),
      ),
    );
  }
}

/// Card that appears when a pharmacy marker is selected
class _SelectedPharmacyCard extends StatelessWidget {
  final Pharmacy pharmacy;
  final VoidCallback onClose;
  final VoidCallback onTap;
  const _SelectedPharmacyCard({
    required this.pharmacy,
    required this.onClose,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inStock = pharmacy.stock.where((s) => s.inStock).length;
    final total = pharmacy.stock.length;

    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Pharmacy icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: pharmacy.isOpen
                          ? MedTrackColors.successLight
                          : MedTrackColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_pharmacy,
                      color: pharmacy.isOpen
                          ? MedTrackColors.success
                          : MedTrackColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + address
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pharmacy.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pharmacy.location,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MedTrackColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.star,
                    label: '${pharmacy.rating}',
                    color: MedTrackColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.medication,
                    label: '$inStock/$total in stock',
                    color: MedTrackColors.primary,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.directions_walk,
                    label: '${pharmacy.distanceKm.toStringAsFixed(1)} km',
                    color: MedTrackColors.info,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: pharmacy.isOpen
                          ? MedTrackColors.successLight
                          : MedTrackColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pharmacy.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pharmacy.isOpen
                            ? MedTrackColors.success
                            : MedTrackColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Directions / details row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: const Text('Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MedTrackColors.primary,
                        side: const BorderSide(color: MedTrackColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1'
                          '&destination=${pharmacy.latitude},${pharmacy.longitude}',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not open maps')),
                          );
                        }
                      },
                      icon: const Icon(Icons.directions, size: 16),
                      label: const Text('Directions'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MedTrackColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet with pharmacy list + drag handle
class _BottomPharmacySheet extends StatelessWidget {
  final List<Pharmacy> pharmacies;
  final bool showList;
  final VoidCallback onToggle;
  final ValueChanged<Pharmacy> onPharmacyTap;
  final ValueChanged<Pharmacy> onNavigate;

  const _BottomPharmacySheet({
    required this.pharmacies,
    required this.showList,
    required this.onToggle,
    required this.onPharmacyTap,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle + summary bar ────────────────────────────
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MedTrackColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_pharmacy,
                        size: 20,
                        color: MedTrackColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${pharmacies.length} pharmacies nearby',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        showList
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: MedTrackColors.textHint,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Pharmacy horizontal list ────────────────────────
          if (showList)
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                itemCount: pharmacies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, idx) {
                  final p = pharmacies[idx];
                  final inStock = p.stock.where((s) => s.inStock).length;
                  return GestureDetector(
                    onTap: () => onPharmacyTap(p),
                    onDoubleTap: () => onNavigate(p),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MedTrackColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: MedTrackColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: p.isOpen
                                      ? MedTrackColors.successLight
                                      : MedTrackColors.errorLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.local_pharmacy,
                                  size: 18,
                                  color: p.isOpen
                                      ? MedTrackColors.success
                                      : MedTrackColors.error,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: MedTrackColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 14,
                                color: MedTrackColors.secondary,
                              ),
                              Text(
                                ' ${p.rating}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.medication,
                                size: 14,
                                color: MedTrackColors.textHint,
                              ),
                              Text(
                                ' $inStock/${p.stock.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: MedTrackColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${p.distanceKm.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: MedTrackColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Safe area bottom padding
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Radio-style sort option for the bottom sheet
class _SortOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String current;
  final VoidCallback onTap;

  const _SortOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? MedTrackColors.primary : MedTrackColors.textHint,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? MedTrackColors.primary : MedTrackColors.textPrimary,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: MedTrackColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

// Floating suggestions list shown under the search bar while typing.
// Tapping a row hands the pharmacy back to the map screen via [onPick].
class _SuggestionsOverlay extends StatelessWidget {
  final List<Pharmacy> suggestions;
  final String query;
  final void Function(Pharmacy) onPick;

  const _SuggestionsOverlay({
    required this.suggestions,
    required this.query,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Sits flush below the search bar (12 + ~52 row + 8 gap).
        padding: const EdgeInsets.fromLTRB(12, 72, 12, 0),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: suggestions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_off_rounded,
                          size: 18,
                          color: MedTrackColors.textHint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No pharmacies match "$query"',
                            style: const TextStyle(
                              fontSize: 13,
                              color: MedTrackColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: suggestions.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: MedTrackColors.divider,
                    ),
                    itemBuilder: (_, i) {
                      final p = suggestions[i];
                      final subtitle = [
                        if (p.location.isNotEmpty) p.location,
                        if (p.region.isNotEmpty) p.region,
                      ].join(' · ');
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: MedTrackColors.primary.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.local_pharmacy_rounded,
                            size: 20,
                            color: MedTrackColors.primary,
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: subtitle.isEmpty
                            ? null
                            : Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: MedTrackColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(
                          Icons.north_east_rounded,
                          size: 16,
                          color: MedTrackColors.textHint,
                        ),
                        onTap: () => onPick(p),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
