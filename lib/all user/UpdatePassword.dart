import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UpdatePasswordPage extends StatefulWidget {
  const UpdatePasswordPage({super.key});

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  String? userRole;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            userRole = userDoc.data()?['role'] as String?;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching user role: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getBackgroundImage() {
    if (userRole == 'makeup artist' || userRole == 'admin') {
      return 'assets/purple_background.png';
    }
    return 'assets/image_4.png';
  }

  Future<void> _updatePassword() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorMessage = "Please fill in both fields.");
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~]).{6,}$');
    if (!passwordRegex.hasMatch(newPassword)) {
      setState(() {
        _errorMessage = 'Password must have at least 1 capital letter, 1 symbol, 1 number and at least 6 characters.';
      });
      return;
    }

    try {
      setState(() => _isLoading = true);
      final user = _auth.currentUser;
      if (user != null) {
        await user.updatePassword(newPassword);
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password updated successfully.")),
        );

        Navigator.of(context).pop(); // Go back settings page
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "Something went wrong.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            _getBackgroundImage(),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Column(
              children: [
                // Back button
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(
                        Icons.arrow_back, color: Colors.black, size: 26),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: SizedBox(
                      height: MediaQuery
                          .of(context)
                          .size
                          .height * 0.75, // Adjust if needed
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "Update Password",
                              style: TextStyle(
                                fontSize: 32,
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Georgia',
                              ),
                            ),
                            const SizedBox(height: 30),

                            // New Password Field (inlined)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "New Password",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontFamily: 'Georgia',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: const Color(0xFFFB81EE), width: 1.5),
                                  ),
                                  child: TextField(
                                    controller: _newPasswordController,
                                    obscureText: !_newPasswordVisible,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.lock, color: Color(0xFFFB81EE)),
                                      hintText: "Enter Your Password Here",
                                      hintStyle: const TextStyle(color: Colors.grey),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _newPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                          color: const Color(0xFFFB81EE),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _newPasswordVisible = !_newPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Confirm Password Field (inlined)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Confirm New Password",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    fontFamily: 'Georgia',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: const Color(0xFFFB81EE), width: 1.5),
                                  ),
                                  child: TextField(
                                    controller: _confirmPasswordController,
                                    obscureText: !_confirmPasswordVisible,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.lock, color: Color(0xFFFB81EE)),
                                      hintText: "Confirm Your Password Here",
                                      hintStyle: const TextStyle(color: Colors.grey),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _confirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                          color: const Color(0xFFFB81EE),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _confirmPasswordVisible = !_confirmPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),
                            if (_errorMessage != null)
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 14),
                              ),
                            if (_successMessage != null)
                              Text(
                                _successMessage!,
                                style: const TextStyle(
                                    color: Colors.green, fontSize: 14),
                              ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _updatePassword,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDA6AE7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 60),
                              ),
                              child:const Text(
                                "Confirm",
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading) Container(
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
                    // Animated dots
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
          ),
        ],
      ),
    );
  }

  // Widget _buildPasswordField(String label,
  //     String hint,
  //     TextEditingController controller,
  //     bool isVisible,
  //     VoidCallback onToggleVisibility,) {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.start,
  //     children: [
  //       Text(
  //         label,
  //         style: const TextStyle(
  //           fontSize: 18,
  //           fontWeight: FontWeight.w600,
  //           color: Colors.black87,
  //           fontFamily: 'Georgia',
  //         ),
  //       ),
  //       const SizedBox(height: 8),
  //       Container(
  //         decoration: BoxDecoration(
  //           borderRadius: BorderRadius.circular(30),
  //           border: Border.all(color: const Color(0xFFFB81EE), width: 1.5),
  //         ),
  //         child: TextField(
  //           controller: controller,
  //           obscureText: !isVisible,
  //           decoration: InputDecoration(
  //             prefixIcon: const Icon(Icons.lock, color: Color(0xFFFB81EE)),
  //             hintText: hint,
  //             hintStyle: const TextStyle(color: Colors.grey),
  //             border: InputBorder.none,
  //             contentPadding: const EdgeInsets.symmetric(vertical: 14),
  //             suffixIcon: IconButton(
  //               icon: Icon(
  //                 isVisible ? Icons.visibility : Icons.visibility_off,
  //                 color: const Color(0xFFFB81EE),
  //               ),
  //               onPressed: onToggleVisibility,
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }
}

