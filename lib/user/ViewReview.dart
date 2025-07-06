import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting

class ViewReviewPage extends StatefulWidget {
  final String appointmentId;
  const ViewReviewPage({super.key, required this.appointmentId});

  @override
  State<ViewReviewPage> createState() => _ViewReviewPageState();
}

class _ViewReviewPageState extends State<ViewReviewPage> {
  Map<String, dynamic>? _review;
  bool _isLoading = true;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _loadReview();
  }

  Future<void> _loadReview() async {
    try {
      // Get the appointment document reference
      final appointmentRef = FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId);
      // Query for the review with the specific appointment_id
      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('appointment_id', isEqualTo: appointmentRef)
          .limit(1)
          .get();
      if (reviewsQuery.docs.isEmpty) {
        // No review found for this appointment
        if (mounted) {
          setState(() {
            _review = null;
            _isLoading = false;
            _loadingError = null;
          });
        }
        return;
      }
      final reviewDoc = reviewsQuery.docs.first;
      final reviewData = reviewDoc.data();
      final customerRef = reviewData['customer_id'] as DocumentReference?;
      String customerName = '';
      String customerImage = '';
      if (customerRef != null) {
        final customerDoc = await customerRef.get();
        if (customerDoc.exists) {
          final customerData = customerDoc.data() as Map<String, dynamic>?;
          customerName = customerData?['name'] ?? '';
          customerImage = customerData?['profile pictures'] ?? '';
        }
      }
      final review = {
        'id': reviewDoc.id,
        'customer_name': customerName,
        'customer_image': customerImage,
        'rating': reviewData['rating'] ?? 0,
        'review_text': reviewData['review_text'] ?? '',
        'timestamp': reviewData['timestamp'] as Timestamp?,
        'likes_count': reviewData['likes_count'] ?? 0,
        'comments_count': reviewData['comments_count'] ?? 0,
      };
      if (mounted) {
        setState(() {
          _review = review;
          _isLoading = false;
          _loadingError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingError = e.toString();
        });
      }
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'No date available';

    final reviewDateTime = timestamp.toDate();

    // Format: "Dec 15, 2023 at 2:30 PM"
    final dateFormatter = DateFormat('MMM dd, yyyy');
    final timeFormatter = DateFormat('h:mm a');

    final dateStr = dateFormatter.format(reviewDateTime);
    final timeStr = timeFormatter.format(reviewDateTime);

    return '$dateStr at $timeStr';
  }

  Widget _buildProfileImage(String? imageUrl) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFE4B5),
      ),
      child: ClipOval(
        child: _buildImageContent(imageUrl),
      ),
    );
  }

  Widget _buildImageContent(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(
        Icons.person,
        size: 24,
        color: Colors.black54,
      );
    }

    try {
      final uri = Uri.parse(imageUrl);
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        throw const FormatException('Invalid URL scheme');
      }
    } catch (e) {
      return const Icon(
        Icons.person,
        size: 24,
        color: Colors.black54,
      );
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(
          Icons.person,
          size: 24,
          color: Colors.black54,
        );
      },
    );
  }

  Widget _buildStarRating(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          Icons.star,
          size: 16,
          color: index < rating
              ? const Color(0xFFFFD700)
              : const Color(0xFFE8E8E8),
        );
      }),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with profile, name, and timestamp
          Row(
            children: [
              _buildProfileImage(review['customer_image']),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['customer_name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _buildStarRating(review['rating']),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _formatTimestamp(review['timestamp']),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Review text
          Text(
            review['review_text'],
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 16),

        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Review",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: Stack(
        children: [
          // Background image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Review content
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE91E63)),
      );
    }

    if (_loadingError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Error loading review",
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _loadingError = null;
                });
                _loadReview();
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_review == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_outlined, size: 64, color: Colors.black26),
            SizedBox(height: 16),
            Text(
              "No review for this appointment",
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildReviewCard(_review!),
    );
  }
}