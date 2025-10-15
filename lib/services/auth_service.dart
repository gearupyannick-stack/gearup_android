// lib/services/auth_service.dart
import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns a Firebase [User] if successful, or null if the user cancels.
  Future<User?> signInWithGoogle() async {
    if (!Platform.isAndroid) {
      throw 'Google Sign-In is only enabled on Android for now.';
    }

    // Trigger the Google Sign-In flow.
    final googleUser = await GoogleSignIn(
      scopes: <String>[
        'email',
      ],
    ).signIn();

    if (googleUser == null) {
      // User aborted
      return null;
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    return userCred.user;
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
}