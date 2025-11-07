import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'Login.dart';
import 'EmailVerificationPage.dart';
import 'Policy.dart';

class RegisterPage extends StatefulWidget {
  final String role; // 'User' or 'MakeupArtist'

  const RegisterPage({super.key, required this.role});

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
  bool _agreedToPolicy = false;

  bool _isLoading = false;
  String? _errorMessage;

  Future<Map<String, bool>> checkUsernameEmailExists(String username, String email, String phoneNumber) async {
    bool usernameExists = false;
    bool emailExists = false;
    bool phoneExists = false;

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

    final phoneSnapshot = await _firestore
        .collection('users')
        .where('phone number', isEqualTo: phoneNumber)
        .limit(1)
        .get();
    phoneExists = phoneSnapshot.docs.isNotEmpty;

    return {
      'usernameExists': usernameExists,
      'emailExists': emailExists,
      'phoneExists': phoneExists
    };
  }

  bool _isValidMalaysianPhone(String phone) {
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.length >= 10 && digitsOnly.length <= 11;
  }

  bool _isValidEmail(String email) {
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

    // Check if policy is agreed
    if (!_agreedToPolicy) {
      setState(() {
        _errorMessage = 'You must agree to the Terms and Privacy Policies to continue.';
        _isLoading = false;
      });
      return;
    }

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

    final usernameRegex = RegExp(r'^(?=.*\d)(?=.*[^A-Za-z0-9]).{6,}$');
    if (!usernameRegex.hasMatch(username)) {
      setState(() {
        _errorMessage = 'Username must be at least 6 characters long, include 1 number and 1 symbol.';
        _isLoading = false;
      });
      return;
    }

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
      final checkResult = await checkUsernameEmailExists(username, email, phone_number);

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

      if (checkResult['phoneExists'] ?? false) {
        setState(() {
          _errorMessage = 'Phone Number already exists.';
          _isLoading = false;
        });
        return;
      }

      // Register with Firebase Auth
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Navigate to email verification page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EmailVerificationPage(
            email: email,
            name: name,
            username: username,
            phoneNumber: phone_number,
            role: widget.role,
          ),
        ),
      );

    } on FirebaseAuthException catch (e) {
      // If there's an error, clean up the auth account
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        try {
          await currentUser.delete();  // ✅ Only delete auth user, no Firestore record exists yet
        } catch (cleanupError) {
          print('Error cleaning up after failed registration: $cleanupError');
        }
      }

      setState(() {
        _errorMessage = e.message;
      });
    }catch (e) {
      // Handle any other errors
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        try {
          await currentUser.delete();  // Only delete auth user, no Firestore record exists yet
        } catch (cleanupError) {
          print('Error cleaning up after failed registration: $cleanupError');
        }
      }

      setState(() {
        _errorMessage = 'An error occurred during registration. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if registering as makeup artist
    bool isMakeupArtist = widget.role == 'MakeupArtist';

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
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.06,
                vertical: MediaQuery.of(context).size.height * 0.05,
              ),
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    isMakeupArtist ? 'Register as Makeup Artist' : 'Register',
                    style: const TextStyle(
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
                  _buildPhoneTextField(),
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

                  // Policy Agreement Checkbox
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _errorMessage != null && !_agreedToPolicy
                            ? Colors.red
                            : const Color(0xFFFB81EE),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _agreedToPolicy,
                          onChanged: (value) {
                            setState(() {
                              _agreedToPolicy = value ?? false;
                              if (_agreedToPolicy) _errorMessage = null;
                            });
                          },
                          activeColor: const Color(0xFFC367CA),
                          checkColor: Colors.white,
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _agreedToPolicy = !_agreedToPolicy;
                                if (_agreedToPolicy) _errorMessage = null;
                              });
                            },
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const PolicyAgreementPage(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'Terms and Privacy Policies',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFC367CA),
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_errorMessage!, style: TextStyle(color: Colors.red)),
                    ),

                  ElevatedButton(
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
                          MaterialPageRoute(
                            builder: (context) => RegisterPage(
                              role: isMakeupArtist ? 'User' : 'MakeupArtist',
                            ),
                          ),
                        ),
                        child: Text(
                          isMakeupArtist ? 'Sign Up As User' : 'Sign Up As Makeup Artist',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading) _buildLoading(),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDA9BF5)),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Processing...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 600 + (index * 200)),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: Color(0xFFDA9BF5).withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneTextField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
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
            color: Color(0xFFFB81EE),
          ),
          onPressed: toggleVisibility,
        )
            : null,
      ),
    );
  }
}