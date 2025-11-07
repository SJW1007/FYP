import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/FcmService.dart';
import 'VerifyPassword.dart';
import 'Login.dart';
import '../user/ReportDetailsPage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? userRole;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            userRole = userDoc.data()?['role'] as String?;
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching user role: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _logout(BuildContext context) async {
    await FCMService().deleteToken();
    await FirebaseAuth.instance.signOut();
    // Use pushAndRemoveUntil to clear the entire navigation stack
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false, // This removes all previous routes
    );
  }

  String _getBackgroundImage() {
    if (userRole == 'makeup artist' || userRole == 'admin') {
      return 'assets/purple_background.png';
    }
    return 'assets/image_4.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Image.asset(
            _getBackgroundImage(),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      if(userRole!='admin')
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      const Text(
                        "Settings",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Show loading indicator while fetching user role
                  if (isLoading)
                    const CircularProgressIndicator()
                  else ...[
                    _buildButton(
                      icon: Icons.logout,
                      label: "Logout",
                      onPressed: () => _logout(context),
                    ),
                    const SizedBox(height: 20),

                      _buildButton(
                        icon: Icons.lock_reset,
                        label: "Update Password",
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => VerifyPasswordPage()),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (userRole == 'user')
                    _buildButton(
                      icon: Icons.report,
                      label: "Report Status",
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReportDetailsPage()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 55,
      decoration: BoxDecoration(
        color: const Color(0xFFF2D7F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextButton.icon(
        icon: Icon(icon, color: Colors.black),
        label: Text(label, style: const TextStyle(color: Colors.black, fontSize: 16)),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}