import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../models/sync_queue_model.dart';
import '../services/sqlite_service.dart';

class AuthRepository {
  final SqliteService _sqlite = SqliteService.instance;

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Strict online Supabase authentication with fallback to cached SQLite credentials when offline.
  Future<UserModel> signIn(String email, String password) async {
    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw 'Please enter both email and password.';
    }

    bool isOnlineAttempted = false;

    // 1. Attempt Cloud Supabase Authentication
    try {
      final client = _supabase;
      if (client != null) {
        isOnlineAttempted = true;
        final response = await client.auth.signInWithPassword(
          email: cleanEmail,
          password: cleanPassword,
        );

        final user = response.user;
        if (user != null) {
          final profile = await _fetchOrCreateProfile(user.id, cleanEmail);
          // Cache user profile and hashed password locally for future offline logins
          await _sqlite.saveUser(profile, password: cleanPassword);
          return profile;
        }
      }
    } on AuthException catch (e) {
      // Supabase returned an explicit authentication error -> REJECT LOGIN IMMEDIATELY
      throw 'Authentication failed: ${e.message}';
    } on SocketException catch (_) {
      // Offline: Device has no internet connection
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

  /// Register a new user in Supabase Auth and Supabase database, caching into SQLite.
  Future<UserModel> register(
    String email,
    String password,
    String role,
    String branch,
  ) async {
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

    // 1. Attempt Cloud Supabase Auth User Creation
    try {
      final client = _supabase;
      if (client != null) {
        final response = await client.auth.signUp(
          email: cleanEmail,
          password: cleanPassword,
        );

        if (response.user != null) {
          uid = response.user!.id;
          registeredOnline = true;
        }
      }
    } on AuthException catch (e) {
      throw 'Registration failed: ${e.message}';
    } on SocketException catch (_) {
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

    // 2. Save profile in Supabase table if online
    if (registeredOnline) {
      try {
        final client = _supabase;
        if (client != null) {
          await client.from('users').upsert(userModel.toMap());
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

  Future<UserModel> _fetchOrCreateProfile(String uid, String email) async {
    try {
      final client = _supabase;
      if (client != null) {
        final data = await client
            .from('users')
            .select()
            .eq('uid', uid)
            .maybeSingle();
        if (data != null) {
          return UserModel.fromMap(data, uid);
        }
      }
    } catch (_) {}

    final isAdmin = email.toLowerCase().contains('admin');
    final isLipa =
        email.toLowerCase().contains('staff') ||
        email.toLowerCase().contains('lipa');
    final role = isAdmin ? 'admin' : 'staff';
    final branch = isLipa ? 'Lipa' : 'San Pablo';

    final user = UserModel(uid: uid, email: email, role: role, branch: branch);

    try {
      final client = _supabase;
      if (client != null) {
        await client.from('users').upsert(user.toMap());
      }
    } catch (_) {}

    return user;
  }

  Future<void> signOut() async {
    try {
      final client = _supabase;
      if (client != null) {
        await client.auth.signOut();
      }
    } catch (_) {}
  }
}
