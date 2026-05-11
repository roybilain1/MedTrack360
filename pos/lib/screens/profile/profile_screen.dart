import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// ── Pharmacy / branch data ─────────────────────────────────────────────────
// These values must match the node record in the MoPH Command Center
// (System Governance → Network Pulse table: HWID HW-00423).

const _kBranch = 'Al-Amin Pharmacy';
const _kLicense = 'LIC-BEY-0041';
const _kHwid = 'HW-00423'; // Hardware node ID assigned by MoPH
const _kAddress = 'Hamra St., Beirut, Lebanon';
const _kHours = 'Mon – Sat  08:00 – 20:00';
const _kMoPH = 'MoPH-registered · Controlled class A–D';
const _kPhone = '+961 1 750 000';
const _kEmail = 'alamin@medtrack.io';
const _kSyncVer = 'v2.6.1'; // Must match Command Center's expected sync version

// ═════════════════════════════════════════════════════════════════════════════

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: MedTrackShapes.cardRadius),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MedTrackColors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.power_settings_new_rounded,
                color: MedTrackColors.error,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Exit MedTrack 360'),
          ],
        ),
        content: const Text(
          'All unsaved changes will be lost.\n'
          'Are you sure you want to close the application?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MedTrackColors.error,
              shape: const RoundedRectangleBorder(
                borderRadius: MedTrackShapes.buttonRadius,
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (confirmed == true) exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_pharmacy_rounded,
                  color: MedTrackColors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Pharmacy Information',
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Pharmacy overview card ────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MedTrackColors.surface,
              borderRadius: MedTrackShapes.cardRadius,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: MedTrackShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gradient banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        MedTrackColors.teal,
                        MedTrackColors.teal.withValues(alpha: 0.80),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.local_pharmacy_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _kBranch,
                                  style: tt.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$_kLicense · $_kHwid',
                                  style: tt.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.90),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Info grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.location_on_outlined,
                              'Address',
                              _kAddress,
                            ),
                          ),
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.phone_outlined,
                              'Contact',
                              _kPhone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.access_time_rounded,
                              'Working Hours',
                              _kHours,
                            ),
                          ),
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.badge_outlined,
                              'License',
                              _kLicense,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.email_outlined,
                              'Branch Email',
                              _kEmail,
                            ),
                          ),
                          Expanded(
                            child: _PharmacyInfoRow(
                              Icons.medical_services_outlined,
                              'MoPH Status',
                              _kMoPH,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Command Center Connection ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MedTrackColors.surface,
              borderRadius: MedTrackShapes.cardRadius,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: MedTrackShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      size: 16,
                      color: MedTrackColors.teal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MoPH Command Center',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: MedTrackColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This device is a registered POS node. Sales, price violations, '
                  'and stock movements are synced to the Command Center after each '
                  'transaction. MoPH officials monitor this node via system governance.',
                  style: tt.bodySmall?.copyWith(
                    color: MedTrackColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _CmdCenterRow(
                        Icons.router_rounded,
                        'Node HWID',
                        _kHwid,
                        highlight: true,
                      ),
                    ),
                    Expanded(
                      child: _CmdCenterRow(
                        Icons.verified_rounded,
                        'Sync Version',
                        _kSyncVer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CmdCenterRow(
                        Icons.link_rounded,
                        'License',
                        _kLicense,
                      ),
                    ),
                    Expanded(
                      child: _CmdCenterRow(
                        Icons.wifi_rounded,
                        'Command Center',
                        'Synced · 34 ms',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Exit button ───────────────────────────────────────────────────
          SizedBox(
            width: 280,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _confirmExit(context),
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text('Exit Application'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MedTrackColors.error,
                side: const BorderSide(color: MedTrackColors.error, width: 1.5),
                shape: const RoundedRectangleBorder(
                  borderRadius: MedTrackShapes.buttonRadius,
                ),
                textStyle: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────

class _CmdCenterRow extends StatelessWidget {
  const _CmdCenterRow(
    this.icon,
    this.label,
    this.value, {
    this.highlight = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: MedTrackColors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: tt.bodySmall?.copyWith(
                  color: highlight
                      ? MedTrackColors.teal
                      : MedTrackColors.textPrimary,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: highlight ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────

class _PharmacyInfoRow extends StatelessWidget {
  const _PharmacyInfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: MedTrackColors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  color: MedTrackColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: tt.bodySmall?.copyWith(
                  color: MedTrackColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
