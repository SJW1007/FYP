import 'package:shared_preferences/shared_preferences.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailConfig {
  static const String smtpServer = 'smtp.gmail.com';
  static const int smtpPort = 587; // or 465 for SSL
  static const String adminEmail = 'seejiawei39@gmail.com';

  // Use a proper key name for storing the password
  static const String _passwordKey = 'admin_email_password';

  // Method to get SMTP server configuration with SSL handling
  static SmtpServer getSmtpServer(String password) {
    return SmtpServer(
      smtpServer,
      port: smtpPort,
      username: adminEmail,
      password: password,
      ssl: false, // Use STARTTLS instead of SSL for port 587
      allowInsecure: true,
      ignoreBadCertificate: true,
    );
  }

  // Alternative SSL configuration for port 465
  static SmtpServer getSecureSmtpServer(String password) {
    return SmtpServer(
      smtpServer,
      port: 465,
      username: adminEmail,
      password: password,
      ssl: true, // Use SSL for port 465
      allowInsecure: true,
      ignoreBadCertificate: true,
    );
  }

  // Method to get the stored password with error handling
  static Future<String> get adminPassword async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_passwordKey) ?? '';
    } catch (e) {
      print('Error getting admin password: $e');
      return '';
    }
  }

  // Helper method to store the password
  static Future<void> setAdminPassword(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_passwordKey, password);
    } catch (e) {
      print('Error setting admin password: $e');
      throw Exception('Failed to store email password: $e');
    }
  }

  // Helper method to check if password is stored
  static Future<bool> hasStoredPassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final password = prefs.getString(_passwordKey);
      return password != null && password.isNotEmpty;
    } catch (e) {
      print('Error checking stored password: $e');
      return false;
    }
  }

  // Alternative method to get password with retry mechanism
  static Future<String> getAdminPasswordWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_passwordKey) ?? '';
      } catch (e) {
        print('Attempt ${i + 1} failed to get admin password: $e');
        if (i == maxRetries - 1) {
          // Last attempt failed, return empty string
          return '';
        }
        // Wait a bit before retrying
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
    return '';
  }
}