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
  bool _showAllReviews = false;

  // New variables to store rating data from database
  double averageRating = 0.0;
  int totalReviews = 0;

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

        // DEBUG: Check rating fields
        if (data['average_rating'] != null) {
          print('Average rating type: ${data['average_rating'].runtimeType}');
          print('Average rating data: ${data['average_rating']}');
        }

        if (data['total_reviews'] != null) {
          print('Total reviews type: ${data['total_reviews'].runtimeType}');
          print('Total reviews data: ${data['total_reviews']}');
        }

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

        // DEBUG: Check category structure
        if (data['category'] != null) {
          print('Category type: ${data['category'].runtimeType}');
          print('Category data: ${data['category']}');
        }

        // DEBUG: Check price structure
        if (data['price'] != null) {
          print('Price type: ${data['price'].runtimeType}');
          print('Price data: ${data['price']}');
        }

        print('=== END DEBUG ===');

        setState(() {
          makeupArtistData = data;
          // Extract rating data from database
          averageRating = (data['average_rating'] ?? 0).toDouble();
          totalReviews = (data['total_reviews'] ?? 0).toInt();
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

  // Helper method to format categories and prices
  List<String> _getCategoriesWithPrices() {
    List<String> result = [];

    if (makeupArtistData == null ||
        makeupArtistData!['category'] == null ||
        makeupArtistData!['price'] == null) {
      return ['N/A'];
    }

    final categories = makeupArtistData!['category'];
    final prices = makeupArtistData!['price'];

    if (categories is List && prices is Map<String, dynamic>) {
      for (var category in categories) {
        String categoryStr = category.toString();
        String price = prices[categoryStr]?.toString() ?? 'Price not set';
        result.add('$categoryStr    $price');
      }
    }

    return result.isEmpty ? ['N/A'] : result;
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

  // Helper method to get reviews
  Future<List<Map<String, dynamic>>> _getReviews() async {
    if (makeupArtistData == null) return [];

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return [];

      print('Looking for reviews for user ID: $currentUserId');

      // Step 1: First, find the makeup_artists document where user_id equals current user
      final makeupArtistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: FirebaseFirestore.instance.collection('users').doc(currentUserId))
          .get();

      if (makeupArtistQuery.docs.isEmpty) {
        print('No makeup artist document found for current user');
        return [];
      }

      // Get the makeup_artist document ID
      final makeupArtistDocId = makeupArtistQuery.docs.first.id;
      print('Found makeup artist doc ID: $makeupArtistDocId');

      // Step 2: Query reviews using the makeup_artist document reference
      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('artist_id', isEqualTo: FirebaseFirestore.instance.collection('makeup_artists').doc(makeupArtistDocId))
          .orderBy('timestamp', descending: true)
          .get();

      print('Found ${reviewsQuery.docs.length} reviews');

      final reviews = <Map<String, dynamic>>[];

      for (final doc in reviewsQuery.docs) {
        final reviewData = doc.data();
        print('Review data: $reviewData');

        // Get customer name and profile picture from customer_id reference
        String customerName = 'Anonymous';
        String customerImage = '';

        if (reviewData['customer_id'] != null) {
          try {
            dynamic customerId = reviewData['customer_id'];
            DocumentSnapshot customerDoc;

            if (customerId is DocumentReference) {
              customerDoc = await customerId.get();
            } else if (customerId is String) {
              customerDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(customerId)
                  .get();
            } else {
              throw Exception('Invalid customer_id format');
            }

            if (customerDoc.exists) {
              final customerData = customerDoc.data() as Map<String, dynamic>?;
              customerName = customerData?['name'] ?? customerData?['full_name'] ?? 'Anonymous';
              customerImage = customerData?['profile pictures'] ?? '';
            }
          } catch (e) {
            print('Error fetching customer name: $e');
          }
        }

        reviews.add({
          'id': doc.id,
          'rating': reviewData['rating'] ?? 0,
          'comment': reviewData['review_text'] ?? reviewData['comment'] ?? reviewData['review'] ?? '',
          'user_name': customerName,
          'profile_picture': customerImage,
          'created_at': reviewData['timestamp'],
          'images': reviewData['images'] ?? [],
        });
      }

      return reviews;
    } catch (e) {
      print('Error loading reviews: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  isMakeupArtist
                      ? 'assets/purple_background.png'
                      : 'assets/image_4.png',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
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
                            return const Icon(Icons.person, size: 60, color: Colors.purple);
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name display
                    Text(
                      isMakeupArtist && makeupArtistData != null
                          ? (makeupArtistData!['studio_name'] ?? 'N/A')
                          : (userData!['name'] ?? 'N/A'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),

                    // Contact info for makeup artists
                    if (isMakeupArtist && makeupArtistData != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone, size: 16, color: Color(0xFF923DC3)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '0${makeupArtistData!['phone_number'].toString()}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.email, size: 16, color: Color(0xFF923DC3)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              makeupArtistData!['email'] ?? 'N/A',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
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
                      _buildReviewsSection(),
                      const SizedBox(height: 24),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // Settings button positioned absolutely
          Positioned(
            top: 36,
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
              icon: const Icon(Icons.settings, color: Color(0xFF474545), size: 40),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
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
        backgroundColor: const Color(0xFFDA9BF5),
        child: const Icon(Icons.edit, color: Colors.white),
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
        profileInfoRow(
          Icons.phone,
          'Phone Number',
          userData!['phone number'] != null
              ? '0${userData!['phone number']}'
              : 'N/A',
        ),
        const SizedBox(height: 16),
        profileInfoRow(Icons.email, 'Email', userData!['email'] ?? 'N/A'),
      ],
    );
  }

  Widget _buildMakeupArtistInfo() {
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
          _buildCategoryAndPriceTile(),
          _buildInfoTile('Working Hour', _formatWorkingHour()),
          _buildInfoTile('Working Day', _formatWorkingDay()),
          _buildInfoTile('Time Slot', _getFormattedTimeSlot()),
          _buildInfoTile('About', makeupArtistData!['about'] ?? 'N/A', isLongText: true),
        ],
      ),
    );
  }

  Widget _buildCategoryAndPriceTile() {
    List<String> categoriesWithPrices = _getCategoriesWithPrices();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 120,
            child: Text(
              'Category & Prices',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: categoriesWithPrices.map((categoryPrice) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    categoryPrice,
                    style: const TextStyle(fontSize: 14),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                );
              }).toList(),
            ),
          ),
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
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              softWrap: true,
              overflow: TextOverflow.visible,
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
            return GestureDetector( // ADD THIS
              onTap: () => _showImageDialog(
                context,
                portfolioImages[index],
              ), // ADD THIS
              child: Container(
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
                              color: Colors.purple, size: 40),
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
              ),
            ); // ADD THIS
          },
        ),
      ],
    );
  }

  Widget _buildReviewsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getReviews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reviews = snapshot.data ?? [];

        final displayedReviews = _showAllReviews
            ? reviews
            : reviews.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with average rating - NOW USING DATABASE VALUES
            Row(
              children: [
                const Text(
                  'Reviews',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (totalReviews > 0)
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '${averageRating.toStringAsFixed(1)} ($totalReviews)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Reviews list
            reviews.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No reviews yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            )
                : Column(
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedReviews.length,
                  itemBuilder: (context, index) {
                    final review = displayedReviews[index];
                    final reviewImages = review['images'] as List<dynamic>? ?? [];
                    final displayImages = reviewImages.take(6).toList();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // User info and rating
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFFFFE4B5),
                                  backgroundImage:
                                  review['profile_picture'] != null &&
                                      review['profile_picture'].isNotEmpty
                                      ? NetworkImage(review['profile_picture'])
                                      : null,
                                  child: review['profile_picture'] == null ||
                                      review['profile_picture'].isEmpty
                                      ? const Icon(Icons.person, size: 20)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        review['user_name'] ?? 'Anonymous',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Row(
                                        children: List.generate(
                                          5,
                                              (i) => Icon(
                                            Icons.star,
                                            size: 16,
                                            color: i < (review['rating'] ?? 0)
                                                ? Colors.amber
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Comment
                            const SizedBox(height: 12),
                            Text(
                              review['comment'] != null && review['comment'].isNotEmpty
                                  ? review['comment']
                                  : 'This customer had a wonderful experience with the makeup artist!',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: review['comment'] != null && review['comment'].isNotEmpty
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                                color: review['comment'] != null && review['comment'].isNotEmpty
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),

                            // Review Images
                            if (displayImages.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 80,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: displayImages.length,
                                  itemBuilder: (context, imageIndex) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        right: imageIndex < displayImages.length - 1 ? 8 : 0,
                                      ),
                                      child: GestureDetector(
                                        onTap: () => _showImageDialog(context, displayImages[imageIndex].toString()),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade300),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              displayImages[imageIndex].toString(),
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Center(
                                                    child: Icon(Icons.image_not_supported,
                                                        color: Colors.grey, size: 24),
                                                  ),
                                                );
                                              },
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return Container(
                                                  color: Colors.grey.shade200,
                                                  child: const Center(
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Centered Show More / Show Less
                if (reviews.length > 3)
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllReviews = !_showAllReviews;
                        });
                      },
                      child: Text(_showAllReviews ? 'Show Less' : 'Show More'),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _formatDate(dynamic timestamp) {
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return '';
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black87,
                  ),
                ),

                Center(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error, size: 48, color: Colors.red),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.red, fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            padding: const EdgeInsets.all(40),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 40,
                  right: 20,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              spreadRadius: 1,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Tap outside or X to close • Pinch to zoom',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget profileInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                overflow: TextOverflow.fade,
                softWrap: true,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ],
    );
  }
}