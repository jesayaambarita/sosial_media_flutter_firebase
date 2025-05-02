import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  static const String _loginKey = "isLoggedIn";
  static const String _keyUsername = 'username';
  static const String _favoriteKey = "isFavoriteIn";

  static Future<void> setLoginStatus(String username) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    await prefs.setBool(_loginKey, true);
  }

  // Cek apakah user sudah login
  static Future<bool> isLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loginKey) ?? false;
  }

  // Ambil username yang tersimpan
  static Future<String?> getUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  // Logout dan hapus semua data terkait login
  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginKey); // Hapus status login
    await prefs.remove(_keyUsername); // Hapus username
    await prefs.remove(_favoriteKey);
  }

  static Future<void> setFavoriteStatus(
      String productId, bool isFavorited) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('favorite_$productId', isFavorited);
  }

  static Future<bool> getFavoriteStatus(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('favorite_$productId') ??
        false; // Default false jika tidak ada
  }
}
