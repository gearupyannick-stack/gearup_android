// lib/pages/training_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/lives_storage.dart';
import 'challenges/brand_challenge_page.dart';
import 'challenges/models_by_brand_challenge_page.dart';
import 'challenges/model_challenge_page.dart';
import 'challenges/origin_challenge_page.dart';
import 'challenges/engine_type_challenge_page.dart';
import 'challenges/max_speed_challenge_page.dart';
import 'challenges/acceleration_challenge_page.dart';
import 'challenges/power_challenge_page.dart';
import 'challenges/special_feature_challenge_page.dart';
import '../services/audio_feedback.dart';

// Premium imports
import '../services/premium_service.dart';
import 'premium_page.dart';

class TrainingPage extends StatefulWidget {
  final VoidCallback? onLifeWon;
  final VoidCallback? recordChallengeCompletion;

  TrainingPage({this.onLifeWon, this.recordChallengeCompletion});

  @override
  _TrainingPageState createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final LivesStorage livesStorage = LivesStorage();

  Map<String, String> bestResults = {
    'Brand': 'Brand - New challenge',
    'Models by Brand': 'Models by Brand - New challenge',
    'Model': 'Model - New challenge',
    'Origin': 'Origin - New challenge',
    'Engine Type': 'Engine Type - New challenge',
    'Max Speed': 'Max Speed - New challenge',
    'Acceleration': 'Acceleration - New challenge',
    'Power': 'Power - New challenge',
    'Special Feature': 'Special Feature - New challenge',
  };

  // Which training tiles are gated (count against daily free attempts)
  final Set<String> _gatedTitles = {
    'Engine Type',
    'Max Speed',
    'Acceleration',
    'Power',
    'Special Feature',
  };

  @override
  void initState() {
    super.initState();

    // audio: page open
    try {
      AudioFeedback.instance.playEvent(SoundEvent.pageOpen);
    } catch (_) {}

    _loadBestResults();

    // Ensure PremiumService is initialised earlier in main.dart, but refresh view
    // in case it was loaded after this page was created.
    PremiumService.instance.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadBestResults() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      bestResults.forEach((label, _) {
        final key = 'best_${label.replaceAll(' ', '')}';
        bestResults[label] = prefs.getString(key) ?? '$label - New challenge';
      });
    });
  }

  /// Helper for "Coming soon" buttons
  Widget _buildComingSoonButton(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () {
          try {
            AudioFeedback.instance.playEvent(SoundEvent.tap);
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coming soon'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildButton(String label, Widget page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () => _maybeStartChallenge(label, page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(bestResults[label]!, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Future<void> _maybeStartChallenge(String title, Widget page) async {
    try {
      AudioFeedback.instance.playEvent(SoundEvent.tap);
    } catch (_) {}

    final premium = PremiumService.instance;
    final bool isGated = _gatedTitles.contains(title);

    // If gated and not premium and no remaining attempts -> prompt upgrade
    if (isGated && !premium.isPremium && !premium.canStartTrainingNow()) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Besoin de plus d\'essais'),
          content: const Text('Tu as atteint la limite gratuite pour les challenges avancés. Passe Premium pour des essais illimités.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Plus tard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
              },
              child: const Text('Passer Premium'),
            ),
          ],
        ),
      );
      return;
    }

    // If allowed and user is not premium and this is gated, record the attempt
    if (isGated && !premium.isPremium) {
      await premium.recordTrainingStart();
      // refresh UI to show updated remaining count
      if (mounted) setState(() {});
    }

    // Push the challenge page and await result (original behavior)
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    // Optionally call the callback passed by parent to register completion
    try {
      widget.recordChallengeCompletion?.call();
    } catch (_) {}
  }

  Widget _buildGatedStatus() {
    final premium = PremiumService.instance;
    final remaining = premium.isPremium ? '∞' : premium.remainingTrainingAttempts().toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text('Gated remaining: $remaining', style: const TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Show gated status row at top (helps user see remaining attempts)
          _buildGatedStatus(),
          _buildButton('Brand', BrandChallengePage()),
          _buildButton('Models by Brand', ModelsByBrandChallengePage()),
          _buildButton('Model', ModelChallengePage()),
          _buildButton('Origin', OriginChallengePage()),
          _buildButton('Engine Type', EngineTypeChallengePage()),
          _buildButton('Max Speed', MaxSpeedChallengePage()),
          _buildButton('Acceleration', AccelerationChallengePage()),
          _buildButton('Power', PowerChallengePage()),
          _buildButton('Special Feature', SpecialFeatureChallengePage()),
          const SizedBox(height: 24),
          _buildComingSoonButton('Engine Sound'),
          _buildComingSoonButton('Head lights'),
          _buildComingSoonButton('Rear Lights'),
          _buildComingSoonButton('Signals'),
        ],
      ),
    );
  }
}