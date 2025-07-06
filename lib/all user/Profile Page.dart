import 'package:blush_up/all%20user/Settings.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'EditProfile.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? userData;
  Map<String, dynamic>? makeupArtistData;
  bool isMakeupArtist = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // Load basic user data
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          userData = userDoc.data();
          // Check if user is a makeup artist based on user type or role field
          isMakeupArtist = userData!['role'] == 'makeup artist';
        });

        // If user is a makeup artist, load makeup artist specific data
        if (isMakeupArtist) {
          await _loadMakeupArtistData(user.uid);
        }
      }
    }
  }

  Future<void> _loadMakeupArtistData(String userId) async {
    try {
      // Query makeup_artist collection where user_id reference equals current user id
      final makeupArtistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: FirebaseFirestore.instance.collection('users').doc(userId))
          .get();

      if (makeupArtistQuery.docs.isNotEmpty) {
        final data = makeupArtistQuery.docs.first.data();

        // DEBUG: Print all makeup artist data
        print('=== MAKEUP ARTIST DATA DEBUG ===');
        print('Full data: $data');

        // DEBUG: Check working day structure
        if (data['working day'] != null) {
          print('Working day type: ${data['working day'].runtimeType}');
          print('Working day data: ${data['working day']}');
        }

        // DEBUG: Check working hour structure
        if (data['working hour'] != null) {
          print('Working hour type: ${data['working hour'].runtimeType}');
          print('Working hour data: ${data['working hour']}');
        }

        // DEBUG: Check portfolio structure
        if (data['portfolio'] != null) {
          print('Portfolio type: ${data['portfolio'].runtimeType}');
          print('Portfolio data: ${data['portfolio']}');
        }

        // DEBUG: Check time slots if they exist
        if (data['time_slots'] != null) {
          print('Time slots type: ${data['time_slots'].runtimeType}');
          print('Time slots data: ${data['time_slots']}');
        }

        print('=== END DEBUG ===');

        setState(() {
          makeupArtistData = data;
        });
      }
    } catch (e) {
      print('Error loading makeup artist data: $e');
    }
  }

  // Helper method to format working day from nested map
  String _formatWorkingDay() {
    if (makeupArtistData == null || makeupArtistData!['working day'] == null) {
      return 'N/A';
    }

    final workingDay = makeupArtistData!['working day'];
    if (workingDay is Map<String, dynamic>) {
      final from = workingDay['From'] ?? '';
      final to = workingDay['To'] ?? '';
      return '$from - $to';
    }

    return workingDay.toString();
  }

  // Helper method to format working hour
  String _formatWorkingHour() {
    if (makeupArtistData == null || makeupArtistData!['working hour'] == null) {
      return 'N/A';
    }

    final workingHour = makeupArtistData!['working hour'];
    if (workingHour is String) {
      return workingHour;
    } else if (workingHour is Map<String, dynamic>) {
      // Handle if working hour is also a map structure
      return workingHour.toString();
    }

    return workingHour.toString();
  }

  // Helper method to get portfolio images
  List<String> _getPortfolioImages() {
    if (makeupArtistData == null || makeupArtistData!['portfolio'] == null) {
      return [];
    }

    final portfolio = makeupArtistData!['portfolio'];
    if (portfolio is List) {
      return portfolio.map((item) => item.toString()).toList();
    }

    return [];
  }

  // Helper method to get time slots formatted as "x person x hour"
  String _getFormattedTimeSlot() {
    if (makeupArtistData == null || makeupArtistData!['time slot'] == null) {
      return 'N/A';
    }

    final timeSlot = makeupArtistData!['time slot'];

    if (timeSlot is Map<String, dynamic>) {
      final hour = timeSlot['hour'] ?? 0;
      final person = timeSlot['person'] ?? 0;
      return '$hour hour $person person';
    }

    return timeSlot.toString();
  }

  TimeOfDay? _parseTimeOfDay(String? timeString) {
    if (timeString == null || timeString.isEmpty) return null;

    try {
      // Clean the string and handle different formats
      String cleanTime = timeString.trim();
      bool isPM = cleanTime.toUpperCase().contains('PM');
      bool isAM = cleanTime.toUpperCase().contains('AM');

      // Remove AM/PM and clean up
      cleanTime = cleanTime.replaceAll(RegExp(r'\s*(AM|PM|am|pm)\s*'), '').trim();

      // Split by colon
      final parts = cleanTime.split(':');
      if (parts.length != 2) return null;

      int hour = int.parse(parts[0].trim());
      int minute = int.parse(parts[1].trim());

      // Handle 12-hour format conversion
      if (isPM && hour != 12) {
        hour += 12;
      } else if (isAM && hour == 12) {
        hour = 0;
      }

      // Validate hour and minute ranges
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return null;
      }

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print('Error parsing time: $timeString, Error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: userData == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
          children: [
            // Conditional background based on user role
            if (isMakeupArtist)
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/purple_background.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Image.asset(
                'assets/image_4.png',
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.transparent,
                      child: ClipOval(
                        child: Image.network(
                          userData!['profile pictures'] ?? '',
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.person, size: 60, color: Colors.grey);
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name display - FIXED: Handle null makeupArtistData
                    Text(
                      isMakeupArtist && makeupArtistData != null
                          ? (makeupArtistData!['studio_name'] ?? 'N/A')
                          : (userData!['name'] ?? 'N/A'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Contact info for makeup artists - FIXED: Handle null makeupArtistData
                    if (isMakeupArtist && makeupArtistData != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone, size: 16),
                          const SizedBox(width: 4),
                          Text(makeupArtistData!['phone_number'] ?? 'N/A'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.email, size: 16),
                          const SizedBox(width: 4),
                          Text(makeupArtistData!['email'] ?? 'N/A'),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    const Divider(thickness: 1),
                    const SizedBox(height: 16),

                    // Different content based on user type
                    if (isMakeupArtist)
                      _buildMakeupArtistInfo()
                    else
                      _buildRegularUserInfo(),

                    const SizedBox(height: 24),

                    // Portfolio section for makeup artists
                    if (isMakeupArtist && makeupArtistData != null) ...[
                      _buildPortfolioSection(),
                      const SizedBox(height: 24),
                    ],

                    // Edit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          String userTypeString = userData!['role'] ?? 'user';
                          UserType userType = userTypeString == 'makeup artist'
                              ? UserType.makeupArtist
                              : UserType.user;

                          // Helper function to parse working day
                          String? getWorkingDayFrom() {
                            if (makeupArtistData?['working day'] is Map<String, dynamic>) {
                              return makeupArtistData!['working day']['From'];
                            }
                            return null;
                          }

                          String? getWorkingDayTo() {
                            if (makeupArtistData?['working day'] is Map<String, dynamic>) {
                              return makeupArtistData!['working day']['To'];
                            }
                            return null;
                          }

                          // Helper function to parse time slot
                          String? getWorkingSlotHour() {
                            if (makeupArtistData?['time slot'] is Map<String, dynamic>) {
                              final hour = makeupArtistData!['time slot']['hour'];
                              return '$hour Hour${hour > 1 ? 's' : ''}';
                            }
                            return null;
                          }

                          String? getWorkingSlotPerson() {
                            if (makeupArtistData?['time slot'] is Map<String, dynamic>) {
                              final person = makeupArtistData!['time slot']['person'];
                              if (person == 1) return '1 Person';
                              if (person == 2) return '2 Persons';
                              if (person == 3) return '3 Persons';
                              if (person == 4) return '4 Persons';
                              return '6+ Persons';
                            }
                            return null;
                          }

                          // Helper function to parse working hour to start/end time
                          TimeOfDay? getStartTime() {
                            final workingHour = makeupArtistData?['working hour'];
                            if (workingHour is String) {
                              // Assuming format like "10:00 AM - 7:00 PM"
                              final parts = workingHour.split(' - ');
                              if (parts.isNotEmpty) {
                                return _parseTimeOfDay(parts[0].trim());
                              }
                            }
                            return null;
                          }

                          TimeOfDay? getEndTime() {
                            final workingHour = makeupArtistData?['working hour'];
                            if (workingHour is String) {
                              // Assuming format like "10:00 AM - 7:00 PM
                              final parts = workingHour.split(' - ');
                              if (parts.length > 1) {
                                return _parseTimeOfDay(parts[1].trim());
                              }
                            }
                            return null;
                          }

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditProfilePage(
                                name: userData!['name'] ?? '',
                                phone: userData!['phone number'] ?? '',
                                profilePicture: userData!['profile pictures'] ?? '',
                                userType: userType,
                                // Pass makeup artist data from makeupArtistData instead of userData
                                studioName: userType == UserType.makeupArtist ? makeupArtistData!['studio_name'] : null,
                                artistPhone: userType == UserType.makeupArtist ? makeupArtistData!['phone_number'] : null,
                                artistEmail: userType == UserType.makeupArtist ? makeupArtistData!['email'] : null,
                                address: userType == UserType.makeupArtist ? makeupArtistData!['address'] : null,
                                about: userType == UserType.makeupArtist ? makeupArtistData!['about'] : null,
                                startTime: userType == UserType.makeupArtist ? getStartTime() : null,
                                endTime: userType == UserType.makeupArtist ? getEndTime() : null,
                                workingDayFrom: userType == UserType.makeupArtist ? getWorkingDayFrom() : null,
                                workingDayTo: userType == UserType.makeupArtist ? getWorkingDayTo() : null,
                                workingSlotHour: userType == UserType.makeupArtist ? getWorkingSlotHour() : null,
                                workingSlotPerson: userType == UserType.makeupArtist ? getWorkingSlotPerson() : null,
                                category: userType == UserType.makeupArtist ? makeupArtistData!['category'] : null,
                                price: userType == UserType.makeupArtist ? makeupArtistData!['price'] : null,
                                portfolioImages: userType == UserType.makeupArtist ? _getPortfolioImages() : null,
                              ),
                            ),
                          );

                          if (result == true) {
                            await _loadUserData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Profile updated successfully!')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDA9BF5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Edit',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings, color: Color(0xFFF4B92F), size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularUserInfo() {
    return Column(
      children: [
        profileInfoRow(Icons.edit, 'Username', userData!['username'] ?? 'N/A'),
        const SizedBox(height: 16),
        profileInfoRow(Icons.person, 'Name', userData!['name'] ?? 'N/A'),
        const SizedBox(height: 16),
        profileInfoRow(Icons.phone, 'Phone Number', userData!['phone number'] ?? 'N/A'),
        const SizedBox(height: 16),
        profileInfoRow(Icons.email, 'Email', userData!['email'] ?? 'N/A'),
      ],
    );
  }

  Widget _buildMakeupArtistInfo() {
    // Show loading indicator if makeup artist data is still loading
    if (makeupArtistData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.purple.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildInfoTile('Address', makeupArtistData!['address'] ?? 'N/A'),
          _buildInfoTile('Category', makeupArtistData!['category'] ?? 'N/A'),
          _buildInfoTile('Working Hour', _formatWorkingHour()),
          _buildInfoTile('Working Day', _formatWorkingDay()),
          _buildInfoTile('Price', makeupArtistData!['price'] ?? 'N/A'),
          _buildInfoTile('Time Slot', _getFormattedTimeSlot()),
          _buildInfoTile('About', makeupArtistData!['about'] ?? 'N/A', isLongText: true),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, {bool isLongText = false, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: isLongText ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSection() {
    List<String> portfolioImages = _getPortfolioImages();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Portfolio:',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        portfolioImages.isEmpty
            ? const Center(
          child: Text(
            'No portfolio images available',
            style: TextStyle(color: Colors.grey),
          ),
        )
            : GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: portfolioImages.length,
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  portfolioImages[index],
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.image_not_supported,
                            color: Colors.grey, size: 40),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget profileInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      ],
    );
  }
}