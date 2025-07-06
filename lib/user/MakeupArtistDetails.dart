import 'BookAppointment.dart';
import 'AllReviewsPage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MakeupArtistDetailsPage extends StatelessWidget {
  final String userId;
  const MakeupArtistDetailsPage({super.key, required this.userId});

  Future<Map<String, dynamic>?> fetchArtistDetails(String userId) async {
    try {
      // 1. Fetch from 'users' collection
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final userData = userDoc.data()!;
      final userRef = FirebaseFirestore.instance.doc('users/$userId');

      // 2. Fetch from 'makeup_artists' where user_id is reference to this user
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return null;

      final artistData = artistQuery.docs.first.data();

      // 3. Fetch reviews for this artist
      final reviewsData = await fetchReviews(userId);

      // Combine user and artist data
      return {
        'name': artistData['studio_name'] ?? 'N/A',
        'email': artistData['email'] ?? 'N/A',
        'phone': artistData['phone_number'] ?? 'N/A',
        'profile pictures': userData['profile pictures'] ?? '',
        'category': artistData['category'] ?? 'N/A',
        'address': artistData['address'] ?? 'N/A',
        'price': artistData['price'] ?? 'N/A',
        'working_day': artistData['working day'] is Map
            ? Map<String, String>.from(artistData['working day'])
            : {},
        'working_hour': artistData['working hour'] ?? 'N/A',
        'about': artistData['about'] ?? 'N/A',
        'portfolio': List<String>.from(artistData['portfolio'] ?? []),
        'reviews': reviewsData['reviews'],
        'average_rating': reviewsData['average_rating'],
        'total_reviews': reviewsData['total_reviews'],
      };
    } catch (e) {
      print('Error fetching artist details: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchReviews(String artistUserId) async {
    try {
      final userRef = FirebaseFirestore.instance.doc('users/$artistUserId');

      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) {
        throw Exception("Artist not found for user $artistUserId");
      }

      final artistDocRef = artistQuery.docs.first.reference;

      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('artist_id', isEqualTo: artistDocRef)
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> reviews = [];
      double totalRating = 0.0;
      int totalReviews = reviewsQuery.docs.length;
      for (var doc in reviewsQuery.docs) {
        final reviewData = doc.data();
        final customerRef = reviewData['customer_id'] as DocumentReference?;

        String customerName = 'Anonymous';
        String profilePicture = '';

        if (customerRef != null) {
          final customerDoc = await customerRef.get();
          if (customerDoc.exists) {
            final customerData = customerDoc.data() as Map<String, dynamic>;
            customerName = customerData['name'] ?? 'Anonymous';
            profilePicture = customerData['profile pictures'] ?? '';
          }
        }
        reviews.add({
          'id': doc.id,
          'rating': reviewData['rating'] ?? 0,
          'comment': reviewData['review_text'] ?? '',
          'customer_name': customerName,
          'customer_profile': profilePicture,
          'created_at': reviewData['timestamp'],
        });
        totalRating += (reviewData['rating'] ?? 0).toDouble();
      }
      double averageRating = totalReviews > 0 ? totalRating / totalReviews : 0.0;

      return {
        'reviews': reviews,
        'average_rating': averageRating,
        'total_reviews': totalReviews,
      };
    } catch (e) {
      print('Error fetching reviews: $e');
      return {
        'reviews': <Map<String, dynamic>>[],
        'average_rating': 0.0,
        'total_reviews': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: fetchArtistDetails(userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return const Center(child: Text("User data not found"));
            }

            final userData = snapshot.data!;
            final name = userData['name'] ?? 'N/A';
            final email = userData['email'] ?? 'N/A';
            final phone = userData['phone'] ?? 'N/A';
            final profilePicture = userData['profile pictures'] ?? '';
            final category = userData['category'] ?? 'N/A';
            final address = userData['address'] ?? 'N/A';
            final price = userData['price'] ?? 'N/A';
            final workingDayMap = userData['working_day'] as Map<String, String>? ?? {};
            final workingDayText = workingDayMap.isNotEmpty
                ? '${workingDayMap['From'] ?? ''} to ${workingDayMap['To'] ?? ''}'
                : 'N/A';
            final workingHour = userData['working_hour'] ?? 'N/A';
            final about = userData['about'] ?? 'N/A';

            // Review data
            final reviews = userData['reviews'] as List<Map<String, dynamic>>? ?? [];
            final averageRating = userData['average_rating'] ?? 0.0;
            final totalReviews = userData['total_reviews'] ?? 0;

            return Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/image_4.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Expanded(
                              child: Center(
                                child: Text(
                                  'Makeup Artist',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 16),
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: profilePicture.isNotEmpty
                              ? NetworkImage(profilePicture)
                              : null,
                          child: profilePicture.isEmpty
                              ? const Icon(Icons.person, size: 50, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('📞 $phone'),
                        Text('✉️ $email'),
                        const SizedBox(height: 20),

                        infoRow(Icons.category, 'Category', category),
                        infoRow(Icons.location_on, 'Address', address),
                        infoRow(Icons.attach_money, 'Price', price),

                        // Review Display
                        buildReviewSummary(averageRating, totalReviews),

                        infoRow(Icons.calendar_today, 'Working day', workingDayText),
                        infoRow(Icons.access_time, 'Working Hour', workingHour),
                        const SizedBox(height: 24),

                        Row(
                          children: const [
                            Icon(Icons.chat_bubble_outline),
                            SizedBox(width: 12),
                            Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          about,
                          style: const TextStyle(color: Colors.black87, height: 1.4),
                          textAlign: TextAlign.justify,
                        ),
                        const SizedBox(height: 24),

                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Portfolio:',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          physics: const NeverScrollableScrollPhysics(),
                          children: List.generate(userData['portfolio'].length, (index) {
                            final imageUrl = userData['portfolio'][index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Center(
                                  child: Icon(Icons.broken_image, color: Colors.red),
                                ),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),

                        // Reviews Section - Now passing required parameters
                        buildReviewsSection(context, reviews, name, averageRating, totalReviews),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BookAppointmentPage(userId: userId),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pinkAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Book Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildReviewSummary(double averageRating, int totalReviews) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.star, size: 20),
          const SizedBox(width: 12),
          const Text('Rating: ', style: TextStyle(fontWeight: FontWeight.bold)),
          buildStarRating(averageRating),
          const SizedBox(width: 8),
          Text(
            '${averageRating.toStringAsFixed(1)} (${totalReviews} review${totalReviews != 1 ? 's' : ''})',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.amber, size: 16);
        } else if (index < rating) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 16);
        } else {
          return const Icon(Icons.star_border, color: Colors.amber, size: 16);
        }
      }),
    );
  }

  // Fixed method signature - now accepts required parameters
  Widget buildReviewsSection(BuildContext context, List<Map<String, dynamic>> reviews, String artistName, double averageRating, int totalReviews) {
    if (reviews.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Reviews:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Column(
              children: [
                Icon(Icons.rate_review_outlined, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No reviews yet',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                Text(
                  'Be the first to leave a review!',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Limit reviews to first 5 for display on this page
    final reviewsToShow = reviews.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Reviews:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),

        // Show only first 5 reviews as cards
        Column(
          children: reviewsToShow.map((review) => buildReviewCard(review)).toList(),
        ),

        // Show "View all reviews" button if there are more than 5 reviews
        if (reviews.length > 5)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AllReviewsPage(
                      reviews: reviews, // Pass all reviews to the all reviews page
                      artistName: artistName,
                      averageRating: averageRating,
                      totalReviews: totalReviews,
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('View all ${reviews.length} reviews'),
            ),
          ),
      ],
    );
  }

  Widget buildReviewCard(Map<String, dynamic> review) {
    final profilePicture = review['customer_profile'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.pinkAccent.withOpacity(0.1),
                backgroundImage: profilePicture.isNotEmpty
                    ? NetworkImage(profilePicture)
                    : null,
                child: profilePicture.isEmpty
                    ? Text(
                  (review['customer_name'] ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pinkAccent,
                  ),
                )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['customer_name'] ?? 'Anonymous',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        buildStarRating((review['rating'] ?? 0).toDouble()),
                        const SizedBox(width: 8),
                        if (review['created_at'] != null)
                          Text(
                            formatDate(review['created_at']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review['comment'] != null && review['comment'].toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                review['comment'].toString(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String formatDate(dynamic timestamp) {
    if (timestamp == null) return '';

    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is DateTime) {
        date = timestamp;
      } else {
        return '';
      }

      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  Widget infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}