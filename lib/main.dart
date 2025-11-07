import 'package:blush_up/service/AuthWrapper.dart';
import 'package:blush_up/service/OtpService.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'all user/Login.dart';
import 'all user/OtpVerificationPage.dart' show OtpVerificationPage;
import 'user/UserNavigation.dart';
import 'makeup_artist/MakeupArtistNavigation.dart';
import 'admin/AdminNavigation.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'service/FcmService.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );

  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
    print('✅ .env loaded successfully');
  } catch (e) {
    print('❌ Failed to load .env: $e');
  }

  // Initialize FCM
  await FCMService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  StreamSubscription<DocumentSnapshot>? _makeupArtistSubscription;
  String? _currentUserId;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    // _setupAuthStateListener();
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _makeupArtistSubscription?.cancel();
    super.dispose();
  }

  // Monitor auth state changes globally
  // void _setupAuthStateListener() {
  //   FirebaseAuth.instance.authStateChanges().listen((User? user) async {
  //     if (user == null) {
  //       // User signed out or session expired
  //       print('🔴 User signed out or session expired');
  //
  //       // Cancel any active listeners
  //       await _userDocSubscription?.cancel();
  //       await _makeupArtistSubscription?.cancel();
  //       _currentUserId = null;
  //       _currentUserRole = null;
  //
  //       // Navigate to login page
  //       navigatorKey.currentState?.pushAndRemoveUntil(
  //         MaterialPageRoute(builder: (context) => const LoginPage()),
  //             (route) => false,
  //       );
  //     } else {
  //       // User signed in
  //       print('🟢 User authenticated: ${user.uid}');
  //       _currentUserId = user.uid;
  //
  //       // Start monitoring user document and status
  //       _monitorUserDocument(user.uid);
  //     }
  //   });
  //
  //   // Optional: Listen for token refresh failures
  //   FirebaseAuth.instance.idTokenChanges().listen((User? user) async {
  //     if (user != null) {
  //       try {
  //         // Try to get fresh token
  //         await user.getIdToken(true);
  //         print('✅ Token refreshed successfully');
  //       } catch (e) {
  //         print('❌ Token refresh failed: $e');
  //         // Sign out if token refresh fails
  //         await FirebaseAuth.instance.signOut();
  //       }
  //     }
  //   });
  // }

  // Monitor user document for deletion or role changes
  void _monitorUserDocument(String userId) {
    print('🔍 Starting to monitor user document for: $userId');

    // Cancel existing subscription first
    _userDocSubscription?.cancel();

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (docSnapshot) {
        print('🔔 User document snapshot received. Exists: ${docSnapshot.exists}');

        if (!docSnapshot.exists) {
          // User document was deleted
          print('🚨 User document deleted - logging out');
          _showLogoutMessage('Your account has been deleted');
          return; // Don't sign out here, let the dialog handler do it
        }

        final userData = docSnapshot.data();
        if (userData == null) {
          print('⚠️ User data is null');
          return;
        }

        final role = userData['role'];
        print('👤 User role: $role');
        _currentUserRole = role;

        // If role is makeup artist, monitor their status
        if (role == 'makeup artist') {
          print('💄 User is makeup artist - starting status monitor');
          _monitorMakeupArtistStatus(userId);
        } else {
          // Cancel makeup artist listener if role changed
          print('🔄 User is not makeup artist - canceling status monitor');
          _makeupArtistSubscription?.cancel();
          _makeupArtistSubscription = null;
        }
      },
      onError: (error) {
        print('❌ Error monitoring user document: $error');
        print('Error details: ${error.toString()}');
      },
    );
  }

  // Monitor makeup artist status changes
  void _monitorMakeupArtistStatus(String userId) async {
    print('🔍 Starting to monitor makeup artist status for user: $userId');

    // Cancel existing subscription first
    _makeupArtistSubscription?.cancel();

    try {
      // First, find the makeup artist document ID
      final querySnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: FirebaseFirestore.instance.doc('users/$userId'))
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('⚠️ No makeup artist document found for user: $userId');
        return;
      }

      final artistDocId = querySnapshot.docs.first.id;
      print('✅ Found makeup artist document ID: $artistDocId');

      // Now listen to that specific document for real-time updates
      _makeupArtistSubscription = FirebaseFirestore.instance
          .collection('makeup_artists')
          .doc(artistDocId)
          .snapshots()
          .listen(
            (docSnapshot) {
          print('🔔 Makeup artist document snapshot received. Exists: ${docSnapshot.exists}');

          if (!docSnapshot.exists) {
            // Makeup artist document deleted
            print('🚨 Makeup artist document deleted - logging out');
            _showLogoutMessage('Your makeup artist profile has been removed');
            return;
          }

          final makeupArtistData = docSnapshot.data();
          if (makeupArtistData == null) {
            print('⚠️ Makeup artist data is null');
            return;
          }

          final status = makeupArtistData['status'];

          print('📊 Makeup artist status from Firestore: "$status" (type: ${status.runtimeType})');
          print('📄 Full document data: $makeupArtistData');

          // Auto-logout if status is not Approved
          final statusStr = status.toString().trim();

          if (statusStr != 'Approved') {
            String message;
            switch (statusStr) {
              case 'Pending':
                message = 'Your application is pending approval. You have been logged out.';
                break;
              case 'Rejected':
                message = 'Your application has been rejected. Please check your email for details.';
                break;
              case 'Disabled':
                message = 'Your account has been disabled. Please check your email for details.';
                break;
              default:
                message = 'Your account status has changed to "$statusStr". Please contact support.';
            }

            print('🚨 Status is "$statusStr" (not Approved) - logging out');

            // Show message and only sign out when user dismisses dialog
            _showLogoutMessage(message);
          } else {
            print('✅ Status is Approved - user can stay logged in');
          }
        },
        onError: (error) {
          print('❌ Error monitoring makeup artist status: $error');
          print('Error details: ${error.toString()}');
        },
      );
    } catch (e) {
      print('❌ Error setting up makeup artist monitor: $e');
    }
  }

  // Show logout message to user
  void _showLogoutMessage(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => WillPopScope(
          onWillPop: () async => false, // Prevent back button dismiss
          child: AlertDialog(
            title: const Text('Session Ended'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop(); // Close dialog first
                  // Then sign out, which will trigger navigation to login
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    } else {
      // If no context available, sign out directly
      FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Blush Up',
      theme: ThemeData(
        fontFamily: 'Georgia',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFDA9BF5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

