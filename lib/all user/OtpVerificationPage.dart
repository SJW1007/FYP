import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/OtpService.dart';
import '../service/FcmService.dart';

class OtpVerificationPage extends StatefulWidget {
  final String userId;
  final String email;
  final String role;
  final VoidCallback onVerified;
  final Future<void> Function() onCancelled;

  const OtpVerificationPage({
    Key? key,
    required this.userId,
    required this.email,
    required this.role,
    required this.onVerified,
    required this.onCancelled,
  }) : super(key: key);

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isVerifying = false;
  bool _isResending = false;
  bool _isAccountLocked = false; // NEW: Track if account is locked
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _checkAccountLock();
    _startCooldown(60);
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // Check if account is locked
  Future<void> _checkAccountLock() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final lockedUntil = userData['locked_until'] as Timestamp?;

        if (lockedUntil != null) {
          final unlockTime = lockedUntil.toDate();

          if (DateTime.now().isBefore(unlockTime)) {
            // Account is still locked
            final remainingTime = unlockTime.difference(DateTime.now());
            final hours = remainingTime.inHours;
            final minutes = remainingTime.inMinutes % 60;

            setState(() {
              _isAccountLocked = true; // Set locked state
              _errorMessage = 'Account locked due to too many failed attempts. Try again in ${hours}h ${minutes}m.';
            });

            // Sign out and redirect
            await Future.delayed(const Duration(seconds: 3));
            await _auth.signOut();
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } else {
            // Lock period has expired, clear the lock
            await userDoc.reference.update({
              'locked_until': FieldValue.delete(),
            });
          }
        }
      }
    } catch (e) {
      print('Error checking account lock: $e');
    }
  }

  void _startCooldown(int seconds) {
    setState(() {
      _resendCooldown = seconds;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final enteredOtp = _otpControllers.map((c) => c.text).join();

      if (enteredOtp.length != 6) {
        setState(() {
          _errorMessage = 'Please enter the complete 6-digit code';
          _isVerifying = false;
        });
        return;
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Session expired. Please login again.';
          _isVerifying = false;
        });
        return;
      }

      // Check if account is locked before verifying
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final lockedUntil = userData['locked_until'] as Timestamp?;

        if (lockedUntil != null && DateTime.now().isBefore(lockedUntil.toDate())) {
          final remainingTime = lockedUntil.toDate().difference(DateTime.now());
          final hours = remainingTime.inHours;
          final minutes = remainingTime.inMinutes % 60;

          setState(() {
            _isAccountLocked = true; // Set locked state
            _errorMessage = 'Account locked. Try again in ${hours}h ${minutes}m.';
            _isVerifying = false;
          });

          await Future.delayed(const Duration(seconds: 2));
          await _auth.signOut();
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        }
      }

      // Query the latest unused OTP
      final otpQuery = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('otp_codes')
          .where('used', isEqualTo: false)
          .orderBy('created_at', descending: true)
          .limit(1)
          .get();

      if (otpQuery.docs.isEmpty) {
        setState(() {
          _errorMessage = 'No valid OTP found. Please request a new one.';
          _isVerifying = false;
        });
        return;
      }

      final otpDoc = otpQuery.docs.first;
      final otpData = otpDoc.data();
      final storedOtp = otpData['code'];
      final expiresAt = (otpData['expires_at'] as Timestamp).toDate();

      // Check if OTP has expired
      if (DateTime.now().isAfter(expiresAt)) {
        setState(() {
          _errorMessage = 'OTP has expired. Please request a new one.';
          _isVerifying = false;
        });
        await otpDoc.reference.update({'used': true});
        return;
      }

      // Verify the OTP
      if (enteredOtp == storedOtp) {
        // SUCCESS: Mark OTP as used AND add verification timestamp
        await otpDoc.reference.update({
          'used': true,
          'verified_at': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification successful!'),
              backgroundColor: Colors.green,
            ),
          );
          await FCMService().initialize();
        }

        widget.onVerified();
      } else {
        // FAILED ATTEMPT
        final failedAttempts = (otpData['failed_attempts'] ?? 0) + 1;
        await otpDoc.reference.update({'failed_attempts': failedAttempts});

        if (failedAttempts >= 3) {
          // Lock account for 24 hours
          final lockUntil = DateTime.now().add(const Duration(hours: 24));

          await _firestore.collection('users').doc(currentUser.uid).update({
            'locked_until': Timestamp.fromDate(lockUntil),
          });

          // Mark OTP as used
          await otpDoc.reference.update({'used': true});

          // Sign out
          await _auth.signOut();

          setState(() {
            _isAccountLocked = true; // Set locked state
            _errorMessage = 'Too many failed attempts. Account locked for 24 hours.';
            _isVerifying = false;
          });

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
        } else {
          setState(() {
            _errorMessage = 'Invalid OTP. ${3 - failedAttempts} attempts remaining.';
            _isVerifying = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0 || _isAccountLocked) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('Session expired. Please login again.');
      }

      // Check if account is locked
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final lockedUntil = userData['locked_until'] as Timestamp?;

        if (lockedUntil != null && DateTime.now().isBefore(lockedUntil.toDate())) {
          final remainingTime = lockedUntil.toDate().difference(DateTime.now());
          final hours = remainingTime.inHours;
          final minutes = remainingTime.inMinutes % 60;

          setState(() {
            _isAccountLocked = true; // Set locked state
            _errorMessage = 'Account locked. Try again in ${hours}h ${minutes}m.';
            _isResending = false;
          });
          return;
        }
      }

      // Call OTP service
      final otpService = OtpService();
      await otpService.sendOtp(widget.email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New OTP sent to your email!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clear the text fields
      for (var controller in _otpControllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();

      _startCooldown(60);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to resend OTP. Please try again.';
      });
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (_isAccountLocked) return false; // Prevent back navigation when locked

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Login?'),
        content: const Text('Are you sure you want to cancel the verification? You will be signed out.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Continue'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldPop == true) {
      await widget.onCancelled();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text(
                'OTP Verification',
                style: TextStyle(color: Colors.black),
              ),
              centerTitle: true,
              automaticallyImplyLeading: false,
              leading: _isAccountLocked ? null : IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () async {
                  final shouldCancel = await _onWillPop();
                  if (shouldCancel) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            body: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/image_4.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFB81EE).withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.mail_outline,
                                          size: 80,
                                          color: Color(0xFFC367CA),
                                        ),
                                      ),
                                      const SizedBox(height: 30),
                                      const Text(
                                        'Verify Your Email',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Georgia',
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'We sent a verification code to',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.email,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFC367CA),
                                        ),
                                      ),
                                      const SizedBox(height: 40),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: List.generate(6, (index) {
                                          return SizedBox(
                                            width: 50,
                                            child: TextField(
                                              controller: _otpControllers[index],
                                              focusNode: _focusNodes[index],
                                              enabled: !_isAccountLocked, // Disable when locked
                                              textAlign: TextAlign.center,
                                              keyboardType: TextInputType.number,
                                              maxLength: 1,
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: _isAccountLocked ? Colors.grey : Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                counterText: '',
                                                filled: _isAccountLocked,
                                                fillColor: _isAccountLocked ? Colors.grey[200] : null,
                                                enabledBorder: OutlineInputBorder(
                                                  borderSide: BorderSide(
                                                    color: _isAccountLocked ? Colors.grey : const Color(0xFFFB81EE),
                                                    width: 2,
                                                  ),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                disabledBorder: OutlineInputBorder(
                                                  borderSide: const BorderSide(color: Colors.grey, width: 2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderSide: const BorderSide(color: Color(0xFFC367CA), width: 2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              onChanged: (value) {
                                                if (_isAccountLocked) return;

                                                if (value.isNotEmpty && index < 5) {
                                                  _focusNodes[index + 1].requestFocus();
                                                } else if (value.isEmpty && index > 0) {
                                                  _focusNodes[index - 1].requestFocus();
                                                }

                                                if (index == 5 && value.isNotEmpty) {
                                                  _verifyOtp();
                                                }
                                              },
                                            ),
                                          );
                                        }),
                                      ),
                                      const SizedBox(height: 20),
                                      if (_errorMessage != null)
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.error_outline, color: Colors.red),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: const TextStyle(color: Colors.red),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 30),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: (_isVerifying || _isAccountLocked) ? null : _verifyOtp,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _isAccountLocked ? Colors.grey : const Color(0xFFC367CA),
                                            disabledBackgroundColor: Colors.grey,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _isVerifying
                                              ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                              : Text(
                                            'Verify',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: _isAccountLocked ? Colors.white70 : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            "Didn't receive the code?",
                                            style: TextStyle(color: Colors.grey[600]),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: (_resendCooldown > 0 || _isResending || _isAccountLocked) ? null : _resendOtp,
                                            child: _isResending
                                                ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFC367CA)),
                                              ),
                                            )
                                                : Text(
                                              _resendCooldown > 0
                                                  ? 'Resend in ${_resendCooldown}s'
                                                  : 'Resend',
                                              style: TextStyle(
                                                color: (_resendCooldown > 0 || _isAccountLocked)
                                                    ? Colors.grey
                                                    : const Color(0xFFC367CA),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              )
                          )
                      );
                    })
            )
        )
    );
  }
}