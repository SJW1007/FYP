import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AllReviewsPage extends StatefulWidget {
  final List<Map<String, dynamic>> reviews;
  final String artistName;
  final double averageRating;
  final int totalReviews;

  const AllReviewsPage({
    super.key,
    required this.reviews,
    required this.artistName,
    required this.averageRating,
    required this.totalReviews,
  });

  @override
  State<AllReviewsPage> createState() => _AllReviewsPageState();
}

class _AllReviewsPageState extends State<AllReviewsPage> {
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
          // Content with semi-transparent overlay
          Container(
            child: Column(
              children: [
                // AppBar
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    '${widget.artistName} Reviews',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                ),

                // Review Summary Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        widget.averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.pinkAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildStarRating(widget.averageRating, size: 24),
                      const SizedBox(height: 8),
                      Text(
                        'Based on ${widget.totalReviews} review${widget.totalReviews != 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      buildRatingBreakdown(),
                    ],
                  ),
                ),

                // Reviews List
                Expanded(
                  child: widget.reviews.isEmpty
                      ? buildEmptyState()
                      : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.reviews.length,
                    itemBuilder: (context, index) {
                      return buildReviewCard(widget.reviews[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 80,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Be the first to leave a review!',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRatingBreakdown() {
    if (widget.reviews.isEmpty) return const SizedBox.shrink();

    // Calculate rating distribution
    Map<int, int> ratingCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (var review in widget.reviews) {
      int rating = (review['rating'] ?? 0).round();
      if (rating >= 1 && rating <= 5) {
        ratingCounts[rating] = (ratingCounts[rating] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 12),
        ...List.generate(5, (index) {
          int stars = 5 - index;
          int count = ratingCounts[stars] ?? 0;
          double percentage = widget.totalReviews > 0 ? count / widget.totalReviews : 0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  '$stars',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.pinkAccent),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 30,
                  child: Text(
                    '$count',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget buildReviewCard(Map<String, dynamic> review) {
    // Use the customer_profile that's already fetched in the first page
    final String profilePictureUrl = review['customer_profile'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Profile Picture or Avatar
              buildProfileAvatar(
                profilePictureUrl: profilePictureUrl,
                customerName: review['customer_name'] ?? 'Anonymous',
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
          if (review['comment'] != null &&
              review['comment'].toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                review['comment'].toString(),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildProfileAvatar({
    required String profilePictureUrl,
    required String customerName,
  }) {
    const double radius = 24;

    if (profilePictureUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(profilePictureUrl),
        onBackgroundImageError: (exception, stackTrace) {
          // Handle image loading error
          print('Error loading profile picture: $exception');
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.pinkAccent.withOpacity(0.3),
              width: 2,
            ),
          ),
        ),
      );
    }

    // Fallback to initial avatar
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.pinkAccent.withOpacity(0.1),
      child: Text(
        customerName.isNotEmpty ? customerName[0].toUpperCase() : 'A',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.pinkAccent,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget buildStarRating(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: size);
        } else if (index < rating) {
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        } else {
          return Icon(Icons.star_border, color: Colors.amber, size: size);
        }
      }),
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

      // Format as "Jan 15, 2024"
      List<String> months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];

      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return '';
    }
  }
}