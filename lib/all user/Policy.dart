import 'package:flutter/material.dart';

class PolicyAgreementPage extends StatelessWidget {
  const PolicyAgreementPage({super.key});

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
          SafeArea(
            child: Column(
              children: [
                // Back Button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width * 0.06,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Terms and Privacy Policies',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please read our terms and privacy policies carefully before using the app.',
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Georgia',
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // Policy Content Container
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFB81EE), width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildPolicySection(
                                  '1. Acceptance of Terms',
                                  'By using our makeup artist booking app, you agree to these terms and conditions. If you do not agree, please do not use our services.',
                                ),
                                _buildPolicySection(
                                  '2. User Accounts',
                                  'You are responsible for maintaining the confidentiality of your account credentials. You must provide accurate and complete information during registration.',
                                ),
                                _buildPolicySection(
                                  '3. Booking Services',
                                  'All bookings are subject to availability and must be made at least 3 days in advance. Bookings are arranged directly between users and makeup artists through the app.',
                                ),
                                _buildPolicySection(
                                  '4. Makeup Artist Responsibilities',
                                  'Makeup artists must provide professional services as described. They must maintain valid certifications and comply with health and safety regulations.',
                                ),
                                _buildPolicySection(
                                  '5. User Conduct',
                                  'Users must treat makeup artists with respect. Any abusive behavior, harassment, or inappropriate conduct will result in account suspension or termination.',
                                ),
                                _buildPolicySection(
                                  '6. Privacy and Information Sharing',
                                  'We collect and store your personal information (name, email, phone number, username) securely. When you book a makeup artist, your contact information and booking details will be shared with the artist to facilitate the service. We do not share your information with other third parties without your consent.',
                                ),
                                _buildPolicySection(
                                  '7. Cancellation',
                                  'Cancellations must be made at least 3 days before the scheduled appointment.',
                                ),
                                _buildPolicySection(
                                  '8. Liability',
                                  'We are not liable for any damages or injuries resulting from services provided by makeup artists. Users book services at their own risk.',
                                ),
                                _buildPolicySection(
                                  '9. Intellectual Property',
                                  'All content on the app, including logos, text, and images, is protected by copyright. Unauthorized use is prohibited.',
                                ),
                                _buildPolicySection(
                                  '10. Changes to Terms',
                                  'We reserve the right to modify these terms at any time. Continued use of the app constitutes acceptance of updated terms.',
                                ),
                                _buildPolicySection(
                                  '11. Image Search Privacy',
                                  'When using the image-based search feature, the uploaded images are processed temporarily and are not stored permanently in our system. These images are used only to identify matching makeup styles and are deleted immediately after the search is completed.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
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

  Widget _buildPolicySection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFFC367CA),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}