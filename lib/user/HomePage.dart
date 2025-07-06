import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'MakeupArtistDetails.dart';
import 'MakeupArtistLocationPage.dart'; // New page for showing location
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allArtists = [];
  List<Map<String, dynamic>> _filteredArtists = [];
  final ImagePicker _picker = ImagePicker();
  bool _isImageSearchLoading = false;
  Map<int, bool> _expandedAddresses = {}; // Track which addresses are expanded

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void initState() {
    super.initState();
    fetchMakeupArtists();
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
      final category = artist['category']?.toLowerCase() ?? '';

      return name.contains(lowerQuery) ||
          matchedCategories.any((cat) => category.contains(cat));
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
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Select Image Source",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Color(0xFFDA9BF5)),
                title: const Text("Use Camera"),
                onTap: () async {
                  Navigator.pop(context);
                  final photo = await _picker.pickImage(source: ImageSource.camera);
                  if (photo != null) {
                    await _handleImageSearch(File(photo.path));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFFDA9BF5)),
                title: const Text("Choose from Gallery"),
                onTap: () async {
                  Navigator.pop(context);
                  final image = await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    await _handleImageSearch(File(image.path));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleImageSearch(File imageFile) async {
    // Start loading
    setState(() {
      _isImageSearchLoading = true;
    });

    try {
      // Check if dotenv is properly loaded and API key exists
      final apiKey = dotenv.env['API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception("API key not found. Please check your .env file configuration.");
      }

      print("🔑 Using API key (length: ${apiKey.length})");

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Roboflow API Call
      final roboflowResponse = await http.post(
        Uri.parse("https://classify.roboflow.com/makeup-detection-ttdth/1?api_key=$apiKey"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: base64Image,
      );

      print("📡 API Response Status: ${roboflowResponse.statusCode}");

      if (roboflowResponse.statusCode != 200) {
        print("📡 API Response Body: ${roboflowResponse.body}");
        throw Exception("Roboflow API failed with status ${roboflowResponse.statusCode}: ${roboflowResponse.body}");
      }

      final responseJson = jsonDecode(roboflowResponse.body);
      print("📡 Full API Response: $responseJson");

      // Check if predictions exist and are not empty
      if (responseJson['predictions'] == null ||
          (responseJson['predictions'] as List).isEmpty) {
        throw Exception("No makeup style detected in the image. Please try another image.");
      }

      final detectedTag = responseJson['predictions'][0]['class'] as String;
      print("🎯 Detected Tag: $detectedTag");

      // Define tag-category mappings (case-insensitive)
      final tagToCategoryMap = {
        'bridal': ['wedding'],
        'kpop': ['korean style'],
        // Add more mappings as needed
      };
      final lowerTag = detectedTag.toLowerCase();
      // Find matching categories
      final matchingCategories = <String>{};
      // Check direct mapping
      if (tagToCategoryMap.containsKey(lowerTag)) {
        matchingCategories.addAll(tagToCategoryMap[lowerTag]!);
      }
      // Always include the detected tag itself
      matchingCategories.add(lowerTag);
      print("🔍 Searching for categories: $matchingCategories");
      // Filter artists
      final filtered = _allArtists.where((artist) {
        final category = artist['category']?.toLowerCase() ?? '';
        return matchingCategories.any((cat) => category.contains(cat));
      }).toList();
      setState(() {
        _searchController.text = detectedTag; // Update search bar
        _filteredArtists = filtered;
        _isImageSearchLoading = false; // Stop loading
      });
      print('✅ Filtered ${filtered.length} artists with tag: $detectedTag');
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${filtered.length} artists matching "$detectedTag"'),
            backgroundColor: filtered.isEmpty ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isImageSearchLoading = false; // Stop loading on error
      });
      print('❌ Image search failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }



  // Helper method to format location display text
  String _getLocationDisplayText(Map<String, dynamic> artist) {
    final address = artist['address']?.toString().trim() ?? '';
    if  (address.isNotEmpty) {
      return address;
    } else {
      return 'Location not specified';
    }
  }

  // Helper method to check if location data is available for navigation
  bool _hasLocationData(Map<String, dynamic> artist) {
    final address = artist['address']?.toString().trim() ?? '';
    // Check if we have coordinates OR at least an address
    return (address != null ) ||
        address.isNotEmpty;
  }

  Future<void> fetchMakeupArtists() async {
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

        data.add({
          'user_id': userId,
          'name': artistData['studio_name']??'',
          'profile pictures': profilePic,
          'price': artistData['price'] ?? '',
          'category': artistData['category'] ?? '',
          'images': List<String>.from(artistData['portfolio'] ?? []),
          'address': artistData['address']?.toString().trim() ?? '',
        });
      }
    }

    setState(() {
      _allArtists = data;
      _filteredArtists = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
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
            // Foreground content
            _allArtists.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Homepage Label
                  const Text(
                    "Homepage",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // search bar with camera and search button
                  Container(
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
                        // Camera Icon Button (for image search)
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

                        // TextField for typing
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

                        // Text Search Button
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

                  const SizedBox(height: 20),

                  // Makeup Artist List
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredArtists.length,
                      itemBuilder: (context, index) {
                        final p = _filteredArtists[index];
                        final hasLocation = _hasLocationData(p);

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
                            child: Column(
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

                                    // Name and Category
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p['name'] ?? '',
                                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            p['category'] ?? '',
                                            style: const TextStyle(fontSize: 16, color: Color(0xFF925F70)),
                                          ),
                                          const SizedBox(height: 4),
                                          // Location info with improved handling
                                          _buildExpandableLocation(p, index),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                SizedBox(
                                  height: 160,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: (p['images'] as List).length.clamp(0, 6), // max 6 images
                                    itemBuilder: (context, imgIndex) {
                                      final imgUrl = p['images'][imgIndex];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            imgUrl,
                                            width: 160, // fixed width for horizontal layout
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
                                      );
                                    },
                                  ),
                                ),

                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      p['price'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF925F70),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        // Location button - conditionally shown
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
                                        // Book Now button
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
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Loading overlay for image search
            if (_isImageSearchLoading) _buildImageSearchLoading(),
          ],
        ),
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