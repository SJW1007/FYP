import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../all user/Login.dart';
import '../makeup_artist/RegisterMakeupArtist.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  bool _isLoading = false;
  String? _errorMessage;

  Future<Map<String, bool>> checkUsernameEmailExists(String username, String email) async {
    bool usernameExists = false;
    bool emailExists = false;

    // Check username
    final usernameSnapshot = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    usernameExists = usernameSnapshot.docs.isNotEmpty;

    // Check email
    final emailSnapshot = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    emailExists = emailSnapshot.docs.isNotEmpty;

    return {
      'usernameExists': usernameExists,
      'emailExists': emailExists,
    };
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

  Future<void> _registerUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final phone_number = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Field validation
    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the name.';
        _isLoading = false;
      });
      return;
    }

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the username.';
        _isLoading = false;
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the email.';
        _isLoading = false;
      });
      return;
    }

    // Email format validation - ADD THIS
    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
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

    // Validate phone number (10-11 digits)
    if (!_isValidMalaysianPhone(phone_number)) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number (10-11 digits).';
        _isLoading = false;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the password.';
        _isLoading = false;
      });
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        _errorMessage = 'Please confirm your password.';
        _isLoading = false;
      });
      return;
    }

    // Username validation: at least 6 characters, 1 number, and 1 symbol
    final usernameRegex = RegExp(r'^(?=.*\d)(?=.*[^A-Za-z0-9]).{6,}$');
    if (!usernameRegex.hasMatch(username)) {
      setState(() {
        _errorMessage = 'Username must be at least 6 characters long, include 1 number and 1 symbol.';
        _isLoading = false;
      });
      return;
    }

    // Password validation
    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~]).{6,}$');
    if (!passwordRegex.hasMatch(password)) {
      setState(() {
        _errorMessage = 'Password must have 1 capital letter, 1 symbol, 1 number and at least 6 characters long.';
        _isLoading = false;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
        _isLoading = false;
      });
      return;
    }

    try {
      // Check if username/email exists in Firestore
      final checkResult = await checkUsernameEmailExists(username, email);

      if (checkResult['usernameExists'] ?? false) {
        setState(() {
          _errorMessage = 'Username already exists.';
          _isLoading = false;
        });
        return;
      }

      if (checkResult['emailExists'] ?? false) {
        setState(() {
          _errorMessage = 'Email already exists.';
          _isLoading = false;
        });
        return;
      }

      // Register with Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;
      const defaultProfilePicUrl = 'https://firebasestorage.googleapis.com/v0/b/fyp-makeup-artist-booking.firebasestorage.app/o/default%2Fimage%2010.png?alt=media&token=824d9761-509f-4090-a6df-96ecd61799c8';

      // Save user details to Firestore
      await _firestore.collection('users').doc(userId).set({
        'name': name,
        'username': username,
        'email': email,
        'phone number': phone_number,
        'role': 'user',
        'profile pictures': defaultProfilePicUrl,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration successful!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
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
                    'Register',
                    style: TextStyle(
                      fontSize: 28,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create an Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Georgia',
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Username Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Username', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField('Username', _usernameController, Icons.person),
                  const SizedBox(height: 15),

                  // Name Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Name', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField('Name', _nameController, Icons.badge),
                  const SizedBox(height: 15),

                  // Email Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Email', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField('Email', _emailController, Icons.email),
                  const SizedBox(height: 15),

                  // Phone Number Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Phone Number', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildPhoneTextField(), // Use special phone field
                  const SizedBox(height: 15),

                  // Password Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    'Password',
                    _passwordController,
                    Icons.lock,
                    obscureText: true,
                    isTextVisible: _passwordVisible,
                    toggleVisibility: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
                  const SizedBox(height: 15),

                  // Confirm Password Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Confirm Password', style: TextStyle(fontSize: 16, color: Colors.black)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    'Confirm Password',
                    _confirmPasswordController,
                    Icons.lock,
                    obscureText: true,
                    isTextVisible: _confirmPasswordVisible,
                    toggleVisibility: () {
                      setState(() {
                        _confirmPasswordVisible = !_confirmPasswordVisible;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_errorMessage!, style: TextStyle(color: Colors.red)),
                    ),

                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                    onPressed: _registerUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC367CA),
                      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
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
                          MaterialPageRoute(builder: (context) => RegisterMakeupArtistPage()),
                        ),
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

  // Simple phone number text field
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

  Widget _buildTextField(
      String label,
      TextEditingController controller,
      IconData icon, {
        bool obscureText = false,
        VoidCallback? toggleVisibility,
        bool isTextVisible = false,
      }) {
    return TextField(
      controller: controller,
      obscureText: obscureText && !isTextVisible,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Color(0xFFFB81EE)),
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
        suffixIcon: obscureText
            ? IconButton(
          icon: Icon(
            isTextVisible ? Icons.visibility : Icons.visibility_off,
            color: Color(0xFFFB81EE), // Changed to pink color
          ),
          onPressed: toggleVisibility,
        )
            : null,
      ),
    );
  }
}