import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../all user/Login.dart';
import 'RegisterMakeupArtistDetail.dart';
import '../user/Register.dart';

class RegisterMakeupArtistPage extends StatefulWidget {
  const RegisterMakeupArtistPage({super.key});

  @override
  State<RegisterMakeupArtistPage> createState() => _RegisterMakeupArtistPageState();
}

class _RegisterMakeupArtistPageState extends State<RegisterMakeupArtistPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  Future<void> _registerUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phone_number = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validate inputs
    if (username.isEmpty ||name.isEmpty|| email.isEmpty || password.isEmpty || confirmPassword.isEmpty || phone_number.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
        _isLoading = false;
      });
      return;
    }
    // Simple phone number validation (10-11 digits)
    bool _isValidMalaysianPhone(String phone) {
      // Remove all non-digits
      String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

      // Check if it's between 10-11 digits
      return digitsOnly.length >= 10 && digitsOnly.length <= 11;
    }

    bool _isValidEmail(String email) {
      // Regular expression for email validation
      final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      return emailRegex.hasMatch(email);
    }

    // Validate password
    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~]).{6,}$');
    if (!passwordRegex.hasMatch(password)) {
      setState(() {
        _errorMessage = 'Password must have 1 capital letter, 1 symbol, 1 number and at least 6 characters.';
        _isLoading = false;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match';
        _isLoading = false;
      });
      return;
    }

    if (phone_number.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the phone number.';
        _isLoading = false;
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _isLoading = false;
      });
      return;
    }

    // Validate phone number (10-11 digits)
    if (!_isValidMalaysianPhone(phone_number)) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number (10-11 digits).';
        _isLoading = false;
      });
      return;
    }

    try {
      // Check if username already exists
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .get();
      if (usernameQuery.docs.isNotEmpty) {
        setState(() {
          _errorMessage = 'Username already exists';
          _isLoading = false;
        });
        return;
      }


      // Check if email already exists in Realtime DB (optional but extra safe)
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        setState(() {
          _errorMessage = 'Email already exists';
          _isLoading = false;
        });
        return;
      }

      // Create user in Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;
      const defaultProfilePicUrl = 'https://firebasestorage.googleapis.com/v0/b/fyp-makeup-artist-booking.firebasestorage.app/o/default%2Fimage%2010.png?alt=media&token=824d9761-509f-4090-a6df-96ecd61799c8';

      // Store basic user info in database with proper error handling
      await _firestore.collection('users').doc(userId).set({
        'username': username,
        'email': email,
        'phone_number': phone_number,
        'name': name,
        'role': 'makeup artist',
        'profile pictures': defaultProfilePicUrl,
      });


      // Verify data was saved (optional verification step)
      final savedData = await _firestore.collection('users').doc(userId).get();
      if (!savedData.exists) {
        throw Exception('Failed to save user data to database');
      }

      // Navigate to detail page with user data only after successful save
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RegisterMakeupArtistDetailPage(
              userId: userId,
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Authentication error occurred';
      });
    } catch (e) {
      // Catch all other exceptions including database errors
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
      });
      print('Registration error: $e'); // For debugging
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
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SingleChildScrollView(
            child: Container(
              height: MediaQuery.of(context).size.height,
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Register as Makeup Artist',
                      style: TextStyle(
                          fontSize: 28, fontFamily: 'Georgia', fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Create an Account',
                      style: TextStyle(fontSize: 16, fontFamily: 'Georgia')),

                  const SizedBox(height: 30),

                  _buildTextField('Username', _usernameController, Icons.badge),
                  const SizedBox(height: 15),
                  _buildTextField('Email', _emailController, Icons.email),
                  const SizedBox(height: 15),
                  _buildTextField('Name', _nameController, Icons.badge),
                  const SizedBox(height: 15),
                  _buildPhoneTextField(), // Use special phone field
                  const SizedBox(height: 15),
                  _buildPasswordTextField('Password', _passwordController, Icons.lock, _isPasswordVisible, () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  }),
                  const SizedBox(height: 15),
                  _buildPasswordTextField('Confirm Password', _confirmPasswordController, Icons.lock, _isConfirmPasswordVisible, () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  }),
                  // Phone Number Field
                  const SizedBox(height: 15),


                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 20),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                    onPressed: _registerUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC367CA),
                      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Next',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginPage()),
                        ),
                        child: const Text('Login', style: TextStyle(color: Colors.black)),
                      ),
                      const Text('|', style: TextStyle(color: Colors.black)),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => RegisterPage()),
                        ),
                        child: const Text('Sign Up', style: TextStyle(color: Colors.black)),
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

  Widget _buildPhoneTextField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.number, // Pure number keyboard
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly, // Only allow digits
        LengthLimitingTextInputFormatter(11), // Max 11 digits
      ],
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.phone, color: Color(0xFFFB81EE)),
        hintText: 'Enter Phone Number',
        hintStyle: const TextStyle(color: Colors.grey),
        helperText: 'Enter 10-11 digits (e.g., 0123456789)',
        helperStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFFB81EE)),
        hintText: 'Enter Your $label Here',
        hintStyle: const TextStyle(color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }

  Widget _buildPasswordTextField(String label, TextEditingController controller, IconData icon, bool isVisible, VoidCallback onToggle) {
    return TextField(
      controller: controller,
      obscureText: !isVisible,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFFB81EE)),
        suffixIcon: IconButton(
          icon: Icon(
            isVisible ? Icons.visibility : Icons.visibility_off,
            color: const Color(0xFFFB81EE),
          ),
          onPressed: onToggle,
        ),
        hintText: 'Enter Your $label Here',
        hintStyle: const TextStyle(color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }
}