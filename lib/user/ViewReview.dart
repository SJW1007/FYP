import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'EditReview.dart';

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
  String? _reviewId;
  bool _canEdit = false;
  bool _isDeleting = false;

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
      _reviewId = reviewDoc.id;

      final customerRef = reviewData['customer_id'] as DocumentReference?;
      String customerName = '';
      String customerImage = '';

      // Check if current user can edit this review
      final currentUser = FirebaseAuth.instance.currentUser;
      _canEdit = currentUser != null && customerRef != null &&
          customerRef.id == currentUser.uid;

      if (customerRef != null) {
        final customerDoc = await customerRef.get();
        if (customerDoc.exists) {
          final customerData = customerDoc.data() as Map<String, dynamic>?;
          customerName = customerData?['name'] ?? '';
          customerImage = customerData?['profile pictures'] ?? '';
        }
      }
      // Add this after loading the basic review data
      List<String> reviewImages = [];
      if (reviewData['images'] != null) {
        reviewImages = List<String>.from(reviewData['images']);
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
        'images': reviewImages, // Add this line
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

  Future<void> _navigateToEditReview() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditReviewPage(
          reviewId: _reviewId!,
          reviewData: _review!,
        ),
      ),
    ).then((updated) {
      if (updated == true) {
        _loadReview();
      }
    });
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First row: Profile picture, name, datetime, and action buttons
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
                    Text(
                      _formatTimestamp(review['timestamp']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              // Action buttons - only show if user can edit
              if (_canEdit) ...[
                IconButton(
                  onPressed: _isDeleting ? null : _navigateToEditReview,
                  icon: const Icon(
                    Icons.edit,
                    color: Color(0xFFE91E63),
                    size: 20,
                  ),
                  tooltip: 'Edit Review',
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          //  Stars rating
          Padding(
            padding: const EdgeInsets.only(left:0),
            child: _buildStarRating(review['rating']),
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
          if (review['images'] != null && review['images'].isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: review['images'].length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _showImageDialog(context, review['images'][index]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          review['images'][index],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
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
                // Backdrop - tap to close
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black87,
                  ),
                ),

                // Image container
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

                // Close button
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

                // Bottom instruction text
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
}