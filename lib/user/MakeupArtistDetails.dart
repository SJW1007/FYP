import 'package:firebase_auth/firebase_auth.dart';
import 'BookAppointment.dart';
import 'AllReviewsPage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../all user/ChatPage.dart';

class MakeupArtistDetailsPage extends StatefulWidget {
  final String userId;
  const MakeupArtistDetailsPage({super.key, required this.userId});

  @override
  State<MakeupArtistDetailsPage> createState() => _MakeupArtistDetailsPageState();
}

class _MakeupArtistDetailsPageState extends State<MakeupArtistDetailsPage> {
  int? _selectedReportReason;
  final TextEditingController _customComplaintController = TextEditingController();
  List<File> _evidenceImages = [];
  final ImagePicker _picker = ImagePicker();
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
        'phone': artistData['phone_number'].toString() ?? 'N/A',
        'profile pictures': userData['profile pictures'] ?? '',
        'category': artistData['category'] ?? [], // Keep as array
        'address': artistData['address'] ?? 'N/A',
        'price': artistData['price'] ?? {}, // Keep as map
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
          'images': List<String>.from(reviewData['images'] ?? []),
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

  Widget _buildReportOption(int value, String text, StateSetter setDialogState) {
    return RadioListTile<int>(
      title: Text(text),
      value: value,
      groupValue: _selectedReportReason,
      onChanged: (int? newValue) {
        setDialogState(() {
          _selectedReportReason = newValue;
        });
      },
      activeColor: Colors.red,
      contentPadding: EdgeInsets.zero,
    );
  }

  // Method to show report dialog
  void _showReportDialog(BuildContext context) {
    // Reset dialog state
    _selectedReportReason = null;
    _customComplaintController.clear();
    _evidenceImages.clear();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.report, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Report Artist'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Why are you reporting this makeup artist?',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),

