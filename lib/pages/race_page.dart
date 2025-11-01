import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_feedback.dart';
import '../services/image_service_cache.dart';
import '../services/collab_wan_service.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';

class RacePage extends StatefulWidget {
  final String? username;
  
  const RacePage({
    Key? key,
    this.username,
  }) : super(key: key);

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
  bool _handlingEndRace = false;

  // New: race / car animation state
  bool _raceStarted = false;
  late final AnimationController _carController;
  final TextEditingController _nameController = TextEditingController();

  // --- Collab / players state ---
  final CollabWanService _collab = CollabWanService();
  StreamSubscription<List<PlayerInfo>>? _playersSub;
  List<PlayerInfo> _playersInRoom = [];
  String? _currentRoomCode;
  Timer? _presenceTimer;
  bool _waitingForNextQuestion = false;
  StreamSubscription<List<CollabMessage>>? _messagesSub;
  bool _raceEndedByServer = false;

  // quiz / step-race state
  List<int> _quizSelectedIndices = [];
  int _quizCurrentPos = 0;        // 0..N-1 current step
  int _quizScore = 0;
  double _currentDistance = 0.0; // traveled distance in px along path
  double _stepDistance = 0.0;    // _totalPathLength / totalQuestions
  String? _roomCreatorId;
  
  // ADD these fields inside _RacePageState
  static const String _kRaceInterstitialCounterKey = 'race_interstitial_counter';

  // --- path data for tracks (normalized coords in [0..1]) ---
  // Monza (RaceTrack0) — the list you asked for
  final List<List<double>> _monzaNorm = [
    [0.75, 0.32],[0.75, 0.23],[0.65, 0.20],[0.55, 0.23],[0.50, 0.30],[0.45, 0.37],[0.20, 0.40],
    [0.18, 0.50],[0.20, 0.55],[0.28, 0.60],[0.31, 0.70],[0.30, 0.80],[0.40, 0.82],[0.72, 0.80],
    [0.75, 0.75],[0.72, 0.65],[0.50, 0.62],[0.52, 0.52],[0.75, 0.37],[0.75, 0.32]
  ];

  // Monaco (RaceTrack1) — normalized centerline waypoints
  final List<List<double>> _monacoNorm = [
    [0.55, 0.81],[0.71, 0.75],[0.80, 0.63],[0.76, 0.52],[0.70, 0.48],[0.48, 0.45],[0.46, 0.40],
    [0.53, 0.34],[0.75, 0.36],[0.82, 0.30],[0.80, 0.22],[0.71, 0.19],[0.57, 0.23],[0.45, 0.19],
    [0.38, 0.12],[0.26, 0.11],[0.21, 0.17],[0.30, 0.33],[0.28, 0.37],[0.14, 0.44],[0.10, 0.51],
    [0.20, 0.56],[0.38, 0.56],[0.45, 0.60],[0.41, 0.66],[0.21, 0.70],[0.15, 0.74],[0.20, 0.82],
    [0.38, 0.85],[0.55, 0.81]
  ];

  final List<List<double>> _suzukaNorm = [
    [0.76, 0.79],[0.75, 0.19],[0.67, 0.13],[0.34, 0.13],[0.21, 0.18],[0.25, 0.28],[0.49, 0.36],
    [0.51, 0.45],[0.46, 0.50],[0.26, 0.53],[0.24, 0.64],[0.35, 0.72],[0.48, 0.75],[0.54, 0.84],
    [0.69, 0.86],[0.74, 0.81],[0.76, 0.79]
  ];

  final List<List<double>> _spaNorm = [
    [0.69, 0.88],[0.74, 0.85],[0.71, 0.79],[0.47, 0.75],[0.42, 0.70],[0.46, 0.64],[0.55, 0.59],
    [0.66, 0.62],[0.75, 0.66],[0.82, 0.52],[0.69, 0.40],[0.77, 0.18],[0.67, 0.09],[0.56, 0.11],
    [0.60, 0.24],[0.44, 0.29],[0.26, 0.23],[0.14, 0.26],[0.14, 0.37],[0.40, 0.41],[0.47, 0.48],
    [0.43, 0.53],[0.20, 0.55],[0.13, 0.77],[0.23, 0.84],[0.69, 0.88]
  ];


  final List<List<double>> _silverstoneNorm = [
    [0.82, 0.75],[0.81, 0.43],[0.73, 0.35],[0.73, 0.28],[0.77, 0.18],[0.71, 0.12],[0.63, 0.14],
    [0.57, 0.24],[0.47, 0.30],[0.40, 0.37],[0.30, 0.36],[0.29, 0.30],[0.34, 0.26],[0.42, 0.19],
    [0.42, 0.12],[0.32, 0.07],[0.19, 0.07],[0.13, 0.13],[0.13, 0.63],[0.07, 0.72],[0.11, 0.80],
    [0.21, 0.85],[0.28, 0.79],[0.29, 0.69],[0.41, 0.62],[0.37, 0.51],[0.46, 0.47],[0.58, 0.49],
    [0.60, 0.53],[0.53, 0.64],[0.60, 0.74],[0.51, 0.82],[0.58, 0.88],[0.73, 0.90],[0.80, 0.83],
    [0.82, 0.75]
  ];

  late final Map<int, List<List<double>>> _tracksNorm;

  // --- prepared path in pixel coords (computed per image size) ---
  List<Offset> _pathPoints = [];
  List<double> _cumLengths = []; // cumulative lengths, starts with 0.0
  double _totalPathLength = 0.0;
  // reentrancy guard to avoid parallel question loops
  bool _isAskingQuestion = false;

  // small epsilon for numeric stability
  static const double _eps = 1e-6;

  Future<List<PlayerInfo>> getPlayers(String roomCode) async {
    // Implement logic to fetch players in the room
    // This is a placeholder; replace with your actual logic
    return [];
  }

  // re-use the same arrays from HomePage logic (copy of home_page.dart)
  final List<int> _easyQuestions   = [1, 2, 3, 6];
  final List<int> _mediumQuestions = [4, 5, 11, 12];
  final List<int> _hardQuestions   = [7, 8, 9, 10];
  // Subscriptions for public-track presence + messages
  final Map<int, StreamSubscription<List<PlayerInfo>>> _publicPlayersSubs = {};
  final Map<int, StreamSubscription<List<CollabMessage>>> _publicMessagesSubs = {};
  final Map<int, bool> _publicRoomHasWaiting = { for (var i = 0; i <= 4; i++) i: false };
  final Map<int, bool> _publicRoomRunning = { for (var i = 0; i <= 4; i++) i: false };

