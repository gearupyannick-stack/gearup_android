// lib/pages/profile_page.dart
// ignore_for_file: unused_element, deprecated_member_use, unused_field

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

import '../services/image_service_cache.dart';
import 'preload_page.dart';
import '../services/audio_feedback.dart';
import '../services/auth_service.dart'; // <-- NEW: use singleton AuthService
import '../services/language_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/analytics_service.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onReplayTutorial;
  const ProfilePage({Key? key, this.onReplayTutorial}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Profile info
  String username = '';
  String favoriteBrand = '';
  String favoriteModel = '';
  int profilePicIndex = 0;
  String createdAt = '';
  bool _isDataLoaded = false;
  String? _justUnlockedAchievement;

  // Stats counters
  int dailyStreak = 0;
  int trainingCompletedCount = 0;
  int correctAnswerCount = 0;
  int categoriesMastered = 0;
  int challengesAttemptedCount = 0;
  int questionAttemptCount = 0;

  // Progress (gears) data
  int _gearCount = 0;
  int _currentTrack = 1;
  int _sessionsCompleted = 0;
  int _requiredGearsForCurrentLevel = 0;
  int _currentLevelGears = 0;
  double _progressValue = 0.0;

  // Google sign-in related (stored in SharedPreferences by your sign-in flow)
  bool _googleSignedIn = false;
  String? _googleDisplayName;
  String? _googleEmail;
  String? _googlePhotoUrl;
  bool _useGoogleName = true; // si true, on affiche le nom Google au lieu du pseudo local

  // guest detection
  bool _isGuest = false;
  bool _isAnonymous = false;

  // For the edit dialog
  List<String> _brandOptions = [];
  Map<String, List<String>> _brandToModels = {};
  bool _isCarDataLoaded = false;

  String _getAchievementIdFromName(String name) {
    return name.split("–")[0].trim().toLowerCase().replaceAll(' ', '_');
  }

  bool isUnlocked(String name) {
    final id = _getAchievementIdFromName(name);
    return unlockedAchievementIds.contains(id);
  }

  Map<String, List<String>> _getAchievementMap(BuildContext context) {
    return {
      'achievements.categories.trackProgression'.tr(): [
        'achievements.list.firstFlag'.tr(),
        'achievements.list.levelComplete'.tr(),
        'achievements.list.midTrackMilestone'.tr(),
        'achievements.list.trackConqueror'.tr(),
      ],
      'achievements.categories.perfectRuns'.tr(): [
        'achievements.list.cleanSlate'.tr(),
        'achievements.list.zeroLifeLoss'.tr(),
        'achievements.list.swiftRacer'.tr(),
      ],
      'achievements.categories.gearMastery'.tr(): [
        'achievements.list.gearRookie'.tr(),
        'achievements.list.gearGrinder'.tr(),
        'achievements.list.gearTycoon'.tr(),
      ],
      'achievements.categories.gateTrackUnlocks'.tr(): [
        'achievements.list.gateOpener'.tr(),
        'achievements.list.trackUnlockerI'.tr(),
        'achievements.list.trackUnlockerII'.tr(),
      ],
      'achievements.categories.comebackCorrection'.tr(): [
        'achievements.list.secondChance'.tr(),
        'achievements.list.perseverance'.tr(),
      ],
      'achievements.categories.trainingAchievements'.tr(): [
        'achievements.list.trainingInitiate'.tr(),
        'achievements.list.trainingRegular'.tr(),
        'achievements.list.trainingVeteran'.tr(),
        'achievements.list.quizStreak'.tr(),
        'achievements.list.sharpshooter'.tr(),
        'achievements.list.allRounder'.tr(),
        'achievements.list.trainingAllStar'.tr(),
      ],
    };
  }

  @override
  void initState() {
    super.initState();

    // Initialize AuthService (GoogleSignIn v7+ wrapper)
    AuthService.instance.init().catchError((e) {
      debugPrint('AuthService.init error: $e');
    });

    // audio: page open
    try {
      AudioFeedback.instance.playEvent(SoundEvent.pageOpen);
    } catch (_) {}

    // Track screen view
    AnalyticsService.instance.logProfileViewed();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewAchievement();
    });
    _loadProfileData();
    _loadCarData();
    _loadDailyStreak();
    _loadTrainingCompletedCount();
    _loadCorrectAnswerCount();
    _loadCategoriesMasteredCount();
    _loadChallengesAttemptedCount();
    _loadQuestionAttemptCount();
    _loadUnlockedAchievements();
  }

  List<String> unlockedAchievementIds = [];

  Future<void> _loadUnlockedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      unlockedAchievementIds = prefs.getStringList('unlockedAchievements') ?? [];
    });
  }

  void showAchievementSnackBar(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('profile.achievementUnlocked'.tr(namedArgs: {'title': title})),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  Future<void> unlockAchievement(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = prefs.getStringList('unlockedAchievements') ?? [];
    if (!unlocked.contains(id)) {
      unlocked.add(id);
      await prefs.setStringList('unlockedAchievements', unlocked);
      final title = _getDisplayNameFromId(id);
      showAchievementSnackBar(title);
    }
  }

  String _getDisplayNameFromId(String id) {
    for (final entry in _getAchievementMap(context).entries) {
      for (final name in entry.value) {
        if (_getAchievementIdFromName(name) == id) {
          return name.split("–")[0].trim();
        }
      }
    }
    return id;
  }

  Future<void> _checkNewAchievement() async {
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getStringList('unlockedAchievements') ?? [];
    final old = prefs.getStringList('shownAchievements') ?? [];
    for (final id in all) {
      if (!old.contains(id)) {
        old.add(id);
        await prefs.setStringList('shownAchievements', old);
        break;
      }
    }
  }

  bool isAchievementUnlocked(String id) {
    return unlockedAchievementIds.contains(id);
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();

    // Read Google-related prefs (your Google sign-in flow should set these keys)
    final googleSigned = prefs.getBool('google_signed_in') ?? false;
    final googleName = prefs.getString('google_displayName');
    final googleEmail = prefs.getString('google_email');
    final googlePhoto = prefs.getString('google_photoUrl');
    final useGoogleNamePref = prefs.getBool('use_google_name') ?? true;

    // Read stored username and other profile fields
    final storedUsername = prefs.getString('username');
    final storedFavoriteBrand = prefs.getString('favoriteBrand') ?? 'N/A';
    final storedFavoriteModel = prefs.getString('favoriteModel') ?? 'N/A';
    final storedCreatedAt = prefs.getString('createdAt');
    final storedPicIndex = prefs.getInt('profilePictureIndex');

    // Decide guest status (fallback heuristic)
    final guestPref = prefs.getBool('is_guest');
    final isGuestDetermined = guestPref ??
        (storedUsername == null ||
            storedUsername.isEmpty ||
            storedUsername == 'N/A' ||
            storedUsername.startsWith('unnamed'));

    // Check if user is anonymous (Firebase anonymous auth)
    final isAnonymousDetermined = AuthService.instance.isAnonymous();

    // Compute profilePicIndex and createdAt (persist if missing)
    int resolvedPicIndex;
    if (storedPicIndex == null) {
      resolvedPicIndex = Random().nextInt(6);
      await prefs.setInt('profilePictureIndex', resolvedPicIndex);
    } else {
      resolvedPicIndex = storedPicIndex;
    }

    final resolvedCreatedAt =
        storedCreatedAt ?? DateTime.now().toLocal().toIso8601String().split('T').first;
    if (storedCreatedAt == null) {
      await prefs.setString('createdAt', resolvedCreatedAt);
    }

    // Decide username: prefer persisted username, but allow Google name when signed in & opted-in
    String resolvedUsername =
        (storedUsername == null || storedUsername.isEmpty || storedUsername == 'N/A')
            ? 'unnamed_carenthusiast'
            : storedUsername;

    if (googleSigned && useGoogleNamePref && (googleName != null && googleName.isNotEmpty)) {
      resolvedUsername = googleName;
    }

    // Finally apply to state
    setState(() {
      _googleSignedIn = googleSigned;
      _googleDisplayName = googleName;
      _googleEmail = googleEmail;
      _googlePhotoUrl = googlePhoto;
      _useGoogleName = useGoogleNamePref;

      _isGuest = isGuestDetermined;
      _isAnonymous = isAnonymousDetermined;

      username = resolvedUsername;
      favoriteBrand = storedFavoriteBrand;
      favoriteModel = storedFavoriteModel;
      profilePicIndex = resolvedPicIndex;
      createdAt = resolvedCreatedAt;
      _isDataLoaded = true;
    });

    // Persist username if missing in prefs (keep behavior you had)
    if (prefs.getString('username') == null ||
        prefs.getString('username')!.isEmpty ||
        prefs.getString('username') == 'N/A') {
      await prefs.setString('username', username);
    }

    // If car data already loaded, try to fill random brand/model if missing
    await _ensureRandomProfileIfMissing();

    // Load progress that depends on prefs
    _loadProgressData();
  }

  Widget _buildAvatarHeader(String memSince) {
    final fileBase = _formatImageName(favoriteBrand, favoriteModel);

    final Widget avatarImage = ClipOval(
      child: _googleSignedIn && _googlePhotoUrl != null && _useGoogleName
          ? Image.network(
              _googlePhotoUrl!,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => Image.asset(
                'assets/profile/avatar.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            )
          : Image(
              image: ImageCacheService.instance.imageProvider('${fileBase}${profilePicIndex}.webp'),
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => Image.asset(
                'assets/profile/avatar.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
    );

    final displayName = (_googleSignedIn && _useGoogleName && (_googleDisplayName?.isNotEmpty ?? false))
        ? _googleDisplayName!
        : username;

    // indicator (small badge) showing signed-in status
    final statusChip = _googleSignedIn
        ? Chip(label: Text(_googleEmail ?? 'profile.googleUser'.tr(), style: const TextStyle(color: Colors.white70)), avatar: const Icon(Icons.check_circle, size: 16), backgroundColor: const Color(0xFF1E1E1E))
        : (_isAnonymous || _isGuest ? Chip(label: Text('profile.anonymousAccount'.tr(), style: const TextStyle(color: Colors.white70)), backgroundColor: const Color(0xFF1E1E1E)) : const SizedBox.shrink());

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _showAccountDialog,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.transparent,
                  child: avatarImage,
                ),
                Positioned(
                  top: -6,
                  left: -6,
                  child: Material(
                    color: Colors.black.withOpacity(0.05),
                    shape: const CircleBorder(),
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.language, size: 18),
                      tooltip: 'language.title'.tr(),
                      onPressed: _showLanguageSelector,
                    ),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: Material(
                    color: Colors.black.withOpacity(0.05),
                    shape: const CircleBorder(),
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'profile.editProfileTooltip'.tr(),
                      onPressed: _showEditProfileDialog,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          GestureDetector(
            onTap: _showAccountDialog,
            child: Column(
              children: [
                Text(displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('profile.memberSince'.tr() + ': $memSince', style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          statusChip,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_fire_department, color: Colors.orange),
              const SizedBox(width: 6),
              Text('profile.dailyStreak'.tr() + ': ' + 'profile.days'.tr(namedArgs: {'count': dailyStreak.toString()}), style: const TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadDailyStreak() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      dailyStreak = prefs.getInt('dayStreak') ?? 0;
    });
  }

  Future<void> _loadTrainingCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      trainingCompletedCount = prefs.getInt('trainingCompletedCount') ?? 0;
    });
  }

  Future<void> _loadCorrectAnswerCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      correctAnswerCount = prefs.getInt('correctAnswerCount') ?? 0;
    });
  }

  Future<void> _loadCategoriesMasteredCount() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'best_Brand',
      'best_Model',
      'best_Origin',
      'best_EngineType',
      'best_MaxSpeed',
      'best_Acceleration',
      'best_Power',
      'best_SpecialFeature'
    ];
    int count = 0;
    for (var key in keys) {
      final val = prefs.getString(key);
      if (val != null && val.contains('Best score : 20/20')) {
        count++;
      }
    }
    setState(() {
      categoriesMastered = count;
    });
  }

  Future<void> _loadChallengesAttemptedCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      challengesAttemptedCount = prefs.getInt('challengesAttemptedCount') ?? 0;
    });
  }

  Future<void> _loadQuestionAttemptCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      questionAttemptCount = prefs.getInt('questionAttemptCount') ?? 0;
    });
  }

  Widget _buildMiniAchievement(String fullText) {
    final title = fullText.split("–")[0].trim();
    final id = _getAchievementIdFromName(fullText);
    final isUnlocked = unlockedAchievementIds.contains(id);
    return GestureDetector(
      onTap: () {
        try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
        _showAchievementPopup(context, fullText);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 40, color: isUnlocked ? Colors.amber : Colors.grey),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _showAllAchievementsPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final allNames = _getAchievementMap(context).entries.expand((e) => e.value).toList();
        return AlertDialog(
          title: Text('profile.achievements'.tr()),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              children: allNames.map((name) => _buildMiniAchievement(name)).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                try {
                  AudioFeedback.instance.playEvent(SoundEvent.tap);
                } catch (_) {}
                Navigator.of(ctx).pop();
              },
              child: Text('common.close'.tr()),
            ),
          ],
        );
      },
    );
  }

  String _fileBase(String brand, String model) {
    final combined = (brand + model).replaceAll(RegExp(r'[ ./]'), '');
    return combined.splitMapJoin(
      RegExp(r'\w+'),
      onMatch: (m) => m[0]!.toUpperCase() + m.group(0)!.substring(1).toLowerCase(),
      onNonMatch: (n) => '',
    );
  }

  Future<void> _loadProgressData() async {
    final prefs = await SharedPreferences.getInstance();
    int gearCount = prefs.getInt('gearCount') ?? 0;
    int currentTrack;
    int baseGears;
    if (gearCount < 750) {
      currentTrack = 1;
      baseGears = 0;
    } else if (gearCount < 3250) {
      currentTrack = 2;
      baseGears = 750;
    } else {
      currentTrack = 3;
      baseGears = 3250;
    }
    int maxLevels = currentTrack == 1 ? 10 : currentTrack == 2 ? 20 : 30;
    int extraGears = gearCount - baseGears;
    int sessions = 0;
    int levelGears = extraGears;
    for (int lvl = 1; lvl <= maxLevels; lvl++) {
      int req = (currentTrack == 3 && lvl >= 20) ? 220 : (30 + (lvl - 1) * 10);
      if (levelGears >= req) {
        levelGears -= req;
        sessions = lvl;
      } else {
        break;
      }
    }
    int reqForCurrent = (currentTrack == 3 && sessions + 1 >= 20) ? 220 : (30 + sessions * 10);
    double prog = reqForCurrent > 0 ? levelGears / reqForCurrent : 0.0;
    setState(() {
      _gearCount = gearCount;
      _currentTrack = currentTrack;
      _sessionsCompleted = sessions;
      _requiredGearsForCurrentLevel = reqForCurrent;
      _currentLevelGears = levelGears;
      _progressValue = prog.clamp(0.0, 1.0);
    });
  }

  Future<void> _loadCarData() async {
    try {
      final raw = await rootBundle.loadString('assets/cars.csv');
      final lines = raw.split('\n');
      final brands = <String>{};
      final map = <String, Set<String>>{};
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 2) continue;
        if (i == 0 && parts[0].toLowerCase().contains('brand')) continue;
        final b = parts[0].trim(), m = parts[1].trim();
        brands.add(b);
        map.putIfAbsent(b, () => {}).add(m);
      }
      setState(() {
        _brandOptions = brands.toList()..sort();
        _brandToModels = {for (var b in _brandOptions) b: (map[b] ?? {}).toList()..sort()};
        _isCarDataLoaded = true;
      });

      // Now that car data is available, ensure random brand/model if missing
      await _ensureRandomProfileIfMissing();
    } catch (_) {
      setState(() => _isCarDataLoaded = false);
    }
  }

  // --- NEW: start Google sign-in flow via AuthService and persist prefs
  Future<void> _startGoogleSignInFlow({BuildContext? dialogContext}) async {
    try {
      final credential = await AuthService.instance.signInWithGoogle();
      if (credential == null) {
        // user cancelled
        if (dialogContext != null) Navigator.of(dialogContext).pop();
        return;
      }

      final user = credential.user;
      final prefs = await SharedPreferences.getInstance();

      final displayName = user?.displayName ?? '';
      final email = user?.email ?? '';
      final photoUrl = user?.photoURL ?? '';

      await prefs.setBool('google_signed_in', true);
      await prefs.setString('google_displayName', displayName);
      await prefs.setString('google_email', email);
      await prefs.setString('google_photoUrl', photoUrl);
      await prefs.setBool('use_google_name', true);
      await prefs.setBool('is_guest', false);

      if (!mounted) return;
      setState(() {
        _googleSignedIn = true;
        _googleDisplayName = displayName.isNotEmpty ? displayName : null;
        _googleEmail = email.isNotEmpty ? email : null;
        _googlePhotoUrl = photoUrl.isNotEmpty ? photoUrl : null;
        _useGoogleName = true;
        _isGuest = false;
        if (_useGoogleName && (_googleDisplayName?.isNotEmpty ?? false)) {
          username = _googleDisplayName!;
        }
      });

      if (dialogContext != null) {
        Navigator.of(dialogContext).pop(); // close progress dialog
        Navigator.of(dialogContext).pop(); // close edit dialog
      }
    } catch (err) {
      if (dialogContext != null) Navigator.of(dialogContext).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile.googleSignInFailed'.tr(namedArgs: {'error': err.toString()}))),
        );
      }
    }
  }

  // --- START: language selector dialog
  void _showLanguageSelector() {
    final currentLang = LanguageService.getCurrentLanguageCode(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('language.selectLanguage'.tr(), style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: LanguageService.availableLanguages.length,
              itemBuilder: (context, index) {
                final langCode = LanguageService.availableLanguages.keys.elementAt(index);
                final langName = LanguageService.availableLanguages[langCode]!;
                final flag = LanguageService.getLanguageFlag(langCode);
                final isSelected = langCode == currentLang;

                return ListTile(
                  leading: Text(flag, style: const TextStyle(fontSize: 24)),
                  title: Text(langName, style: const TextStyle(color: Colors.white)),
                  trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await LanguageService.changeLanguage(context, langCode);
                      if (!mounted) return;
                      final languageName = LanguageService.getLanguageName(langCode);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('language.languageChanged'.tr(namedArgs: {'language': languageName}))),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('language.languageChangeFailed'.tr())),
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('common.close'.tr()),
            ),
          ],
        );
      },
    );
  }
  // --- END language selector dialog

  // --- NEW: show account information dialog (with disconnect)
  void _showAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('profile.settings'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_googlePhotoUrl != null && _googlePhotoUrl!.isNotEmpty)
                CircleAvatar(radius: 36, backgroundImage: NetworkImage(_googlePhotoUrl!))
              else
                const CircleAvatar(radius: 36, child: Icon(Icons.person)),
              const SizedBox(height: 12),
              Text(_googleDisplayName ?? username, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_googleEmail ?? '', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                _googleSignedIn ? 'profile.connectedWithGoogle'.tr() : (_isGuest ? 'profile.guestAccount'.tr() : 'profile.localProfile'.tr()),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          actions: [
            if (_googleSignedIn)
              TextButton(
                onPressed: () {
                  try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                  // close dialog then open disconnect confirmation
                  Navigator.of(ctx).pop();
                  showDialog(
                    context: context,
                    builder: (confirmCtx) => AlertDialog(
                      title: Text('profile.disconnectConfirm'.tr()),
                      content: Text('profile.disconnectWarning'.tr()),
                      actions: [
                        TextButton(
                          onPressed: () {
                            try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                            Navigator.of(confirmCtx).pop();
                          },
                          child: Text('common.cancel'.tr()),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                            _disconnectGoogleAccount(confirmCtx);
                          },
                          child: Text('profile.disconnectGoogle'.tr()),
                        ),
                      ],
                    ),
                  );
                },
                child: Text('profile.disconnectGoogle'.tr()),
              ),
            TextButton(
              onPressed: () {
                try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                Navigator.of(ctx).pop();
              },
              child: Text('common.close'.tr()),
            ),
          ],
        );
      },
    );
  }

  /// Ensures we have a random favoriteBrand/favoriteModel when none is set.
  /// Also ensures username default is saved if it was missing.
  Future<void> _ensureRandomProfileIfMissing() async {
    if (!_isCarDataLoaded) return;
    final prefs = await SharedPreferences.getInstance();

    // Username persistence (already defaulted). Save if necessary.
    if (prefs.getString('username') == null ||
        prefs.getString('username')!.isEmpty ||
        prefs.getString('username') == 'N/A') {
      await prefs.setString('username', username.isEmpty ? 'unnamed_carenthusiast' : username);
    }

    // If favorites are missing, pick a random brand and model once and persist
    final needsRandom =
        (favoriteBrand.isEmpty || favoriteBrand == 'N/A') ||
        (favoriteModel.isEmpty || favoriteModel == 'N/A');

    if (needsRandom && _brandOptions.isNotEmpty) {
      // Use a seeded RNG per install for reproducibility across app restarts for a given user
      final savedSeed = prefs.getInt('installSeed') ??
          DateTime.now().millisecondsSinceEpoch..let((s) => prefs.setInt('installSeed', s));
      final rng = Random(savedSeed);

      final randBrand = _brandOptions[rng.nextInt(_brandOptions.length)];
      final models = _brandToModels[randBrand] ?? const <String>[];
      if (models.isNotEmpty) {
        final randModel = models[rng.nextInt(models.length)];
        await prefs.setString('favoriteBrand', randBrand);
        await prefs.setString('favoriteModel', randModel);
        setState(() {
          favoriteBrand = randBrand;
          favoriteModel = randModel;
        });
      }
    }
  }

  void _showAchievementPopup(BuildContext context, String fullText) {
    final parts = fullText.split("–");
    final title = parts[0].trim();
    final description = parts.length > 1 ? parts[1].trim() : "No description available";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () {
              try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
              Navigator.of(ctx).pop();
            },
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  String _capitalizeEachWord(String input) {
    return input
        .split(RegExp(r'\s+'))
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join();
  }

  String _formatImageName(String brand, String model) {
    String input = (brand + model).replaceAll(RegExp(r'[ ./]'), '');
    return input
        .split(RegExp(r'(?=[A-Z])|(?<=[a-z])(?=[A-Z])|(?<=[a-z])(?=[0-9])'))
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join();
  }

  void _showUnlockedAchievementsPopup(BuildContext context) {
    final unlocked = _getAchievementMap(context).entries
        .expand((e) => e.value)
        .where((name) => isUnlocked(name))
        .toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('profile.unlocked'.tr() + ' ' + 'profile.achievements'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            children: unlocked.map((name) => _buildMiniAchievement(name)).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                AudioFeedback.instance.playEvent(SoundEvent.tap);
              } catch (_) {}
              Navigator.of(context).pop();
            },
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  void _showLockedAchievementsPopup(BuildContext context) {
    final locked = _getAchievementMap(context).entries
        .expand((e) => e.value)
        .where((name) => !isUnlocked(name))
        .toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('profile.locked'.tr() + ' ' + 'profile.achievements'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            children: locked.map((name) => _buildMiniAchievement(name)).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              try {
                AudioFeedback.instance.playEvent(SoundEvent.tap);
              } catch (_) {}
              Navigator.of(context).pop();
            },
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  // --- NEW: Link anonymous account to Google
  Future<void> _linkGoogleAccount() async {
    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Attempt to link
      final credential = await AuthService.instance.linkGoogleAccount();

      // Close loading
      if (!mounted) return;
      Navigator.of(context).pop();

      if (credential == null) {
        // User cancelled
        return;
      }

      final user = credential.user;
      if (user == null) {
        throw 'Failed to link account';
      }

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_signed_in', true);
      await prefs.setString('google_displayName', user.displayName ?? '');
      await prefs.setString('google_email', user.email ?? '');
      await prefs.setString('google_photoUrl', user.photoURL ?? '');
      await prefs.setBool('use_google_name', true);
      await prefs.setBool('is_guest', false);
      await prefs.setString('auth_method', 'google');
      await prefs.setString('firebase_uid', user.uid);
      await prefs.remove('anonymous_since');

      // Track account linking in Analytics
      await AnalyticsService.instance.logAccountLinked(
        fromMethod: 'anonymous',
        toMethod: 'google',
      );

      // Update UI state
      setState(() {
        _googleSignedIn = true;
        _googleDisplayName = user.displayName;
        _googleEmail = user.email;
        _googlePhotoUrl = user.photoURL;
        _useGoogleName = true;
        _isGuest = false;
        _isAnonymous = false;
        if (_useGoogleName && (_googleDisplayName?.isNotEmpty ?? false)) {
          username = _googleDisplayName!;
        }
      });

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('profile.accountConnected'.tr()),
          duration: const Duration(seconds: 4),
        ),
      );
    } on FirebaseAuthException catch (e) {
      // Close loading if still open
      if (mounted) Navigator.of(context).pop();

      String errorMessage = 'Failed to connect account: ${e.message}';
      if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use') {
        errorMessage = 'profile.googleAccountInUse'.tr();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Close loading if still open
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting account: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // --- NEW: disconnect using AuthService (revoke tokens + sign out)
  Future<void> _disconnectGoogleAccount(BuildContext dialogContext) async {
    // affiche progress
    showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Use AuthService to disconnect (it signs out Firebase + Google properly)
      await AuthService.instance.disconnectGoogle();

      // Track sign-out in Analytics
      await AnalyticsService.instance.logSignOut();
    } catch (_) {
      // ignore
    }

    // Clear persisted flags/tokens in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('google_signed_in', false);
    await prefs.remove('google_displayName');
    await prefs.remove('google_email');
    await prefs.remove('google_photoUrl');
    await prefs.setBool('use_google_name', false);
    // Optional: mark user as guest so heuristics won't auto-resign
    await prefs.setBool('is_guest', true);

    // 4) Update local state and close dialogs
    if (!mounted) {
      Navigator.of(dialogContext).pop();
      return;
    }

    setState(() {
      _googleSignedIn = false;
      _googleDisplayName = null;
      _googleEmail = null;
      _googlePhotoUrl = null;
      _useGoogleName = false;
      _isGuest = true;
      username = prefs.getString('username') ?? 'unnamed_carenthusiast';
    });

    // fermer le loader puis la boite d'édition
    Navigator.of(dialogContext).pop(); // close progress
    Navigator.of(dialogContext).pop(); // close edit dialog
  }

  // Remplacer entièrement la fonction _showEditProfileDialog par ceci :
  void _showEditProfileDialog() {
    // copies initiales (hors du StatefulBuilder pour qu'elles persistent)
    String u = username;
    if (!_isCarDataLoaded) return;
    String fb = favoriteBrand != 'N/A' && favoriteBrand.isNotEmpty ? favoriteBrand : _brandOptions.first;
    String fm = favoriteModel != 'N/A' && favoriteModel.isNotEmpty ? favoriteModel : _brandToModels[fb]!.first;

    // <- important : localUseGoogleName déclaré ici (outside builder)
    bool localUseGoogleName = _useGoogleName;

    // controller stable pour l'input username
    final usernameController = TextEditingController(text: u);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text('profile.editProfile'.tr()),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  // Username field (controller stable)
                  TextField(
                    controller: usernameController,
                    style: const TextStyle(color: Colors.white70),
                    decoration: InputDecoration(
                      labelText: 'profile.username'.tr(),
                      labelStyle: const TextStyle(color: Colors.white70),
                    ),
                    onChanged: (v) => u = v,
                  ),
                  const SizedBox(height: 12),

                  // Favorite Brand dropdown
                  // Remplace l'ancien DropdownButtonFormField Favorite Brand par ceci :
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<String>(
                      value: fb,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(color: Colors.white70),
                      decoration: InputDecoration(
                        labelText: 'profile.favoriteBrand'.tr(),
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      dropdownColor: const Color(0xFF1E1E1E),
                      items: _brandOptions.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: Colors.white70)))).toList(),
                      onChanged: (v) {
                        setSt(() {
                          fb = v!;
                          fm = _brandToModels[fb]!.first;
                        });
                      },
                    ),
                  ),

                  // Remplace l'ancien DropdownButtonFormField Favorite Model par ceci :
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<String>(
                      value: fm,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(color: Colors.white70),
                      decoration: InputDecoration(
                        labelText: 'profile.favoriteModel'.tr(),
                        labelStyle: const TextStyle(color: Colors.white70),
                      ),
                      dropdownColor: const Color(0xFF1E1E1E),
                      items: _brandToModels[fb]!.map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(color: Colors.white70)))).toList(),
                      onChanged: (v) => setSt(() => fm = v!),
                    ),
                  ),

                  // If Google signed in, show options
                  if (_googleSignedIn) ...[
                    CheckboxListTile(
                      title: Text('profile.useGoogleProfile'.tr(), style: const TextStyle(color: Colors.white70)),
                      value: localUseGoogleName,
                      onChanged: (val) => setSt(() => localUseGoogleName = val ?? false),
                    ),
                    const SizedBox(height: 8),
                    Text('profile.signedInAs'.tr(namedArgs: {'name': _googleDisplayName ?? _googleEmail ?? 'profile.googleUser'.tr()}),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),

                    // Disconnect button for signed-in users
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                        onPressed: () {
                          try {
                            AudioFeedback.instance.playEvent(SoundEvent.tap);
                          } catch (_) {}
                          _disconnectGoogleAccount(ctx);
                        },
                        child: Text('profile.disconnectGoogle'.tr()),
                      ),
                    ),
                  ],
                  // Note: Removed automatic Google sign-in prompt for guests
                  // Users should sign in from the Welcome page when first using the app
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();

                  // use the controller text (most reliable)
                  final newUsername = usernameController.text.trim();

                  // Persist choices
                  await prefs.setString('username', newUsername);
                  await prefs.setString('favoriteBrand', fb);
                  await prefs.setString('favoriteModel', fm);
                  await prefs.setBool('use_google_name', localUseGoogleName);

                  if (!mounted) return;

                  setState(() {
                    // update in-memory flags
                    _useGoogleName = localUseGoogleName;

                    // If user wants to use Google name and is signed-in, prefer Google display name,
                    // otherwise keep the freshly typed username (or fallback default)
                    username = (_googleSignedIn && _useGoogleName && (_googleDisplayName?.isNotEmpty ?? false))
                        ? _googleDisplayName!
                        : (newUsername.isEmpty ? 'unnamed_carenthusiast' : newUsername);

                    favoriteBrand = fb;
                    favoriteModel = fm;
                  });

                  // Close dialog (NE PAS disposer le controller ici)
                  Navigator.of(ctx).pop();
                },
                child: Text('common.save'.tr()),
              ),
              TextButton(
                onPressed: () {
                  try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                  // NE PAS disposer le controller ici pour éviter l'error "used after disposed"
                  Navigator.of(ctx).pop();
                },
                child: Text('common.cancel'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Member since formatting
    String memSince = createdAt;
    try {
      final dt = DateTime.parse(createdAt);
      final mns = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      memSince = '${mns[dt.month - 1]} ${dt.year}';
    } catch (_) {}

    final accuracy = questionAttemptCount > 0
        ? ((correctAnswerCount / questionAttemptCount) * 100).round()
        : 0;

    final allAchievements = _getAchievementMap(context).entries.expand((e) => e.value).toList();
    final unlocked = allAchievements.where((name) => isUnlocked(name)).toList();
    final locked = allAchievements.where((name) => !isUnlocked(name)).toList();
    final topRow = List<String>.from(unlocked.take(3));
    while (topRow.length < 3) topRow.add('');
    final bottomRow = List<String>.from(locked.take(3));
    while (bottomRow.length < 3) bottomRow.add('');

    if (_justUnlockedAchievement != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('profile.achievementUnlocked'.tr(namedArgs: {'title': _justUnlockedAchievement ?? ''})),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
          ),
        );
      });
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // <-- replaced avatar block with the helper
                  _buildAvatarHeader(memSince),

                  const SizedBox(height: 20),

                  // Show "Connect to Google" banner for anonymous users
                  if (_isAnonymous && !_googleSignedIn) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4285F4), Color(0xFF34A853)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cloud_upload, color: Colors.white, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'profile.connectGoogle'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'anonymousUpgrade.neverLose'.tr() + ' • ' + 'anonymousUpgrade.accessAny'.tr(),
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _linkGoogleAccount,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF4285F4),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                'profile.connectGoogle'.tr(),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text(
                    'profile.trackLevelProgress'.tr(namedArgs: {
                      'track': _currentTrack.toString(),
                      'level': (_sessionsCompleted + 1).toString(),
                      'current': _currentLevelGears.toString(),
                      'required': _requiredGearsForCurrentLevel.toString()
                    }),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progressValue,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 24),
                  Text('profile.stats'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildStatCard('profile.trainingSessions'.tr(), trainingCompletedCount.toString(), Icons.fitness_center),
                        _buildStatCard('profile.correctAnswers'.tr(), correctAnswerCount.toString(), Icons.check_circle),
                        _buildStatCard('profile.categoriesMastered'.tr(), '$categoriesMastered/8', Icons.category),
                        _buildStatCard('profile.challengesAttempted'.tr(), challengesAttemptedCount.toString(), Icons.flag),
                        _buildStatCard('profile.accuracy'.tr(), '$accuracy%', Icons.bar_chart),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('profile.achievements'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  if (unlocked.isNotEmpty)
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1,
                      children: List.generate(3, (i) {
                        final name = topRow[i];
                        if (name.isEmpty) return const SizedBox();
                        final isLast = i == 2;
                        return GestureDetector(
                          onTap: () {
                            try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                            if (isLast) {
                              _showUnlockedAchievementsPopup(context);
                            } else {
                              _showAchievementPopup(context, name);
                            }
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.emoji_events, size: 60, color: Colors.yellow[700]!),
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      name.split("–")[0].trim(),
                                      style: const TextStyle(fontSize: 12),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (isLast)
                                const Positioned(top: 4, right: 4, child: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey)),
                            ],
                          ),
                        );
                      }),
                    ),

                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1,
                    children: List.generate(3, (i) {
                      final name = (i < locked.length) ? locked[i] : '';
                      if (name.isEmpty) return const SizedBox();
                      final isLast = i == 2;
                      return GestureDetector(
                        onTap: () {
                          try { AudioFeedback.instance.playEvent(SoundEvent.tap); } catch (_) {}
                          if (isLast) {
                            _showLockedAchievementsPopup(context);
                          } else {
                            _showAchievementPopup(context, name);
                          }
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.emoji_events, size: 60, color: Colors.grey),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    name.split("–")[0].trim(),
                                    style: const TextStyle(fontSize: 12),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (isLast)
                              const Positioned(top: 4, right: 4, child: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey)),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          // Open PreloadPage with no arguments
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Map<String, int>>(
                  MaterialPageRoute(builder: (_) => const PreloadPage()),
                );
                if (!mounted) return;
                if (result != null) {
                  final downloaded = result['downloaded'] ?? 0;
                  final cached = result['cached'] ?? 0;
                  final failed = result['failed'] ?? 0;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('preload.downloadStatus'.tr(namedArgs: {'downloaded': downloaded.toString(), 'cached': cached.toString(), 'failed': failed.toString()})),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
              child: Text('preload.ensureLoaded'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Colors.blue),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// Simple inline helper
extension Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}