                      // Report reasons
                      _buildReportOption(1, 'Inappropriate content', setDialogState),
                      _buildReportOption(2, 'Fake profile', setDialogState),
                      _buildReportOption(3, 'Poor service', setDialogState),
                      _buildReportOption(4, 'Scam or fraud', setDialogState),
                      _buildReportOption(5, 'Harassment', setDialogState),
                      _buildReportOption(6, 'Other', setDialogState),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _customComplaintController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: _selectedReportReason == 6
                              ? 'Please describe your complaint *'
                              : 'Additional details (optional)',
                          hintText: 'Provide more details about your complaint...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Evidence section
                      const Text(
                        'Evidence',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Center(
                        // Add evidence button with improved functionality
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            _showImageSourceDialog(setDialogState);
                          },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(_evidenceImages.isEmpty
                              ? 'Add Photos (6 pictures)'
                              : 'Add More Photos (${_evidenceImages.length}/6)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.pinkAccent,
                            side: const BorderSide(color: Colors.pinkAccent),
                          ),
                        ),
                      ),

                      // Display selected images with improved layout
                      if (_evidenceImages.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _evidenceImages.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        _evidenceImages[index],
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () {
                                          _removeEvidenceImage(index);
                                          setDialogState(() {});
                                        },
                                        child: Container(
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
                            },
                          ),
                        ),

                      // Warning message for required photos
                      if (_selectedReportReason != null && _evidenceImages.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Photos are required for all reports',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _customComplaintController.clear();
                    _evidenceImages.clear();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _selectedReportReason != null && _evidenceImages.isNotEmpty
                      ? () {
                    Navigator.of(context).pop(); // Close report dialog first
                    _submitReport(); // Then submit report (which will show loading)
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit Report'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImageSourceDialog([StateSetter? dialogSetState]) {
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
                          _takePhotoFromCamera(dialogSetState); // Pass dialogSetState here
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
                          _pickFromGallery(dialogSetState); // Pass dialogSetState here
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

  // Method to take photo from camera
  Future<void> _takePhotoFromCamera([StateSetter? dialogSetState]) async {
    try {
      // Check if we already have 6 images
      if (_evidenceImages.length >= 6) {
        _showMaxLimitDialog();
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        _evidenceImages.add(File(pickedFile.path));
        setState(() {}); // Update the main widget state
        if (dialogSetState != null) {
          dialogSetState(() {}); // Update the dialog state
        }
      }
    } catch (e) {
      print('Error taking photo from camera: $e');
      _showErrorDialog('Error taking photo. Please try again.');
    }
  }

// Method to pick image from gallery
  Future<void> _pickFromGallery([StateSetter? dialogSetState]) async {
    try {
      // Check if we already have 6 images
      if (_evidenceImages.length >= 6) {
        _showMaxLimitDialog();
        return;
      }

      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isNotEmpty) {
        // Calculate how many more images we can add
        final int remainingSlots = 6 - _evidenceImages.length;

        // Take only the number of images that fit within the limit
        final List<XFile> imagesToAdd = pickedFiles.take(remainingSlots).toList();

        // Convert XFile to File and add to existing images
        List<File> newImages = imagesToAdd.map((xFile) => File(xFile.path)).toList();
        _evidenceImages.addAll(newImages);

        setState(() {}); // Update the main widget state
        if (dialogSetState != null) {
          dialogSetState(() {}); // Update the dialog state
        }

        // Show dialog if user selected more images than allowed
        if (pickedFiles.length > remainingSlots) {
          _showSelectionLimitDialog(pickedFiles.length, remainingSlots);
        }
      }
    } catch (e) {
      print('Error picking images from gallery: $e');
      _showErrorDialog('Error selecting images. Please try again.');
    }
  }


  void _showMaxLimitDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Maximum Limit Reached', style: TextStyle(fontSize: 22)),
            ],
          ),
          content: const Text('You can only select up to 6 photos for evidence. Please remove some photos if you want to add new ones.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

// Helper method to show selection limit dialog
  void _showSelectionLimitDialog(int selectedCount, int remainingSlots) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('Selection Limited'),
            ],
          ),
          content: Text('You selected $selectedCount photos, but only $remainingSlots more ${remainingSlots == 1 ? 'photo' : 'photos'} could be added. Maximum limit is 6 photos.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

// Helper method to show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Error'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }


  String _getReasonText(int reason) {
    switch (reason) {
      case 1: return 'Inappropriate content';
      case 2: return 'Fake profile';
      case 3: return 'Poor service';
      case 4: return 'Scam or fraud';
      case 5: return 'Harassment';
      case 6: return 'Other';
      default: return 'Unknown';
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

  Future<void> _submitReport() async {
    // Store the context before async operations
    final BuildContext currentContext = context;

    // Show loading overlay with proper context handling
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button
          child: _buildReportSubmissionLoading(),
        );
      },
    );

    try {
      final String reasonText = _getReasonText(_selectedReportReason!);
      final String complaint = _customComplaintController.text.trim();
      final int evidenceCount = _evidenceImages.length;

      // Check if user is logged in
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (Navigator.canPop(currentContext)) {
          Navigator.of(currentContext).pop(); // Close loading dialog
        }
        if (mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(content: Text('You must be logged in to submit a report.')),
          );
        }
        return;
      }

      final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

      // Get makeup artist reference
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) {
        if (Navigator.canPop(currentContext)) {
          Navigator.of(currentContext).pop(); // Close loading dialog
        }
        if (mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(content: Text('Makeup artist not found')),
          );
        }
        return;
      }

      final makeupArtistDocRef = artistQuery.docs.first.reference;

      // Upload evidence images and get URLs
      List<String> evidenceUrls = [];
      if (_evidenceImages.isNotEmpty) {
        for (int i = 0; i < _evidenceImages.length; i++) {
          try {
            final complaintRef = FirebaseStorage.instance
                .ref()
                .child('complaints')
                .child(currentUser.uid)
                .child('evidence_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

            await complaintRef.putFile(_evidenceImages[i]);
            final url = await complaintRef.getDownloadURL();
            evidenceUrls.add(url);
          } catch (e) {
            print('Error uploading evidence image $i: $e');
          }
        }
      }

      // Create report data with status system
      final reportData = {
        'artist_id': makeupArtistDocRef,
        'reporter_id': currentUserRef,
        'reason': reasonText,
        'complaint_details': complaint.isEmpty ? null : complaint,
        'evidence_urls': evidenceUrls,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'admin_reponse': null,
        'resolved_by': null,
        'resolved_at': null,
      };

      // Save to Firestore
      await FirebaseFirestore.instance.collection('reports').add(reportData);

      // Close loading dialog
      if (Navigator.canPop(currentContext)) {
        Navigator.of(currentContext).pop();
      }

      // Show success dialog
      if (mounted) {
        _showReportSuccessDialog(currentContext, reasonText, complaint, evidenceCount);
      }

      // Clear the form
      _customComplaintController.clear();
      _evidenceImages.clear();
      _selectedReportReason = null;

    } catch (e) {
      print('Error submitting report: $e');

      // Close loading dialog
      if (Navigator.canPop(currentContext)) {
        Navigator.of(currentContext).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(
            content: Text('Error submitting report: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Loading widget for report submission
  Widget _buildReportSubmissionLoading() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Submitting your report...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Processing complaint and evidence',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                // Simple loading indicator instead of animated dots
                Text(
                  'Please wait...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// Success dialog to show after report submission
  void _showReportSuccessDialog(BuildContext context, String reasonText, String complaint, int evidenceCount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Report Submitted',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold),),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your report has been submitted and is now under review.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Track Report Status',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'To check the status of your report, navigate to:',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Profile → Settings → Report Status',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Got it',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Method to remove evidence image
  void _removeEvidenceImage(int index) {
    if (index >= 0 && index < _evidenceImages.length) {
      _evidenceImages.removeAt(index);
    }
  }

// Method to handle chat navigation
  void _navigateToChat(BuildContext context, String artistUserId, String artistName, String artistProfilePic) {
    // Navigate to chat page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          artistId: artistUserId,
          artistName: artistName,
          artistProfilePic: artistProfilePic,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, String artistUserId, String artistName, String artistProfilePic) {
    return Column(
      children: [
        // Book appointment button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookAppointmentPage(userId: widget.userId),
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
            child: const Text(
              'Book Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // You'll need to get the artist data first for the chat
            fetchArtistDetails(widget.userId).then((userData) {
              if (userData != null) {
                _navigateToChat(
                    context,
                    widget.userId,
                    userData['name'] ?? 'Artist',
                    userData['profile pictures'] ?? ''
                );
              }
            });
          },
          backgroundColor:const Color(0xFF5D83C8),
          child: const Icon(
            Icons.chat,
            color: Colors.white,
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/image_4.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: fetchArtistDetails(widget.userId),
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
                final categoryList = userData['category'] as List<dynamic>? ?? [];
                final address = userData['address'] ?? 'N/A';
                final priceMap = userData['price'] as Map<String, dynamic>? ?? {};
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
                    // Container(
                    //   decoration: const BoxDecoration(
                    //     image: DecorationImage(
                    //       image: AssetImage('assets/image_4.png'),
                    //       fit: BoxFit.cover,
                    //     ),
                    //   ),
                    // ),

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
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                                    ),
                                  ),
                                ),
                                // Report button in app bar
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (String result) {
                                    if (result == 'report') {
                                      _showReportDialog(context);
                                    }
                                  },
                                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                    const PopupMenuItem<String>(
                                      value: 'report',
                                      child: Row(
                                        children: [
                                          Icon(Icons.report, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Report Artist'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.phone,color: Color(0xFFFB81EE),),
                                const SizedBox(width: 4,),
                                Text('0$phone',style: const TextStyle(
                                  color: Color(0xFF925F70),
                                  fontSize: 14,
                                ),),
                              ],
                            ),
                            const SizedBox(height:4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.email,color: Color(0xFFFB81EE),),
                                const SizedBox(width: 4,),
                                Text('$email',style: const TextStyle(
                                  color: Color(0xFF925F70),
                                  fontSize: 14,
                                ),),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Category and Price section
                            buildCategoryAndPriceSection(categoryList, priceMap),

                            // Address section
                            buildInfoSection(Icons.location_on, 'Address', address),

                            // Review Display
                            buildReviewSummary(averageRating, totalReviews),

                            // Working day section
                            buildInfoSection(Icons.calendar_today, 'Working Day', workingDayText),

                            // Working hour section
                            buildInfoSection(Icons.access_time, 'Working Hour', workingHour),

                            // About section
                            buildAboutSection(about),

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
                                return GestureDetector(
                                  onTap: () => _showImageDialog(context, imageUrl),
                                  child: ClipRRect(
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
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 24),

                            // Reviews Section - Now passing required parameters
                            buildReviewsSection(context, reviews, name, averageRating, totalReviews),
                            const SizedBox(height: 24),

                            _buildActionButtons(context, widget.userId, name, profilePicture),
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
        )
    );
  }

  //  Build Category and Price section
  Widget buildCategoryAndPriceSection(List<dynamic> categoryList, Map<String, dynamic> priceMap) {
    if (categoryList.isEmpty) {
      return buildInfoSection(Icons.category, 'Category and Price', 'N/A');
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and label
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.category,
                  size: 20,
                  color: Color(0xFFFB81EE),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Category and Price',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Reduced gap between items
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: categoryList.asMap().entries.map<Widget>((entry) {
                        final index = entry.key;
                        final category = entry.value;
                        final categoryStr = category.toString();
                        final price = priceMap[categoryStr] ?? 'N/A';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2), // Reduced from 4 to 2
                          child: Row(
                            children: [
                              Text(
                                '${index + 1}. $categoryStr',
                                style: const TextStyle(
                                  color: Color(0xFF925F70),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 20,),
                              Text(
                                price.toString(),
                                style: const TextStyle(
                                  color: Color(0xFF925F70),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build info section
  Widget buildInfoSection(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: Color(0xFFFB81EE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF925F70),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build review summary with new layout
  Widget buildReviewSummary(double averageRating, int totalReviews) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.star,
              size: 20,
              color: Color(0xFFFB81EE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${averageRating.toStringAsFixed(1)} (${totalReviews} review${totalReviews != 1 ? 's' : ''})',
                  style: const TextStyle(
                    color: Color(0xFF925F70),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Build About section with new layout
  Widget buildAboutSection(String about) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 20,
              color: Color(0xFFFB81EE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  about,
                  style: const TextStyle(
                    color: Color(0xFF925F70),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
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
                Icon(Icons.rate_review_outlined, size: 40, color: Colors.pink),
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

    // Limit reviews to first 3 for display on this page
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
    final reviewImages = List<String>.from(review['images'] ?? []);
    final reviewText = review['comment']?.toString().trim() ?? '';

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

          // Review text or default message
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              reviewText.isNotEmpty
                  ? reviewText
                  : "This customer feels the makeup artist did an excellent job! ✨",
              style: TextStyle(
                color: reviewText.isNotEmpty ? Colors.black87 : Colors.grey[600],
                fontSize: 14,
                height: 1.4,
                fontStyle: reviewText.isNotEmpty ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),

          // Review images section
          if (reviewImages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Photos:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: reviewImages.length > 6 ? 6 : reviewImages.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _showImageDialog(context, reviewImages[index]),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                reviewImages[index],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
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