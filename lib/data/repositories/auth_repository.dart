import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/sync_queue_model.dart';
import '../services/sqlite_service.dart';
import '../../firebase_options.dart';

class AuthRepository {
  final SqliteService _sqlite = SqliteService.instance;
  final String _apiKey = DefaultFirebaseOptions.linux.apiKey;

  FirebaseFirestore? _safeFirestore;
  FirebaseFirestore? get _firestore {
    try {
      return _safeFirestore ??= FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Strict online Firebase authentication with fallback to cached SQLite credentials when offline.
  Future<UserModel> signIn(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter both email and password.';
    }

    bool isOnlineAttempted = false;

    // 1. Attempt Cloud Firebase Authentication via Identity Toolkit REST
    try {
      final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': cleanPassword,
          'returnSecureToken': true,
        }),
      ).timeout(const Duration(seconds: 7));

      isOnlineAttempted = true;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        // Online login succeeded!
        final uid = data['localId'] as String? ?? '';
        final idToken = data['idToken'] as String? ?? '';

        final profile = await _fetchOrCreateProfile(uid, cleanEmail, idToken);
        // Cache user profile and hashed password locally for future offline logins
        await _sqlite.saveUser(profile, password: cleanPassword);
        return profile;
      } else {
        // Firebase returned an explicit error -> REJECT LOGIN IMMEDIATELY
        final error = data['error'];
        final message = (error is Map) ? error['message'] as String? : null;

        if (message == 'EMAIL_NOT_FOUND' || message == 'INVALID_PASSWORD' || message == 'INVALID_LOGIN_CREDENTIALS') {
          throw 'Invalid email or password.';
        } else if (message == 'USER_DISABLED') {
          throw 'This user account has been disabled.';
        } else if (message == 'TOO_MANY_ATTEMPTS_TRY_LATER') {
          throw 'Too many failed login attempts. Please try again later.';
        } else {
          throw 'Authentication failed: ${message ?? "Unknown error"}.';
        }
      }
    } on SocketException catch (_) {
      // Offline: Device has no internet connection
    } on http.ClientException catch (_) {
      // Offline: Network transport failure
    } on TimeoutException catch (_) {
      // Offline: Connection timed out
    } catch (e) {
      if (isOnlineAttempted || e is String) {
        rethrow;
      }
    }

    // 2. OFFLINE SCENARIO: Verify against cached local SQLite credentials
    final cached = await _sqlite.getUserWithCredentials(cleanEmail);

    if (cached == null) {
      throw 'Offline Mode: No cached account found for "$cleanEmail". Please connect to the internet to sign in.';
    }

    final expectedHash = cached['passwordHash'] as String? ?? '';
    final enteredHash = SqliteService.hashPassword(cleanPassword);

    if (expectedHash.isNotEmpty && expectedHash == enteredHash) {
      return cached['user'] as UserModel;
    } else {
      throw 'Offline Mode: Incorrect password for cached account.';
    }
  }

  /// Register a new user in Firebase Auth and Cloud Firestore, caching into SQLite.
  Future<UserModel> register(String email, String password, String role, String branch) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter email and password.';
    }
    if (cleanPassword.length < 6) {
      throw 'Password must be at least 6 characters long.';
    }

    String uid = 'user_${DateTime.now().millisecondsSinceEpoch}';
    bool registeredOnline = false;

    // 1. Attempt Cloud Firebase Auth User Creation
    try {
      final url = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': cleanEmail,
          'password': cleanPassword,
          'returnSecureToken': true,
        }),
      ).timeout(const Duration(seconds: 7));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        uid = data['localId'] as String? ?? uid;
        registeredOnline = true;
      } else {
        final error = data['error'];
        final message = (error is Map) ? error['message'] as String? : null;
        if (message == 'EMAIL_EXISTS') {
          throw 'This email address is already registered.';
        } else {
          throw 'Registration failed: ${message ?? "Unknown error"}.';
        }
      }
    } on SocketException catch (_) {
      // Offline registration
    } on http.ClientException catch (_) {
      // Offline registration
    } on TimeoutException catch (_) {
      // Offline registration
    } catch (e) {
      if (e is String) rethrow;
    }

    final userModel = UserModel(
      uid: uid,
      email: cleanEmail,
      role: role,
      branch: branch,
    );

    // 2. Save profile in Firestore if online
    if (registeredOnline) {
      try {
        final fs = _firestore;
        if (fs != null) {
          await fs.collection('users').doc(uid).set(userModel.toMap(), SetOptions(merge: true));
        }
      } catch (_) {}
    } else {
      // Enqueue sync task so cloud is updated when internet is restored
      final syncTask = SyncQueueModel(
        id: 'sync_user_${DateTime.now().millisecondsSinceEpoch}',
        pendingEventId: userModel.uid,
        targetCollection: 'users',
        branch: branch,
      );
      await _sqlite.enqueueSyncTask(syncTask);
    }

    // 3. Save to local SQLite cache with hashed password
    await _sqlite.saveUser(userModel, password: cleanPassword);
    return userModel;
  }

  Future<UserModel> _fetchOrCreateProfile(String uid, String email, String idToken) async {
    try {
      final fs = _firestore;
      if (fs != null) {
        final doc = await fs.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          return UserModel.fromFirestore(doc);
        }
      }
    } catch (_) {}

    final isAdmin = email.toLowerCase().contains('admin');
    final isLipa = email.toLowerCase().contains('staff') || email.toLowerCase().contains('lipa');
    final role = isAdmin ? 'admin' : 'staff';
    final branch = isLipa ? 'Lipa' : 'San Pablo';

    final user = UserModel(
      uid: uid,
      email: email,
      role: role,
      branch: branch,
    );

    try {
      final fs = _firestore;
      if (fs != null) {
        await fs.collection('users').doc(uid).set(user.toMap(), SetOptions(merge: true));
      }
    } catch (_) {}

    return user;
  }

  Future<void> signOut() async {}
}
