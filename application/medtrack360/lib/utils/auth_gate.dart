import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../theme/app_theme.dart';

/// Shows a polished modal bottom sheet asking the user to sign in.
/// [icon], [title] and [subtitle] let callers tune the copy for a specific
/// action (e.g. watchlist vs. writing a review).
Future<void> showSignInRequiredSheet(
  BuildContext context, {
  IconData icon = Icons.lock_outline_rounded,
  String title = 'Sign in to continue',
  String subtitle = 'Create an account or sign in to access this feature.',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _SignInRequiredSheet(
      icon: icon,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _SignInRequiredSheet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SignInRequiredSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: MedTrackColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: MedTrackColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    MedTrackColors.primary.withValues(alpha: 0.12),
                    MedTrackColors.secondary.withValues(alpha: 0.18),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: MedTrackColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: MedTrackColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: MedTrackColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MedTrackColors.primary,
                  foregroundColor: MedTrackColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.login_rounded, size: 20),
                label: const Text('Sign in'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MedTrackColors.primary,
                  side: const BorderSide(color: MedTrackColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Create account'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute(builder: (_) => const SignUpScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: MedTrackColors.textHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