  // helper to create fileBase (same behavior as HomePage)
  String _formatFileName(String brand, String model) {
    String input = (brand + model).replaceAll(RegExp(r'[ ./]'), '');
    return input
        .split(RegExp(r'(?=[A-Z])|(?<=[a-z])(?=[A-Z])|(?<=[a-z])(?=[0-9])'))
        .map((word) =>
            word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join();
  }

  Future<void> _showRaceResultDialog(List<PlayerInfo> players, PlayerInfo winner) async {
    if (!mounted) return;

    // Sort players for presentation (winner first)
    final displayList = List<PlayerInfo>.from(players);
    displayList.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return a.errors.compareTo(b.errors);
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Race finished!'),
              const SizedBox(height: 6),
              Text('Winner: ${winner.displayName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header row
                Row(
                  children: const [
                    Expanded(child: Text('Player', style: TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(width: 8),
                    Text('Score', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 12),
                    Text('Err', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: displayList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final p = displayList[i];
                      final isWinner = p.id == winner.id || p.displayName == winner.displayName;
                      final isLocal = p.id == _collab.localPlayerId || p.displayName == _nameController.text.trim();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: isWinner ? Colors.green[800] : Colors.grey[900],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.displayName.isNotEmpty ? p.displayName : (isLocal ? 'You' : 'Player'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isWinner ? FontWeight.w700 : FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${p.score}', style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 12),
                            Text('${p.errors}', style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadRaceInterstitialCounter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.getInt(_kRaceInterstitialCounterKey);
      if (mounted) {
        setState(() {
        });
      } else {
      }
    } catch (e) {
      // ignore errors gracefully
      // print('Failed to load race interstitial counter: $e');
    }
  }

  PlayerInfo _determineWinner(List<PlayerInfo> players) {
    if (players.isEmpty) {
      return PlayerInfo(id: '', displayName: 'No one', lastSeen: DateTime.now(), score: 0, errors: 0);
    }

    // defensive: make a sorted copy
    final sorted = List<PlayerInfo>.from(players);
    sorted.sort((a, b) {
      // primary: score desc
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      // secondary: errors asc
      final errCmp = a.errors.compareTo(b.errors);
      if (errCmp != 0) return errCmp;
      // tertiary: earlier lastSeen wins (smaller DateTime)
      return a.lastSeen.compareTo(b.lastSeen);
    });

    return sorted.first;
  }

  Future<void> _handleServerEndRace(Map<String, dynamic> payload) async {
    if (!mounted) return;
    debugPrint('Handling server end_race payload: $payload');

    // If not in race view, ignore.
    if (!_inPublicRaceView) {
      debugPrint('Ignoring end_race: not in public race view.');
      return;
    }

    // Prevent duplicate handling / re-entry
    if (_handlingEndRace || _raceEndedByServer) {
      debugPrint('Already handling end_race or race already marked ended; ignoring.');
      return;
    }

    _handlingEndRace = true;
    // tentatively mark ended; may be cleared if we ignore
    _raceEndedByServer = true;

    try {
      final localId = _collab.localPlayerId;
      final room = _currentRoomCode;

      // Safely extract winner fields from payload
      final winnerIdRaw = payload['winnerId'];
      final winnerNameRaw = payload['winnerName'];
      final String? winnerId = winnerIdRaw == null ? null : winnerIdRaw.toString();
      final String? winnerName = winnerNameRaw == null ? null : winnerNameRaw.toString();
      final bool payloadHasWinner = (winnerId != null && winnerId.isNotEmpty) ||
                                    (winnerName != null && winnerName.isNotEmpty);

      // Snapshot players to avoid concurrent mutation
      List<PlayerInfo> playersSnapshot = List<PlayerInfo>.from(_playersInRoom);

      // Ensure local player present and up-to-date in snapshot (use current _quizScore)
      final localName = _nameController.text.trim().isEmpty ? 'You' : _nameController.text.trim();
      final idxLocal = playersSnapshot.indexWhere((p) => p.id == localId || p.displayName == localName);
      if (idxLocal >= 0) {
        final p = playersSnapshot[idxLocal];
        playersSnapshot[idxLocal] = PlayerInfo(
          id: p.id,
          displayName: p.displayName.isNotEmpty ? p.displayName : localName,
          lastSeen: p.lastSeen,
          score: _quizScore,
          errors: p.errors,
        );
      } else {
        playersSnapshot.add(PlayerInfo(
          id: localId,
          displayName: localName,
          lastSeen: DateTime.now(),
          score: _quizScore,
          errors: 0,
        ));
      }

      // Determine winner: prefer server-provided id/name, fallback to local logic
      PlayerInfo winner;
      if (payloadHasWinner && winnerId != null && winnerId.isNotEmpty) {
        winner = playersSnapshot.firstWhere(
          (p) => p.id == winnerId,
          orElse: () => PlayerInfo(
            id: winnerId,
            displayName: (winnerName != null && winnerName.isNotEmpty) ? winnerName : 'Winner',
            lastSeen: DateTime.now(),
            score: 0,
            errors: 0,
          ),
        );
      } else if (payloadHasWinner && winnerName != null && winnerName.isNotEmpty) {
        winner = playersSnapshot.firstWhere(
          (p) => p.displayName == winnerName,
          orElse: () => PlayerInfo(
            id: '',
            displayName: winnerName,
            lastSeen: DateTime.now(),
            score: 0,
            errors: 0,
          ),
        );
      } else {
        winner = _determineWinner(playersSnapshot);
      }

      // total slots expected for this race
      final totalSlots = _quizSelectedIndices.length;
      final bool localCompleted = (totalSlots > 0) && (_quizScore >= totalSlots);

      // CRITICAL: If the winner selected is the local player but the local player has NOT actually
      // completed the required number of correct answers, ignore this end_race (do NOT show "You won").
      if (winner.id == localId && !localCompleted) {
        debugPrint('Ignoring end_race: decided winner is local but local has not completed quiz (score=$_quizScore / required=$totalSlots).');
        // clear the temporary flags so future end_race messages can be processed normally
        _handlingEndRace = false;
        _raceEndedByServer = false;
        return;
      }

      // If local player lost, show small "You lost" SnackBar (non-blocking).
      if (localId != winner.id) {
        try {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('You lost — Winner: ${winner.displayName}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (_) {
          // ignore snackbar errors
        }
      }

      // Show the full results dialog (blocking until dismissed).
      try {
        await _showRaceResultDialog(playersSnapshot, winner);
      } catch (e) {
        debugPrint('Error showing race result dialog: $e');
      }

      // best-effort ack to server that we handled the end
      if (room != null) {
        try {
          await _collab.sendMessage(room, {
            'type': 'ack_end_race',
            'playerId': localId,
          });
        } catch (e) {
          debugPrint('Failed to send ack_end_race: $e');
        }
      }

      // Now leave and cleanup UI — this will cancel subscriptions.
      try {
        await _leaveCurrentRoom();
      } catch (e) {
        debugPrint('Error leaving room after end_race: $e');
      }

      // **Show interstitial AFTER user dismissed results dialog and after leaving the room**
      try {
        await _maybeShowRaceInterstitial();
      } catch (e, st) {
        debugPrint('Race interstitial attempt failed in server end flow: $e\n$st');
      }

      if (!mounted) return;
      setState(() {
        _inPublicRaceView = false;
        _activeTrackIndex = null;
        _raceStarted = false;
        _quizSelectedIndices = [];
        _quizCurrentPos = 0;
        _quizScore = 0;
        _currentDistance = 0.0;
        _waitingForNextQuestion = false;
        _roomCreatorId = null;

        // reset server-end flag so a new game later can run normally
        _raceEndedByServer = false;
      });
    } finally {
      // Ensure reentrancy guard cleared if we didn't already return.
      _handlingEndRace = false;
    }
  }

  Future<void> _onRaceFinished() async {
    if (!mounted) return;

    debugPrint('Race finished locally — running finish flow.');

    // ensure the car isn't repeating
    try { _carController.stop(); } catch (_) {}

    // If server already declared the race ended, don't re-run finish logic.
    if (_raceEndedByServer) {
      debugPrint('Race already ended by server; aborting local finish flow.');
      return;
    }

    // send local final score to server (best-effort)
    final room = _currentRoomCode;
    final localId = _collab.localPlayerId;
    if (room != null) {
      try {
        await _collab.sendMessage(room, {
          'type': 'score_update',
          'playerId': localId,
          'score': _quizScore,
        });
      } catch (e) {
        debugPrint('Failed to send final score update: $e');
      }
    }

    // give server/opponent a short moment to push final scores
    await Future.delayed(const Duration(milliseconds: 700));

    // snapshot players (copy to avoid concurrent mutation)
    List<PlayerInfo> playersSnapshot = List<PlayerInfo>.from(_playersInRoom);

    // ensure local player present and up-to-date
    final localName = _nameController.text.trim().isEmpty ? 'You' : _nameController.text.trim();
    final idxLocal = playersSnapshot.indexWhere((p) => p.id == localId || p.displayName == localName);
    if (idxLocal >= 0) {
      final p = playersSnapshot[idxLocal];
      playersSnapshot[idxLocal] = PlayerInfo(
        id: p.id,
        displayName: p.displayName.isNotEmpty ? p.displayName : localName,
        lastSeen: p.lastSeen,
        score: _quizScore,
        errors: p.errors,
      );
    } else {
      playersSnapshot.add(PlayerInfo(
        id: localId,
        displayName: localName,
        lastSeen: DateTime.now(),
        score: _quizScore,
        errors: 0,
      ));
    }

    // determine winner (local decision only if server hasn't already declared one)
    final winner = _determineWinner(playersSnapshot);

    // Track race finished
    final didWin = winner.id == localId || winner.displayName == localName;
    AnalyticsService.instance.logEvent(
      name: 'race_finished',
      parameters: {
        'track': _activeTrackIndex ?? 0,
        'score': _quizScore,
        'is_multiplayer': _currentRoomCode != null ? 'true' : 'false',
        'won': didWin ? 'true' : 'false',
        'players_count': playersSnapshot.length,
      },
    );

    // mark that *we* are ending the race and inform others — include winnerName so receivers can show it
    _raceEndedByServer = true;

    if (room != null) {
      try {
        await _collab.sendMessage(room, {
          'type': 'end_race',
          'winnerId': winner.id,
          'winnerName': winner.displayName,
        });
      } catch (e) {
        debugPrint('Failed to send end_race message: $e');
      }
    }

    // show results dialog (blocking until user dismisses)
    await _showRaceResultDialog(playersSnapshot, winner);

    // cleanup & leave room, return to track grid
    await _leaveCurrentRoom();

    // **Show interstitial AFTER user dismissed results dialog and after leaving the room**
    try {
      await _maybeShowRaceInterstitial();
    } catch (e, st) {
      debugPrint('Race interstitial attempt failed: $e\n$st');
    }

    if (!mounted) return;
    setState(() {
      _inPublicRaceView = false;
      _activeTrackIndex = null;
    });
  }

  // --- replace existing _startCar() with this ---
  void _startCar() {
    if (!mounted) return;

    setState(() {
      _raceStarted = true;
    });

    // Track race started
    AnalyticsService.instance.logEvent(
      name: 'race_started',
      parameters: {
        'track': _activeTrackIndex ?? 0,
        'is_multiplayer': _currentRoomCode != null ? 'true' : 'false',
      },
    );

    // stop any ongoing action first
    try { _carController.stop(); } catch (_) {}

    final cur = _carController.value.clamp(0.0, 1.0);
    final remaining = (1.0 - cur).clamp(0.0, 1.0);

    // if already at or extremely close to the end, trigger finish immediately
    if (remaining <= 1e-3) {
      // ensure visual at end
      try { _carController.value = 1.0; } catch (_) {}
      // call finish handler on next microtask so UI settles
      Future.microtask(() => _onRaceFinished());
      return;
    }

    final baseDuration = _carController.duration ?? const Duration(seconds: 6);
    final ms = max(300, (baseDuration.inMilliseconds * remaining).round());
    final animDuration = Duration(milliseconds: ms);

    // animate the rest of the lap once, then run finish handler
    _carController
        .animateTo(1.0, duration: animDuration, curve: Curves.easeInOut)
        .then((_) {
      if (mounted) _onRaceFinished();
    }).catchError((err) {
      debugPrint('Car animation to finish failed: $err');
      if (mounted) _onRaceFinished();
    });
  }

  void _subscribePublicTracks() {
    // cancel existing first (safe)
    _unsubscribePublicTracks();

    for (int i = 0; i <= 4; i++) {
      final roomCode = 'TRACK_${i}';

      // players stream subscription
      try {
        _publicPlayersSubs[i] = _collab.playersStream(roomCode).listen(
          (players) {
            if (!mounted) return;

            // If the room has no players, clear running flag (room finished / cleaned up)
            if (players.isEmpty) {
              if (_publicRoomRunning[i] != false || _publicRoomHasWaiting[i] != false) {
                setState(() {
                  _publicRoomRunning[i] = false;
                  _publicRoomHasWaiting[i] = false;
                });
              }
              return;
            }

            // waiting means exactly one player AND the room is not currently running
            final bool waitingNow = (players.length == 1) && (_publicRoomRunning[i] == false);

            if (_publicRoomHasWaiting[i] != waitingNow) {
              setState(() {
                _publicRoomHasWaiting[i] = waitingNow;
              });
            }

            // if players >= 2 then the room is running (race started by someone) — but
            // prefer to rely on explicit start_race message; this is a safe fallback.
            if (players.length >= 2 && _publicRoomRunning[i] != true) {
              setState(() {
                _publicRoomRunning[i] = true;
                _publicRoomHasWaiting[i] = false;
              });
            }
          },
          onError: (err) {
            debugPrint('Error in public playersStream($roomCode): $err');
            if (mounted && _publicRoomHasWaiting[i] != false) {
              setState(() => _publicRoomHasWaiting[i] = false);
            }
          },
          cancelOnError: false,
        );
      } catch (e) {
        debugPrint('Failed to subscribe to playersStream for $roomCode: $e');
        if (mounted && _publicRoomHasWaiting[i] != false) {
          setState(() => _publicRoomHasWaiting[i] = false);
        }
      }

      // messages stream subscription (listen for start_race / end_race)
      try {
        _publicMessagesSubs[i] = _collab.messagesStream(roomCode).listen(
          (messages) {
            if (!mounted) return;
            for (final msg in messages) {
              final t = msg.payload['type'];
              if (t == 'start_race') {
                // mark running; clear waiting badge
                if (_publicRoomRunning[i] != true || _publicRoomHasWaiting[i] != false) {
                  setState(() {
                    _publicRoomRunning[i] = true;
                    _publicRoomHasWaiting[i] = false;
                  });
                }
              } else if (t == 'end_race') {
                // backend explicitly ended race — clear running flag; playersStream will update waiting
                if (_publicRoomRunning[i] != false) {
                  setState(() {
                    _publicRoomRunning[i] = false;
                  });
                }
              }
            }
          },
          onError: (err) {
            debugPrint('Error in public messagesStream($roomCode): $err');
            // don't change running flag on message errors
          },
          cancelOnError: false,
        );
      } catch (e) {
        debugPrint('Failed to subscribe to messagesStream for $roomCode: $e');
      }
    }
  }

  /// Fetch the profile username from SharedPreferences (tries several common keys).
  /// Returns an empty string if not found or if value equals the default placeholder.
  Future<String> _fetchProfileUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // try several plausible keys used across the app
      final candidates = <String?>[
        prefs.getString('username'),
        prefs.getString('displayName'),
        prefs.getString('profile_username'),
        prefs.getString('profile_displayName'),
        prefs.getString('name'),
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final v = c.trim();
        if (v.isEmpty) continue;
        // don't treat the placeholder as a real name (case-insensitive)
        if (v.toLowerCase() == 'unamed_carenthusiast') continue;
        return v;
      }
    } catch (e) {
      debugPrint('Failed to read profile username: $e');
    }
    return '';
  }

  void _unsubscribePublicTracks() {
    for (final sub in _publicPlayersSubs.values) {
      try { sub.cancel(); } catch (_) {}
    }
    _publicPlayersSubs.clear();

    for (final sub in _publicMessagesSubs.values) {
      try { sub.cancel(); } catch (_) {}
    }
    _publicMessagesSubs.clear();
  }

  // --- Car data used by the questions (same CSV used in home_page.dart) ---
  List<Map<String, String>> carData = [];

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

  Future<bool> _showQuestionWidget(Widget content) async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _QuestionPage(
          content: content,
          onLeave: () async {
            // Called when user chooses Leave from the question AppBar.
            try { _carController.stop(); } catch (_) {}

            // best-effort notify server and remove presence/score when leaving from the question.
            await _leaveCurrentRoom();

            // Only attempt ad if there was race activity
            final bool hadProgress = _raceStarted || _quizCurrentPos > 0 || _quizScore > 0;
            if (hadProgress) {
              try {
                await _maybeShowRaceInterstitial();
              } catch (e) {
                debugPrint('Race interstitial on leave (question) failed: $e');
              }
            }

            if (!mounted) return;
            setState(() {
              _raceAborted = true;
              _inPublicRaceView = false;
              _activeTrackIndex = null;
              _raceStarted = false;
              _quizSelectedIndices = [];
              _quizCurrentPos = 0;
              _quizScore = 0;
              _currentDistance = 0.0;
              _pathPoints = [];
              _cumLengths = [];
              _totalPathLength = 0.0;
              _waitingForNextQuestion = false;
              _roomCreatorId = null;
            });
          },
        ),
      ),
    );
    return res == true;
  }

  // Given a player's score, return their distance along the track
  double _distanceForPlayer(PlayerInfo player) {
    if (_quizSelectedIndices.isEmpty || _stepDistance <= 0) return 0.0;
    final maxScore = _quizSelectedIndices.length;
    final progress = player.score / maxScore;
    return progress * _totalPathLength;
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

  // add to class fields
  final Map<int, double> _trackAspect = {}; // cache width/height ratio (width/height) per track

  Future<void> _ensureTrackAspect(int trackIdx) async {
    if (_trackAspect.containsKey(trackIdx)) return;
    try {
      final data = await rootBundle.load('assets/home/RaceTrack$trackIdx.png');
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      if (img.height > 0) {
        _trackAspect[trackIdx] = img.width / img.height;
      } else {
        _trackAspect[trackIdx] = 1.8; // fallback
      }
    } catch (e) {
      // fallback aspect ratio (tweak if you know exact ratio)
      _trackAspect[trackIdx] = 1.8;
      debugPrint('Failed to decode asset aspect for track $trackIdx: $e');
    }
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
      _currentDistance = 0.0;
      _waitingForNextQuestion = false;
    });

    // Give layout one frame so LayoutBuilder can call _preparePath and compute _totalPathLength.
    await Future.delayed(const Duration(milliseconds: 120));

    if (_totalPathLength <= _eps) {
      final W = MediaQuery.of(context).size.width;
      final H = max(100.0, MediaQuery.of(context).size.height - 120.0);
      await _preparePath(W, H, _safeIndex(_activeTrackIndex));
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

  Future<void> _joinPrivateGame(int index, String displayName, String roomCode, {bool isCreator = false}) async {
    // Mark UI state (local)
    setState(() {
      _activeTrackIndex = index;
      _inPublicRaceView = true;
      _raceStarted = false;
      _quizSelectedIndices = [];
      _quizCurrentPos = 0;
      _quizScore = 0;
      _currentDistance = 0.0;
      _pathPoints = [];
      _cumLengths = [];
      _totalPathLength = 0.0;
      _raceAborted = false;
    });
    _carController.stop();
    _carController.reset();
    _currentRoomCode = roomCode;
    try {
      // Create/join room (createRoom calls joinRoom internally)
      await _collab.createRoom(roomCode, displayName: displayName);
      if (isCreator) {
        _roomCreatorId = _collab.localPlayerId; // Only set if creating the room
      }
      // Initial presence touch
      unawaited(_collab.touchPresence(roomCode));
      // Clean up stale players when joining
      await _collab.cleanupStalePlayers(roomCode, ttl: const Duration(seconds: 15));
      // Subscribe to players list
      _playersSub?.cancel();
      _playersSub = _collab.playersStream(roomCode).listen((players) async {
        if (!mounted) return;
        // Merge incoming players with existing ones to preserve score/errors
        setState(() {
          _playersInRoom = players.map((newPlayer) {
            final existingPlayer = _playersInRoom.firstWhere(
              (p) => p.id == newPlayer.id,
              orElse: () => newPlayer,
            );
            return PlayerInfo(
              id: newPlayer.id,
              displayName: newPlayer.displayName,
              lastSeen: newPlayer.lastSeen,
              score: existingPlayer.score,
              errors: existingPlayer.errors,
            );
          }).toList();
        });

        // Auto-start if 2+ players and not already started
        if (!_raceStarted && players.length >= 2) {
          debugPrint('Starting race with ${players.length} players!');
          await _startQuizRace();
        }
      });

      // Listen for score/error updates + start_race + end_race
      _messagesSub = _collab.messagesStream(_currentRoomCode!).listen(
        (messages) {
          for (final msg in messages) {
            final type = msg.payload['type'];
            if (type == 'score_update') {
              setState(() {
                _playersInRoom = _playersInRoom.map((p) {
                  if (p.id == msg.payload['playerId']) {
                    return PlayerInfo(
                      id: p.id,
                      displayName: p.displayName,
                      lastSeen: p.lastSeen,
                      score: msg.payload['score'],
                      errors: p.errors,
                    );
                  }
                  return p;
                }).toList();
              });
            } else if (type == 'error_update') {
              setState(() {
                _playersInRoom = _playersInRoom.map((p) {
                  if (p.id == msg.payload['playerId']) {
                    return PlayerInfo(
                      id: p.id,
                      displayName: p.displayName,
                      lastSeen: p.lastSeen,
                      score: p.score,
                      errors: msg.payload['errors'],
                    );
                  }
                  return p;
                }).toList();
              });
            } else if (type == 'start_race') {
              // Start the race for all players when the message is received
              if (!_raceStarted) {
                debugPrint('Received start_race message, starting race!');
                _startQuizRace();
              }
            } else if (type == 'end_race') {
              // If we're not showing the race UI, ignore stale end_race messages.
              if (!_inPublicRaceView) {
                debugPrint('Received end_race but not in public race view — ignoring.');
                continue;
              }

              // Extract payload copy
              Map<String, dynamic> payload;
              try {
                payload = Map<String, dynamic>.from(msg.payload);
              } catch (e) {
                debugPrint('Invalid end_race payload format: $e');
                continue;
              }

              // Inspect winner info
              final winnerIdRaw = payload['winnerId'];
              final winnerNameRaw = payload['winnerName'];
              final bool payloadHasWinner = (winnerIdRaw != null && winnerIdRaw.toString().isNotEmpty) ||
                                            (winnerNameRaw != null && winnerNameRaw.toString().isNotEmpty);

              // total slots expected for this race and local completion status
              final totalSlots = _quizSelectedIndices.length;
              final bool localCompleted = (totalSlots > 0) && (_quizScore >= totalSlots);

              if (!_raceStarted && _quizSelectedIndices.isEmpty) {
                // We haven't started a local race and have no quiz slots selected yet.
                // An `end_race` received here is likely the tail of a previous race
                // (sent before we joined) — ignore it unconditionally to avoid
                // showing stale results to a player joining a public room.
                debugPrint('Received end_race before local race start — ignoring.');
                continue;
              }

              // If the server named the local player as winner but the local player hasn't completed the required
              // number of correct answers, ignore it (we only show "you won" when local actually finished).
              if (payloadHasWinner && (winnerIdRaw == _collab.localPlayerId || winnerNameRaw == _nameController.text.trim()) && !localCompleted) {
                debugPrint('Ignoring end_race: server named local as winner but local not finished (score=$_quizScore / required=$totalSlots).');
                continue;
              }

              // Prevent re-entry / duplicate handling
              if (_handlingEndRace || _raceEndedByServer) {
                debugPrint('Received end_race but already handling or marked ended — ignoring.');
                continue;
              }

              try {
                final payloadCopy = Map<String, dynamic>.from(msg.payload);
                // fire-and-forget the handler (it contains guards).
                _handleServerEndRace(payloadCopy);
              } catch (e) {
                debugPrint('Error handling server end_race: $e');
              }
            }
          }
        },
        onError: (err) {
          debugPrint('Error in messagesStream(${_currentRoomCode ?? "unknown"}): $err');
        },
        cancelOnError: false,
      );

      // Periodic presence update
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (_currentRoomCode != null) {
          _collab.touchPresence(_currentRoomCode!);
        }
      });
    } catch (e) {
      debugPrint('Failed to join/create room $roomCode: $e');
      // Tidy up and give feedback
      _playersSub?.cancel();
      _presenceTimer?.cancel();
      _playersInRoom = [];
      _currentRoomCode = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to join private room: $e')),
        );
      }
    }
  }

  Future<void> _showPrivateJoinDialog(int index, String title) async {
    // Try to use profile username if available, otherwise fall back to random Player###.
    final profileName = await _fetchProfileUsername();
    if (profileName.isNotEmpty) {
      _nameController.text = profileName;
    } else {
      _nameController.text = 'Player${Random().nextInt(900) + 100}';
    }

    final questionsPerTrack = {0: 5, 1: 9, 2: 12, 3: 16, 4: 20};
    final qCount = questionsPerTrack[_safeIndex(index)] ?? 12;
    showDialog(
      context: context,
      builder: (context) {
        final roomCodeController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "You're about to enter a private multiplayer game.\n\n"
                      "You will need to answer $qCount questions correctly to complete the lap.\n\n"
                      "Choose your player name:",
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Create Room Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () async {
                        final carModels = carData.map((car) => car['model']!).toList()..shuffle();
                        String roomCode = carModels.isNotEmpty ? carModels.first : 'room${Random().nextInt(900) + 100}';
                        roomCode = roomCode.split(' ').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                        Navigator.of(context).pop();
                        final playerName = _nameController.text.trim().isEmpty
                            ? 'Player${Random().nextInt(900) + 100}'
                            : _nameController.text.trim();
                        debugPrint('Creating/joining private room: $roomCode as $playerName');
                        FocusScope.of(context).unfocus();
                        _joinPrivateGame(index, playerName, roomCode, isCreator: true);
                      },
                      child: const Text('Create Room'),
                    ),
                    const SizedBox(height: 8),
                    // Join Room Section
                    TextField(
                      controller: roomCodeController,
                      decoration: InputDecoration(
                        hintText: 'Enter room code',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    final roomCode = roomCodeController.text.trim();
                    if (roomCode.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a room code.')),
                      );
                      return;
                    }
                    debugPrint('Joining private room: $roomCode as $playerName');
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                    _joinPrivateGame(index, playerName, roomCode, isCreator: false);
                  },
                  child: const Text('Join Room'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- replace the entire _askNextQuestion() with this function ---
  Future<void> _askNextQuestion() async {
    if (!mounted) return;

    // quick guard: don't re-enter
    if (_isAskingQuestion) {
      debugPrint('_askNextQuestion: re-entry avoided');
      return;
    }
    _isAskingQuestion = true;

    try {
      // stop immediately if user aborted or left view
      if (_raceAborted || !_inPublicRaceView) return;

      // Hide waiting UI while we prepare the question
      if (_waitingForNextQuestion) {
        setState(() => _waitingForNextQuestion = false);
      }

      final totalSlots = _quizSelectedIndices.length;

      // If we've already completed all required correct answers -> finish race
      if (_quizCurrentPos >= totalSlots) {
        if (mounted) setState(() {}); // ensure UI consistent
        _startCar();
        return;
      }

      // Safety re-check
      if (_raceAborted || !_inPublicRaceView) return;

      final qIndex = _quizSelectedIndices[_quizCurrentPos];

      final handler = handlerByIndex[qIndex];
      if (handler == null) {
        // No handler for this question type: skip this slot (treat as auto-skip).
        debugPrint('No handler for question index $qIndex — skipping this slot');
        // advance the slot (this behaves like a filled slot so player moves forward)
        _quizCurrentPos++;
        // If finishing after skipping, start car
        if (_quizCurrentPos >= totalSlots) {
          if (mounted) setState(() {});
          _startCar();
          return;
        }
        // show waiting UI so user can proceed
        if (mounted) setState(() => _waitingForNextQuestion = true);
        return;
      }

      // Ask the question (this pushes the question page and waits for pop).
      bool correct = false;
      try {
        correct = await handler(
          _quizCurrentPos + 1,
          currentScore: _quizScore,
          totalQuestions: totalSlots,
        );
      } catch (e, st) {
        // Protect against handler crashes (e.g., unexpected nulls or asset issues).
        debugPrint('Question handler for index $qIndex threw: $e\n$st');
        // Treat as incorrect and allow user to continue rather than crashing the whole page.
        correct = false;
      }

      // Stop if user left during question
      if (_raceAborted || !_inPublicRaceView) return;
      if (!mounted) return;

      final localPlayerId = _collab.localPlayerId;

      if (correct) {
        // Correct -> increment score and advance the slot and move car
        _quizScore++;

        // Notify server of new score (best-effort)
        if (_currentRoomCode != null) {
          try {
            await _collab.sendMessage(_currentRoomCode!, {
              'type': 'score_update',
              'playerId': localPlayerId,
              'score': _quizScore,
            });
          } catch (e) {
            debugPrint('Failed to send score_update: $e');
          }
        }

        // Advance the slot only when correct
        _quizCurrentPos++;

        // Move car visually one step
        if (_raceAborted || !_inPublicRaceView) return;
        try {
          // Ensure stepDistance is valid; if not, attempt a safe recompute.
          if (_stepDistance <= 0 || _totalPathLength <= _eps) {
            final W = MediaQuery.of(context).size.width;
            final H = max(100.0, MediaQuery.of(context).size.height - 120.0);
            await _preparePath(W, H, _safeIndex(_activeTrackIndex));
            _stepDistance = (_totalPathLength > 0 ? _totalPathLength / totalSlots : 0.0);
          }
          await _advanceByStep();
        } catch (e, st) {
          debugPrint('Error advancing car for track ${_safeIndex(_activeTrackIndex)} after question $qIndex: $e\n$st');
          // Fall back: ensure we don't deadlock the quiz; mark waiting so user can continue.
          if (mounted) setState(() => _waitingForNextQuestion = true);
        }

        // If we've now completed all slots (i.e. got required number of correct answers), finish
        if (_quizCurrentPos >= totalSlots) {
          if (mounted) setState(() {});
          _startCar();
          return;
        }

        // Otherwise show waiting badge and let user press Next to continue
        if (mounted) setState(() => _waitingForNextQuestion = true);
      } else {
        // Incorrect -> increment error count on server, do NOT advance the slot or move the car
        if (_currentRoomCode != null) {
          // best-effort compute current errors and increment
          final currentErrors = _playersInRoom
              .firstWhere((p) => p.id == localPlayerId, orElse: () => PlayerInfo(id: '', displayName: '', lastSeen: DateTime.now(), score: 0, errors: 0))
              .errors;
          try {
            await _collab.sendMessage(_currentRoomCode!, {
              'type': 'error_update',
              'playerId': localPlayerId,
              'errors': currentErrors + 1,
            });
          } catch (e) {
            debugPrint('Failed to send error_update: $e');
          }
        }

        // Do NOT change _quizCurrentPos or _quizScore. Let the user try again (or get a new question for same slot).
        if (mounted) setState(() => _waitingForNextQuestion = true);
      }
    } finally {
      _isAskingQuestion = false;
    }
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

  Future<void> _maybeShowRaceInterstitial() async {
    try {
      await AdService.instance.incrementRaceAndMaybeShow();
    } catch (e, st) {
      debugPrint('AdService.incrementRaceAndMaybeShow failed: $e\n$st');
    }
  }


  @override
  void initState() {
    super.initState();
    _carController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _loadRaceInterstitialCounter();
    _tracksNorm = {
      0: _monzaNorm,
      1: _monacoNorm,
      2: _suzukaNorm,
      3: _spaNorm,
      4: _silverstoneNorm,
    };

    // load CSV now for quiz questions (non-blocking)
    _loadCarData();

    // Subscribe to public track presence streams so the track buttons update live.
    // We always subscribe so the UI reflects other players even if the user hasn't joined.
    _subscribePublicTracks();
  }

  @override
  void dispose() {
    // Leave room (fire-and-forget)
    try { _leaveCurrentRoom(); } catch (_) {}
    _carController.dispose();
    _nameController.dispose();
    try { _playersSub?.cancel(); } catch (_) {}
    try { _messagesSub?.cancel(); } catch (_) {}
    _presenceTimer?.cancel();

    // cancel public track subscriptions (players + messages)
    _unsubscribePublicTracks();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ===== Top block (buttons only) that slides as one piece =====
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _inPublicRaceView
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildModeButton("Public Room", true),
                              _buildModeButton("Private Room", false),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(thickness: 0.5),
                        ],
                      ),
                    ),
            ),
          ),

          // ===== Content zone (tracks grid + coming-soon promo OR race view) =====
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _inPublicRaceView
                  ? _buildRaceView()
                  // when NOT in race view, we show the tracks grid AND the promo below it
                  : _buildTracksWithPromo(isPrivate: !isPublicMode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTracksWithPromo({required bool isPrivate}) {
    return _buildTracksGrid(isPrivate: isPrivate);
  }

  Widget _buildComingSoonPromo() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isPublicMode
          ? Column(
              key: const ValueKey('leaderboard_promo_in_grid'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LEADERBOARD — COMING SOON',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'A space to see top players and your rank — stay tuned!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 250,
                  child: Image.asset(
                    'assets/home/leaderboard_coming_soon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            )
          : Column(
              key: const ValueKey('clubs_promo_in_grid'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CLUBS — COMING SOON',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create car-lover clubs and compete with other clubs — coming soon!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 250,
                  child: Image.asset(
                    'assets/home/clubs_coming_soon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModeButton(String label, bool public) {
    final selected = isPublicMode == public;

    return GestureDetector(
      onTap: () {
        // toggle mode and manage subscriptions
        setState(() => isPublicMode = public);
        if (public) {
          _subscribePublicTracks();
        } else {
          _unsubscribePublicTracks();
        }
      },
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

  Widget _buildPlayerStatLine({required PlayerInfo player, required bool isLocal}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isLocal ? Colors.blue : Colors.green,
            child: Text(
              player.displayName.isNotEmpty ? player.displayName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              player.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              Icon(Icons.star, size: 14, color: Colors.amber[400]),
              const SizedBox(width: 4),
              Text('${player.score} pts', style: TextStyle(fontSize: 12, color: Colors.grey[200])),
              const SizedBox(width: 8),
              Icon(Icons.error, size: 14, color: Colors.red[400]),
              const SizedBox(width: 4),
              Text('${player.errors} err', style: TextStyle(fontSize: 12, color: Colors.grey[200])),
            ],
          ),
        ],
      ),
    );
  }

  // Remplace la fonction _buildTracksGrid par ceci :
  Widget _buildTracksGrid({required bool isPrivate}) {
    final titles = ['Monza', 'Monaco', 'Suzuka', 'Spa', 'Silverstone', 'Random'];

    // On utilise CustomScrollView + SliverGrid pour que la grille soit scrollable
    // et qu'on puisse ajouter ensuite un SliverToBoxAdapter pour le promo.
    return CustomScrollView(
      key: ValueKey(isPrivate ? 'privateTracks' : 'publicTracks'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildTrackButton(i, titles[i], isPrivate: isPrivate),
              childCount: titles.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
          ),
        ),

        // Promo "Coming soon" placé **après** la grille — il défile avec la grille.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: _buildComingSoonPromo(),
          ),
        ),

        // petit espace en bas
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // Return a roomCode (string) that currently has exactly one waiting player and is NOT running.
  // Returns null otherwise.
  Future<String?> _findRoomWithWaitingPlayers(int index) async {
    if (index < 0 || index > 4) return null;
    final waiting = _publicRoomHasWaiting[index] == true;
    final running = _publicRoomRunning[index] == true;
    if (waiting && !running) {
      return 'TRACK_${index}';
    }
    return null;
  }

  Future<void> _showPublicJoinDialog(int index, String title, {String? roomCodeOverride}) async {
    // Try to use profile username if available, otherwise fallback to random Player###.
    final profileName = await _fetchProfileUsername();
    if (profileName.isNotEmpty) {
      _nameController.text = profileName;
    } else {
      _nameController.text = 'Player${Random().nextInt(900) + 100}';
    }

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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final playerName = _nameController.text.trim().isEmpty
                    ? 'Player${Random().nextInt(900) + 100}'
                    : _nameController.text.trim();
                debugPrint('Joining as: $playerName (roomOverride=$roomCodeOverride)');
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (!mounted) return;
                  _joinPublicGame(index, playerName, roomCodeOverride: roomCodeOverride);
                });
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrackButton(int index, String title, {required bool isPrivate}) {
    return GestureDetector(
      onTap: () async {
        if (index == 5) {
          // Random button logic: pick a random track (0..4)
          final randomIndex = Random().nextInt(5);
          final baseTitles = ['Monza', 'Monaco', 'Suzuka', 'Spa', 'Silverstone'];
          final randomTitle = baseTitles[randomIndex];

          if (isPrivate) {
            debugPrint('Private random track tapped: $randomIndex');
            _showPrivateJoinDialog(randomIndex, randomTitle);
          } else {
            // PUBLIC: try to join an existing waiting room; if none, create new room when joining.
            // However, if the user is already playing in a room whose code starts with TRACK_{randomIndex},
            // force creation of a new room instead of joining the active game.
            String? roomToJoin = await _findRoomWithWaitingPlayers(randomIndex);
            if (_currentRoomCode != null && _currentRoomCode!.startsWith('TRACK_${randomIndex}')) {
              // Prevent joining the same running room — create a new room instead
              roomToJoin = null;
            }
            _showPublicJoinDialog(randomIndex, randomTitle, roomCodeOverride: roomToJoin);
          }
        } else {
          if (isPrivate) {
            _showPrivateJoinDialog(index, title);
          } else {
            // PUBLIC: attempt to join existing waiting room for this track,
            // but if the user is already playing on this track (currentRoomCode startsWith TRACK_index),
            // force them to create a fresh waiting room instead.
            String? roomToJoin = await _findRoomWithWaitingPlayers(index);
            if (_currentRoomCode != null && _currentRoomCode!.startsWith('TRACK_${index}')) {
              roomToJoin = null;
            }
            _showPublicJoinDialog(index, title, roomCodeOverride: roomToJoin);
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: index == 5 ? const Color(0xFF3D0000) : null,
            image: index != 5
                ? DecorationImage(
                    image: AssetImage('assets/home/RaceTrack$index.png'),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: Stack(
            children: [
              if (index != 5)
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

              // presence dot (public-only and not Random)
              if (!isPrivate && index != 5)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: (_publicRoomHasWaiting[index] == true) ? 'Player waiting' : 'Empty',
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: (_publicRoomHasWaiting[index] == true) ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70, width: 1.5),
                        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26, offset: Offset(0,1))],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinPublicGame(int index, String displayName, {String? roomCodeOverride}) async {
    // Mark UI state (local)
    setState(() {
      _activeTrackIndex = index;
      _inPublicRaceView = true;
      _raceStarted = false;
      _quizSelectedIndices = [];
      _quizCurrentPos = 0;
      _quizScore = 0;
      _currentDistance = 0.0;
      _pathPoints = [];
      _cumLengths = [];
      _totalPathLength = 0.0;
      _raceAborted = false;
    });

    _carController.stop();
    _carController.reset();

    // Allow an override (used when joining an existing waiting room),
    // otherwise default to canonical per-track room
    final roomCode = roomCodeOverride ?? 'TRACK_${index}';
    _currentRoomCode = roomCode;

    try {
      // Create/join room (createRoom calls joinRoom internally)
      await _collab.createRoom(roomCode, displayName: displayName);

      // Initial presence touch
      unawaited(_collab.touchPresence(roomCode));
      // Clean up stale players when joining
      await _collab.cleanupStalePlayers(roomCode, ttl: const Duration(seconds: 15));

      // Subscribe to players list
      _playersSub?.cancel();
      _playersSub = _collab.playersStream(roomCode).listen((players) {
        if (!mounted) return;
        // Merge incoming players with existing ones to preserve score/errors
        setState(() {
          _playersInRoom = players.map((newPlayer) {
            final existingPlayer = _playersInRoom.firstWhere(
              (p) => p.id == newPlayer.id,
              orElse: () => newPlayer,
            );
            return PlayerInfo(
              id: newPlayer.id,
              displayName: newPlayer.displayName,
              lastSeen: newPlayer.lastSeen,
              score: existingPlayer.score,
              errors: existingPlayer.errors,
            );
          }).toList();
        });

        // Auto-start if 2+ players and not already started
        if (!_raceStarted && players.length >= 2) {
          debugPrint('Starting race with ${players.length} players!');
          _startQuizRace();
        }
      });

      // Listen for score/error updates + start_race + end_race
      _messagesSub = _collab.messagesStream(_currentRoomCode!).listen(
        (messages) {
          for (final msg in messages) {
            final type = msg.payload['type'];
            if (type == 'score_update') {
              setState(() {
                _playersInRoom = _playersInRoom.map((p) {
                  if (p.id == msg.payload['playerId']) {
                    return PlayerInfo(
                      id: p.id,
                      displayName: p.displayName,
                      lastSeen: p.lastSeen,
                      score: msg.payload['score'],
                      errors: p.errors,
                    );
                  }
                  return p;
                }).toList();
              });
            } else if (type == 'error_update') {
              setState(() {
                _playersInRoom = _playersInRoom.map((p) {
                  if (p.id == msg.payload['playerId']) {
                    return PlayerInfo(
                      id: p.id,
                      displayName: p.displayName,
                      lastSeen: p.lastSeen,
                      score: p.score,
                      errors: msg.payload['errors'],
                    );
                  }
                  return p;
                }).toList();
              });
            } else if (type == 'start_race') {
              // Start the race for all players when the message is received
              if (!_raceStarted) {
                debugPrint('Received start_race message, starting race!');
                _startQuizRace();
              }
            } else if (type == 'end_race') {
              // If we're not showing the race UI, ignore stale end_race messages.
              if (!_inPublicRaceView) {
                debugPrint('Received end_race but not in public race view — ignoring.');
                continue;
              }

              // Extract payload copy
              Map<String, dynamic> payload;
              try {
                payload = Map<String, dynamic>.from(msg.payload);
              } catch (e) {
                debugPrint('Invalid end_race payload format: $e');
                continue;
              }

              // Inspect winner info
              final winnerIdRaw = payload['winnerId'];
              final winnerNameRaw = payload['winnerName'];
              final bool payloadHasWinner = (winnerIdRaw != null && winnerIdRaw.toString().isNotEmpty) ||
                                            (winnerNameRaw != null && winnerNameRaw.toString().isNotEmpty);

              // total slots expected for this race and local completion status
              final totalSlots = _quizSelectedIndices.length;
              final bool localCompleted = (totalSlots > 0) && (_quizScore >= totalSlots);

              if (!_raceStarted && _quizSelectedIndices.isEmpty) {
                // We haven't started a local race and have no quiz slots selected yet.
                // An `end_race` received here is likely the tail of a previous race
                // (sent before we joined) — ignore it unconditionally to avoid
                // showing stale results to a player joining a public room.
                debugPrint('Received end_race before local race start — ignoring.');
                continue;
              }

              // If the server named the local player as winner but the local player hasn't completed the required
              // number of correct answers, ignore it (we only show "you won" when local actually finished).
              if (payloadHasWinner && (winnerIdRaw == _collab.localPlayerId || winnerNameRaw == _nameController.text.trim()) && !localCompleted) {
                debugPrint('Ignoring end_race: server named local as winner but local not finished (score=$_quizScore / required=$totalSlots).');
                continue;
              }

              // Prevent re-entry / duplicate handling
              if (_handlingEndRace || _raceEndedByServer) {
                debugPrint('Received end_race but already handling or marked ended — ignoring.');
                continue;
              }

              try {
                final payloadCopy = Map<String, dynamic>.from(msg.payload);
                // fire-and-forget the handler (it contains guards).
                _handleServerEndRace(payloadCopy);
              } catch (e) {
                debugPrint('Error handling server end_race: $e');
              }
            }
          }
        },
        onError: (err) {
          debugPrint('Error in messagesStream(${_currentRoomCode ?? "unknown"}): $err');
        },
        cancelOnError: false,
      );

      // Periodic presence update
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (_currentRoomCode != null) {
          _collab.touchPresence(_currentRoomCode!);
        }
      });
    } catch (e) {
      debugPrint('Failed to join/create room $roomCode: $e');
      _playersSub?.cancel();
      _presenceTimer?.cancel();
      _playersInRoom = [];
      _currentRoomCode = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to join multiplayer room: $e')),
        );
      }
    }
  }

  Future<void> _leaveCurrentRoom() async {
    final room = _currentRoomCode;
    // stop presence updates first
    _presenceTimer?.cancel();
    _presenceTimer = null;

    try {
      if (room != null) {
        // try to reset our score/errors on the room so when we come back there's no leftover value
        try {
          final localId = _collab.localPlayerId;
          // best-effort: send score update = 0 and errors = 0
          await _collab.sendMessage(room, {
            'type': 'score_update',
            'playerId': localId,
            'score': 0,
          });
          await _collab.sendMessage(room, {
            'type': 'error_update',
            'playerId': localId,
            'errors': 0,
          });
        } catch (e) {
          debugPrint('Failed to reset local score on server for $room: $e');
          // continue to leave even if reset failed
        }

        try {
          await _collab.leaveRoom(room);
        } catch (e) {
          debugPrint('Error calling leaveRoom($room): $e');
        }
      }
    } catch (_) {
      // swallow any error to avoid crashing on leave
    }

    // cancel any subscriptions related to being in a room
    try { await _playersSub?.cancel(); } catch (_) {}
    _playersSub = null;
    try { await _messagesSub?.cancel(); } catch (_) {}
    _messagesSub = null;

    // finally clear local UI state
    if (mounted) {
      setState(() {
        _playersInRoom = [];
        _currentRoomCode = null;
        _raceStarted = false;
        _quizSelectedIndices = [];
        _quizCurrentPos = 0;
        _quizScore = 0;
        _currentDistance = 0.0;
        _pathPoints = [];
        _cumLengths = [];
        _totalPathLength = 0.0;
        _waitingForNextQuestion = false;
        _roomCreatorId = null;
      });
    }
  }

  // helper to clamp index safely
  int _safeIndex(int? val) {
    final v = val ?? 0;
    if (v < 0) return 0;
    if (v > 4) return 4;
    return v;
  }

  Future<void> _preparePath(double W, double H, int trackIdx) async {
    // ensure we know the image aspect
    await _ensureTrackAspect(trackIdx);
    final aspect = _trackAspect[trackIdx] ?? 1.8; // width / height

    // For BoxFit.fitWidth + Alignment.topCenter the image will be scaled to fit the width (W)
    // renderedImageHeight = W / aspect
    final renderedImageHeight = W / aspect;

    // choose normalized list by track index
    final List<List<double>> norm = _tracksNorm[trackIdx] ?? _monzaNorm;

    // convert to pixel positions relative to the **rendered image box**.
    // We align the image at the top (topOffset = 0). If you prefer centered, compute topOffset.
    final double topOffset = 0.0;

    _pathPoints = norm
        .map((p) => Offset(p[0] * W, topOffset + p[1] * renderedImageHeight))
        .toList();

    // ensure path has at least 2 points
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

    if (_totalPathLength <= _eps) _totalPathLength = 1.0;

    // adjust animation duration so car speed roughly similar across sizes
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
  Widget _buildRaceView() {
    final idx = _safeIndex(_activeTrackIndex);
    return Column(
      key: ValueKey('publicRaceView_$idx'),
      children: [
        // Use Stack so we can overlay the room code
        Expanded(
          child: Stack(
            children: [
              // Full-width track image
              Positioned.fill(
                child: Image.asset(
                  'assets/home/RaceTrack$idx.png',
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final W = constraints.maxWidth;
                    final H = constraints.maxHeight;
                    final idx = _safeIndex(_activeTrackIndex);
                    if (_pathPoints.isEmpty) {
                      // schedule async preparation once — this will call setState when done
                      Future.microtask(() async {
                        await _preparePath(W, H, idx);
                        if (mounted) setState(() {});
                      });
                    }
                    return AnimatedBuilder(
                      animation: _carController,
                      builder: (context, child) {
                        final children = <Widget>[];
                        // Add local player's car
                        if (_raceStarted) {
                          final distance = _carController.value * _totalPathLength;
                          final pa = _posAngleAtDistance(distance);
                          final pos = pa['pos'];
                          final angle = pa['angle'];
                          final left = pos.dx.clamp(0.0, W - 36);
                          final top = pos.dy.clamp(0.0, H - 24);
                          children.add(
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
                          );
                        }
                        // Add other players' cars
                        for (final player in _playersInRoom) {
                          if (player.id == _collab.localPlayerId) continue; // Skip local player
                          final distance = _distanceForPlayer(player);
                          final pa = _posAngleAtDistance(distance);
                          final pos = pa['pos'];
                          final angle = pa['angle'];
                          final left = pos.dx.clamp(0.0, W - 36);
                          final top = pos.dy.clamp(0.0, H - 24);
                          children.add(
                            Positioned(
                              left: left,
                              top: top,
                              child: Transform.rotate(
                                angle: angle,
                                child: SizedBox(
                                  width: 36,
                                  height: 24,
                                  child: Image.asset('assets/home/car_opponent.png', fit: BoxFit.contain),
                                ),
                              ),
                            ),
                          );
                        }
                        return Stack(children: children);
                      },
                    );
                  },
                ),
              ),
              if (!_raceStarted && _playersInRoom.isNotEmpty && _roomCreatorId == _collab.localPlayerId)
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () async {
                        debugPrint('Room creator started the race!');
                        try {
                          await _collab.sendMessage(_currentRoomCode!, {
                            'type': 'start_race',
                          });
                        } catch (e) {
                          debugPrint('Failed to send start_race: $e');
                        }
                        await _startQuizRace();
                      },
                      child: const Text(
                        'Start Race',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              // Top-left small "Leave" button
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
                      onPressed: () async {
                        // stop animation and leave the room first
                        _carController.stop();
                        await _leaveCurrentRoom();

                        // Only attempt to show ad if there was race activity (started or progress)
                        final bool hadProgress = _raceStarted || _quizCurrentPos > 0 || _quizScore > 0;
                        if (hadProgress) {
                          try {
                            await _maybeShowRaceInterstitial();
                          } catch (e) {
                            debugPrint('Race interstitial on leave failed: $e');
                          }
                        }

                        if (!mounted) return;
                        setState(() {
                          _inPublicRaceView = false;
                          _activeTrackIndex = null;
                          _raceStarted = false;
                          _quizSelectedIndices = [];
                          _quizCurrentPos = 0;
                          _quizScore = 0;
                          _currentDistance = 0.0;
                          _waitingForNextQuestion = false;
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
              // Waiting for players overlay
              if (!_raceStarted && _playersInRoom.length < 2)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Waiting for another player...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              if (_waitingForNextQuestion)
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(right: 8, top: 8),
                    child: SizedBox(
                      height: 36,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.black45,
                          minimumSize: const Size(120, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          setState(() {
                            _waitingForNextQuestion = false;
                          });
                          await _askNextQuestion();
                        },
                        child: const Text(
                          'Next Question',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
                // Room code overlay (only for private rooms)
                if (_currentRoomCode != null && !_raceStarted && !isPublicMode)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Room Code:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currentRoomCode!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Share this code with friends!',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        // Bottom reserved area for other players' stats
        Container(
          height: 120,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_playersInRoom.isNotEmpty)
                  _buildPlayerStatLine(
                    player: _playersInRoom.firstWhere(
                      (p) => p.displayName == _nameController.text.trim(),
                      orElse: () => PlayerInfo(id: '', displayName: 'You', lastSeen: DateTime.now(), score: _quizScore, errors: 0),
                    ),
                    isLocal: true,
                  ),
                const SizedBox(height: 8),
                if (_playersInRoom.length >= 2)
                  _buildPlayerStatLine(
                    player: _playersInRoom.firstWhere(
                      (p) => p.displayName != _nameController.text.trim(),
                      orElse: () => PlayerInfo(id: '', displayName: 'Opponent', lastSeen: DateTime.now(), score: 0, errors: 0),
                    ),
                    isLocal: false,
                  ),
                if (!_raceStarted && _playersInRoom.length >= 2)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _roomCreatorId == _collab.localPlayerId
                              ? 'Press "Start Race" to begin!'
                              : 'Waiting for the room creator to start the race...',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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