import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WriteReviewPage extends StatefulWidget {
  final String appointmentId;
  const WriteReviewPage({super.key, required this.appointmentId});

  @override
  State<WriteReviewPage> createState() => _WriteReviewPageState();
}

class _WriteReviewPageState extends State<WriteReviewPage> {
  int _rating = 0;
  final TextEditingController _reviewController = TextEditingController();
  bool _isSubmitting = false;

  // Cache the artist details to prevent refetching
  Map<String, dynamic>? _cachedArtistDetails;
  bool _isLoadingArtist = true;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _loadArtistDetails();
  }

  Future<void> _loadArtistDetails() async {
    try {
      final artistDetails = await fetchArtistDetails(widget.appointmentId);
      if (mounted) {
        setState(() {
          _cachedArtistDetails = artistDetails;
          _isLoadingArtist = false;
          _loadingError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingArtist = false;
          _loadingError = e.toString();
        });
      }
    }
  }

  Future<Map<String, dynamic>?> fetchArtistDetails(String appointmentId) async {
    try {
      print("Fetching artist details for appointment: $appointmentId");

      // 1. Get appointment document
      final appointmentDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .get();

      if (!appointmentDoc.exists) {
        print("Appointment not found");
        return null;
      }

      final appointmentData = appointmentDoc.data();
      if (appointmentData == null) {
        print("Appointment data is null");
        return null;
      }

      // 2. Get artist_id reference from appointment
      final artistRef = appointmentData['artist_id'] as DocumentReference?;
      if (artistRef == null) {
        print("Artist reference not found in appointment");
        return null;
      }

      // 3. Get makeup artist document using the reference
      final artistDoc = await artistRef.get();
      if (!artistDoc.exists) {
        print("Artist document not found");
        return null;
      }

      final artistData = artistDoc.data() as Map<String, dynamic>?;
      if (artistData == null) {
        print("Artist data is null");
        return null;
      }

      // 4. Get user_id reference from makeup artist
      final userRef = artistData['user_id'] as DocumentReference?;
      if (userRef == null) {
        print("User reference not found in artist data");
        return null;
      }

      // 5. Get user document using the reference
      final userDoc = await userRef.get();
      if (!userDoc.exists) {
        print("User document not found");
        return null;
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      if (userData == null) {
        print("User data is null");
        return null;
      }

      // 6. Get existing reviews count for this artist
      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('artist_id', isEqualTo: artistRef)
          .get();

      // 7. Combine all the data
      return {
        'name': (artistData['studio_name'] as String?) ?? 'Unknown Artist',
        'profile_picture': (userData['profile pictures'] as String?) ?? '',
        'category': (artistData['category'] as String?) ?? 'Unknown Category',
        'reviews_count': reviewsQuery.docs.length,
        'artist_ref': artistRef, // Keep the reference for saving review
        'artist_doc_id': artistDoc.id,
      };
    } catch (e) {
      print('Error fetching artist details: $e');
      return null;
    }
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a rating")),
      );
      return;
    }
    if (_reviewController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write a review")),
      );
      return;
    }
    // Get current user
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please log in to submit a review")),
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    try {
      // Use cached artist details instead of fetching again
      if (_cachedArtistDetails == null || _cachedArtistDetails!['artist_ref'] == null) {
        throw Exception("Could not find artist details");
      }

      final artistRef = _cachedArtistDetails!['artist_ref'] as DocumentReference;
      final currentUserRef = FirebaseFirestore.instance.doc('users/${currentUser.uid}');
      final appointmentRef = FirebaseFirestore.instance.doc('appointments/${widget.appointmentId}');

      // Add review to reviews collection (including appointment_id)
      await FirebaseFirestore.instance.collection('reviews').add({
        'artist_id': artistRef,
        'customer_id': currentUserRef,
        'appointment_id': appointmentRef,
        'rating': _rating,
        'review_text': _reviewController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      // Update artist's average rating
      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('artist_id', isEqualTo: artistRef)
          .get();
      double totalRating = 0;
      for (var doc in reviewsQuery.docs) {
        final data = doc.data();
        final rating = data['rating'];
        if (rating is num) {
          totalRating += rating.toDouble();
        }
      }
      double averageRating = reviewsQuery.docs.isNotEmpty
          ? totalRating / reviewsQuery.docs.length
          : 0.0;
      // Update makeup_artists collection with new average rating
      await FirebaseFirestore.instance
          .collection('makeup_artists')
          .doc(_cachedArtistDetails!['artist_doc_id'])
          .update({
        'average_rating': averageRating,
        'total_reviews': reviewsQuery.docs.length,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Review submitted successfully!")),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error submitting review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit review: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildProfileImage(String? imageUrl) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFE4B5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: _buildImageContent(imageUrl),
      ),
    );
  }

  Widget _buildImageContent(String? imageUrl) {
    // Check if URL is valid and not empty
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(
        Icons.person,
        size: 60,
        color: Colors.black54,
      );
    }

    // Validate URL format
    try {
      final uri = Uri.parse(imageUrl);
      if (!uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        throw const FormatException('Invalid URL scheme');
      }
    } catch (e) {
      print('Invalid image URL: $imageUrl, Error: $e');
      return const Icon(
        Icons.person,
        size: 60,
        color: Colors.black54,
      );
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
            color: const Color(0xFFFB81EE),
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        print('Image loading error: $error');
        print('Image URL: $imageUrl');
        return const Icon(
          Icons.person,
          size: 60,
          color: Colors.black54,
        );
      },
    );
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Rate Your Experience",
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
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
    // Show loading indicator only when initially loading
    if (_isLoadingArtist) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFB81EE)),
      );
    }

    // Show error state
    if (_loadingError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Error loading artist details",
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoadingArtist = true;
                  _loadingError = null;
                });
                _loadArtistDetails();
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    // Show no data state
    if (_cachedArtistDetails == null) {
      return const Center(
        child: Text(
          "Artist not found.",
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      );
    }

    // Show the main content using cached data
    final artist = _cachedArtistDetails!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Profile Picture
          _buildProfileImage(artist['profile_picture'] as String?),

          const SizedBox(height: 20),

          // Artist Name
          Text(
            artist['name'] as String? ?? 'Unknown Artist',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          // Category
          Text(
            artist['category'] as String? ?? 'Unknown Category',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black54,
              fontWeight: FontWeight.w400,
            ),
          ),

          const SizedBox(height: 40),

          // Question
          const Text(
            "How was your experience?",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 30),

          // Rating Display
          Text(
            _rating.toString(),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w300,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          // Reviews Count
          Text(
            "${artist['reviews_count'] ?? 0} reviews",
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 20),

          // Star Rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _rating = index + 1;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star,
                    size: 36,
                    color: index < _rating
                        ? const Color(0xFFFB81EE)
                        : const Color(0xFFE8E8E8),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 40),

          // Review Text Field
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _reviewController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "Write your review here...",
                hintStyle: TextStyle(
                  color: Colors.black38,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF923DC3),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Text(
                "Submit",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}