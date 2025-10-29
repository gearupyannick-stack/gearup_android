// lib/pages/training_page.dart
import 'dart:async';
import 'package:flutter/material.dart';

// Keep existing relative imports to your challenge pages:
import 'challenges/brand_challenge_page.dart';
import 'challenges/models_by_brand_challenge_page.dart';
import 'challenges/model_challenge_page.dart';
import 'challenges/origin_challenge_page.dart';
import 'challenges/engine_type_challenge_page.dart';
import 'challenges/max_speed_challenge_page.dart';
import 'challenges/acceleration_challenge_page.dart';
import 'challenges/power_challenge_page.dart';
import 'challenges/special_feature_challenge_page.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/premium_service.dart';
import 'premium_page.dart';
import '../services/audio_feedback.dart'; // keep your audio hook if used

// New: ads + persistence for temporary ad-granted trials
import '../services/ad_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef VoidAsync = Future<void> Function();

class TrainingPage extends StatefulWidget {
  final VoidAsync? onLifeWon;
  final VoidCallback? recordChallengeCompletion;
  const TrainingPage({Key? key, this.onLifeWon, this.recordChallengeCompletion}) : super(key: key);

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  // define which challenges are gated (the rest will be free always)
  static const List<String> _gatedTitles = [
    'Origin',
    'Engine Type',
    'Max Speed',
    'Acceleration',
    'Power',
    'Special Feature',
  ];

  // free (always open)
  static final List<_Challenge> _alwaysFree = [
    _Challenge('Brand', BrandChallengePage()),
    _Challenge('Models by Brand', ModelsByBrandChallengePage()),
    _Challenge('Model', ModelChallengePage()),
  ];

  // gated list
  static final List<_Challenge> _gated = [
    _Challenge('Origin', OriginChallengePage()),
    _Challenge('Engine Type', EngineTypeChallengePage()),
    _Challenge('Max Speed', MaxSpeedChallengePage()),
    _Challenge('Acceleration', AccelerationChallengePage()),
    _Challenge('Power', PowerChallengePage()),
    _Challenge('Special Feature', SpecialFeatureChallengePage()),
  ];

  // merged list for display order (you can reorder if desired)
  late final List<_Challenge> _challenges = [
    ..._alwaysFree,
    ..._gated,
  ];

  // --- Temp storage key for ad-granted trials (fallback if PremiumService has no grant method)
  static const String _kTempAdTrialsKey = 'temp_rewarded_training_trials';

  // local counter used to add trials granted by watching rewarded ads (persisted)
  int _tempAdGrantedTrials = 0;

  // Completer used to wait for the ad reward callback
  Completer<bool>? _adGrantCompleter;

  @override
  void initState() {
    super.initState();
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}

