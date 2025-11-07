import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../all user/Login.dart';
import '../makeup_artist/RegisterMakeupArtist.dart';
import 'Register.dart';
import '../makeup_artist/RegisterMakeupArtistDetail.dart';

class EmailVerificationPage extends StatefulWidget {
  final String email;
  final String name;
  final String username;
  final String phoneNumber;
  final String role;

  const EmailVerificationPage({
    super.key,
    required this.email,
    required this.name,
    required this.username,
    required this.phoneNumber,
    required this.role,
  });

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  Timer? _timer;
  bool _isEmailVerified = false;
  bool _canResendEmail = false;
  bool _isLoading = false;
  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _isEmailVerified = _auth.currentUser?.emailVerified ?? false;

    if (!_isEmailVerified) {
      _sendVerificationEmail();
      _checkEmailVerified();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendVerificationEmail() async {
    try {
      final user = _auth.currentUser!;
      await user.sendEmailVerification();

      setState(() {
        _canResendEmail = false;
        _resendCooldown = 60;
      });

      _startResendCooldown();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email sent to ${widget.email}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending verification email: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startResendCooldown() {
    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (_resendCooldown == 0) {
          setState(() {
            _canResendEmail = true;
          });
          timer.cancel();
        } else {
          setState(() {
            _resendCooldown--;
          });
        }
      },
    );
  }

  Future<void> _checkEmailVerified() async {
    _timer = Timer.periodic(
      const Duration(seconds: 3),
          (timer) async {
        await _auth.currentUser?.reload();
        final user = _auth.currentUser;

        if (user?.emailVerified ?? false) {
          timer.cancel();
          setState(() {
            _isEmailVerified = true;
          });

          // Save user data to Firestore after email verification
          await _saveUserToFirestore();

          // Navigate based on role
          _navigateBasedOnRole();
        }
      },
    );
  }

  Future<void> _saveUserToFirestore() async {
    try {
      final user = _auth.currentUser!;
      const defaultProfilePicUrl = 'https://firebasestorage.googleapis.com/v0/b/fyp-makeup-artist-booking.firebasestorage.app/o/default%2Fimage%2010.png?alt=media&token=824d9761-509f-4090-a6df-96ecd61799c8';

      // Determine the role to save in database
      String roleToSave;
      if (widget.role.toLowerCase() == 'user') {
        roleToSave = 'user';
      } else if (widget.role.toLowerCase() == 'makeupartist') {
        roleToSave = 'makeup artist';
      } else {
        roleToSave = widget.role.toLowerCase(); // fallback
      }

      await _firestore.collection('users').doc(user.uid).set({
        'name': widget.name,
        'username': widget.username,
        'email': widget.email,
        'phone number': int.parse(widget.phoneNumber),
        'role': roleToSave,
        'profile pictures': defaultProfilePicUrl,
      });
    } catch (e) {
      print('Error saving user data: $e');
    }
  }

  void _navigateBasedOnRole() {
    if (widget.role.toLowerCase() == 'user') {
      _navigateToLogin();
    } else if (widget.role.toLowerCase() == 'makeupartist') {
      _navigateToMakeupArtistDetails();
    } else {
      // Default fallback to login
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email verified successfully! '),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
    );
  }

  void _navigateToMakeupArtistDetails() {
    final user = _auth.currentUser!;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email verified successfully!'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => RegisterMakeupArtistDetailPage(
          userId: user.uid,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _changeEmail() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Change Email Address',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'To change your email address, your current account will be deleted and you\'ll need to register again with a new email.',
          style: TextStyle(fontFamily: 'Georgia'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close the dialog first
              await _deleteUserAndNavigateBack();
            },
            child: const Text(
              'Change Email',
              style: TextStyle(color: Color(0xFFC367CA)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUserAndNavigateBack() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Cancel timers first
      _timer?.cancel();
      _cooldownTimer?.cancel();

      final user = _auth.currentUser;
      if (user != null) {
        // Delete the user from Firebase Auth
        await user.delete();

        // Also delete from Firestore if it was already saved
        // (though in your current flow, it shouldn't be saved yet)
        try {
          await _firestore.collection('users').doc(user.uid).delete();
        } catch (e) {
          // User data might not exist in Firestore yet, which is fine
          print('Firestore deletion note: $e');
        }
      }

      // Navigate based on the original role
      if (widget.role.toLowerCase() == 'makeupartist') {
        // Navigate back to makeup artist registration
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RegisterMakeupArtistPage(),
          ),
              (route) => false,
        );
      } else {
        // Navigate back to regular user registration
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RegisterPage(role: 'User',),
          ),
              (route) => false,
        );
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted. Please register with new email.'),
          backgroundColor: Colors.orange,
        ),
      );

    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'requires-recent-login':
          errorMessage = 'Please log in again to change your email address.';
          break;
        case 'user-not-found':
          errorMessage = 'User account not found.';
          break;
        default:
          errorMessage = 'Error: ${e.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Foreground Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.email_outlined,
                    size: 80,
                    color: Color(0xFFC367CA),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Verify Your Email',
                    style: TextStyle(
                      fontSize: 28,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'We\'ve sent a verification link to:',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Georgia',
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Text(
                    widget.email,
                    style: const TextStyle(
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC367CA),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  Text(
                    widget.role.toLowerCase() == 'makeupartist'
                        ? 'Please check your email and click the verification link. After verification, you\'ll request to complete your makeup artist profile.'
                        : 'Please check your email and click the verification link to complete your registration.',
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Georgia',
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Resend Email Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canResendEmail ? _sendVerificationEmail : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canResendEmail
                            ? const Color(0xFFC367CA)
                            : Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _canResendEmail
                            ? 'Resend Verification Email'
                            : 'Resend in ${_resendCooldown}s',
                        style: TextStyle(
                          color: _canResendEmail ? Colors.white : Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Change Email Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _changeEmail,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFC367CA)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Change Email Address',
                        style: TextStyle(
                          color: Color(0xFFC367CA),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Status indicator
                  if (_isEmailVerified)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          widget.role.toLowerCase() == 'makeupartist'
                              ? 'Email verified!'
                              : 'Email verified! Redirecting to login',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold,fontSize: 14),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Waiting for verification...',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}