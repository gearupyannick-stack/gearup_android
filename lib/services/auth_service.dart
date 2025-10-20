// lib/services/auth_service.dart
// Singleton AuthService compatible avec différentes sous-versions de google_sign_in.
// Utilise 'dynamic' pour appeler certaines APIs de google_sign_in afin d'éviter
// erreurs d'analyse si la signature change légèrement entre versions.
//
// Usage:
//   await AuthService.instance.init();
//   final cred = await AuthService.instance.signInWithGoogle();
//   await AuthService.instance.signOut();
//   await AuthService.instance.disconnectGoogle();

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._private();
  static final AuthService instance = AuthService._private();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _initialized = false;
  Completer<void>? _initCompleter;

  /// Initialise GoogleSignIn (optionnel serverClientId pour certains flows).
  Future<void> init({String? serverClientId}) async {
    if (_initialized) return;
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      if (serverClientId != null) {
        // certaines versions acceptent serverClientId
        await (_googleSignIn as dynamic).initialize(serverClientId: serverClientId);
      } else {
        // call initialize; if not present, dynamic call peut lever, on ignore ensuite
        try {
          await (_googleSignIn as dynamic).initialize();
        } catch (_) {
          // Si la méthode initialize() n'existe pas dans la version installée, on l'ignore.
        }
      }

      // Attempt lightweight auth non-bloquant si disponible (v7+)
      try {
        final dyn = _googleSignIn as dynamic;
        if (dyn.attemptLightweightAuthentication != null) {
          // ignore: unawaited_futures
          dyn.attemptLightweightAuthentication().catchError((_) {});
        }
      } catch (_) {}

      _initialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  /// Retourne true si Firebase a un user connecté ou si google_sign_in signale connecté.
  Future<bool> isSignedIn() async {
    // FirebaseAuth est la source de vérité pour ton app — vérifie en priorité.
    try {
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) return true;
    } catch (_) {}

    // Fallback : interroger google_sign_in via dynamic (selon la version).
    try {
      final dyn = _googleSignIn as dynamic;
      // Certaines versions exposent isSignedIn() as Future<bool>
      if (dyn.isSignedIn != null) {
        final res = await dyn.isSignedIn();
        if (res is bool) return res;
      }
      // Autre fallback : currentUser property (peut ne pas exister selon version)
      try {
        final cur = dyn.currentUser;
        return cur != null;
      } catch (_) {}
    } catch (_) {}

    return false;
  }

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Tentative de connexion Google -> Firebase.
  /// Retourne UserCredential ou null si l'utilisateur annule.
  Future<UserCredential?> signInWithGoogle() async {
    if (!_initialized) {
      await init();
    }

    try {
      final dynGs = _googleSignIn as dynamic;

      // La méthode moderne est authenticate() sur v7+, sinon on essaye signIn().
      GoogleSignInAccount? googleAccount;
      try {
        if (dynGs.authenticate != null) {
          googleAccount = await dynGs.authenticate();
        } else {
          // fallback aux anciennes API
          googleAccount = await dynGs.signIn();
        }
      } catch (e) {
        // fallback: try signIn silently then signIn
        try {
          googleAccount = await dynGs.signInSilently();
        } catch (_) {
          try {
            googleAccount = await dynGs.signIn();
          } catch (_) {
            rethrow;
          }
        }
      }

      if (googleAccount == null) {
        // utilisateur a annulé
        return null;
      }

      // Obtenir le token/auth info — on utilise dynamic pour être tolerant aux variations
      dynamic googleAuth;
      try {
        googleAuth = await googleAccount.authentication;
      } catch (e) {
        // Si authentication() n'existe pas, on essaie serverAuthCode (moins idéal)
        try {
          googleAuth = (googleAccount as dynamic).serverAuthCode;
        } catch (_) {
          googleAuth = null;
        }
      }

      String? idToken;
      String? accessToken;

      try {
        // dynamic property access pour idToken/accessToken (selon la version)
        idToken = (googleAuth as dynamic)?.idToken as String?;
      } catch (_) {
        idToken = null;
      }
      try {
        accessToken = (googleAuth as dynamic)?.accessToken as String?;
      } catch (_) {
        accessToken = null;
      }

      // Si ni idToken ni accessToken dispo, essaye serverAuthCode (peu courant)
      if ((idToken == null || idToken.isEmpty) && (accessToken == null || accessToken.isEmpty)) {
        try {
          final serverCode = (googleAccount as dynamic).serverAuthCode as String?;
          if (serverCode != null && serverCode.isNotEmpty) {
            // serverCode n'est pas directement utilisable pour FirebaseCredential dans la plupart des cas,
            // mais on signale une erreur claire ici.
            throw FirebaseAuthException(
              code: 'NO_TOKEN',
              message:
                  'Aucun idToken/accessToken récupéré depuis GoogleSignIn; serverAuthCode disponible (serverCode), configure OAuth server-side si besoin.',
            );
          } else {
            throw FirebaseAuthException(
              code: 'NO_TOKEN',
              message: 'Impossible d\'obtenir idToken/accessToken depuis GoogleSignIn.',
            );
          }
        } catch (e) {
          rethrow;
        }
      }

      // Construire credential Firebase
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Déconnexion Firebase + GoogleSignIn (sécurisé)
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      final dyn = _googleSignIn as dynamic;
      if (dyn.signOut != null) {
        await dyn.signOut();
      }
    } catch (_) {}
  }

  /// Déconnecte (revoke) le compte Google puis déconnecte Firebase.
  Future<void> disconnectGoogle() async {
    try {
      final dyn = _googleSignIn as dynamic;
      if (dyn.disconnect != null) {
        await dyn.disconnect();
        // Some platform implementations may not expose disconnect, ignore if not present.
      } else if (dyn.signOut != null) {
        await dyn.signOut();
      }
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}