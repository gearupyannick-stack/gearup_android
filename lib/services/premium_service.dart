// lib/services/premium_service.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Central place to manage Premium entitlement and training limits.
class PremiumService {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  static const String _kIsPremium = 'isPremium';
  static const String _kTrainCount = 'training_attempts_today';
  static const String _kTrainDate = 'training_attempts_date';

  // Free daily limit for gated training challenges (set to 5 as requested)
  static const int freeDailyTrainingLimit = 5;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  String _attemptsDate = '';
  int _attemptsToday = 0;

  /// Initialize from SharedPreferences (call this at app start).
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_kIsPremium) ?? false;

    final today = _yyyyMmDd(DateTime.now());
    _attemptsDate = prefs.getString(_kTrainDate) ?? today;
    _attemptsToday = prefs.getInt(_kTrainCount) ?? 0;
    if (_attemptsDate != today) {
      _attemptsDate = today;
      _attemptsToday = 0;
      await _persistAttempts();
    }
  }

  /// Mark user as premium (persisted)
  Future<void> setPremium(bool v) async {
    _isPremium = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsPremium, v);
  }

  /// Returns whether the user can start a gated training now.
  bool canStartTrainingNow() {
    if (_isPremium) return true;
    return _attemptsToday < freeDailyTrainingLimit;
  }

  /// Remaining attempts for non-premium user.
  int remainingTrainingAttempts() {
    if (_isPremium) return -1; // -1 => infinite
    return freeDailyTrainingLimit - _attemptsToday;
  }

  /// Record that a training attempt was started (increments daily counter)
  Future<void> recordTrainingStart() async {
    final today = _yyyyMmDd(DateTime.now());
    if (_attemptsDate != today) {
      _attemptsDate = today;
      _attemptsToday = 0;
    }
    _attemptsToday += 1;
    await _persistAttempts();
  }

  Future<void> _persistAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTrainCount, _attemptsToday);
    await prefs.setString(_kTrainDate, _attemptsDate);
  }

  String _yyyyMmDd(DateTime d) =>
      "${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
}