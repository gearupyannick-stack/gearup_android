import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../services/audio_feedback.dart';
import '../services/image_service_cache.dart';

class RacePage extends StatefulWidget {
  const RacePage({Key? key}) : super(key: key);

  @override
  State<RacePage> createState() => _RacePageState();
}

// --- Audio + streak mixin used by many question State classes ---
mixin AudioAnswerMixin<T extends StatefulWidget> on State<T> {
  // streak local to each State instance
  int _streak = 0;

  void _audioPlayTap() {
    try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
  }

  void _audioPlayAnswerCorrect() {
    try { AudioFeedback.instance.playEvent(SoundEvent.answerCorrect); } catch (_) {}
  }

  void _audioPlayAnswerWrong() {
    try { AudioFeedback.instance.playEvent(SoundEvent.answerWrong); } catch (_) {}
  }

  void _audioPlayStreak({int? milestone}) {
    try {
      if (milestone != null) {
        AudioFeedback.instance.playEvent(SoundEvent.streak, meta: {'milestone': milestone});
      } else {
        AudioFeedback.instance.playEvent(SoundEvent.streak);
      }
    } catch (_) {}
  }

  void _audioPlayPageFlip() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageFlip); } catch (_) {}
  }

}

class _RacePageState extends State<RacePage> with SingleTickerProviderStateMixin {
  bool isPublicMode = true;
  int? _activeTrackIndex;
  bool _inPublicRaceView = false;

  // signal to abort the current race / quiz (set when user taps Leave inside a question)
  bool _raceAborted = false;

  // New: race / car animation state
  bool _raceStarted = false;
  late final AnimationController _carController;
  final TextEditingController _nameController = TextEditingController();

  // current travel distance along the path (pixels)
  double _carDistance = 0.0;

  // store the chosen question sequence for the race
  List<int> _selectedIndicesForRace = [];

  // quiz / step-race state
  List<int> _quizSelectedIndices = [];
  int _quizCurrentPos = 0;        // 0..N-1 current step
  int _quizScore = 0;
  double _currentDistance = 0.0; // traveled distance in px along path
  double _stepDistance = 0.0;    // _totalPathLength / totalQuestions
  bool _quizInProgress = false;

  // --- path data for tracks (normalized coords in [0..1]) ---
  // Monza (RaceTrack0) — the list you asked for
  final List<List<double>> _monzaNorm = [
    [0.75, 0.32],    //[x, y]
    [0.75, 0.23],
    [0.65, 0.20], //2
    [0.55, 0.23],
    [0.50, 0.30],
    [0.45, 0.37],
    [0.20, 0.40], //6
    [0.18, 0.50],
    [0.20, 0.55],
    [0.28, 0.60], //9
    [0.31, 0.70],
    [0.30, 0.80], //11
    [0.40, 0.82],
    [0.72, 0.80], //13
    [0.75, 0.75],
    [0.72, 0.65], //15
    [0.50, 0.62],
    [0.52, 0.52], //17
    [0.75, 0.37],
    [0.75, 0.32]
  ];

  // Monaco (RaceTrack1) — normalized centerline waypoints
  final List<List<double>> _monacoNorm = [
    [0.55, 0.81],
    [0.71, 0.75],
    [0.80, 0.63], //2
    [0.76, 0.52],
    [0.70, 0.48], //4
    [0.48, 0.45],
    [0.46, 0.40], //6
    [0.53, 0.34],
    [0.75, 0.36], //8
    [0.82, 0.30],
    [0.80, 0.22], //10
    [0.71, 0.19],
    [0.57, 0.23], //12
    [0.45, 0.19],
    [0.38, 0.12], //14
    [0.26, 0.11],
    [0.21, 0.17], //16
    [0.30, 0.33],
    [0.28, 0.37], //18
    [0.14, 0.44],
    [0.10, 0.51], //20
    [0.20, 0.56],
    [0.38, 0.56], //22
    [0.45, 0.60],
    [0.41, 0.66], //24
    [0.21, 0.70],
    [0.15, 0.74], //26
    [0.20, 0.82],
    [0.38, 0.85], //28
    [0.55, 0.81]
  ];

  final List<List<double>> _suzukaNorm = [
    [0.76, 0.79],
    [0.75, 0.19],
    [0.67, 0.13], //2
    [0.34, 0.13],
    [0.21, 0.18], //4
    [0.25, 0.28],
    [0.49, 0.36], //6
    [0.51, 0.45],
    [0.46, 0.50], //8
    [0.26, 0.53],
    [0.24, 0.64], //10
    [0.35, 0.72],
    [0.48, 0.75], //12
    [0.54, 0.84],
    [0.69, 0.86], //14
    [0.74, 0.81],
    [0.76, 0.79] //16
  ];

  final List<List<double>> _spaNorm = [
    [0.69, 0.88],
    [0.74, 0.85],
    [0.71, 0.79], //2
    [0.47, 0.75],
    [0.42, 0.70], //4
    [0.46, 0.64],
    [0.55, 0.59], //6
    [0.66, 0.62],
    [0.75, 0.66], //8
    [0.82, 0.52],
    [0.69, 0.40], //10
    [0.77, 0.18],
    [0.67, 0.09], //12
    [0.56, 0.11],
    [0.60, 0.24], //14
    [0.44, 0.29],
    [0.26, 0.23], //16
    [0.14, 0.26],
    [0.14, 0.37], //18
    [0.40, 0.41],
    [0.47, 0.48], //20
    [0.43, 0.53],
    [0.20, 0.55], //22
    [0.13, 0.77],
    [0.23, 0.84], //24
    [0.69, 0.88]
  ];


  final List<List<double>> _silverstoneNorm = [
    [0.82, 0.75],
    [0.81, 0.43],
    [0.73, 0.35], //2
    [0.73, 0.28],
    [0.77, 0.18], //4
    [0.71, 0.12],
    [0.63, 0.14], //6
    [0.57, 0.24],
    [0.47, 0.30], //8
    [0.40, 0.37],
    [0.30, 0.36], //10
    [0.29, 0.30],
    [0.34, 0.26], //12
    [0.42, 0.19],
    [0.42, 0.12], //14
    [0.32, 0.07],
    [0.19, 0.07], //16
    [0.13, 0.13],
    [0.13, 0.63], //20
    [0.07, 0.72],
    [0.11, 0.80], //22
    [0.21, 0.85],
    [0.28, 0.79], //24
    [0.29, 0.69],
    [0.41, 0.62], //26
    [0.37, 0.51],
    [0.46, 0.47], //28
    [0.58, 0.49],
    [0.60, 0.53], //30
    [0.53, 0.64],
    [0.60, 0.74], //32
    [0.51, 0.82],
    [0.58, 0.88], //34
    [0.73, 0.90],
    [0.80, 0.83], //36
    [0.82, 0.75]
  ];

  late final Map<int, List<List<double>>> _tracksNorm;

