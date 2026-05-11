import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Shows a compact location-permission popup dialog.
/// Returns `true` if the user granted permission, `false` if skipped.
Future<bool> showLocationPermissionPopup(BuildContext context) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Location Permission',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (ctx, a1, a2, child) {
      final curved = CurvedAnimation(parent: a1, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(curved),
        child: FadeTransition(opacity: a1, child: child),
      );
    },
    pageBuilder: (ctx, _, __) => const _LocationPermissionDialog(),
  );
  return result ?? false;
}

// ═══════════════════════════════════════════════════════════════
class _LocationPermissionDialog extends StatefulWidget {
  const _LocationPermissionDialog();

  @override
  State<_LocationPermissionDialog> createState() =>
      _LocationPermissionDialogState();
}

class _LocationPermissionDialogState extends State<_LocationPermissionDialog> {
  bool _requesting = false;

  Future<void> _allowLocation() async {
    setState(() => _requesting = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      }
    } catch (_) {}

    await _markSeenAndClose(true);
  }

  Future<void> _skip() async {
    await _markSeenAndClose(false);
  }

  Future<void> _markSeenAndClose(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_prompt_seen', true);
    if (!mounted) return;
    Navigator.of(context).pop(granted);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Location icon ─────────────────────────────
                _buildIcon(),
                const SizedBox(height: 20),

                // ── Title ─────────────────────────────────────
                const Text(
                  'Find Nearby Pharmacies',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: MedTrackColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Description ───────────────────────────────
                Text(
                  'Allow location access to discover pharmacies near you and get directions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: MedTrackColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Features ──────────────────────────────────
                _buildFeature(
                  Icons.near_me_rounded,
                  'Sorted by distance',
                  MedTrackColors.info,
                ),
                const SizedBox(height: 8),
                _buildFeature(
                  Icons.map_rounded,
                  'See your location on the map',
                  MedTrackColors.teal,
                ),
                const SizedBox(height: 8),
                _buildFeature(
                  Icons.directions_rounded,
                  'Get directions to pharmacies',
                  MedTrackColors.secondary,
                ),
                const SizedBox(height: 24),

                // ── Allow button ──────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1A3A4A),
                          Color(0xFF1B5E4B),
                          Color(0xFF1A7365),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1B5E4B,
                          ).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _requesting ? null : _allowLocation,
                      icon: _requesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                      label: Text(
                        _requesting ? 'Requesting...' : 'Allow Location',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Skip button ───────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: TextButton(
                    onPressed: _requesting ? null : _skip,
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Maybe Later',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: MedTrackColors.textHint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Privacy note ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 12,
                      color: MedTrackColors.textHint.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Your location stays on your device',
                      style: TextStyle(
                        fontSize: 11,
                        color: MedTrackColors.textHint.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            MedTrackColors.teal.withValues(alpha: 0.10),
            MedTrackColors.info.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.3, 0.7, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: MedTrackColors.teal.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),
          // Inner circle
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: MedTrackColors.teal.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 26,
              color: MedTrackColors.teal,
            ),
          ),
          // Small pharmacy badge
          Positioned(
            top: 4,
            right: 2,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_pharmacy_rounded,
                size: 13,
                color: MedTrackColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MedTrackColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
