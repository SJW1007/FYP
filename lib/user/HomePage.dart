import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'MakeupArtistDetails.dart';
import 'MakeupArtistLocationPage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blush_up/all%20user/ChatPage.dart';
import 'PreferencesSelection.dart';
import 'package:blush_up/all user/Login.dart';

typedef LoadingStateCallback = void Function(bool isLoading);

class HomePage extends StatefulWidget {
  final LoadingStateCallback? onLoadingStateChanged;

  const HomePage({
    super.key,
    this.onLoadingStateChanged,
  });
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allArtists = [];
  List<Map<String, dynamic>> _filteredArtists = [];
  final ImagePicker _picker = ImagePicker();
  bool _isImageSearchLoading = false;
  Map<int, bool> _expandedAddresses = {}; // Track which addresses are expanded
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  StreamSubscription<DocumentSnapshot>? _makeupArtistSubscription;
  String? _currentUserRole;

  // Image upload constraints
  static const int maxImageSizeInBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxImageSizeInMB = 10;
  static const List<String> supportedImageFormats = ['jpg', 'jpeg', 'png', 'heic'];

  List<Map<String, dynamic>> _recommendedArtists = [];
  bool _showRecommendations = false;
  String? _currentUserId; // You'll need to get this from your auth system

  @override
  void dispose() {
    _searchController.dispose();
    _userDocSubscription?.cancel();
    _makeupArtistSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkUserPreferences();
    // _setupAuthStateListener();
  }

  // void _setupAuthStateListener() {
  //   FirebaseAuth.instance.authStateChanges().listen((User? user) async {
  //     if (user == null) {
  //       // User signed out or session expired
  //       print('🔴 User signed out or session expired');
  //
  //       // Cancel any active listeners
  //       await _userDocSubscription?.cancel();
  //       await _makeupArtistSubscription?.cancel();
  //       _currentUserId = null;
  //       _currentUserRole = null;
  //
  //       // Navigate to login page
  //       navigatorKey.currentState?.pushAndRemoveUntil(
  //         MaterialPageRoute(builder: (context) => const LoginPage()),
  //             (route) => false,
  //       );
  //     } else {
  //       // User signed in
  //       print('🟢 User authenticated: ${user.uid}');
  //       _currentUserId = user.uid;
  //
  //       // Start monitoring user document and status
  //       _monitorUserDocument(user.uid);
  //     }
  //   });
  //
  //   // Optional: Listen for token refresh failures
  //   FirebaseAuth.instance.idTokenChanges().listen((User? user) async {
  //     if (user != null) {
  //       try {
  //         // Try to get fresh token
  //         await user.getIdToken(true);
  //         print('✅ Token refreshed successfully');
  //       } catch (e) {
  //         print('❌ Token refresh failed: $e');
  //         // Sign out if token refresh fails
  //         await FirebaseAuth.instance.signOut();
  //       }
  //     }
  //   });
  // }

