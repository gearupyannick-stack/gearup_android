// lib/pages/origin_challenge_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:easy_localization/easy_localization.dart';
import '../../services/audio_feedback.dart'; // added by audio patch
import '../../widgets/enhanced_answer_button.dart';
import '../../widgets/question_progress_bar.dart';
import '../../widgets/animated_score_display.dart';
import '../../widgets/challenge_completion_dialog.dart';

import '../../services/image_service_cache.dart'; // ← Utilisation du cache local

class OriginChallengePage extends StatefulWidget {
  @override
  _OriginChallengePageState createState() => _OriginChallengePageState();
}

class _OriginChallengePageState extends State<OriginChallengePage> {
  // ── Data ───────────────────────────────────────────────────────────────────
  final List<Map<String, String>> _carData = [];
  List<String> _options = [];

  String? _currentBrand;
  String? _currentModel;
  String  _correctOrigin = '';

  // ── Quiz progress ────────────────────────────────────────────────────────────
  int    _questionCount  = 0;
  int    _correctAnswers = 0;
  int    _elapsedSeconds = 0;
  Timer? _quizTimer;

  // ── Frame animation ─────────────────────────────────────────────────────────
  int    _frameIndex = 0;
  Timer? _frameTimer;
  static const int _maxFrames = 6;

  // ── Answer‐highlighting ─────────────────────────────────────────────────────
  String? _selectedOrigin;
  bool    _answered      = false;
  List<bool> _answerHistory = [];

  int _currentStreak = 0;
  bool _showScoreChange = false;
  bool _wasLastAnswerCorrect = false;

  @override
  void initState() {
    super.initState();
    
    // audio: page open
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
_loadCsv();

    // overall quiz timer
    _quizTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });

    _startFrameTimer();
  }

  void _startFrameTimer() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_answered) {
        setState(() {
          _frameIndex = (_frameIndex + 1) % _maxFrames;
        });
      }
    });
  }

  void _goToNextFrame() {
    if (_answered) return;
    setState(() {
      _frameIndex = (_frameIndex + 1) % _maxFrames;
    });
    _startFrameTimer();
  }

  void _goToPreviousFrame() {
    if (_answered) return;
    setState(() {
      _frameIndex = (_frameIndex - 1 + _maxFrames) % _maxFrames;
    });
    _startFrameTimer();
  }

  @override
  void dispose() {
    _quizTimer?.cancel();
    _frameTimer?.cancel();
        // audio: page close
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}

super.dispose();
  }

  Future<void> _loadCsv() async {
    final raw = await rootBundle.loadString('assets/cars.csv');
    final lines = const LineSplitter().convert(raw);
    for (var line in lines) {
      final parts = line.split(',');
      if (parts.length >= 10) {
        _carData.add({
          'brand'  : parts[0].trim(),
          'model'  : parts[1].trim(),
          'origin' : parts[9].trim(),
        });
      }
    }
    _nextQuestion();
  }

  void _nextQuestion() {
    if (_questionCount >= 20) {
      return _finishQuiz();
    }
    _questionCount++;
    _selectedOrigin = null;
    _answered       = false;

    final rnd = Random();
    final row = _carData[rnd.nextInt(_carData.length)];
    _currentBrand  = row['brand'];
    _currentModel  = row['model'];
    _correctOrigin = row['origin']!;

    // Build 4 distinct options with uniqueness check
    final used = <String>{_correctOrigin};
    final opts = [_correctOrigin];
    while (opts.length < 4) {
      final candidate = _carData[rnd.nextInt(_carData.length)]['origin']!;
      if (!used.contains(candidate)) {
        used.add(candidate);
        opts.add(candidate);
      }
    }

    setState(() {
      _options = opts..shuffle();
    });
  }

  void _onTap(String selection) {
    if (_answered) return;
    final isCorrect = selection == _correctOrigin;

    setState(() {
      _selectedOrigin = selection;
      _answered       = true;
      if (isCorrect) {
        _correctAnswers++;
      }
      _answerHistory.add(isCorrect);

      if (isCorrect) {
        _currentStreak++;
      } else {
        _currentStreak = 0;
      }
      _wasLastAnswerCorrect = isCorrect;
      _showScoreChange = true;
    });

    // Reset the animation flag after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _showScoreChange = false;
        });
      }
    });

    // Play appropriate answer feedback sound
    try {
      AudioFeedback.instance.playEvent(
        isCorrect ? SoundEvent.answerCorrect : SoundEvent.answerWrong
      );
    } catch (_) {}

    Future.delayed(const Duration(seconds: 1), _nextQuestion);
  }

  void _finishQuiz() {
    _quizTimer?.cancel();
    _frameTimer?.cancel();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChallengeCompletionDialog(
        correctAnswers: _correctAnswers,
        totalQuestions: 20,
        totalSeconds: _elapsedSeconds,
        onClose: () {
          Navigator.of(ctx).pop();
          if (_correctAnswers >= 10) {
            Navigator.of(context).pop(true);
          } else {
            Navigator.pop(
              context,
              '$_correctAnswers/20 in ${_elapsedSeconds ~/ 60}\'${(_elapsedSeconds % 60).toString().padLeft(2, '0')}\'\'',
            );
          }
        },
      ),
    );
  }

  /// Sanitizes "BrandModel" into your file-base, e.g. "Porsche911".
  String _fileBase(String brand, String model) {
    final combined = (brand + model).replaceAll(RegExp(r'[ ./]'), '');
    return combined
        .split(RegExp(r'(?=[A-Z])|(?<=[a-z])(?=[A-Z])|(?<=[a-z])(?=[0-9])'))
        .map((w) =>
            w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : '')
        .join();
  }

  /// Displays the current frame image from cache instead of FutureBuilder.
  Widget _buildFrameImage() {
    final base = _fileBase(_currentBrand!, _currentModel!);
    final fileName = '$base$_frameIndex.webp';
    return Image(
      key: ValueKey<int>(_frameIndex),
      image: ImageCacheService.instance.imageProvider(fileName),
      height: 220,
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text('challenges.origin'.tr()),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                'Time: $minutes:$seconds | Q: $_questionCount/20',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: _currentBrand == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                QuestionProgressBar(
                  currentQuestion: _questionCount,
                  totalQuestions: 20,
                  answeredCorrectly: _answerHistory,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  AnimatedScoreDisplay(
                    currentScore: _correctAnswers,
                    totalQuestions: 20,
                    currentStreak: _currentStreak,
                    showScoreChange: _showScoreChange,
                    wasCorrect: _wasLastAnswerCorrect,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'challenges.whatOrigin'.tr() + ' ${_currentBrand!}?',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // rotating car image fetched from cache
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: _buildFrameImage(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Manual frame controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, size: 20),
                        onPressed: _answered ? null : _goToPreviousFrame,
                        color: Colors.white70,
                      ),
                      Text(
                        '${_frameIndex + 1}/$_maxFrames',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 20),
                        onPressed: _answered ? null : _goToNextFrame,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _maxFrames,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _frameIndex == index
                              ? Colors.red
                              : Colors.grey.withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // answer buttons
                  for (var origin in _options)
                    EnhancedAnswerButton(
                      text: origin,
                      backgroundColor: _answered
                          ? (origin == _correctOrigin
                              ? Colors.green
                              : (origin == _selectedOrigin
                                  ? Colors.red
                                  : Colors.grey[800]!))
                          : Colors.grey[800]!,
                      onTap: () => _onTap(origin),
                      isDisabled: _answered,
                    ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}