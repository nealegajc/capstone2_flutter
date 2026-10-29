import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static String get url {
    final value =
        dotenv.env['SUPABASE_URL'] ??
        const String.fromEnvironment('SUPABASE_URL');
    if (value.isEmpty) {
      debugPrint(
        'WARNING: SUPABASE_URL is missing from environment configuration.',
      );
    }
    return value;
  }

  static String get anonKey {
    final value =
        dotenv.env['SUPABASE_ANON_KEY'] ??
        const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (value.isEmpty) {
      debugPrint(
        'WARNING: SUPABASE_ANON_KEY is missing from environment configuration.',
      );
    }
    return value;
  }
}