    // Load persisted temporary ad trials
    _loadTempAdTrials();
    // Make sure PremiumService is initialized in app start (Main). If not, ensure init is called elsewhere.
  }

  Future<void> _loadTempAdTrials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_kTempAdTrialsKey) ?? 0;
      if (mounted) {
        setState(() {
          _tempAdGrantedTrials = v;
        });
      } else {
        _tempAdGrantedTrials = v;
      }
    } catch (e) {
      debugPrint('Failed to load temp ad trials: $e');
    }
  }

  Future<void> _saveTempAdTrials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTempAdTrialsKey, _tempAdGrantedTrials);
    } catch (e) {
      debugPrint('Failed to save temp ad trials: $e');
    }
  }

  Future<void> _handleAdGrantedTrials() async {
    debugPrint('[_handleAdGrantedTrials] reward callback entered');

    try {
      final premium = PremiumService.instance;

      // 1) Always update local fallback first so UI reflects the grant immediately
      if (mounted) {
        setState(() {
          _tempAdGrantedTrials += 5;
        });
      } else {
        _tempAdGrantedTrials += 5;
      }

      // Persist immediately so subsequent reads see the value.
      await _saveTempAdTrials();
      debugPrint('[_handleAdGrantedTrials] local _tempAdGrantedTrials updated -> $_tempAdGrantedTrials');

      // 2) Also try to update PremiumService if it exposes an API (best-effort)
      try {
        final dynamic dyn = premium as dynamic;
        if (dyn.grantTrainingTrials != null) {
          try { dyn.grantTrainingTrials(5); debugPrint('[_handleAdGrantedTrials] premium.grantTrainingTrials called'); } catch (_) {}
        } else if (dyn.addTrainingAttempts != null) {
          try { dyn.addTrainingAttempts(5); debugPrint('[_handleAdGrantedTrials] premium.addTrainingAttempts called'); } catch (_) {}
        } else if (dyn.addTrainingTrials != null) {
          try { dyn.addTrainingTrials(5); debugPrint('[_handleAdGrantedTrials] premium.addTrainingTrials called'); } catch (_) {}
        } else if (dyn.increaseTrainingAttempts != null) {
          try { dyn.increaseTrainingAttempts(5); debugPrint('[_handleAdGrantedTrials] premium.increaseTrainingAttempts called'); } catch (_) {}
        } else {
          debugPrint('[_handleAdGrantedTrials] no premium grant API found (ok)');
        }
      } catch (e) {
        debugPrint('[_handleAdGrantedTrials] attempted premium API call failed: $e');
      }

    } catch (e) {
      debugPrint('[_handleAdGrantedTrials] error: $e');
    } finally {
      // Signal the waiting flow (if any)
      try {
        _adGrantCompleter?.complete(true);
      } catch (_) {}
    }
  }

  /// Entry point when user taps a challenge button.
  /// This function handles:
  ///  - gating by premium & daily limit
  ///  - consuming temp ad-granted trials if present
  ///  - showing the "limit reached" dialog offering "Watch ad for +5 trials"
  Future<void> _maybeStartChallenge(String title, Widget page) async {
    final premium = PremiumService.instance;

    final bool isGated = _gatedTitles.contains(title);

    if (isGated && !premium.isPremium) {
      // If user has temp ad-granted trials, consume one first.
      if (_tempAdGrantedTrials > 0) {
        if (mounted) {
          setState(() {
            _tempAdGrantedTrials -= 1;
          });
        } else {
          _tempAdGrantedTrials -= 1;
        }
        await _saveTempAdTrials();

        // Navigate to challenge (we consumed one temp trial)
        await _navigateToChallenge(page);
        return;
      }

      // If they can start (under daily free limit), record & go
      if (premium.canStartTrainingNow()) {
        await premium.recordTrainingStart();
        await _navigateToChallenge(page);
        return;
      }

      // Otherwise: daily limit reached — offer upgrade or rewarded ad
      await _showLimitReachedDialog(title, page);
      return;
    }

    // not gated or premium user: just go
    if (isGated && premium.isPremium) {
      await _navigateToChallenge(page);
    } else if (!isGated) {
      await _navigateToChallenge(page);
    }
  }

  Future<void> _navigateToChallenge(Widget page) async {
    // open the challenge page and wait until the user returns
    final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    // --- refresh local persisted temp trials so UI shows correct remaining immediately
    try {
      await _loadTempAdTrials();
    } catch (e) {
      debugPrint('_navigateToChallenge: _loadTempAdTrials failed: $e');
    }

    // --- best-effort: ask PremiumService to refresh its internal counters if such method exists
    try {
      final premium = PremiumService.instance;
      final dynamic dyn = premium as dynamic;
      if (dyn.refresh != null) {
        await dyn.refresh();
      } else if (dyn.reload != null) {
        await dyn.reload();
      } else if (dyn.sync != null) {
        await dyn.sync();
      }
    } catch (_) {
      // ignore; PremiumService may not have those methods — that's fine
    }

    // Force a rebuild so the header counter reads the fresh values (premium.remainingTrainingAttempts + _tempAdGrantedTrials)
    if (mounted) setState(() {});

    // If the pushed challenge returned `true`, treat that as a successful completion
    // and notify the parent via onLifeWon so it can actually increment lives & refresh UI.
    try {
      if (result == true) {
        await widget.onLifeWon?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('+1 life earned!')));
        }
      }
    } catch (e) {
      debugPrint('TrainingPage: error awarding life after training: $e');
    }

    // existing behaviour: call optional external callback to record completion
    widget.recordChallengeCompletion?.call();

    // increment challenge counter (and show interstitial per your rule every 5)
    try {
      await AdService.instance.incrementChallengeAndMaybeShow();
    } catch (e) {
      debugPrint('AdService.incrementChallengeAndMaybeShow error: $e');
    }
  }

  // Dialog shown when free daily attempts are exhausted for non-premium users.
  // Offers: Close / Watch ad to get +5 trials / Upgrade
  Future<void> _showLimitReachedDialog(String title, Widget page) async {
    // Show dialog - actions only return a String result; navigation occurs after the dialog is dismissed
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Daily limit reached"),
        content: const Text(
          "Free users can try 5 gated Training challenges per day.\n\n"
          "You can upgrade for unlimited access or watch a short ad to get +5 trials now.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text("Close")),
          TextButton(onPressed: () => Navigator.pop(ctx, 'upgrade'), child: const Text("Upgrade")),
          TextButton(onPressed: () => Navigator.pop(ctx, 'watch'), child: const Text("Watch ad (+5)")),
        ],
      ),
    );

    if (result == 'upgrade') {
      // Use the root navigator to reliably open the Premium page from a dialog context
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const PremiumPage()),
      );
      return;
    } else if (result == 'watch') {
      // Show a small loading Snack while ad loads/shows
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('Loading ad...')));

      // Prepare a completer so we can wait until the reward callback runs
      _adGrantCompleter = Completer<bool>();

      // Show the rewarded ad; pass our page handler so the reward callback executes inside this state
      try {
        await AdService.instance.showRewardedTrainingTrials(
          onGrantedTrials: (RewardItem reward) {
            // we don't need the reward fields here — run the handler that grants +5
            _handleAdGrantedTrials();
          },
        );
      } catch (e) {
        debugPrint('Error while showing rewarded training ad: $e');
      }

      // Remove loading snack
      try { messenger.clearSnackBars(); } catch (_) {}

      // Wait for the grant to happen (completer) with a timeout (5s)
      bool granted = false;
      try {
        granted = await _adGrantCompleter!.future.timeout(const Duration(seconds: 6));
      } catch (_) {
        granted = false;
      } finally {
        // cleanup
        _adGrantCompleter = null;
      }

      // If the grant was acknowledged (true) OR PremiumService now allows starts, navigate.
      final premium = PremiumService.instance;
      if (granted) {
        // consume one trial immediately and navigate
        if (mounted) {
          setState(() {
            if (_tempAdGrantedTrials > 0) _tempAdGrantedTrials -= 1;
          });
        } else {
          if (_tempAdGrantedTrials > 0) _tempAdGrantedTrials -= 1;
        }
        await _saveTempAdTrials();
        await _navigateToChallenge(page);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — +5 trials granted!')));
        return;
      }

      // Sometimes the PremiumService may have been updated directly by our handler.
      try {
        if (premium.canStartTrainingNow()) {
          await premium.recordTrainingStart();
          await _navigateToChallenge(page);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks — +5 trials granted!')));
          return;
        }
      } catch (_) {
        // ignore
      }

      // failed to obtain grant
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad unavailable — please try again later.')));
    } else {
      // closed dialog -> nothing to do
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumService.instance;
    final isPremium = premium.isPremium;

    // Show remaining for gated challenges only:
    // Use premium.remainingTrainingAttempts() + _tempAdGrantedTrials so ad-grants are visible immediately.
    int remainingInt = 0;
    try {
      remainingInt = isPremium ? 9999 : (premium.remainingTrainingAttempts() + _tempAdGrantedTrials);
    } catch (_) {
      // if PremiumService API is missing, just show temp trials
      remainingInt = _tempAdGrantedTrials;
    }
    final remaining = isPremium ? '∞' : remainingInt.toString();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + remaining counter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Training", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    const Icon(Icons.fitness_center, size: 18),
                    const SizedBox(width: 6),
                    Text("Paid challenge remaining: $remaining", style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    if (!isPremium)
                      TextButton(
                        onPressed: () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(builder: (_) => const PremiumPage()),
                        ),
                        child: const Text("Upgrade"),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Buttons grid
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 1.2, crossAxisSpacing: 12, mainAxisSpacing: 12,
                ),
                itemCount: _challenges.length,
                itemBuilder: (context, index) {
                  final c = _challenges[index];
                  final bool isGatedItem = _gatedTitles.contains(c.title);
                  return ElevatedButton(
                    onPressed: () => _maybeStartChallenge(c.title, c.page),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Stack(
                      children: [
                        Center(child: Text(c.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
                        if (isGatedItem)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(Icons.lock, size: 16, color: premium.isPremium ? Colors.amber : Colors.white70),
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
  }
}

class _Challenge {
  final String title;
  final Widget page;
  const _Challenge(this.title, this.page);
}