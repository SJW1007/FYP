import 'package:blush_up/service/OtpService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'Login.dart';
import 'OtpVerificationPage.dart' show OtpVerificationPage;
import '../user/UserNavigation.dart';
import '../makeup_artist/MakeupArtistNavigation.dart';
import '../admin/AdminNavigation.dart';
import 'dart:async';

class NavigateToOtpVerification extends StatefulWidget {
  final String userId;
  final String email;
  final String role;

  const NavigateToOtpVerification({
    required this.userId,
    required this.email,
    required this.role,
  });

  @override
  State<NavigateToOtpVerification> createState() => NavigateToOtpVerificationState();
}

class NavigateToOtpVerificationState extends State<NavigateToOtpVerification> {
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _resendOtpAndNavigate();
  }

  Future<void> _resendOtpAndNavigate() async {
    try {
      print('🔄 Resuming OTP verification flow...');
      print('   Sending new OTP to: ${widget.email}');

      // Send a new OTP since the old one might have expired
      final otpService = OtpService();
      await otpService.sendOtp(widget.email);

      print('✅ New OTP sent successfully');

      setState(() {
        _otpSent = true;
      });

      if (mounted) {
        // Navigate to OTP verification page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OtpVerificationPage(
              userId: widget.userId,
              email: widget.email,
              role: widget.role,
              onVerified: () {
                // Navigate to appropriate home based on role
                if (widget.role == 'user') {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const UserNavigation()),
                        (route) => false,
                  );
                } else if (widget.role == 'makeup artist') {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const MainNavigation()),
                        (route) => false,
                  );
                } else if (widget.role == 'admin') {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const AdminMainNavigation()),
                        (route) => false,
                  );
                }
              },
              onCancelled: () async {
                await FirebaseAuth.instance.signOut();
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Failed to resend OTP: $e');
      // If OTP sending fails, sign out and go to login
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFDA9BF5), Color(0xFFC367CA)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.mail_outline,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 30),
              const Text(
                'Resuming Verification',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'We\'re sending a new verification code to complete your login',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
