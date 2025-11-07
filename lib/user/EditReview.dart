import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class EditReviewPage extends StatefulWidget {
  final String reviewId;
  final Map<String, dynamic> reviewData;

  const EditReviewPage({
    super.key,
    required this.reviewId,
    required this.reviewData,
  });

  @override
  State<EditReviewPage> createState() => _EditReviewPageState();
}

class _EditReviewPageState extends State<EditReviewPage> {
  final TextEditingController _reviewController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  int _selectedRating = 5;
  List<String> _existingImages = [];
  List<XFile> _newImageFiles = [];
  bool _isSaving = false;
  bool _isPickingImages = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    _reviewController.text = widget.reviewData['review_text'] ?? '';
    _selectedRating = widget.reviewData['rating'] ?? 5;
    _existingImages = List<String>.from(widget.reviewData['images'] ?? []);
  }

  void _showImageSourceDialog() {
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
                          _pickFromGallery();
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

  Future<void> _takePhoto() async {
    if (_isPickingImages) return;

    // Check if we already have 6 images
    int totalImages = _existingImages.length + _newImageFiles.length;
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

  Future<void> _pickFromGallery() async {
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
        int currentImageCount = _existingImages.length + _newImageFiles.length;
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
          // Show a message informing the user that only the first N images were selected
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

  Future<List<String>> _uploadNewImages() async {
    if (_newImageFiles.isEmpty) return [];

    List<String> uploadedUrls = [];

    try {
      for (XFile imageFile in _newImageFiles) {
        // Create a unique filename
        String fileName = 'review_images/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';

        // Upload to Firebase Storage
        final ref = FirebaseStorage.instance.ref().child(fileName);
        final uploadTask = ref.putFile(File(imageFile.path));
        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        uploadedUrls.add(downloadUrl);
      }
    } catch (e) {
      throw Exception('Failed to upload images: ${e.toString()}');
    }

    return uploadedUrls;
  }

  Future<void> _saveReview() async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Upload new images if any
      List<String> newImageUrls = await _uploadNewImages();

      // Combine existing and new image URLs
      List<String> allImageUrls = [..._existingImages, ...newImageUrls];

      // Update the review in Firestore
      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(widget.reviewId)
          .update({
        'rating': _selectedRating,
        'review_text': _reviewController.text.trim(),
        'images': allImageUrls,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Get the artist reference from the review data
      final artistRef = widget.reviewData['artist_id'] as DocumentReference?;

      if (artistRef != null) {
        // Fetch all reviews for this artist to recalculate average rating
        final reviewsQuery = await FirebaseFirestore.instance
            .collection('reviews')
            .where('artist_id', isEqualTo: artistRef)
            .get();

        // Calculate new average rating
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

        // Update the makeup artist's average rating
        await artistRef.update({
          'average_rating': averageRating,
          'total_reviews': reviewsQuery.docs.length,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review updated successfully'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update review: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildRatingSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rating',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRating = index + 1;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.star,
                  size: 36,
                  color: index < _selectedRating
                      ? const Color(0xFFFFD700)
                      : const Color(0xFFE8E8E8),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildReviewTextInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reviewController,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'Write your review...',
            hintStyle: const TextStyle(color: Colors.black54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black26),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE91E63), width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
            filled: true,
            fillColor: Colors.transparent,
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Images (Optional - Max 6)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            Text(
              '${_existingImages.length + _newImageFiles.length}/6',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Add image button - now opens the image source dialog
                if ((_existingImages.length + _newImageFiles.length) < 6)
                  GestureDetector(
                    onTap: _isPickingImages ? null : _showImageSourceDialog,
                    child: Container(
                      width: 90,
                      height: 90,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFB81EE), width: 2),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withOpacity(0.9),
                      ),
                      child: _isPickingImages
                          ? const CircularProgressIndicator(
                        color: Color(0xFFFB81EE),
                      )
                          : const Icon(
                        Icons.add_photo_alternate,
                        color: Color(0xFFFB81EE),
                        size: 32,
                      ),
                    ),
                  ),

                // Display existing images
                ..._existingImages.asMap().entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            entry.value,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.error, color: Colors.red),
                              );
                            },
                          ),
                        ),
                        // Delete button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _existingImages.removeAt(entry.key);
                              });
                            },
                            child: Container(
                              width: 24,
                              height: 24,
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
                    ),
                  );
                }).toList(),

                // Display newly selected images
                ..._newImageFiles.asMap().entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(entry.value.path),
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Delete button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _newImageFiles.removeAt(entry.key);
                              });
                            },
                            child: Container(
                              width: 24,
                              height: 24,
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
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Edit Review",
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
          // Content
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rating selector
                Container(
                  padding: const EdgeInsets.all(20),
                  child: _buildRatingSelector(),
                ),

                const SizedBox(height: 20),

                // Review text input
                Container(
                  padding: const EdgeInsets.all(20),
                  child: _buildReviewTextInput(),
                ),

                const SizedBox(height: 20),

                // Images section
                Container(
                  padding: const EdgeInsets.all(20),
                  child: _buildImagesSection(),
                ),

                const SizedBox(height: 30),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF923DC3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                    child: const Text(
                      'Update Review',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isSaving) _buildImageSearchLoading(),
        ],
      ),
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
                'Updating review...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait while we update your review',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
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

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }
}