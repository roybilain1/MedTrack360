import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/medication.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'auth_gate.dart';

/// Toggle a medication in the signed-in user's watchlist. Prompts for
/// sign-in via a modal bottom sheet when the user is a guest and surfaces
/// any server error via a SnackBar.
Future<void> toggleWatchlist(BuildContext context, Medication medication) async {
  final appState = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);

  if (!appState.isLoggedIn) {
    await showSignInRequiredSheet(
      context,
      icon: Icons.bookmark_added_rounded,
      title: 'Sign in to save this',
      subtitle:
          'Your watchlist is tied to your MedTrack360 account so it stays '
          'in sync across every device you use.',
    );
    return;
  }

  try {
    if (appState.isInWatchlist(medication.key)) {
      await appState.removeFromWatchlist(medication.key);
    } else {
      await appState.addToWatchlist(medication);
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: MedTrackColors.error,
      ),
    );
  }
}
