import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../user/UserNavigation.dart';
import 'Register.dart';
import 'ForgetPassword.dart';
import 'OtpVerificationPage.dart';
import '../makeup_artist/RegisterMakeupArtist.dart';
import '../makeup_artist/MakeupArtistNavigation.dart';
import '../admin/AdminNavigation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../service/OtpService.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _obscurePassword = true;

  bool _isLoading = false;
  String? _errorMessage;

  // Store user data for OTP verification callback
  String? _pendingUserId;
  String? _pendingEmail;
  String? _pendingRole;

  Future<void> _loginUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final usernameOrEmail = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      if (usernameOrEmail.isEmpty || password.isEmpty) {
        throw Exception('Please fill in all fields');
      }

      String email;
      String? userIdFromLookup; // Changed variable name to avoid conflict

      // Check if input is an email (contains @)
      if (usernameOrEmail.contains('@')) {
        email = usernameOrEmail;

        // Get userId from email BEFORE authentication
        final userQuery = await _firestore
            .collection('users')
            .where('email', isEqualTo: email)
            .get();

        if (userQuery.docs.isNotEmpty) {
          userIdFromLookup = userQuery.docs.first.id;
        }
      } else {
        // If username, fetch email and userId from Firestore
        final snapshot = await _firestore
            .collection('users')
            .where('username', isEqualTo: usernameOrEmail)
            .get();

        if (snapshot.docs.isEmpty) {
          setState(() {
            _errorMessage = 'Username/email or password is invalid';
            _isLoading = false;
          });
          return;
        }

        final userData = snapshot.docs.first.data();
        email = userData['email'];
        userIdFromLookup = snapshot.docs.first.id; // Get userId here
      }

      // ✅ CHECK ACCOUNT LOCK BEFORE AUTHENTICATION
      if (userIdFromLookup != null) {
        final lockCheck = await _checkAccountLock(userIdFromLookup);
        if (lockCheck != null) {
          // Account is locked - DON'T authenticate
          setState(() {
            _errorMessage = lockCheck;
            _isLoading = false;
          });
          return;
        }
      }

      // NOW authenticate with Firebase Auth
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password
        );
      } on FirebaseAuthException catch (authError) {
        if (authError.code == 'wrong-password' ||
            authError.code == 'invalid-credential' ||
            authError.code == 'user-not-found') {
          setState(() {
            _errorMessage = 'Username/email or password is invalid';
            _isLoading = false;
          });
          return;
        }
        rethrow;
      }

      // Step 2: Get user data from Firestore using the authenticated user's UID
      final userId = userCredential.user!.uid; // This is the main userId we use
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        setState(() {
          _errorMessage = 'User data not found. Please contact support.';
          _isLoading = false;
        });
        return;
      }

      // ❌ REMOVE THIS DUPLICATE CHECK - Already checked above before auth
      // if (userId != null) {
      //   final lockCheck = await _checkAccountLock(userId);
      //   ...
      // }

      final userData = userDoc.data()!;
      final role = userData['role'];

      // Step 3: Handle makeup artist status check (WHILE AUTHENTICATED)
      if (role == 'makeup artist') {
        final makeupArtistSnapshot = await _firestore
            .collection('makeup_artists')
            .where('user_id', isEqualTo: _firestore.doc('users/$userId'))
            .get();

        if (makeupArtistSnapshot.docs.isEmpty) {
          await _auth.signOut();
          setState(() {
            _errorMessage = 'Makeup artist application not found. Please contact support.';
            _isLoading = false;
          });
          return;
        }

        final makeupArtistData = makeupArtistSnapshot.docs.first.data();
        final status = makeupArtistData['status'];

        switch (status) {
          case 'Pending':
            await _auth.signOut();
            setState(() {
              _errorMessage = 'Your makeup artist application is still pending. Please wait for admin approval.';
              _isLoading = false;
            });
            return;

          case 'Rejected':
            await _auth.signOut();
            setState(() {
              _errorMessage = 'Your makeup artist application has been rejected. Please check the email for more information.';
              _isLoading = false;
            });
            return;

          case 'Disabled':
            await _auth.signOut();
            setState(() {
              _errorMessage = 'Your account has been disabled. Please check the email for more information.';
              _isLoading = false;
            });
            return;

          case 'Approved':
            break;

          default:
            await _auth.signOut();
            setState(() {
              _errorMessage = 'Invalid application status. Please contact support.';
              _isLoading = false;
            });
            return;
        }
      }

      // Step 4: Store pending user data
      _pendingUserId = userId;
      _pendingEmail = email;
      _pendingRole = role;

      // Step 5: Send OTP WHILE STILL AUTHENTICATED
      try {
        final otpService = OtpService();
        await otpService.sendOtp(email);
        print('✅ OTP sent successfully');
      } catch (otpError) {
        // If OTP sending fails, sign out and show error
        await _auth.signOut();
        setState(() {
          _errorMessage = 'Failed to send OTP. Please try again.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });

      // Step 6: Navigate to OTP verification page (USER STAYS SIGNED IN)
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OtpVerificationPage(
            userId: userId,
            email: email,
            role: role,
            onVerified: _handleVerificationSuccess,
            onCancelled: _handleVerificationCancelled,
          ),
        ),
      );

    } on FirebaseAuthException catch (e) {
      await _auth.signOut();
      setState(() {
        switch (e.code) {
          case 'network-request-failed':
            _errorMessage = 'Network error. Please check your connection.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email format.';
            break;
          default:
            _errorMessage = e.message ?? 'An authentication error occurred.';
        }
      });
    } catch (e) {
      await _auth.signOut();
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Check if account is locked and return error message if locked
  // Returns null if account is not locked (can proceed)
  Future<String?> _checkAccountLock(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (!userDoc.exists) return null;

      final userData = userDoc.data()!;
      final lockedUntil = userData['locked_until'] as Timestamp?;

      if (lockedUntil != null) {
        final unlockTime = lockedUntil.toDate();

        if (DateTime.now().isBefore(unlockTime)) {
          // Account is still locked
          final remainingTime = unlockTime.difference(DateTime.now());
          final hours = remainingTime.inHours;
          final minutes = remainingTime.inMinutes % 60;

          return 'Account locked due to too many failed OTP attempts.\nTry again in ${hours}h ${minutes}m.';
        } else {
          // Lock period expired - remove the lock
          await userDoc.reference.update({
            'locked_until': FieldValue.delete(),
          });
          print('🔓 Account lock expired and removed for user: $userId');
        }
      }

      return null; // Account is not locked
    } catch (e) {
      print('Error checking account lock: $e');
      return null; // Don't block login if check fails
    }
  }

  void _handleVerificationSuccess() async {
    if (_pendingRole == null) return;

    // --- FOR JMETER TESTING: GET AND PRINT AUTH TOKEN ---
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final idToken = await user.getIdToken(true); // Force refresh
        print('--- JMETER AUTH TOKEN ---');
        print('User: ${user.email}');
        print('Token: $idToken');
        print('--------------------------');
      } catch (e) {
        print('Could not get auth token: $e');
      }
    }
    // --- END OF JMETER TESTING CODE ---

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Login successful!")),
    );

    // User is already authenticated, just navigate
    if (_pendingRole == 'user') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const UserNavigation()),
            (route) => false,
      );
    } else if (_pendingRole == 'makeup artist') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigation()),
            (route) => false,
      );
    } else if (_pendingRole == 'admin') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AdminMainNavigation()),
            (route) => false,
      );
    }
  }

  Future<void> _handleVerificationCancelled() async {
    // Sign out user if they cancel OTP verification
    await _auth.signOut();
    setState(() {
      _pendingUserId = null;
      _pendingEmail = null;
      _pendingRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.08,
                  vertical: screenHeight * 0.03,
                ),
                constraints: BoxConstraints(
                  minHeight: screenHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: screenHeight * 0.02),
                    Text(
                      'Welcome To BlushUp!',
                      style: TextStyle(
                        fontSize: screenWidth * 0.06,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Georgia',
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      'Login Now!',
                      style: TextStyle(
                        fontSize: screenWidth * 0.04,
                        fontFamily: 'Georgia',
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.04),

                    // Username/Email Field
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Username or Email',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.person, color: Color(0xFFFB81EE)),
                        hintText: 'Enter Your Username or Email',
                        hintStyle: TextStyle(color: Colors.grey),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: screenHeight * 0.02,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFB81EE)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFB81EE)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),

                    // Password Field
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Password',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.lock, color: Color(0xFFFB81EE)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Color(0xFFFB81EE),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        hintText: 'Enter Your Password Here',
                        hintStyle: TextStyle(color: Colors.grey),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: screenHeight * 0.02,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFB81EE)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFFB81EE)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),

                    // Forgot Password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ForgetPasswordPage()),
                          );
                        },
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: screenWidth * 0.035,
                          ),
                        ),
                      ),
                    ),

                    // Error Message
                    if (_errorMessage != null)
                      Container(
                        margin: EdgeInsets.only(bottom: screenHeight * 0.02),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: screenWidth * 0.035,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _loginUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC367CA),
                          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.018),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.03),

                    // Divider with "or"
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.black38, thickness: 1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: screenWidth * 0.035,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.black38, thickness: 1)),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.025),

                    // Sign Up Text
                    Text(
                      'Don\'t have an account?',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: screenWidth * 0.038,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),

                    // Sign Up Buttons - Stacked for better responsiveness
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterPage(role: 'User'),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.person_add,
                              size: screenWidth * 0.05,
                              color: Color(0xFFC367CA),
                            ),
                            label: Text(
                              'Sign Up as User',
                              style: TextStyle(
                                fontSize: screenWidth * 0.04,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                              side: BorderSide(color: Color(0xFFC367CA), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.012),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterPage(role: 'MakeupArtist'),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.brush,
                              size: screenWidth * 0.05,
                              color: Color(0xFFC367CA),
                            ),
                            label: Text(
                              'Sign Up as Makeup Artist',
                              style: TextStyle(
                                fontSize: screenWidth * 0.04,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                              side: BorderSide(color: Color(0xFFC367CA), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.02),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.025,
                    horizontal: screenWidth * 0.06,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: screenWidth * 0.1,
                        width: screenWidth * 0.1,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDA9BF5)),
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015),
                      Text(
                        'Signing in...',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.008),
                      Text(
                        'Please wait...',
                        style: TextStyle(
                          fontSize: screenWidth * 0.033,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