  // Monitor user document for deletion or role changes
  void _monitorUserDocument(String userId) {
    print('🔍 Starting to monitor user document for: $userId');

    // Cancel existing subscription first
    _userDocSubscription?.cancel();

    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (docSnapshot) {
        print('🔔 User document snapshot received. Exists: ${docSnapshot.exists}');

        if (!docSnapshot.exists) {
          // User document was deleted
          print('🚨 User document deleted - logging out');
          _showLogoutMessage('Your account has been deleted');
          FirebaseAuth.instance.signOut();
          return;
        }

        final userData = docSnapshot.data();
        if (userData == null) {
          print('⚠️ User data is null');
          return;
        }

        final role = userData['role'];
        print('👤 User role: $role');
        _currentUserRole = role;

        // If role is makeup artist, monitor their status
        if (role == 'makeup artist') {
          print('💄 User is makeup artist - starting status monitor');
          _monitorMakeupArtistStatus(userId);
        } else {
          // Cancel makeup artist listener if role changed
          print('🔄 User is not makeup artist - canceling status monitor');
          _makeupArtistSubscription?.cancel();
          _makeupArtistSubscription = null;
        }
      },
      onError: (error) {
        print('❌ Error monitoring user document: $error');
        print('Error details: ${error.toString()}');
      },
    );
  }

  // Monitor makeup artist status changes
  void _monitorMakeupArtistStatus(String userId) async {
    print('🔍 Starting to monitor makeup artist status for user: $userId');

    // Cancel existing subscription first
    _makeupArtistSubscription?.cancel();

    try {
      // First, find the makeup artist document ID
      final querySnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: FirebaseFirestore.instance.doc('users/$userId'))
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('⚠️ No makeup artist document found for user: $userId');
        return;
      }

      final artistDocId = querySnapshot.docs.first.id;
      print('✅ Found makeup artist document ID: $artistDocId');

      // Now listen to that specific document for real-time updates
      _makeupArtistSubscription = FirebaseFirestore.instance//error
          .collection('makeup_artists')
          .doc(artistDocId)
          .snapshots()
          .listen(
            (docSnapshot) {
          print('🔔 Makeup artist document snapshot received. Exists: ${docSnapshot.exists}');

          if (!docSnapshot.exists) {
            // Makeup artist document deleted
            print('🚨 Makeup artist document deleted - logging out');
            _showLogoutMessage('Your makeup artist profile has been removed');
            FirebaseAuth.instance.signOut();
            return;
          }

          final makeupArtistData = docSnapshot.data();
          if (makeupArtistData == null) {
            print('⚠️ Makeup artist data is null');
            return;
          }

          final status = makeupArtistData['status'];

          print('📊 Makeup artist status from Firestore: "$status" (type: ${status.runtimeType})');
          print('📄 Full document data: $makeupArtistData');

          // Auto-logout if status is not Approved
          // Using trim() to handle potential whitespace issues
          final statusStr = status.toString().trim();

          if (statusStr != 'Approved') {
            String message;
            switch (statusStr) {
              case 'Pending':
                message = 'Your application is pending approval. You have been logged out.';
                break;
              case 'Rejected':
                message = 'Your application has been rejected. Please check your email for details.';
                break;
              case 'Disabled':
                message = 'Your account has been disabled. Please check your email for details.';
                break;
              default:
                message = 'Your account status has changed to "$statusStr". Please contact support.';
            }

            print('🚨 Status is "$statusStr" (not Approved) - logging out');

            // Use a small delay to ensure the dialog shows before navigation
            Future.delayed(Duration.zero, () {
              _showLogoutMessage(message);
              // Sign out after a short delay to allow dialog to show
              Future.delayed(const Duration(milliseconds: 500), () {
                FirebaseAuth.instance.signOut();
              });
            });
          } else {
            print('✅ Status is Approved - user can stay logged in');
          }
        },
        onError: (error) {
          print('❌ Error monitoring makeup artist status: $error');
          print('Error details: ${error.toString()}');
        },
      );
    } catch (e) {
      print('❌ Error setting up makeup artist monitor: $e');
    }
  }

  // Show logout message to user
  void _showLogoutMessage(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Show dialog with logout reason
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Session Ended'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _checkUserPreferences() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final preferences = userData['preferences'] as List<dynamic>? ?? [];

        // If user hasn't set preferences and has no booking history, show preferences page
        if (preferences.isEmpty) {
          final hasBookingHistory = await _checkBookingHistory(currentUser.uid);

          if (!hasBookingHistory && mounted) {
            // Navigate to preferences selection page
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const PreferencesSelectionPage(),
              ),
            );
            return;
          }
        }
      }

      // Continue with normal initialization
      fetchMakeupArtists().then((_) {
        _loadRecommendations();
      });
    } catch (e) {
      print('Error checking user preferences: $e');
      // Continue with normal flow if there's an error
      fetchMakeupArtists().then((_) {
        _loadRecommendations();
      });
    }
  }

  Future<bool> _checkBookingHistory(String userId) async {
    try {
      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('customerId', isEqualTo: FirebaseFirestore.instance.doc('users/$userId'))
          .where('status', isEqualTo: 'Completed')
          .limit(1)
          .get();

      return appointmentsSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking booking history: $e');
      return false;
    }
  }


  Future<void> _loadRecommendations() async {
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    print('👤 Current user ID: $_currentUserId');

    if (_currentUserId != null && _allArtists.isNotEmpty) {
      print('🚀 Loading recommendations...');
      final recommendations = await _getRecommendedArtists(_currentUserId!);
      if (mounted) {
        setState(() {
          _recommendedArtists = recommendations;
          _showRecommendations = recommendations.isNotEmpty;
        });
        print('✅ Recommendations loaded: ${recommendations.length} artists');
      }
    } else {
      print('⚠️ Cannot load recommendations: userId=$_currentUserId, artistsCount=${_allArtists.length}');
    }
  }
  void _handleTextSearch(BuildContext context, String query) {
    final lowerQuery = query.toLowerCase();

    // Define tag-category mappings
    final tagToCategoryMap = {
      'bridal': ['wedding'],
      'kpop': ['korean style'],
    };

    // Find additional categories if the query is a known tag
    final matchedCategories = <String>{lowerQuery}; // Always include the direct query
    if (tagToCategoryMap.containsKey(lowerQuery)) {
      matchedCategories.addAll(tagToCategoryMap[lowerQuery]!);
    }

    final filtered = _allArtists.where((artist) {
      final name = artist['name']?.toLowerCase() ?? '';
      final categories = artist['categories'] as List<String>? ?? [];

      // Check if name matches or any category matches
      return name.contains(lowerQuery) ||
          categories.any((category) =>
              matchedCategories.any((cat) => category.toLowerCase().contains(cat)));
    }).toList();

    setState(() {
      _filteredArtists = filtered;
    });
  }

  void _showCameraOrGalleryPicker(BuildContext context) {
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
                        onTap: () async {
                          Navigator.pop(context);
                          final photo = await _picker.pickImage(source: ImageSource.camera);
                          if (photo != null) {
                            await _handleImageSearch(File(photo.path));
                          }
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
                        onTap: () async {
                          Navigator.pop(context);
                          final image = await _picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            await _handleImageSearch(File(image.path));
                          }
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

  Future<void> _handleImageSearch(File imageFile) async {
    if (!mounted) return;

    setState(() {
      _isImageSearchLoading = true;
    });

    widget.onLoadingStateChanged?.call(true);

    try {
      // Step 1: Check file existence
      if (!await imageFile.exists()) {
        throw Exception("Image file not found. Please try selecting the image again.");
      }

      // Step 2: Get file size
      final fileSize = await imageFile.length();
      final fileSizeInMB = fileSize / (1024 * 1024);

      print("📏 Image size: ${fileSizeInMB.toStringAsFixed(2)} MB");

      // Step 3: Validate file size
      if (fileSize > maxImageSizeInBytes) {
        throw Exception(
            "Image is too large (${fileSizeInMB.toStringAsFixed(1)} MB).\n"
                "Please select an image smaller than $maxImageSizeInMB MB."
        );
      }

      if (fileSize == 0) {
        throw Exception("Image file is empty. Please select a valid image.");
      }

      // Step 4: Check file extension
      final fileName = imageFile.path.toLowerCase();
      final fileExtension = fileName.split('.').last;

      if (!supportedImageFormats.contains(fileExtension)) {
        throw Exception(
            "Unsupported image format (.$fileExtension).\n"
                "Please use: ${supportedImageFormats.map((f) => '.$f').join(', ')}"
        );
      }

      print("✅ Image validation passed: $fileExtension format, ${fileSizeInMB.toStringAsFixed(2)} MB");

      // Step 5: Read image bytes
      final imageBytes = await imageFile.readAsBytes();

      if (imageBytes.isEmpty) {
        throw Exception("Failed to read image data. Please try another image.");
      }

      // Step 6: Convert to base64
      final base64Image = base64Encode(imageBytes);

      if (base64Image.isEmpty) {
        throw Exception("Failed to encode image. Please try another image.");
      }

      print("🔄 Image encoded to base64 (${base64Image.length} characters)");

      // Step 7: Call API
      final apiKey = dotenv.env['API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception(
            "API configuration error. Please contact support.\n"
                "(Error code: API_KEY_MISSING)"
        );
      }

      print("🔑 Using API key (length: ${apiKey.length})");

      final roboflowResponse = await http.post(
        Uri.parse("https://classify.roboflow.com/makeup-detection-ttdth/3?api_key=$apiKey"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: base64Image,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception("Request timed out. Please check your internet connection and try again.");
        },
      );

      print("📡 API Response Status: ${roboflowResponse.statusCode}");

      // Step 8: Handle API response
      if (roboflowResponse.statusCode == 413) {
        throw Exception(
            "Image is too large for processing.\n"
                "Please select a smaller image (under 5 MB recommended)."
        );
      }

      if (roboflowResponse.statusCode == 415) {
        throw Exception(
            "Image format not supported by the analysis service.\n"
                "Please try a different image (JPG or PNG recommended)."
        );
      }

      if (roboflowResponse.statusCode == 400) {
        throw Exception(
            "Invalid image. The image may be corrupted or in an unsupported format.\n"
                "Please try another image."
        );
      }

      if (roboflowResponse.statusCode != 200) {
        print("📡 API Error Response: ${roboflowResponse.body}");
        throw Exception(
            "Image analysis failed (Error ${roboflowResponse.statusCode}).\n"
                "Please try again or contact support."
        );
      }

      final responseJson = jsonDecode(roboflowResponse.body);
      print("📡 Full API Response: $responseJson");

      // Step 9: Validate response
      if (responseJson['predictions'] == null) {
        throw Exception(
            "No makeup style detected in the image.\n"
                "Please try an image with clearer makeup or a different angle."
        );
      }

      final predictions = responseJson['predictions'] as List;

      if (predictions.isEmpty) {
        throw Exception(
            "No makeup style detected in the image.\n"
                "Tips:\n"
                "• Ensure the image shows makeup clearly\n"
                "• Use good lighting\n"
                "• Try a close-up photo"
        );
      }

      final detectedTag = predictions[0]['class'] as String;
      final confidence = (predictions[0]['confidence'] as num?)?.toDouble() ?? 0.0;

      print("🎯 Detected Tag: $detectedTag (confidence: ${(confidence * 100).toStringAsFixed(1)}%)");

      // Step 10: Search for matching artists
      final tagToCategoryMap = {
        'bridal': ['wedding'],
        'kpop': ['korean style'],
      };
      final lowerTag = detectedTag.toLowerCase();
      final matchingCategories = <String>{};
      if (tagToCategoryMap.containsKey(lowerTag)) {
        matchingCategories.addAll(tagToCategoryMap[lowerTag]!);
      }
      matchingCategories.add(lowerTag);
      print("🔍 Searching for categories: $matchingCategories");

      final filtered = _allArtists.where((artist) {
        final categories = artist['categories'] as List<String>? ?? [];
        return categories.any((category) =>
            matchingCategories.any((cat) => category.toLowerCase().contains(cat)));
      }).toList();

      if (mounted) {
        setState(() {
          _searchController.text = detectedTag;
          _filteredArtists = filtered;
          _isImageSearchLoading = false;
        });

        widget.onLoadingStateChanged?.call(false);

        print('✅ Filtered ${filtered.length} artists with tag: $detectedTag');

        // Show result message
        if (filtered.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detected: "$detectedTag"',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text('No matching artists found. Try a different search.'),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Found ${filtered.length} artist${filtered.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Matching "$detectedTag" style'),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImageSearchLoading = false;
        });

        widget.onLoadingStateChanged?.call(false);

        print('❌ Image search failed: $e');

        // Show user-friendly error dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700]),
                const SizedBox(width: 12),
                const Text('Search Failed'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.toString().replaceFirst('Exception: ', ''),
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Requirements:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('• Max size: $maxImageSizeInMB MB'),
                        Text('• Formats: ${supportedImageFormats.map((f) => f.toUpperCase()).join(', ')}'),
                        const Text('• Clear, well-lit makeup photo'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // Helper method to format location display text
  String _getLocationDisplayText(Map<String, dynamic> artist) {
    final address = artist['address']?.toString().trim() ?? '';
    if (address.isNotEmpty) {
      return address;
    } else {
      return 'Location not specified';
    }
  }

  // Helper method to check if location data is available for navigation
  bool _hasLocationData(Map<String, dynamic> artist) {
    final address = artist['address']?.toString().trim() ?? '';
    // Check if we have coordinates OR at least an address
    return (address != null) || address.isNotEmpty;
  }

  Future<void> fetchMakeupArtists() async {
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'makeup artist')
          .get();

      List<Map<String, dynamic>> data = [];

      for (var userDoc in userSnapshot.docs) {
        final userId = userDoc.id;
        final userData = userDoc.data();
        final profilePic = userData['profile pictures'] ?? '';

        final artistSnapshot = await FirebaseFirestore.instance
            .collection('makeup_artists')
            .where('user_id', isEqualTo: FirebaseFirestore.instance.doc('users/$userId'))
            .where('status', isEqualTo: 'Approved')
            .get();

        for (var artistDoc in artistSnapshot.docs) {
          final artistData = artistDoc.data();

          // Handle category as array and convert to List<String>
          List<String> categories = [];
          if (artistData['category'] is List) {
            categories = List<String>.from(artistData['category']);
          } else if (artistData['category'] is String) {
            categories = [artistData['category']];
          }

          data.add({
            'user_id': userId,
            'name': artistData['studio_name'] ?? '',
            'profile pictures': profilePic,
            'price': artistData['price'] ?? '',
            'categories': categories, // Store as list
            'images': List<String>.from(artistData['portfolio'] ?? []),
            'address': artistData['address']?.toString().trim() ?? '',
          });
        }
      }

      // Check if the widget is still mounted before calling setState
      if (mounted) {
        setState(() {
          _allArtists = data;
          _filteredArtists = data;
        });

        // Reload recommendations after fetching artists
        _loadRecommendations();
      }
    } catch (e) {
      print('Error fetching makeup artists: $e');
      // Only show error if widget is still mounted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading artists: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<List<Map<String, dynamic>>> _getRecommendedArtists(String currentUserId) async {
    try {
      print('🔍 Getting content-based recommendations for user: $currentUserId');

      // Step 1: Get user's booking history with ratings (Completed AND In Progress)
      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('customerId', isEqualTo: FirebaseFirestore.instance.doc('users/$currentUserId'))
          .where('status', whereIn: ['Completed', 'In Progress'])
          .get();

      print('📋 Found ${appointmentsSnapshot.docs.length} completed and in progress appointments');

      // Step 2: Extract all possible features (categories) from artists
      Set<String> allFeatures = {};
      for (var artist in _allArtists) {
        final categories = artist['categories'] as List<String>? ?? [];
        for (String category in categories) {
          allFeatures.add(category.toLowerCase().trim());
        }
      }

      print('🎯 All available features: $allFeatures');

      // Step 3: Build User Profile P(u,f) = Σ∀R(u,r)>τ F(r,f)
      // Using strict academic formula: count feature presence (1) when rating > threshold
      Map<String, int> userProfile = {}; // Count of highly-rated items with this feature

      Set<String> bookedArtistIds = {};
      Map<String, double> userRatings = {}; // R(u,r): artist_id -> rating

      // Process booking history to build user profile
      if (appointmentsSnapshot.docs.isNotEmpty) {
        print('\n📊 Building User Profile from booking history...');

        for (var appointment in appointmentsSnapshot.docs) {
          final appointmentData = appointment.data();
          final artistRef = appointmentData['artist_id'] as DocumentReference?;
          final category = appointmentData['category'] as String?;
          final status = appointmentData['status'] as String?;

          if (artistRef != null && category != null) {
            final artistId = artistRef.id;
            bookedArtistIds.add(artistId);
            final normalizedCategory = category.toLowerCase().trim();

            // Handle Completed vs In Progress differently
            if (status == 'Completed') {
              // Get rating R(u,r) from reviews for completed appointments
              try {
                final appointmentRef = FirebaseFirestore.instance.doc('appointments/${appointment.id}');
                final reviewsSnapshot = await FirebaseFirestore.instance
                    .collection('reviews')
                    .where('appointment_id', isEqualTo: appointmentRef)
                    .get();

                double totalRating = 0.0;
                int reviewCount = 0;

                for (var review in reviewsSnapshot.docs) {
                  final reviewData = review.data() as Map<String, dynamic>;
                  final rating = (reviewData['rating'] as num?)?.toDouble() ?? 0.0;
                  if (rating > 0) {
                    totalRating += rating;
                    reviewCount++;
                  }
                }

                if (reviewCount > 0) {
                  final avgRating = totalRating / reviewCount;
                  userRatings[artistId] = avgRating;
                  print('⭐ Artist $artistId: User Rating R(u,r) = $avgRating for category "$normalizedCategory" (Completed)');

                  // Build user profile: P(u,f) = Σ∀R(u,r)>τ F(r,f)
                  const double ratingThreshold = 3.0; // τ = 3.0

                  if (avgRating > ratingThreshold) {
                    // FORMULA: Add 1 (F(r,f) = 1) when rating > threshold
                    userProfile[normalizedCategory] = (userProfile[normalizedCategory] ?? 0) + 1;
                    print('   ✅ Added to profile: $normalizedCategory += 1 (rating $avgRating > τ)');
                  } else {
                    print('   ❌ Rating $avgRating ≤ τ ($ratingThreshold), not added to profile');
                  }
                } else {
                  // No review but user booked this category (implicit interest)
                  // Assume neutral positive rating above threshold
                  userProfile[normalizedCategory] = (userProfile[normalizedCategory] ?? 0) + 1;
                  print('   ℹ️ No review (Completed), implicit interest: $normalizedCategory += 1');
                }
              } catch (e) {
                print('⚠️ Error fetching reviews for appointment ${appointment.id}: $e');
                // Still record implicit interest
                userProfile[normalizedCategory] = (userProfile[normalizedCategory] ?? 0) + 1;
              }
            } else if (status == 'In Progress') {
              // Handle In Progress appointments - show intent/interest
              userProfile[normalizedCategory] = (userProfile[normalizedCategory] ?? 0) + 1;
              print('🕐 In Progress appointment for "$normalizedCategory": Added implicit interest += 1');
            }
          }
        }
        print('\n👤 User Profile P(u,f) from bookings (feature counts): $userProfile');
      }

      // Step 4: If no booking history, use stated preferences
      if (userProfile.isEmpty) {
        print('⚠️ No booking history, checking user preferences...');

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final userPreferences = List<String>.from(userData['preferences'] ?? []);

          if (userPreferences.isNotEmpty) {
            print('🎯 Building profile from stated preferences');
            for (String pref in userPreferences) {
              final normalizedPref = pref.toLowerCase().trim();
              userProfile[normalizedPref] = 1; // Single count for each preference
            }
            print('👤 User Profile P(u,f) from preferences: $userProfile');
          }
        }
      }

      // Step 5: If still no profile, return top-rated
      if (userProfile.isEmpty) {
        print('⭐ No profile available, returning top-rated artists');
        return _getTopRatedArtists();
      }

      // Step 6: Calculate content-based similarity for all candidate artists
      print('\n📊 Calculating Content-Based Similarity Scores...');

      List<Map<String, dynamic>> scoredArtists = [];

      for (var artist in _allArtists) {
        final artistId = artist['user_id'] as String?; // Changed from 'id' to 'user_id'

        if (artistId == null) {
          print('⚠️ Skipping artist with null ID: ${artist['name']}');
          continue;
        }

        // Skip already booked artists
        if (bookedArtistIds.contains(artistId)) {
          print('⏭️ Skipping already booked artist: ${artist['name']}');
          continue;
        }
        // Build feature vector for this artist F(artist, f)
        final artistCategories = (artist['categories'] as List<String>? ?? [])
            .map((cat) => cat.toLowerCase().trim())
            .toSet();

        Map<String, int> artistFeatureVector = {};
        for (String feature in allFeatures) {
          artistFeatureVector[feature] = artistCategories.contains(feature) ? 1 : 0;
        }

        // Calculate content-based similarity: Similarity(u, artist) = P(u,f) · F(artist,f)
        // This is dot product of user profile and artist feature vector
        double similarityScore = 0.0;
        List<String> matchingFeatures = [];

        for (String feature in allFeatures) {
          final userFeatureCount = userProfile[feature] ?? 0; // How many highly-rated items had this feature
          final artistHasFeature = artistFeatureVector[feature]!; // 0 or 1

          if (userFeatureCount > 0 && artistHasFeature == 1) {
            similarityScore += userFeatureCount * artistHasFeature;
            matchingFeatures.add(feature);
          }
        }

        if (similarityScore > 0) {
          print('🎯 Artist ${artist['name']}:');
          print('   Matching Features: $matchingFeatures');
          print('   Content-Based Similarity: ${similarityScore.toStringAsFixed(2)}');

          // Detailed calculation breakdown
          _printCalculationBreakdown(userProfile, artist, similarityScore);

          scoredArtists.add({
            ...artist,
            'similarity_score': similarityScore,
            'recommendation_score': similarityScore,
            'matching_features': matchingFeatures,
            'explanation': _generateContentExplanation(artist, matchingFeatures, userProfile)
          });
        }
      }

      // Step 7: Sort by similarity score (descending) and return top N
      if (scoredArtists.isEmpty) {
        print('⚠️ No matching artists found, returning top-rated');
        return _getTopRatedArtists();
      }

      scoredArtists.sort((a, b) =>
          (b['similarity_score'] as double).compareTo(a['similarity_score'] as double));

      final topRecommendations = scoredArtists.take(5).toList();

      print('\n🎊 Top ${topRecommendations.length} Content-Based Recommendations:');
      for (var i = 0; i < topRecommendations.length; i++) {
        final artist = topRecommendations[i];
        print('${i + 1}. ${artist['name']} - Score: ${(artist['similarity_score'] as double).toStringAsFixed(2)}');
        print('   Features: ${artist['matching_features']}');
      }

      return topRecommendations;

    } catch (e) {
      print('❌ Error getting recommendations: $e');
      return [];
    }
  }

  String _generateContentExplanation(
      Map<String, dynamic> artist,
      List<String> matchingFeatures,
      Map<String, int> userProfile) {  // Changed from double to int

    final artistName = artist['name'] ?? 'This artist';

    if (matchingFeatures.isEmpty) {
      return '$artistName is recommended based on popularity';
    }

    // Sort features by count (most booked first)
    matchingFeatures.sort((a, b) =>
        (userProfile[b] ?? 0).compareTo(userProfile[a] ?? 0));

    final topFeature = matchingFeatures.first;
    final featureCount = userProfile[topFeature] ?? 0;

    if (matchingFeatures.length == 1) {
      return '$artistName specializes in $topFeature (based on $featureCount previous booking${featureCount > 1 ? 's' : ''})';
    } else if (matchingFeatures.length <= 3) {
      String featureList = matchingFeatures.join(', ');
      return '$artistName offers $featureList, services you\'ve enjoyed before';
    } else {
      String topFeatures = matchingFeatures.take(3).join(', ');
      return '$artistName provides $topFeatures and more services you\'re interested in';
    }
  }

// VERIFICATION METHOD 1: Print detailed calculation breakdown
  void _printCalculationBreakdown(
      Map<String, int> userProfile,
      Map<String, dynamic> artist,
      double calculatedScore) {
    print('\n═══════════════════════════════════════');
    print('📊 CALCULATION BREAKDOWN for ${artist['name']}');
    print('═══════════════════════════════════════');

    final artistCategories = (artist['categories'] as List<String>? ?? [])
        .map((cat) => cat.toLowerCase().trim())
        .toSet();

    print('\n👤 User Profile:');
    userProfile.forEach((feature, count) {
      print('   $feature: $count');
    });

    print('\n🎨 Artist Features: $artistCategories');

    print('\n🧮 Similarity Calculation:');
    double manualTotal = 0.0;

    for (String feature in artistCategories) {
      final count = userProfile[feature] ?? 0;
      if (count > 0) {
        print('   $feature: $count × 1 = $count');
        manualTotal += count.toDouble();
      }
    }

    print('   ─────────────────────────');
    print('   Total (Manual): $manualTotal');
    print('   Total (System): $calculatedScore');

    // Validate the calculation
    const double epsilon = 0.001;
    bool isCorrect = (manualTotal - calculatedScore).abs() < epsilon;
    print('   Match: ${isCorrect ? "✅ CORRECT" : "❌ ERROR - Difference: ${(manualTotal - calculatedScore).abs()}"}');
    print('═══════════════════════════════════════\n');
  }

// Fallback: Top-rated artists (non-personalized)
  Future<List<Map<String, dynamic>>> _getTopRatedArtists() async {
    print('⭐ Getting top-rated artists as fallback');

    List<Map<String, dynamic>> artistsWithRatings = [];

    for (var artist in _allArtists) {
      try {
        final artistSnapshot = await FirebaseFirestore.instance
            .collection('makeup_artists')
            .where('user_id', isEqualTo: FirebaseFirestore.instance.doc('users/${artist['user_id']}'))
            .where('status', isEqualTo: 'Approved')
            .get();

        if (artistSnapshot.docs.isNotEmpty) {
          final artistData = artistSnapshot.docs.first.data();
          final averageRating = (artistData['average_rating'] as num?)?.toDouble() ?? 0.0;
          artistsWithRatings.add({
            ...artist,
            'rating': averageRating,
            'recommendation_score': averageRating,
            'explanation': 'Popular artist with ${averageRating.toStringAsFixed(1)}⭐ rating'
          });
        }
      } catch (e) {
        print('⚠️ Error fetching rating for artist ${artist['user_id']}: $e');
      }
    }

    artistsWithRatings.sort((a, b) {
      final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
      final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
      return ratingB.compareTo(ratingA);
    });

    return artistsWithRatings.take(5).toList();
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

  // Widget to build category chips
  Widget _buildCategoryChips(List<String> categories) {
    if (categories.isEmpty) {
      return const Text(
        'No categories specified',
        style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: categories.map((category) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFDA9BF5).withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDA9BF5).withOpacity(0.3)),
          ),
          child: Text(
            category,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF925F70),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Homepage",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        actions: [
          if (_recommendedArtists.isNotEmpty && !_isImageSearchLoading)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Material(
                color: _showRecommendations
                    ? const Color(0xFFDA9BF5)
                    : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                elevation: _showRecommendations ? 4 : 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      _showRecommendations = !_showRecommendations;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showRecommendations ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                          color: _showRecommendations ? Colors.white : const Color(0xFFDA9BF5),
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showRecommendations ? 'Hide' : 'For You',
                          style: TextStyle(
                            color: _showRecommendations ? Colors.white : const Color(0xFFDA9BF5),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background Image
          Container(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: _allArtists.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar section - FIXED HEIGHT
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.photo_camera,
                            color: _isImageSearchLoading ? Colors.grey : const Color(0xFFDA9BF5),
                          ),
                          onPressed: _isImageSearchLoading ? null : () {
                            _showCameraOrGalleryPicker(context);
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            enabled: !_isImageSearchLoading,
                            decoration: const InputDecoration(
                              hintText: "Search makeup artist...",
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: Colors.grey),
                            ),
                            onChanged: (text) {
                              if (text.isEmpty) {
                                setState(() {
                                  _filteredArtists = _allArtists;
                                });
                              }
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: _isImageSearchLoading ? null : () {
                            final query = _searchController.text.trim();
                            if (query.isNotEmpty) {
                              _handleTextSearch(context, query);
                            }
                          },
                          child: Text(
                            "Search",
                            style: TextStyle(
                              color: _isImageSearchLoading ? Colors.grey : const Color(0xFFDA9BF5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Scrollable content - recommendations + artist list
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Recommendations section
                        if (_showRecommendations && _recommendedArtists.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(0xFFDA9BF5).withOpacity(0.8),
                                        const Color(0xFF925F70).withOpacity(0.8),
                                      ],
                                    ),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFDA9BF5).withOpacity(0.3),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.auto_awesome,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Just For You',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              'Curated based on your preferences',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Recommendations cards
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.95),
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(20),
                                      bottomRight: Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: SizedBox(
                                    height: 120,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _recommendedArtists.take(5).length,
                                      itemBuilder: (context, index) {
                                        final artist = _recommendedArtists[index];
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => MakeupArtistDetailsPage(userId: artist['user_id']),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            width: 240,
                                            margin: const EdgeInsets.only(right: 16),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Colors.white,
                                                  const Color(0xFFDA9BF5).withOpacity(0.05),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFFDA9BF5).withOpacity(0.2),
                                                width: 1.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFDA9BF5).withOpacity(0.1),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(0xFFDA9BF5).withOpacity(0.3),
                                                        blurRadius: 10,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipOval(
                                                    child: Image.network(
                                                      artist['profile pictures'],
                                                      width: 60,
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Container(
                                                          width: 60,
                                                          height: 60,
                                                          decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                              colors: [
                                                                const Color(0xFFDA9BF5).withOpacity(0.7),
                                                                const Color(0xFF925F70).withOpacity(0.7),
                                                              ],
                                                            ),
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: const Icon(Icons.person, size: 30, color: Colors.white),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        artist['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.black87,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              const Color(0xFFDA9BF5).withOpacity(0.2),
                                                              const Color(0xFF925F70).withOpacity(0.2),
                                                            ],
                                                          ),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.star,
                                                              size: 14,
                                                              color: Colors.amber[700],
                                                            ),
                                                            const SizedBox(width: 4),
                                                            const Text(
                                                              'Recommend',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w600,
                                                                color: Color(0xFF925F70),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Tap to view details',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey[600],
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Makeup Artist List
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredArtists.length,
                          itemBuilder: (context, index) {
                            final p = _filteredArtists[index];
                            final hasLocation = _hasLocationData(p);
                            final categories = p['categories'] as List<String>? ?? [];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ClipOval(
                                              child: Image.network(
                                                p['profile pictures'],
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    width: 60,
                                                    height: 60,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.grey,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.person, size: 30, color: Colors.white),
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(right: 48),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      p['name'] ?? '',
                                                      style: const TextStyle(
                                                        fontSize: 19,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    _buildCategoryChips(categories),
                                                    const SizedBox(height: 6),
                                                    _buildExpandableLocation(p, index),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          height: 160,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: (p['images'] as List).length.clamp(0, 6),
                                            itemBuilder: (context, imgIndex) {
                                              final imgUrl = p['images'][imgIndex];
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: GestureDetector( // ADD THIS
                                                    onTap: () => _showImageDialog(
                                                      context,
                                                      imgUrl,
                                                    ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.network(
                                                    imgUrl,
                                                    width: 160,
                                                    height: 160,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        width: 160,
                                                        height: 160,
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey[300],
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Icon(Icons.image, size: 40, color: Colors.grey),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              )
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            if (hasLocation) ...[
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => MakeupArtistLocationPage(
                                                        artistName: p['name'],
                                                        address: p['address'] ?? 'Address not available',
                                                        profilePicture: p['profile pictures'],
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(Icons.location_on, size: 18),
                                                label: const Text("Location"),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                  elevation: 2,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => MakeupArtistDetailsPage(userId: p['user_id']),
                                                  ),
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFDA9BF5),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                elevation: 3,
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              ),
                                              child: const Text(
                                                "Book Now",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: IconButton(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ChatPage(
                                                artistId: p['user_id'],
                                                artistName: p['name'],
                                                artistProfilePic: p['profile pictures'],
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.chat_bubble_outline),
                                        color: const Color(0xFFDA9BF5),
                                        iconSize: 20,
                                        tooltip: 'Chat with ${p['name']}',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay for image search - ALWAYS ON TOP
          if (_isImageSearchLoading)
            Positioned.fill(
              child: _buildImageSearchLoading(),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandableLocation(Map<String, dynamic> artist, int index) {
    final hasLocation = _hasLocationData(artist);
    final locationText = _getLocationDisplayText(artist);
    final isExpanded = _expandedAddresses[index] ?? false;
    final shouldShowExpansion = locationText.length > 30;

    return InkWell(
      onTap: shouldShowExpansion ? () {
        setState(() {
          _expandedAddresses[index] = !isExpanded;
        });
      } : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on,
            size: 16,
            color: hasLocation ? Colors.grey : Colors.grey[400],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isExpanded || !shouldShowExpansion
                      ? locationText
                      : '${locationText.substring(0, 30)}...',
                  style: TextStyle(
                    fontSize: 14,
                    color: hasLocation ? Colors.grey : Colors.grey[400],
                    fontStyle: hasLocation ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: isExpanded ? null : 1,
                  overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
                if (shouldShowExpansion)
                  Text(
                    isExpanded ? 'Show less' : 'Show more',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDA9BF5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Loading widget for image search
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
                'Analyzing your image...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Finding matching makeup artists',
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
}