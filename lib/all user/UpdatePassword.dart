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


  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

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
          Image.asset('assets/image_4.png', fit: BoxFit.cover),
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
                                fontFamily: 'Georgia',
                              ),
                            ),
                            const SizedBox(height: 30),
                            _buildPasswordField(
                              "New Password",
                              "Enter Your Password Here",
                              _newPasswordController,
                              _newPasswordVisible,
                                  () {
                                setState(() {
                                  _newPasswordVisible = !_newPasswordVisible;
                                });
                              },
                            ),

                            const SizedBox(height: 20),
                            _buildPasswordField(
                              "Confirm New Password",
                              "Confirm Your Password Here",
                              _confirmPasswordController,
                              _confirmPasswordVisible,
                                  () {
                                setState(() {
                                  _confirmPasswordVisible =
                                  !_confirmPasswordVisible;
                                });
                              },
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
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                  color: Colors.white)
                                  : const Text(
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
        ],
      ),
    );
  }

  Widget _buildPasswordField(String label,
      String hint,
      TextEditingController controller,
      bool isVisible,
      VoidCallback onToggleVisibility,) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
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
            controller: controller,
            obscureText: !isVisible,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock, color: Color(0xFFFB81EE)),
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              suffixIcon: IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFFFB81EE),
                ),
                onPressed: onToggleVisibility,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

