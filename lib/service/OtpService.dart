import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class OtpService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: "us-central1");
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Generates a 6-digit OTP code
  String _generateOtp() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Sends OTP via Cloud Function with detailed debugging
  Future<void> sendOtp(String email) async {
    try {
      print('═══════════════════════════════════════');
      print('🚀 STARTING OTP SEND PROCESS');
      print('═══════════════════════════════════════');

      // Step 1: Wait for auth state and token to be fully ready
      print('📍 Step 1: Check Authentication');
      print('   ├─ Waiting for idTokenChanges().first...');
      final currentUser = await _auth.idTokenChanges().first;

      if (currentUser == null) {
        print('   └─ ❌ FAILED: No user signed in after waiting');
        throw Exception('User must be authenticated to send OTP');
      }

      print('   ├─ User ID: ${currentUser.uid}');
      print('   ├─ User Email: ${currentUser.email}');
      print('   └─ ✅ User is authenticated and token is ready');

      // Step 2: Generate OTP
      print('\n📍 Step 2: Generate OTP');
      final otp = _generateOtp();
      print('   ├─ Generated OTP: $otp');
      print('   └─ ✅ OTP generated');

      // Step 3: Store OTP in Firestore
      print('\n📍 Step 3: Store OTP in Firestore');
      try {
        await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('otp_codes')
            .add({
          'code': otp,
          'created_at': FieldValue.serverTimestamp(),
          'expires_at': Timestamp.fromDate(
            DateTime.now().add(const Duration(minutes: 5)),
          ),
          'used': false,
          'failed_attempts': 0,
        });
        print('   └─ ✅ OTP stored in Firestore');
      } catch (e) {
        print('   └─ ❌ FAILED: Error storing OTP: $e');
        throw Exception('Failed to store OTP: $e');
      }

      // Step 4: Call Cloud Function
      print('\n📍 Step 4: Call Cloud Function');
      print('   ├─ Function: sendOtpEmail');
      print('   ├─ Email: $email');
      print('   ├─ OTP: $otp');
      print('   ├─ Auth will be automatically included by Firebase');

      final callable = _functions.httpsCallable('sendOtpEmail');

      try {
        print('   ├─ Calling function...');

        final result = await callable.call({
          'email': email,
          'otp': otp,
        });

        print('   ├─ Function returned successfully');
        print('   ├─ Response: ${result.data}');

        if (result.data['success'] != true) {
          print('   └─ ❌ FAILED: Function returned success=false');
          throw Exception('Failed to send OTP email');
        }

        print('   └─ ✅ Cloud Function executed successfully');
      } catch (e) {
        print('   └─ ❌ FAILED: Error calling function');
        rethrow; // Let the outer catch handle it
      }

      print('\n═══════════════════════════════════════');
      print('✅ OTP SEND PROCESS COMPLETED');
      print('═══════════════════════════════════════\n');

    } on FirebaseFunctionsException catch (e) {
      print('\n═══════════════════════════════════════');
      print('❌ FIREBASE FUNCTIONS ERROR');
      print('═══════════════════════════════════════');
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      print('Details: ${e.details}');
      print('═══════════════════════════════════════\n');

      // Provide user-friendly error messages
      switch (e.code) {
        case 'unauthenticated':
          print('🔍 DIAGNOSIS: The auth token was NOT sent or is invalid');
          print('   Possible causes:');
          print('   1. User signed out between sign-in and this call');
          print('   2. Token expired (unlikely with force refresh)');
          print('   3. Firebase Functions not properly initialized');
          throw Exception('Authentication required. Please sign in again.');

        case 'permission-denied':
          print('🔍 DIAGNOSIS: Token is valid but user lacks permission');
          throw Exception('Permission denied. Please check your account.');

        case 'not-found':
          print('🔍 DIAGNOSIS: User document not found in Firestore');
          throw Exception('User account not found.');

        case 'internal':
          print('🔍 DIAGNOSIS: Server-side error (check Cloud Function logs)');
          throw Exception('Server error. Please try again later.');

        default:
          throw Exception('Failed to send OTP: ${e.message}');
      }
    } catch (e) {
      print('\n═══════════════════════════════════════');
      print('❌ UNEXPECTED ERROR');
      print('═══════════════════════════════════════');
      print('Type: ${e.runtimeType}');
      print('Message: $e');
      print('═══════════════════════════════════════\n');
      rethrow;
    }
  }

  /// Test function to verify authentication is working
  Future<Map<String, dynamic>> testAuthentication() async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return {
        'authenticated': false,
        'error': 'No user signed in',
      };
    }

    try {
      final token = await currentUser.getIdToken(true);

      return {
        'authenticated': true,
        'userId': currentUser.uid,
        'email': currentUser.email,
        'tokenExists': token != null && token.isNotEmpty,
        'tokenLength': token?.length ?? 0,
      };
    } catch (e) {
      return {
        'authenticated': true,
        'userId': currentUser.uid,
        'email': currentUser.email,
        'tokenExists': false,
        'error': e.toString(),
      };
    }
  }

  /// Marks old unused OTPs as expired
  Future<void> cleanupOldOtps(String userId) async {
    try {
      final oldOtps = await _firestore
          .collection('otp_codes')
          .where('user_id', isEqualTo: userId)
          .where('used', isEqualTo: false)
          .get();

      for (var doc in oldOtps.docs) {
        await doc.reference.update({'used': true});
      }
    } catch (e) {
      print('⚠️ Error cleaning up old OTPs: $e');
      // Don't throw - this is a cleanup operation
    }
  }
}
