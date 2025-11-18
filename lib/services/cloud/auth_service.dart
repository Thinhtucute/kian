import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthService {
  static final SupabaseClient _client = SupabaseService.client;

  // Get current user
  static User? get currentUser => _client.auth.currentUser;

  // Check if user is logged in
  static bool get isLoggedIn => currentUser != null;

  // Get current user ID
  static String? get currentUserId => currentUser?.id;

  // Sign up with email and password
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
  }

  // Sign in with email and password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign out
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // Update password
  static Future<UserResponse> updatePassword(String newPassword) async {
    return await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // Listen to auth state changes
  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // Get user session
  static Session? get currentSession => _client.auth.currentSession;

  // Refresh session
  static Future<AuthResponse> refreshSession() async {
    return await _client.auth.refreshSession();
  }
}
