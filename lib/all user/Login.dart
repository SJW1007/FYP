import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../user/UserNavigation.dart';
import '../user/Register.dart';
import 'ForgetPassword.dart';
import '../makeup_artist/RegisterMakeupArtist.dart';
import '../makeup_artist/MakeupArtistNavigation.dart';
import '../admin/AdminNavigation.dart';

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

  Future<void> _loginUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      // Validate input fields
      if (username.isEmpty || password.isEmpty) {
        throw Exception('Please fill in all fields');
      }

      // Step 1: Fetch email n role by username from Firestore
      final snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (snapshot.docs.isEmpty) {
        // If username doesn't exist
        setState(() {
          _errorMessage = 'Username doesn\'t exist';
          _isLoading = false;
        });
        return;
      }

      final userData = snapshot.docs.first.data();
      final userDocId = snapshot.docs.first.id;
      final email = userData['email'];
      final role = userData['role'];

      // Step 2: Authenticate with email & password
      try {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (authError) {
        // Handle authentication-specific errors
        if (authError.code == 'wrong-password' || authError.code == 'invalid'
            '-credential') {
          setState(() {
            _errorMessage = 'Password incorrect';
            _isLoading = false;
          });
          return;
        } else if (authError.code == 'user-not-found') {
          setState(() {
            _errorMessage = 'Username doesn\'t exist';
            _isLoading = false;
          });
          return;
        } else if (authError.code == 'too-many-requests') {
          setState(() {
            _errorMessage = 'Too many failed attempts. Please try again later.';
            _isLoading = false;
          });
          return;
        } else if (authError.code == 'user-disabled') {
          setState(() {
            _errorMessage = 'This account has been disabled.';
            _isLoading = false;
          });
          return;
        } else {
          // Re-throw other Firebase auth errors to be handled by outer catch
          rethrow;
        }
      }

      // Step 3: Handle makeup artist status check
      if (role == 'makeup artist') {
        // Check makeup artist application status
        final makeupArtistSnapshot = await _firestore
            .collection('makeup_artists')
            .where('user_id', isEqualTo: _firestore.doc('users/$userDocId'))
            .get();

        if (makeupArtistSnapshot.docs.isEmpty) {
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
            setState(() {
              _errorMessage = 'Your makeup artist application is still pending. Please wait for admin approval.';
              _isLoading = false;
            });
            return;

          case 'Rejected':
            setState(() {
              _errorMessage = 'Your makeup artist application has been rejected. Please check the email for more information.';
              _isLoading = false;
            });
            return;

          case 'Disabled':
            setState(() {
              _errorMessage = 'Your account has been disable. Please check the email for more information.';
              _isLoading = false;
            });
            return;

          case 'Approved':
          // Proceed to makeup artist navigation
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Login successful!")),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainNavigation()),
            );
            return;

          default:
            setState(() {
              _errorMessage = 'Invalid application status. Please contact support.';
              _isLoading = false;
            });
            return;
        }
      }

      // Step 4: Navigate based on other roles
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login successful!")),
      );

      if (role == 'user') {
        // Navigate to Main Screen for regular users
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserNavigation()),
        );
      } else if (role == 'admin') {
        // Navigate to Admin Screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminMainNavigation()),
        );
      } else {
        // Handle unexpected role or null role
        setState(() {
          _errorMessage = 'Invalid user role. Please contact support.';
          _isLoading = false;
        });
        return;
      }

    } on FirebaseAuthException catch (e) {
      // Handle any remaining Firebase auth errors
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
      // Handle any other errors
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
          SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              height: MediaQuery.of(context).size.height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Welcome To BlushUp!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Georgia',
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Login Now!',
                    style: TextStyle(fontSize: 16, fontFamily: 'Georgia', color: Colors.black),
                  ),
                  const SizedBox(height: 40),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Username', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.person, color: Color(0xFFFB81EE)),
                      hintText: 'Enter Your Username Here',
                      hintStyle: TextStyle(color: Colors.grey),
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
                  const SizedBox(height: 20),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 16, color: Colors.black)),
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

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ForgetPasswordPage()),
                        );
                      },
                      child: const Text('Forgot Password?', style: TextStyle(color: Colors.black87)),
                    ),
                  ),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_errorMessage!, style: TextStyle(color: Colors.red)),
                    ),

                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                    onPressed: _loginUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC367CA),
                      padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),

                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterPage()),
                          );
                        },
                        child: const Text('Sign Up as User', style: TextStyle(color: Colors.black)),
                      ),
                      const Text('|', style: TextStyle(color: Colors.black)),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterMakeupArtistPage()),
                          );
                        },
                        child: const Text('Sign Up As Makeup Artist', style: TextStyle(color: Colors.black)),
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
