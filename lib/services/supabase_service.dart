import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  // Get reference to Supabase client
  static SupabaseClient get client => Supabase.instance.client;
  
  // Initialize Supabase
  static Future<void> initialize() async {
    await dotenv.load(fileName: ".env");
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }
  
  // Optional helper methods
  static bool get isInitialized => Supabase.instance.client != null;
}