import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  // Get reference to Supabase client
  static SupabaseClient get client => Supabase.instance.client;
  
  // Initialize Supabase (must call dotenv.load() first!)
  static Future<void> initialize() async {
    // Load environment variables from .env file
    await dotenv.load(fileName: ".env");
    
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }
  
  static bool get isInitialized {
    try {
      // If throw exception => not initialized
      final _ = Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }
}