import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'UserNavigation.dart';

class PreferencesSelectionPage extends StatefulWidget {
  const PreferencesSelectionPage({super.key});

  @override
  State<PreferencesSelectionPage> createState() => _PreferencesSelectionPageState();
}

class _PreferencesSelectionPageState extends State<PreferencesSelectionPage> with TickerProviderStateMixin {
  final List<String> availableCategories = [
    'wedding',
    'cosplay',
    'korean style'
  ];

  final Map<String, String> categoryDescriptions = {
    'wedding': 'Perfect for weddings and special ceremonies',
    'cosplay': 'Character transformations and creative looks',
    'korean style': 'K-beauty trends and natural glowing looks'
  };

  final Map<String, IconData> categoryIcons = {
    'wedding': Icons.favorite,
    'cosplay': Icons.theater_comedy,
    'korean style': Icons.auto_awesome
  };

  final Map<String, Color> categoryColors = {
    'wedding': const Color(0xFFFFB6C1),
    'cosplay': const Color(0xFF9370DB),
    'korean style': const Color(0xFFFF69B4)
  };

  Set<String> selectedPreferences = {};
  bool isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _savePreferencesAndContinue() async {
    if (selectedPreferences.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one preference'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
          'preferences': selectedPreferences.toList(),
        });

        if (mounted) {
          // Navigate back to home page or main app
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const UserNavigation(initialIndex: 0), // Or HomePage()
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving preferences: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePreference(String category) {
    setState(() {
      if (selectedPreferences.contains(category)) {
        selectedPreferences.remove(category);
      } else {
        selectedPreferences.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE8D5FF),
              Color(0xFFFFE4E6),
              Color(0xFFD4F1FF),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Header section
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFDA9BF5), Color(0xFF925F70)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDA9BF5).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.palette,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'What\'s Your Style?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Choose your makeup preferences to get\npersonalized recommendations',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Categories selection
                  const Text(
                    'Select categories you\'re interested in:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: ListView.builder(
                      itemCount: availableCategories.length,
                      itemBuilder: (context, index) {
                        final category = availableCategories[index];
                        final isSelected = selectedPreferences.contains(category);
                        final categoryColor = categoryColors[category] ?? const Color(0xFFDA9BF5);
                        final categoryIcon = categoryIcons[category] ?? Icons.category;
                        final description = categoryDescriptions[category] ?? '';

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(bottom: 16),
                          child: InkWell(
                            onTap: () => _togglePreference(category),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? categoryColor.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? categoryColor
                                      : Colors.grey.withOpacity(0.3),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? categoryColor.withOpacity(0.2)
                                        : Colors.black.withOpacity(0.05),
                                    blurRadius: isSelected ? 15 : 8,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Category icon
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? categoryColor
                                          : Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      categoryIcon,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey[600],
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Category info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? categoryColor
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          description,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Selection indicator
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? categoryColor
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? categoryColor
                                            : Colors.grey.withOpacity(0.5),
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom section
                  const SizedBox(height: 20),

                  // Selected count
                  if (selectedPreferences.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDA9BF5).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${selectedPreferences.length} preference${selectedPreferences.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                          color: Color(0xFF925F70),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Continue button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _savePreferencesAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedPreferences.isNotEmpty
                            ? const Color(0xFFDA9BF5)
                            : Colors.grey[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: selectedPreferences.isNotEmpty ? 8 : 2,
                        shadowColor: const Color(0xFFDA9BF5).withOpacity(0.3),
                      ),
                      child: isLoading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}