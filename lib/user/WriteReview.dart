import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

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

  // Image handling
  final List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  static const int maxImages = 6;

  // Cache the artist details to prevent refetching
  Map<String, dynamic>? _cachedArtistDetails;
  bool _isLoadingArtist = true;
  String? _loadingError;
  List<XFile> _newImageFiles = [];
  bool _isPickingImages = false;


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

  // Image picker methods
  Future<void> _pickImages() async {
    if (_isPickingImages) return;

    setState(() {
      _isPickingImages = true;
    });

    try {
      final List<XFile>? pickedFiles = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFiles != null && pickedFiles.isNotEmpty) {
        // Calculate how many images we can still add
        int currentImageCount = _selectedImages.length + _newImageFiles.length;
        int availableSlots = 6 - currentImageCount;

        if (availableSlots <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 6 images reached'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        // Take only the first N images that fit within the limit
        List<XFile> imagesToAdd;
        if (pickedFiles.length <= availableSlots) {
          imagesToAdd = pickedFiles;
        } else {
          imagesToAdd = pickedFiles.take(availableSlots).toList();
          // Show message only when user selects more than available slots
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Only the first $availableSlots images were selected (maximum 6 images allowed)'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        setState(() {
          _newImageFiles.addAll(imagesToAdd);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking images: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isPickingImages = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    if (_isPickingImages) return;

    // Check if we already have 6 images
    int totalImages = _selectedImages.length + _newImageFiles.length;
    if (totalImages >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum 6 images reached'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isPickingImages = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null) {
        setState(() {
          _newImageFiles.add(pickedFile);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking photo: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isPickingImages = false;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _showImageOption() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _takePhoto();
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDA9BF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Camera'),
                    ],
                  ),
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _pickImages();
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDA9BF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_library,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Gallery'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<List<String>> _uploadImages() async {
    if (_newImageFiles.isEmpty) {
      print('No images selected for upload');
      return [];
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('User not authenticated');
      throw Exception("User not authenticated");
    }

    List<String> imageUrls = [];

    try {
      for (int i = 0; i < _newImageFiles.length; i++) {
        final file = File(_newImageFiles[i].path);

        // Debug file info
        print('--- Uploading Image $i ---');
        print('File path: ${file.path}');
        print('File exists: ${await file.exists()}');
        if (await file.exists()) {
          print('File size: ${(await file.length()) / 1024} KB');
        }

        final fileName = 'review_${widget.appointmentId}_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        print('Generated filename: $fileName');

        try {
          final storageRef = FirebaseStorage.instance.ref().child('review_images/$fileName');
          print('Storage path: ${storageRef.fullPath}');

          // Start upload
          print('Starting upload...');
          final uploadTask = storageRef.putFile(file);

          // Monitor progress
          uploadTask.snapshotEvents.listen((taskSnapshot) {
            print('Upload progress: ${(taskSnapshot.bytesTransferred / taskSnapshot.totalBytes) * 100}%');
          });

          // Wait for completion
          final taskSnapshot = await uploadTask;
          print('Upload complete!');

          // Get URL
          final downloadUrl = await taskSnapshot.ref.getDownloadURL();
          print('Download URL: $downloadUrl');
          imageUrls.add(downloadUrl);

        } catch (e) {
          print('❌ Error uploading image $i: $e');
          print('Stack trace: ${e is Error ? e.stackTrace : ''}');
          // Continue with other images
        }
      }
    } catch (e) {
      print('❌ Global upload error: $e');
      rethrow;
    }

    return imageUrls;
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImageFiles.removeAt(index);
    });
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

      // 7. Handle profile_picture field - check if it's a List or String
      String profilePicture = '';
      final profilePictureData = userData['profile pictures'];

      if (profilePictureData != null) {
        if (profilePictureData is List && profilePictureData.isNotEmpty) {
          // If it's a list, take the first image
          profilePicture = profilePictureData.first?.toString() ?? '';
        } else if (profilePictureData is String) {
          // If it's already a string
          profilePicture = profilePictureData;
        }
      }

      // 8. Handle category field - check if it's a List or String
      String category = 'Unknown Category';
      final categoryData = artistData['category'];

      if (categoryData != null) {
        if (categoryData is List && categoryData.isNotEmpty) {
          // If it's a list, join all categories with commas or take the first one
          category = categoryData.map((cat) => cat.toString()).join(', ');
          // Or if you prefer just the first category:
          // category = categoryData.first?.toString() ?? 'Unknown Category';
        } else if (categoryData is String) {
          // If it's already a string
          category = categoryData;
        }
      }

      // 9. Combine all the data
      return {
        'name': (artistData['studio_name'] as String?) ?? 'Unknown Artist',
        'profile_picture': profilePicture,
        'category': category,
        'reviews_count': reviewsQuery.docs.length,
        'artist_ref': artistRef, // Keep the reference for saving review
        'artist_doc_id': artistDoc.id,
      };
    } catch (e) {
      print('Error fetching artist details: $e');
      // Print more detailed error information for debugging
      print('Error type: ${e.runtimeType}');
      if (e is TypeError) {
        print('TypeError details: ${e.toString()}');
      }
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

    // Remove the empty text check so it's optional
    // The review text can still be saved as empty
    final reviewText = _reviewController.text.trim();

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
      if (_cachedArtistDetails == null || _cachedArtistDetails!['artist_ref'] == null) {
        throw Exception("Could not find artist details");
      }

      final artistRef = _cachedArtistDetails!['artist_ref'] as DocumentReference;
      final currentUserRef = FirebaseFirestore.instance.doc('users/${currentUser.uid}');
      final appointmentRef = FirebaseFirestore.instance.doc('appointments/${widget.appointmentId}');

      List<String> imageUrls = [];
      if (_newImageFiles.isNotEmpty) {
        imageUrls = await _uploadImages();
      }

      await FirebaseFirestore.instance.collection('reviews').add({
        'artist_id': artistRef,
        'customer_id': currentUserRef,
        'appointment_id': appointmentRef,
        'rating': _rating,
        'review_text': reviewText,
        'images': imageUrls,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update ratings...
      final reviewsQuery = await FirebaseFirestore.instance
          .collection('reviews')
          .where('artist_id', isEqualTo: artistRef)
          .get();

      double totalRating = 0;
      for (var doc in reviewsQuery.docs) {
        final data = doc.data();
        if (data['rating'] is num) {
          totalRating += (data['rating'] as num).toDouble();
        }
      }

      double averageRating = reviewsQuery.docs.isNotEmpty
          ? totalRating / reviewsQuery.docs.length
          : 0.0;

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

  Widget _buildImageSearchLoading() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDA9BF5)),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Uploading review...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              // Animated dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 600 + (index * 200)),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: Color(0xFFDA9BF5).withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Add Photos",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            Text(
              "${_selectedImages.length + _newImageFiles.length}/$maxImages",
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: (_selectedImages.isEmpty && _newImageFiles.isEmpty)
              ? _buildEmptyImageState()
              : _buildImageList(),
        ),
      ],
    );
  }

  Widget _buildEmptyImageState() {
    return InkWell(
      onTap: _showImageOption,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo,
              size: 40,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              "Tap to add photos",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageList() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: (_selectedImages.length + _newImageFiles.length) + ((_selectedImages.length + _newImageFiles.length) < maxImages ? 1 : 0),
            itemBuilder: (context, index) {
              int totalImages = _selectedImages.length + _newImageFiles.length;

              if (index == totalImages) {
                // Add button - only show if less than 6 images
                return InkWell(
                  onTap: _showImageOption,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Color(0xFFFB81EE), width: 2, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Color(0xFFFB81EE), size: 30),
                        Text("Add", style: TextStyle(color: Color(0xFFFB81EE), fontSize: 12)),
                      ],
                    ),
                  ),
                );
              } else {
                // Determine if this is an existing image or new image
                if (index < _selectedImages.length) {
                  // Existing image
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: FileImage(_selectedImages[index]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // New image
                  int newImageIndex = index - _selectedImages.length;
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: FileImage(File(_newImageFiles[newImageIndex].path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeNewImage(newImageIndex),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              }
            },
          ),
        ],
      ),
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
          // loading overlay when submitting
          if (_isSubmitting)
            _buildImageSearchLoading(),
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

          const SizedBox(height: 30),

          // Image Grid
          _buildImageGrid(),

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