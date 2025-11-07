import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../all user/Login.dart';
import '../user/UserNavigation.dart';
import '../makeup_artist/MakeupArtistNavigation.dart';
import '../admin/AdminNavigation.dart';
import 'dart:async';
import '../all user/NavigateToOtpVerification.dart';

// AuthWrapper checks if user is logged in and routes accordingly
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<Widget> _determineHomePage() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('🔍 No user signed in - redirecting to login');
      return const LoginPage();
    }

    try {
      // Refresh token to ensure it's valid
      await user.getIdToken(true);
      print('✅ User token refreshed: ${user.uid}');

      // Check if user document exists
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        print('⚠️ User document not found - signing out');
        await FirebaseAuth.instance.signOut();
        return const LoginPage();
      }

      final userData = userDoc.data()!;

      // ✅ CHECK ACCOUNT LOCK - NEW CODE
      final lockedUntil = userData['locked_until'] as Timestamp?;
      if (lockedUntil != null) {
        final unlockTime = lockedUntil.toDate();

        if (DateTime.now().isBefore(unlockTime)) {
          // Account is still locked - sign out
          print('🔒 Account is locked - signing out');
          await FirebaseAuth.instance.signOut();
          return const LoginPage();
        } else {
          // Lock period expired - remove the lock
          await userDoc.reference.update({
            'locked_until': FieldValue.delete(),
          });
          print('🔓 Account lock expired and removed for user: ${user.uid}');
        }
      }
      // ✅ END OF LOCK CHECK

      final role = userData['role'];
      final email = userData['email'] ?? user.email;

      print('🔍 Checking OTP verification for user: ${user.uid}');
      print('   Role: $role');

      // 🔥 CRITICAL: Check if user has completed OTP verification
      final verifiedOtpQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('otp_codes')
          .where('used', isEqualTo: true)
          .where('verified_at', isNotEqualTo: null)
          .orderBy('verified_at', descending: true)
          .limit(1)
          .get();

      if (verifiedOtpQuery.docs.isEmpty) {
        // User is authenticated but has NEVER completed OTP verification
        print('⚠️ No verified OTP found - user must complete verification');
        print('   User was authenticated but never verified OTP');
        print('   This can happen if they force-closed the app during OTP flow');

        // Navigate to OTP verification flow
        return NavigateToOtpVerification(
          userId: user.uid,
          email: email,
          role: role,
        );
      }

      // Optional: Check if verification is too old
      final lastVerified = (verifiedOtpQuery.docs.first.data()['verified_at'] as Timestamp).toDate();
      final hoursSinceVerification = DateTime.now().difference(lastVerified).inHours;
      print('✅ Last OTP verification: ${hoursSinceVerification} hours ago');

      /*
      // Uncomment this block if you want to require re-verification after 24 hours
      if (hoursSinceVerification > 24) {
        print('⚠️ Last verification was ${hoursSinceVerification} hours ago - require new verification');
        return NavigateToOtpVerification(
          userId: user.uid,
          email: email,
          role: role,
        );
      }
      */

      print('✅ User has verified OTP - allowing access');

      // Route based on role
      if (role == 'user') {
        return const UserNavigation();
      } else if (role == 'admin') {
        return const AdminMainNavigation();
      } else if (role == 'makeup artist') {
        // Check makeup artist status
        final makeupArtistSnapshot = await FirebaseFirestore.instance
            .collection('makeup_artists')
            .where('user_id', isEqualTo: FirebaseFirestore.instance.doc('users/${user.uid}'))
            .get();

        if (makeupArtistSnapshot.docs.isEmpty) {
          print('⚠️ Makeup artist profile not found - signing out');
          await FirebaseAuth.instance.signOut();
          return const LoginPage();
        }

        final makeupArtistData = makeupArtistSnapshot.docs.first.data();
        final status = makeupArtistData['status'];

        if (status == 'Approved') {
          return const MainNavigation();
        } else {
          print('⚠️ Makeup artist status is "$status" - signing out');
          await FirebaseAuth.instance.signOut();
          return const LoginPage();
        }
      }

      // Unknown role
      print('⚠️ Unknown role: $role - signing out');
      await FirebaseAuth.instance.signOut();
      return const LoginPage();

    } catch (e) {
      print('❌ Error determining home page: $e');
      await FirebaseAuth.instance.signOut();
      return const LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _determineHomePage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural,
                        size: 60,
                        color: Color(0xFFDA9BF5),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'BlushUp',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return snapshot.data!;
        }

        return const LoginPage();
      },
    );
  }
}