  // --- prepared path in pixel coords (computed per image size) ---
  List<Offset> _pathPoints = [];
  List<double> _cumLengths = []; // cumulative lengths, starts with 0.0
  double _totalPathLength = 0.0;

  // small epsilon for numeric stability
  static const double _eps = 1e-6;

  // re-use the same arrays from HomePage logic (copy of home_page.dart)
  final List<int> _easyQuestions   = [1, 2, 3, 6];
  final List<int> _mediumQuestions = [4, 5, 11, 12];
  final List<int> _hardQuestions   = [7, 8, 9, 10];

  // helper to create fileBase (same behavior as HomePage)
  String _formatFileName(String brand, String model) {
    String input = (brand + model).replaceAll(RegExp(r'[ ./]'), '');
    return input
        .split(RegExp(r'(?=[A-Z])|(?<=[a-z])(?=[A-Z])|(?<=[a-z])(?=[0-9])'))
        .map((word) =>
            word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join();
  }

  // Placeholder "question" page: very small dialog that simulates a question.
  // We'll replace it with the real per-type question pages in the next block.
  Future<bool> _placeholderQuestion(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final chosen = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Question #$questionNumber (placeholder)'),
          content: const Text('This is a placeholder question. Tap an answer.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(0), child: const Text('A (wrong)')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(1), child: const Text('B (wrong)')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(2), child: const Text('C (wrong)')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(3), child: const Text('D (correct)')),
          ],
        );
      },
    );

    // treat choice 3 (D) as correct for placeholder
    return (chosen == 3);
  }

  // small helper to start the car animation
  void _startCar() {
    setState(() {
      _raceStarted = true;
    });
    _carController.repeat();
  }

  // --- Car data used by the questions (same CSV used in home_page.dart) ---
  List<Map<String, String>> carData = [];

  Future<void> _askAllQuestionsThenStart() async {
    // ensure car data loaded
    if (carData.isEmpty) {
      await _loadCarData();
      if (carData.isEmpty) {
        // nothing to ask
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('No data'),
            content: const Text('No car data available for the quiz.'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
        return;
      }
    }

    // choose number of questions based on active track as a fallback, default to 12
    final questionsPerTrack = {0: 5, 1: 9, 2: 12, 3: 16, 4: 20};
    final idx = _safeIndex(_activeTrackIndex);
    final totalQuestions = questionsPerTrack[idx] ?? 12;

    // build selectedIndices using similar difficulty distribution logic (keeps variety)
    List<int> selectedIndices = [];
    final fullPool = <int>[]..addAll(_easyQuestions)..addAll(_mediumQuestions)..addAll(_hardQuestions);

    if (totalQuestions <= 12) {
      // preserve previous "4 easy / 4 medium / rest hard" behavior when <=12
      if (totalQuestions <= 4) {
        final tmp = List<int>.from(_easyQuestions)..shuffle();
        selectedIndices = tmp.take(totalQuestions).toList();
      } else if (totalQuestions <= 8) {
        final e = List<int>.from(_easyQuestions)..shuffle();
        final m = List<int>.from(_mediumQuestions)..shuffle();
        selectedIndices = []
          ..addAll(e.take(4))
          ..addAll(m.take(totalQuestions - 4));
      } else {
        final e = List<int>.from(_easyQuestions)..shuffle();
        final m = List<int>.from(_mediumQuestions)..shuffle();
        final h = List<int>.from(_hardQuestions)..shuffle();
        selectedIndices = []
          ..addAll(e.take(4))
          ..addAll(m.take(4))
          ..addAll(h.take(totalQuestions - 8));
      }
    } else {
      // For >12 questions (Spa/Silverstone) repeat shuffled full 12-type chunks.
      final rng = Random();
      final repeated = <int>[];
      while (repeated.length < totalQuestions) {
        final chunk = List<int>.from(fullPool)..shuffle(rng);
        repeated.addAll(chunk);
      }
      selectedIndices = repeated.take(totalQuestions).toList();
    }

    int quizScore = 0;
    for (int i = 0; i < selectedIndices.length; i++) {
      final qIndex = selectedIndices[i];
      final method = handlerByIndex[qIndex]!;
      final correct = await method(i + 1, currentScore: quizScore, totalQuestions: selectedIndices.length);
      if (correct) quizScore++;
      if (!mounted) return;
    }

    // show summary
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quiz complete'),
        content: Text('You scored $quizScore / ${selectedIndices.length}. Starting the race...'),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );

    // start car
    _startCar();
  }

  // class-level handler map so any method can access it
  Map<int, Future<bool> Function(int, {required int currentScore, required int totalQuestions})> get handlerByIndex => {
    1: _handleQuestion1_RandomCarImage,
    2: _handleQuestion2_RandomModelBrand,
    3: _handleQuestion3_BrandImageChoice,
    4: _handleQuestion4_DescriptionToCarImage,
    5: _handleQuestion5_ModelOnlyImage,
    6: _handleQuestion6_OriginCountry,
    7: _handleQuestion7_SpecialFeature,
    8: _handleQuestion8_MaxSpeed,
    9: _handleQuestion9_Acceleration,
    10: _handleQuestion10_Horsepower,
    11: _handleQuestion11_DescriptionSlideshow,
    12: _handleQuestion12_ModelNameToBrand,
  };

  // helper to present a question widget and return whether it was correct
  Future<bool> _showQuestionWidget(Widget content) async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _QuestionPage(
          content: content,
          onLeave: () {
            // Called when user chooses Leave from the question AppBar.
            // Set abort flag so the quiz loop stops, stop animation and reset race view.
            try { _carController.stop(); } catch (_) {}
            if (!mounted) return;
            setState(() {
              _raceAborted = true;
              _inPublicRaceView = false;
              _activeTrackIndex = null;
              _raceStarted = false;
              _quizInProgress = false;
              _quizSelectedIndices = [];
              _quizCurrentPos = 0;
              _quizScore = 0;
              _currentDistance = 0.0;
              _pathPoints = [];
              _cumLengths = [];
              _totalPathLength = 0.0;
            });
          },
        ),
      ),
    );
    return res == true;
  }

  // pick a random valid car entry (non-empty map)
  Map<String, String> _randomCarEntry({Random? rng}) {
    rng ??= Random();
    final valid = carData.where((m) => m.isNotEmpty && m['brand'] != null && m['model'] != null).toList();
    return valid.isEmpty ? <String, String>{} : valid[rng.nextInt(valid.length)];
  }

  // pick N distinct values from a field (brand/model/origin/horsepower) excluding optional exclude value
  List<String> _pickRandomFieldOptions(String field, int count, {String? exclude}) {
    final rng = Random();
    final set = <String>{};
    for (var m in carData) {
      if (m[field] != null && m[field]!.trim().isNotEmpty) set.add(m[field]!.trim());
    }
    set.remove(exclude);
    final vals = set.toList()..shuffle(rng);
    final out = <String>[];
    if (exclude != null) out.add(exclude);
    for (var v in vals) {
      if (out.length >= count) break;
      out.add(v);
    }
    // if not enough, fill with duplicates of exclude to avoid crash (rare)
    while (out.length < count) out.add(exclude ?? '');
    out.shuffle(rng);
    return out;
  }

  // pick N distinct car entries (full maps) including one correct entry
  List<Map<String, String>> _pickRandomCarEntries(int count, {required Map<String,String> include}) {
    final rng = Random();
    final pool = carData.where((m) => m.isNotEmpty).toList();
    pool.removeWhere((m) => m['brand'] == include['brand'] && m['model'] == include['model']);
    pool.shuffle(rng);
    final result = <Map<String,String>>[include]..addAll(pool.take(max(0, count - 1)));
    result.shuffle(rng);
    return result;
  }

  // file base helper (reuses your _formatFileName)
  String _fileBaseFromEntry(Map<String, String> e) {
    return _formatFileName(e['brand'] ?? '', e['model'] ?? '');
  }

  // Q1: RandomCarImage -> choose brand options
  Future<bool> _handleQuestion1_RandomCarImage(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final brandOptions = _pickRandomFieldOptions('brand', 4, exclude: correct['brand']);
    // ensure correct included
    if (!brandOptions.contains(correct['brand'])) {
      brandOptions[0] = correct['brand']!;
      brandOptions.shuffle();
    }
    final widget = _RandomCarImageQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      fileBase: fileBase,
      correctAnswer: correct['brand']!,
      options: brandOptions,
    );
    return await _showQuestionWidget(widget);
  }

  // Q2: RandomModelBrand
  Future<bool> _handleQuestion2_RandomModelBrand(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final brandOptions = _pickRandomFieldOptions('brand', 4, exclude: correct['brand']);
    if (!brandOptions.contains(correct['brand'])) {
      brandOptions[0] = correct['brand']!;
      brandOptions.shuffle();
    }
    final widget = _RandomModelBrandQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      fileBase: fileBase,
      correctAnswer: correct['brand']!,
      options: brandOptions,
    );
    return await _showQuestionWidget(widget);
  }

  // Q3: BrandImageChoice (2x2 images, brands)
  Future<bool> _handleQuestion3_BrandImageChoice(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    // pick three other distinct car entries and form imageBases + brands
    final entries = _pickRandomCarEntries(4, include: correct);
    final imageBases = entries.map(_fileBaseFromEntry).toList();
    final optionBrands = entries.map((e) => e['brand'] ?? '').toList();
    final widget = _BrandImageChoiceQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      targetBrand: correct['brand'] ?? '',
      imageBases: imageBases,
      optionBrands: optionBrands,
      correctBrand: correct['brand'] ?? '',
    );
    return await _showQuestionWidget(widget);
  }

  // Q4: Description -> pick 4 imageBases, one correct index
  Future<bool> _handleQuestion4_DescriptionToCarImage(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final entries = _pickRandomCarEntries(4, include: correct);
    final imageBases = entries.map(_fileBaseFromEntry).toList();
    final correctIndex = entries.indexWhere((e) => e['brand'] == correct['brand'] && e['model'] == correct['model']);
    final widget = _DescriptionToCarImageQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      description: correct['description'] ?? '',
      imageBases: imageBases,
      correctIndex: correctIndex < 0 ? 0 : correctIndex,
    );
    return await _showQuestionWidget(widget);
  }

  // Q5: ModelOnlyImage (choose model)
  Future<bool> _handleQuestion5_ModelOnlyImage(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final modelOptions = _pickRandomFieldOptions('model', 4, exclude: correct['model']);
    if (!modelOptions.contains(correct['model'])) {
      modelOptions[0] = correct['model']!;
      modelOptions.shuffle();
    }
    final widget = _ModelOnlyImageQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      fileBase: fileBase,
      correctModel: correct['model'] ?? '',
      options: modelOptions,
    );
    return await _showQuestionWidget(widget);
  }

  // Q6: Origin country
  Future<bool> _handleQuestion6_OriginCountry(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final options = _pickRandomFieldOptions('origin', 4, exclude: correct['origin']);
    if (!options.contains(correct['origin'])) {
      options[0] = correct['origin'] ?? '';
      options.shuffle();
    }
    final widget = _OriginCountryQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      brand: correct['brand'] ?? '',
      model: correct['model'] ?? '',
      fileBase: fileBase,
      origin: correct['origin'] ?? '',
      options: options,
    );
    return await _showQuestionWidget(widget);
  }

  // Q7: Special Feature
  Future<bool> _handleQuestion7_SpecialFeature(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final opts = _pickRandomFieldOptions('specialFeature', 4, exclude: correct['specialFeature']);
    if (!opts.contains(correct['specialFeature'])) {
      opts[0] = correct['specialFeature'] ?? '';
      opts.shuffle();
    }
    final widget = _SpecialFeatureQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      brand: correct['brand'] ?? '',
      model: correct['model'] ?? '',
      fileBase: fileBase,
      correctFeature: correct['specialFeature'] ?? '',
      options: opts,
    );
    return await _showQuestionWidget(widget);
  }

  // Q8: Max Speed
  Future<bool> _handleQuestion8_MaxSpeed(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final opts = _pickRandomFieldOptions('topSpeed', 4, exclude: correct['topSpeed']);
    if (!opts.contains(correct['topSpeed'])) {
      opts[0] = correct['topSpeed'] ?? '';
      opts.shuffle();
    }
    final widget = _MaxSpeedQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      brand: correct['brand'] ?? '',
      model: correct['model'] ?? '',
      fileBase: fileBase,
      correctSpeed: correct['topSpeed'] ?? '',
      options: opts,
    );
    return await _showQuestionWidget(widget);
  }

  // Q9: Acceleration
  Future<bool> _handleQuestion9_Acceleration(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final opts = _pickRandomFieldOptions('acceleration', 4, exclude: correct['acceleration']);
    if (!opts.contains(correct['acceleration'])) {
      opts[0] = correct['acceleration'] ?? '';
      opts.shuffle();
    }
    final widget = _AccelerationQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      brand: correct['brand'] ?? '',
      model: correct['model'] ?? '',
      fileBase: fileBase,
      correctAcceleration: correct['acceleration'] ?? '',
      options: opts,
    );
    return await _showQuestionWidget(widget);
  }

  // Q10: Horsepower
  Future<bool> _handleQuestion10_Horsepower(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final opts = _pickRandomFieldOptions('horsepower', 4, exclude: correct['horsepower']);
    if (!opts.contains(correct['horsepower'])) {
      opts[0] = correct['horsepower'] ?? '';
      opts.shuffle();
    }
    final widget = _HorsepowerQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      fileBase: fileBase,
      correctAnswer: correct['horsepower'] ?? '',
      options: opts,
    );
    return await _showQuestionWidget(widget);
  }

  // Q11: Description Slideshow
  Future<bool> _handleQuestion11_DescriptionSlideshow(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final fileBase = _fileBaseFromEntry(correct);
    final opts = _pickRandomFieldOptions('description', 4, exclude: correct['description']);
    if (!opts.contains(correct['description'])) {
      opts[0] = correct['description'] ?? '';
      opts.shuffle();
    }
    final widget = _DescriptionSlideshowQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      fileBase: fileBase,
      correctDescription: correct['description'] ?? '',
      options: opts,
    );
    return await _showQuestionWidget(widget);
  }

  // Q12: ModelNameToBrand
  Future<bool> _handleQuestion12_ModelNameToBrand(int questionNumber, {required int currentScore, required int totalQuestions}) async {
    final correct = _randomCarEntry();
    if (correct.isEmpty) return false;
    final model = correct['model'] ?? '';
    final brandOptions = _pickRandomFieldOptions('brand', 4, exclude: correct['brand']);
    if (!brandOptions.contains(correct['brand'])) {
      brandOptions[0] = correct['brand']!;
      brandOptions.shuffle();
    }
    final widget = _ModelNameToBrandQuestionContent(
      questionNumber: questionNumber,
      currentScore: currentScore,
      totalQuestions: totalQuestions,
      model: model,
      correctBrand: correct['brand'] ?? '',
      options: brandOptions,
    );
    return await _showQuestionWidget(widget);
  }

  Future<void> _startQuizRace() async {
    _raceAborted = false;
    // ensure car data is loaded
    if (carData.isEmpty) {
      await _loadCarData();
      if (carData.isEmpty) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('No data'),
            content: const Text('No car data available for the quiz.'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
          ),
        );
        return;
      }
    }

    // choose number of questions based on chosen track
    final questionsPerTrack = {0: 5, 1: 9, 2: 12, 3: 16, 4: 20};
    final idx = _safeIndex(_activeTrackIndex);
    final totalQuestions = questionsPerTrack[idx] ?? 12;

    // build selectedIndices using same difficulty distribution as before (but support >12)
    final List<int> selectedIndices = [];
    final fullPool = <int>[]..addAll(_easyQuestions)..addAll(_mediumQuestions)..addAll(_hardQuestions);

    if (totalQuestions <= 12) {
      if (totalQuestions <= 4) {
        final tmp = List<int>.from(_easyQuestions)..shuffle();
        selectedIndices.addAll(tmp.take(totalQuestions));
      } else if (totalQuestions <= 8) {
        final e = List<int>.from(_easyQuestions)..shuffle();
        final m = List<int>.from(_mediumQuestions)..shuffle();
        selectedIndices
          ..addAll(e.take(4))
          ..addAll(m.take(totalQuestions - 4));
      } else {
        final e = List<int>.from(_easyQuestions)..shuffle();
        final m = List<int>.from(_mediumQuestions)..shuffle();
        final h = List<int>.from(_hardQuestions)..shuffle();
        selectedIndices
          ..addAll(e.take(4))
          ..addAll(m.take(4))
          ..addAll(h.take(totalQuestions - 8));
      }
    } else {
      // >12: repeat shuffled fullPool until we have enough
      final rng = Random();
      final repeated = <int>[];
      while (repeated.length < totalQuestions) {
        final chunk = List<int>.from(fullPool)..shuffle(rng);
        repeated.addAll(chunk);
      }
      selectedIndices.addAll(repeated.take(totalQuestions));
    }

    // store quiz state
    setState(() {
      _quizSelectedIndices = selectedIndices;
      _quizCurrentPos = 0;
      _quizScore = 0;
      _quizInProgress = true;
      _currentDistance = 0.0;
    });

    // Give layout one frame so LayoutBuilder can call _preparePath and compute _totalPathLength.
    await Future.delayed(const Duration(milliseconds: 120));

    if (_totalPathLength <= _eps) {
      final W = MediaQuery.of(context).size.width;
      final H = max(100.0, MediaQuery.of(context).size.height - 120.0);
      _preparePath(W, H, _safeIndex(_activeTrackIndex));
    }

    _stepDistance = (_totalPathLength > 0 ? _totalPathLength / _quizSelectedIndices.length : 0.0);

    // reset animation controller to start of lap
    _carController.stop();
    _carController.value = 0.0;
    setState(() {
      _raceStarted = true;
    });

    // ask first question (this will chain the rest)
    await _askNextQuestion();
  }

  Future<void> _askNextQuestion() async {
    if (!mounted) return;

    // stop immediately if user aborted or left view
    if (_raceAborted || !_inPublicRaceView) return;

    if (_quizCurrentPos >= _quizSelectedIndices.length) {
      // finished all steps -> start full continuous race
      setState(() {
        _quizInProgress = false;
      });
      _startCar();
      return;
    }

    final qIndex = _quizSelectedIndices[_quizCurrentPos];

    // If abort happened before selecting handler, stop.
    if (_raceAborted || !_inPublicRaceView) return;

    final handler = handlerByIndex[qIndex];
    if (handler == null) {
      // safety: skip to next
      _quizCurrentPos++;
      // stop if abort set
      if (_raceAborted || !_inPublicRaceView) return;
      await _advanceByStep();
      return _askNextQuestion();
    }

    // Ask question. If the user used Leave inside the question, the onLeave callback
    // sets _raceAborted and resets the view. The question page itself will pop and
    // return false as the result (we still treat it as 'not correct'),
    // but we must check _raceAborted afterwards to avoid continuing the loop.
    final correct = await handler(_quizCurrentPos + 1, currentScore: _quizScore, totalQuestions: _quizSelectedIndices.length);

    // If the race was aborted during the question, stop the loop now.
    if (_raceAborted || !_inPublicRaceView) return;
    if (!mounted) return;

    if (correct) {
      _quizScore++;
      _quizCurrentPos++;
      // Only advance the car if the answer was correct.
      await _advanceByStep();
    } else {
      // If incorrect, do NOT increment _quizCurrentPos: present another question
      // (same position) — keep _quizCurrentPos unchanged so user must pass this step.
      // Do not advance the car.
      // short delay to avoid abrupt push/pop
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // If aborted after advancing/delay, stop now.
    if (_raceAborted || !_inPublicRaceView) return;

    // Next question
    return _askNextQuestion();
  }

  Future<void> _advanceByStep() async {
    if (_totalPathLength <= _eps) return;

    final targetDistance = (_currentDistance + _stepDistance).clamp(0.0, _totalPathLength);
    final targetValue = targetDistance / _totalPathLength;
    // current controller value (0..1)
    final curValue = _carController.value.clamp(0.0, 1.0);

    // compute proportional duration from controller's duration
    final baseDuration = _carController.duration ?? const Duration(seconds: 6);
    final fraction = (targetValue - curValue).abs();
    final ms = max(150, (baseDuration.inMilliseconds * fraction).round()); // min 150ms
    final animDuration = Duration(milliseconds: ms);

    try {
      await _carController.animateTo(targetValue, duration: animDuration, curve: Curves.easeInOut);
    } catch (_) {
      // if animateTo fails for any reason, fallback to setting value directly
      _carController.value = targetValue;
    }

    _currentDistance = targetDistance;
  }

  Future<void> _loadCarData() async {
    try {
      final rawCsv = await rootBundle.loadString('assets/cars.csv');
      final lines = const LineSplitter().convert(rawCsv).toList();
      carData = lines.map<Map<String, String>>((line) {
        final values = line.split(',');
        if (values.length >= 11) {
          return {
            'brand': values[0],
            'model': values[1],
            'description': values[2],
            'engineType': values[3],
            'topSpeed': values[4],
            'acceleration': values[5],
            'horsepower': values[6],
            'priceRange': values[7],
            'year': values[8],
            'origin': values[9],
            'specialFeature': values[10],
          };
        }
        return <String, String>{};
      }).toList();
    } catch (e) {
      debugPrint('Error loading CSV in RacePage: $e');
      carData = [];
    }
  }

  @override
  void initState() {
    super.initState();
    _carController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _tracksNorm = {
      0: _monzaNorm,
      1: _monacoNorm,
      2: _suzukaNorm,
      3: _spaNorm,
      4: _silverstoneNorm,
    };
  
    // load CSV now for quiz questions (non-blocking)
    _loadCarData();
  }

  @override
  void dispose() {
    _carController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // show selector only when NOT in the public race view
          if (!_inPublicRaceView) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildModeButton("Public Room", true),
                  _buildModeButton("Private Room", false),
                ],
              ),
            ),
            const Divider(thickness: 0.5),
          ],

          // ===== Content Zone: tracks grid or public race view =====
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _inPublicRaceView
                  ? _buildPublicRaceView()
                  : _buildTracksGrid(isPrivate: !isPublicMode),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Mode button (red when selected) ----
  Widget _buildModeButton(String label, bool public) {
    final selected = isPublicMode == public;

    return GestureDetector(
      onTap: () => setState(() => isPublicMode = public),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.red : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 60,
            height: 2,
            color: selected ? Colors.red : Colors.transparent,
          ),
        ],
      ),
    );
  }

  // ===== Grid of 5 track buttons (shared for Public & Private) =====
  Widget _buildTracksGrid({required bool isPrivate}) {
    final titles = ['Monza', 'Monaco', 'Suzuka', 'Spa', 'Silverstone'];

    return GridView.count(
      key: ValueKey(isPrivate ? 'privateTracks' : 'publicTracks'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: List.generate(5, (i) {
        return _buildTrackButton(i, titles[i], isPrivate: isPrivate);
      }),
    );
  }

  void _showPublicJoinDialog(int index, String title) {
    // default name: username + random 3-digit number
    _nameController.text = 'Player${Random().nextInt(900) + 100}';

    final questionsPerTrack = {0: 5, 1: 9, 2: 12, 3: 16, 4: 20};
    final qCount = questionsPerTrack[_safeIndex(index)] ?? 12;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You're about to enter a multiplayer game.\n\n"
                "You will need to answer $qCount questions correctly to complete the lap. Difficulty progresses from easy to hard.",
              ),
              const SizedBox(height: 16),
              const Text(
                "Choose your player name:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                final playerName = _nameController.text.trim().isEmpty
                    ? 'Player${Random().nextInt(900) + 100}'
                    : _nameController.text.trim();

                debugPrint('Joining as: $playerName');

                // 1) Close keyboard
                FocusScope.of(context).unfocus();

                // 2) Close dialog
                Navigator.of(context).pop();

                // 3) Wait a short moment so the keyboard/layout settles, then join.
                //    This avoids preparing the path with an incorrect (temporarily smaller)
                //    height caused by the keyboard being visible.
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (!mounted) return;
                  _joinPublicGame(index);
                });
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  // ===== Single track button (image background + name) =====
  Widget _buildTrackButton(int index, String title, {required bool isPrivate}) {
    return GestureDetector(
      onTap: () {
        if (isPrivate) {
          // private behaviour (open code dialog / create private room)
          debugPrint('Private track tapped: $title (index $index)');
        } else {
          // PUBLIC: show the confirmation popup before joining
          _showPublicJoinDialog(index, title);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/home/RaceTrack$index.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              // subtle bottom gradient for text readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black,
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // Track name centered at bottom
              Positioned(
                left: 8,
                right: 8,
                bottom: 10,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54, offset: Offset(0, 2))],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _joinPublicGame(int index) {
    setState(() {
      _activeTrackIndex = index;
      _inPublicRaceView = true;
      _raceStarted = false;
      _quizInProgress = false;
      _quizSelectedIndices = [];
      _quizCurrentPos = 0;
      _quizScore = 0;
      _currentDistance = 0.0;
      _pathPoints = [];
      _cumLengths = [];
      _totalPathLength = 0.0;
      _raceAborted = false; // <--- reset abort flag
    });

    _carController.stop();
    _carController.reset();
  }

  // helper to clamp index safely
  int _safeIndex(int? val) {
    final v = val ?? 0;
    if (v < 0) return 0;
    if (v > 4) return 4;
    return v;
  }

  // Convert normalized track points for a given track index into pixel Offsets,
  // compute cumulative lengths and total length.
  void _preparePath(double W, double H, int trackIdx) {
    // choose normalized list by track index (currently only Monza / idx 0)
    final List<List<double>> norm = _tracksNorm[trackIdx] ?? _monzaNorm;

    // convert to pixel positions
    _pathPoints = norm.map((p) => Offset(p[0] * W, p[1] * H)).toList();

    // ensure path is not degenerate
    if (_pathPoints.length < 2) {
      _cumLengths = [0.0];
      _totalPathLength = 0.0;
      return;
    }

    // compute cumulative lengths
    _cumLengths = [0.0];
    for (var i = 1; i < _pathPoints.length; i++) {
      final seg = (_pathPoints[i] - _pathPoints[i - 1]).distance;
      _cumLengths.add(_cumLengths.last + seg);
    }
    _totalPathLength = _cumLengths.last;

    // guard
    if (_totalPathLength <= _eps) _totalPathLength = 1.0;

    // adjust animation duration so car speed roughly similar across sizes
    // here 150 px/s chosen as base speed; tweak as desired
    final secs = max(4, (_totalPathLength / 150.0).round());
    _carController.duration = Duration(seconds: secs);
    _carController.reset();
  }

  // Given a travel distance along the path (0.._totalPathLength),
  // return interpolated position and tangent angle (radians)
  Map<String, dynamic> _posAngleAtDistance(double distance) {
    if (_pathPoints.isEmpty) {
      return {
        'pos': const Offset(0, 0),
        'angle': 0.0,
      };
    }

    // clamp
    if (distance <= 0) {
      final next = _pathPoints.length > 1 ? _pathPoints[1] : _pathPoints.first;
      final angle = atan2(next.dy - _pathPoints.first.dy, next.dx - _pathPoints.first.dx);
      return {'pos': _pathPoints.first, 'angle': angle};
    }
    if (distance >= _totalPathLength) {
      final n = _pathPoints.length;
      final prev = _pathPoints[n - 2];
      final last = _pathPoints[n - 1];
      final angle = atan2(last.dy - prev.dy, last.dx - prev.dx);
      return {'pos': last, 'angle': angle};
    }

    // find segment index where cumLengths[i] <= distance < cumLengths[i+1]
    int seg = 0;
    // can optimize with binary search; linear is fine for ~20 points
    for (int i = 0; i < _cumLengths.length - 1; i++) {
      if (distance >= _cumLengths[i] && distance <= _cumLengths[i + 1]) {
        seg = i;
        break;
      }
    }

    final segStart = _pathPoints[seg];
    final segEnd = _pathPoints[seg + 1];
    final segStartLen = _cumLengths[seg];
    final segLen = _cumLengths[seg + 1] - segStartLen;
    final local = (distance - segStartLen) / (segLen > 0 ? segLen : 1.0);

    final dx = segEnd.dx - segStart.dx;
    final dy = segEnd.dy - segStart.dy;
    final pos = Offset(segStart.dx + dx * local, segStart.dy + dy * local);
    final angle = atan2(dy, dx);
    return {'pos': pos, 'angle': angle};
  }

  // ===== Public Race View: image fills left->right, leave bottom reserved area
  Widget _buildPublicRaceView() {
    final idx = _safeIndex(_activeTrackIndex);

    return Column(
      key: ValueKey('publicRaceView_$idx'),
      children: [
        // Use Stack so we can overlay the Leave and Start button on the image and animate a car
        Expanded(
          child: Stack(
            children: [
              // Full-width track image
              Positioned.fill(
                child: Image.asset(
                  'assets/home/RaceTrack$idx.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),

              // Animated car following the prepared path
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final W = constraints.maxWidth;
                    final H = constraints.maxHeight;
                    final idx = _safeIndex(_activeTrackIndex);

                    // Prepare path if needed
                    if (_pathPoints.isEmpty) _preparePath(W, H, idx);

                    return AnimatedBuilder(
                      animation: _carController,
                      builder: (context, child) {
                        // compute car position
                        Offset pos;
                        double angle = 0.0;

                        if (_raceStarted) {
                          final distance = _carController.value * _totalPathLength;
                          final pa = _posAngleAtDistance(distance);
                          pos = pa['pos'];
                          angle = pa['angle'];
                        } else {
                          pos = _pathPoints.isNotEmpty
                              ? _pathPoints.first
                              : Offset(W / 2 - 18, H / 2 - 12);
                        }

                        final left = pos.dx.clamp(0.0, W - 36);
                        final top = pos.dy.clamp(0.0, H - 24);

                        return Stack(
                          children: [
                            Positioned(
                              left: left,
                              top: top,
                              child: Transform.rotate(
                                angle: angle,
                                child: SizedBox(
                                  width: 36,
                                  height: 24,
                                  child: Image.asset('assets/home/car.png', fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              // Top-left small "Leave" button (text) - small and constrained
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  minimum: const EdgeInsets.only(left: 8, top: 8),
                  child: SizedBox(
                    height: 36,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black45,
                        minimumSize: const Size(64, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        _carController.stop();
                        setState(() {
                          _inPublicRaceView = false;
                          _activeTrackIndex = null;
                          _raceStarted = false;
                          _quizInProgress = false;
                          _quizSelectedIndices = [];
                          _quizCurrentPos = 0;
                          _quizScore = 0;
                          _currentDistance = 0.0;
                        });
                      },
                      child: const Text(
                        'Leave',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ),
      
              // Center Start button: only show when not started yet
              if (!_raceStarted)
                Positioned.fill(
                  child: Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        // start the step-quiz race workflow
                        await _startQuizRace();
                      },
                      child: const Text(
                        'Start',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Bottom reserved area for other players' stats (adjust height as you want)
        Container(
          height: 120, // reserved space
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(
            children: [
              // Placeholder: replace with real players list / stats widgets
              Expanded(
                child: Text(
                  'Players stats (placeholder)',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),

              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionPage extends StatelessWidget {
  final Widget content;
  final VoidCallback? onLeave;
  const _QuestionPage({required this.content, this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Flag Challenge"),
        actions: [
          IconButton(
            tooltip: 'Leave race',
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Leave race'),
                  content: const Text('Are you sure you want to leave the race? Your progress will be lost.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Leave')),
                  ],
                ),
              );
              if (confirm == true) {
                try { onLeave?.call(); } catch (_) {}
                // close the question page and return false (not-correct).
                Navigator.of(context).pop(false);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: content),
      ),
    );
  }
}

/// Widget for Question 2 – pick the brand of a model
class _RandomModelBrandQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String fileBase;
  final String correctAnswer;
  final List<String> options;

  const _RandomModelBrandQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.fileBase,
    required this.correctAnswer,
    required this.options,
  });

  @override
  State<_RandomModelBrandQuestionContent> createState() =>
      _RandomModelBrandQuestionContentState();
}

class _RandomModelBrandQuestionContentState
    extends State<_RandomModelBrandQuestionContent> with AudioAnswerMixin {
  bool _answered = false;
  String? _selectedBrand;

  void _onTap(String brand) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = brand == widget.correctAnswer;

    setState(() {
      _answered = true;
      _selectedBrand = brand;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber}  "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt
          const Text(
            "What's the brand of this model ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Six static frames, one under the other
          for (int i = 0; i < 6; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: ImageCacheService.instance
                      .imageProvider('${widget.fileBase}$i.webp'),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Brand choice buttons
          for (var b in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (b == widget.correctAnswer
                            ? Colors.green
                            : (b == _selectedBrand
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(b),
                      child: Center(
                        child: Text(
                          b,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Widget for Question 12 ─────────────────────────────────────────────────────
class _ModelNameToBrandQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String model;
  final String correctBrand;
  final List<String> options;

  const _ModelNameToBrandQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.model,
    required this.correctBrand,
    required this.options,
  });

  @override
  State<_ModelNameToBrandQuestionContent> createState() =>
      _ModelNameToBrandQuestionContentState();
}

class _ModelNameToBrandQuestionContentState
    extends State<_ModelNameToBrandQuestionContent> with AudioAnswerMixin {
  bool _answered = false;
  String? _selectedBrand;

  void _onTap(String brand) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = brand == widget.correctBrand;

    setState(() {
      _answered = true;
      _selectedBrand = brand;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: TextStyle(fontSize: 12),
          ),
          SizedBox(height: 30),
          Text(
            "Which brand makes the model:",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          Text(
            widget.model,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 30),
          for (var brand in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (brand == widget.correctBrand
                            ? Colors.green
                            : (brand == _selectedBrand
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(brand),
                      child: Center(
                        child: Text(
                          brand,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// Widget for Question 11 – show six static frames, then centered, padded multi-line buttons
class _DescriptionSlideshowQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String fileBase;
  final String correctDescription;
  final List<String> options;

  const _DescriptionSlideshowQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.fileBase,
    required this.correctDescription,
    required this.options,
  });

  @override
  _DescriptionSlideshowQuestionContentState createState() =>
      _DescriptionSlideshowQuestionContentState();
}

class _DescriptionSlideshowQuestionContentState
    extends State<_DescriptionSlideshowQuestionContent> with AudioAnswerMixin {
  bool _answered = false;
  String? _selectedDescription;

  void _onTap(String description) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = description == widget.correctDescription;

    setState(() {
      _answered = true;
      _selectedDescription = description;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────
          Text(
            "Question #${widget.questionNumber}   "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // ── Prompt ────────────────────────────────────────────────
          const Text(
            "Which description corresponds to this car ?",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ── Six static frames ────────────────────────────────────
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: ImageCacheService.instance
                      .imageProvider('${widget.fileBase}$i.webp'),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          const SizedBox(height: 24),

          // ── Description buttons ──────────────────────────────────
          for (var desc in widget.options)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 6.0, horizontal: 24.0),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: _answered
                      ? (desc == widget.correctDescription
                          ? Colors.green
                          : (desc == _selectedDescription
                              ? Colors.red
                              : Colors.grey[800]!))
                      : Colors.grey[800],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                onPressed: () => _onTap(desc),
                child: Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for Question 10 – horsepower with smooth 2s fade transitions
class _HorsepowerQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String fileBase;
  final String correctAnswer;
  final List<String> options;

  const _HorsepowerQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.fileBase,
    required this.correctAnswer,
    required this.options,
  });

  @override
  _HorsepowerQuestionContentState createState() =>
      _HorsepowerQuestionContentState();
}

class _HorsepowerQuestionContentState
    extends State<_HorsepowerQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedAnswer;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle frames every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String answer) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = answer == widget.correctAnswer;

    setState(() {
      _answered = true;
      _selectedAnswer = answer;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          const Text(
            "How many HorsePower does this car has ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // AnimatedSwitcher for smooth fade between frames
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image(
                key: ValueKey<int>(_frameIndex),
                image: ImageCacheService.instance
                    .imageProvider('${widget.fileBase}$_frameIndex.webp'),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Horsepower option buttons
          for (var opt in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (opt == widget.correctAnswer
                            ? Colors.green
                            : (opt == _selectedAnswer
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(opt),
                      child: Center(
                        child: Text(
                          opt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for Question 9 – acceleration (0–100 km/h) with smooth 2s fade transitions
class _AccelerationQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String brand;
  final String model;
  final String fileBase;
  final String correctAcceleration;
  final List<String> options;

  const _AccelerationQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.brand,
    required this.model,
    required this.fileBase,
    required this.correctAcceleration,
    required this.options,
  });

  @override
  State<_AccelerationQuestionContent> createState() =>
      _AccelerationQuestionContentState();
}

class _AccelerationQuestionContentState
    extends State<_AccelerationQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedAnswer;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle the image every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String answer) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = answer == widget.correctAcceleration;

    setState(() {
      _answered = true;
      _selectedAnswer = answer;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt
          const Text(
            "What's the acceleration time (0-100km/h) of this car ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // AnimatedSwitcher for smooth fade between frames
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image(
                key: ValueKey<int>(_frameIndex),
                image: ImageCacheService.instance
                    .imageProvider('${widget.fileBase}$_frameIndex.webp'),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Acceleration option buttons
          for (var opt in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (opt == widget.correctAcceleration
                            ? Colors.green
                            : (opt == _selectedAnswer
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(opt),
                      child: Center(
                        child: Text(
                          opt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for Question 8 – max speed with smooth 2s fade transitions
class _MaxSpeedQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String brand;
  final String model;
  final String fileBase;
  final String correctSpeed;
  final List<String> options;

  const _MaxSpeedQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.brand,
    required this.model,
    required this.fileBase,
    required this.correctSpeed,
    required this.options,
  });

  @override
  State<_MaxSpeedQuestionContent> createState() =>
      _MaxSpeedQuestionContentState();
}

class _MaxSpeedQuestionContentState
    extends State<_MaxSpeedQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedSpeed;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle frames every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String speed) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = speed == widget.correctSpeed;

    setState(() {
      _answered = true;
      _selectedSpeed = speed;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt
          const Text(
            "What's the max speed of this car ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // AnimatedSwitcher for smooth fade between frames
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image(
                key: ValueKey<int>(_frameIndex),
                image: ImageCacheService.instance
                    .imageProvider('${widget.fileBase}$_frameIndex.webp'),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Speed option buttons
          for (var opt in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (opt == widget.correctSpeed
                            ? Colors.green
                            : (opt == _selectedSpeed
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(opt),
                      child: Center(
                        child: Text(
                          opt,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for Question 7 – special feature with smooth 2s fade transitions
class _SpecialFeatureQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String brand;
  final String model;
  final String fileBase;
  final String correctFeature;
  final List<String> options;

  const _SpecialFeatureQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.brand,
    required this.model,
    required this.fileBase,
    required this.correctFeature,
    required this.options,
  });

  @override
  State<_SpecialFeatureQuestionContent> createState() =>
      _SpecialFeatureQuestionContentState();
}

class _SpecialFeatureQuestionContentState
    extends State<_SpecialFeatureQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedFeature;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle the image every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String feature) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = feature == widget.correctFeature;

    setState(() {
      _answered = true;
      _selectedFeature = feature;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt
          const Text(
            "Which special feature does this car has ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Animated image with smooth fade
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image(
                key: ValueKey<int>(_frameIndex),
                image: ImageCacheService.instance
                    .imageProvider('${widget.fileBase}$_frameIndex.webp'),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Option buttons
          for (var opt in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (opt == widget.correctFeature
                            ? Colors.green
                            : (opt == _selectedFeature
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(opt),
                      child: Center(
                        child: Text(
                          opt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget for Question 4 – description → image with smooth 2s fade transitions
class _DescriptionToCarImageQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String description;
  final List<String> imageBases;
  final int correctIndex;

  const _DescriptionToCarImageQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.description,
    required this.imageBases,
    required this.correctIndex,
  });

  @override
  State<_DescriptionToCarImageQuestionContent> createState() =>
      _DescriptionToCarImageQuestionContentState();
}

class _DescriptionToCarImageQuestionContentState
    extends State<_DescriptionToCarImageQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle frames every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(int index) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = index == widget.correctIndex;

    setState(() {
      _answered = true;
      _selectedIndex = index;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Description prompt
          Text(
            widget.description,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // 2×2 grid of smoothly transitioning images
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.imageBases.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemBuilder: (ctx, i) {
              final base = widget.imageBases[i];
              final assetName = '$base$_frameIndex.webp';
              final isCorrect = (i == widget.correctIndex);
              final isSelected = (i == _selectedIndex);

              return GestureDetector(
                onTap: () => _onTap(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // AnimatedSwitcher for smooth fade between frames
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Image(
                          key: ValueKey<String>(assetName),
                          image: ImageCacheService.instance.imageProvider(assetName),
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Feedback overlay
                      if (_answered)
                        Container(
                          color: isCorrect
                              ? Colors.greenAccent
                              : (isSelected
                                  ? Colors.red
                                  : Colors.transparent),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Widget for Question 3 – tap the image of a certain brand, with smooth 2s fade transitions
class _BrandImageChoiceQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String targetBrand;
  final List<String> imageBases;
  final List<String> optionBrands;
  final String correctBrand;

  const _BrandImageChoiceQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.targetBrand,
    required this.imageBases,
    required this.optionBrands,
    required this.correctBrand,
  });

  @override
  State<_BrandImageChoiceQuestionContent> createState() =>
      _BrandImageChoiceQuestionContentState();
}

class _BrandImageChoiceQuestionContentState
    extends State<_BrandImageChoiceQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedBrand;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle through frames every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String brand) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = brand == widget.correctBrand;

    setState(() {
      _answered = true;
      _selectedBrand = brand;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Text(
          "Question #${widget.questionNumber} – "
          "Score: ${widget.currentScore}/${widget.totalQuestions}",
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Prompt
        Text(
          "Which image represent the ${widget.targetBrand} ?",
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        // 2×2 grid of smoothly transitioning images
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.imageBases.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemBuilder: (ctx, index) {
            final base = widget.imageBases[index];
            final brand = widget.optionBrands[index];
            final assetName = '$base$_frameIndex.webp';

            return GestureDetector(
              onTap: () => _onTap(brand),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // AnimatedSwitcher for smooth fade between frames
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: Image(
                        key: ValueKey<String>(assetName),
                        image: ImageCacheService.instance.imageProvider(assetName),
                        fit: BoxFit.cover,
                      ),
                    ),

                    // Feedback overlay
                    if (_answered)
                      Container(
                        color: brand == widget.correctBrand
                            ? Colors.green
                            : (brand == _selectedBrand
                                ? Colors.red
                                : Colors.transparent),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}


/// Widget for Question 6 – origin country with smooth 2s fade transitions
class _OriginCountryQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String brand;
  final String model;
  final String fileBase;
  final String origin;
  final List<String> options;

  const _OriginCountryQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.brand,
    required this.model,
    required this.fileBase,
    required this.origin,
    required this.options,
  });

  @override
  State<_OriginCountryQuestionContent> createState() =>
      _OriginCountryQuestionContentState();
}

class _OriginCountryQuestionContentState
    extends State<_OriginCountryQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedOrigin;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Cycle frames every 2 seconds
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String origin) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = origin == widget.origin;

    setState(() {
      _answered = true;
      _selectedOrigin = origin;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt
          const Text(
            "Which country does this car come from ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Smoothly fading image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Image(
                key: ValueKey<int>(_frameIndex),
                image: ImageCacheService.instance
                    .imageProvider('${widget.fileBase}$_frameIndex.webp'),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Country choice buttons
          for (var opt in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (opt == widget.origin
                            ? Colors.green
                            : (opt == _selectedOrigin
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(opt),
                      child: Center(
                        child: Text(
                          opt,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget pour la Question 5 – choisir le modèle uniquement via l’image
class _ModelOnlyImageQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String fileBase;
  final String correctModel;
  final List<String> options;

  const _ModelOnlyImageQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.fileBase,
    required this.correctModel,
    required this.options,
  });

  @override
  State<_ModelOnlyImageQuestionContent> createState() =>
      _ModelOnlyImageQuestionContentState();
}

class _ModelOnlyImageQuestionContentState
    extends State<_ModelOnlyImageQuestionContent> with AudioAnswerMixin {
  int _frameIndex = 0;
  bool _answered = false;
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    // play page open sound
    try { AudioFeedback.instance.playEvent(SoundEvent.pageOpen); } catch (_) {}
    // Alterner les frames toutes les 2 secondes
  }

  @override
  void dispose() {
    try { AudioFeedback.instance.playEvent(SoundEvent.pageClose); } catch (_) {}
    // Si CETTE classe a des contrôleurs, dispose-les ici (sinon ne mets rien).
    super.dispose();
  }

  void _onTap(String model) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = model == widget.correctModel;

    setState(() {
      _answered = true;
      _selectedModel = model;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // En-tête
          Text(
            "Question #${widget.questionNumber} – "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          const Text(
            "What is this model ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Image animée en boucle via le cache
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: ImageCacheService.instance.imageProvider(
                '${widget.fileBase}$_frameIndex.webp',
              ),
              key: ValueKey<int>(_frameIndex),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(height: 24),

          // Boutons modèles
          for (var m in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (m == widget.correctModel
                            ? Colors.green
                            : (m == _selectedModel
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(m),
                      child: Center(
                        child: Text(
                          m,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// Widget for Question 1 – static 6-frame stack, no rotation
class _RandomCarImageQuestionContent extends StatefulWidget {
  final int questionNumber;
  final int currentScore;
  final int totalQuestions;
  final String fileBase;
  final String correctAnswer;
  final List<String> options;

  const _RandomCarImageQuestionContent({
    required this.questionNumber,
    required this.currentScore,
    required this.totalQuestions,
    required this.fileBase,
    required this.correctAnswer,
    required this.options,
  });

  @override
  State<_RandomCarImageQuestionContent> createState() =>
      _RandomCarImageQuestionContentState();
}

class _RandomCarImageQuestionContentState
    extends State<_RandomCarImageQuestionContent> with AudioAnswerMixin {
  bool _answered = false;
  String? _selectedBrand;

  void _onTap(String brand) {
    if (_answered) return;

    _audioPlayTap();

    final bool correct = brand == widget.correctAnswer;

    setState(() {
      _answered = true;
      _selectedBrand = brand;
      if (correct) {
        _streak += 1;
      } else {
        _streak = 0;
      }
    });

    if (correct) {
      _audioPlayAnswerCorrect();
      if (_streak > 0 && _streak % 3 == 0) {
        _audioPlayStreak(milestone: _streak);
      }
    } else {
      _audioPlayAnswerWrong();
    }

    Future.delayed(const Duration(seconds: 1), () {
      _audioPlayPageFlip();
      Navigator.of(context).pop(correct);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            "Question #${widget.questionNumber}  "
            "Score: ${widget.currentScore}/${widget.totalQuestions}",
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Prompt (changed)
          const Text(
            "Which car is this ?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Six static frames stacked vertically
          for (int i = 0; i < 6; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: ImageCacheService.instance
                      .imageProvider('${widget.fileBase}$i.webp'),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Brand choice buttons
          for (var b in widget.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: _answered
                        ? (b == widget.correctAnswer
                            ? Colors.green
                            : (b == _selectedBrand
                                ? Colors.red
                                : Colors.grey[800]!))
                        : Colors.grey[800],
                    child: InkWell(
                      onTap: () => _onTap(b),
                      child: Center(
                        child: Text(
                          b,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}