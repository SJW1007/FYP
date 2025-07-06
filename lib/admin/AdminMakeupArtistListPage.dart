import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blush_up/admin/AdminMakeupArtistDetails.dart';

class AdminMakeupArtistList extends StatefulWidget {
  const AdminMakeupArtistList({super.key});

  @override
  State<AdminMakeupArtistList> createState() => _AdminMakeupArtistListState();
}

class _AdminMakeupArtistListState extends State<AdminMakeupArtistList> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allMakeupArtists = [];
  List<Map<String, dynamic>> _filteredMakeupArtists = [];
  List<Map<String, dynamic>> _pendingMakeupArtists = [];
  List<Map<String, dynamic>> _allStatusMakeupArtists = [];
  String? _currentUserId;
  bool _isSearching = false;
  bool _showPending = true; // Toggle between pending and all
  bool _hasInitialized = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  Future<void> _refreshData() async {
    print('Refreshing makeup artists data...');
    await fetchMakeupArtists();
  }

  void _getCurrentUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      fetchMakeupArtists();
    } else {
      print('No user logged in');
    }
  }

  // Helper method to get status color
  Color _getStatusColor(String status) {
    print('🎨 DEBUG: Getting color for status: "$status"');
    switch (status.toLowerCase()) {
      case 'approved':
        print('🎨 DEBUG: Status color -> GREEN');
        return Colors.green;
      case 'rejected'|| 'disabled':
        print('🎨 DEBUG: Status color -> RED');
        return Colors.red;
      case 'pending':
        print('🎨 DEBUG: Status color -> ORANGE');
        return Colors.orange;
      default:
        print('🎨 DEBUG: Status color -> GREY (default for: "$status")');
        return Colors.grey;
    }
  }

  Future<void> fetchMakeupArtists() async {
    setState(() {
      _isLoading = true;
    });
    try {
      print('Fetching makeup artists data...');

      final makeupArtistsSnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .get();

      List<Map<String, dynamic>> makeupArtistsData = [];

      for (var makeupArtistDoc in makeupArtistsSnapshot.docs) {
        final makeupArtistData = makeupArtistDoc.data();
        final makeupArtistId = makeupArtistDoc.id;

        // DEBUG: Print makeup artist data
        print('DEBUG: Processing makeup artist $makeupArtistId');
        print(
            'DEBUG: Raw makeup artist data: ${makeupArtistData.toString()}');
        print('DEBUG: Status from Firebase: "${makeupArtistData['status']}"');

        final userRef = makeupArtistData['user_id'] as DocumentReference?;
        if (userRef != null) {
          final userDoc = await userRef.get();
          final userData = userDoc.data() as Map<String, dynamic>?;

          final processedMakeupArtist = {
            'makeup_artist_id': makeupArtistId,
            'studio_name': makeupArtistData['studio_name'] ?? 'Unknown Studio',
            'category': makeupArtistData['category'] ?? 'Unknown Category',
            'status': makeupArtistData['status'] ?? 'pending',
            'profile_picture': userData?['profile pictures'] ?? '',
            'phone_number': makeupArtistData['phone_number'] ?? '',
            'email': makeupArtistData['email'] ?? '',
            'user_id': userRef.id,
          };

          // DEBUG: Print processed makeup artist
          print(
              'DEBUG: Processed makeup artist status: "${processedMakeupArtist['status']}"');
          print(
              'DEBUG: Processed studio name: "${processedMakeupArtist['studio_name']}"');

          makeupArtistsData.add(processedMakeupArtist);
        }
      }

      final pendingMakeupArtists = <Map<String, dynamic>>[];
      final allMakeupArtists = <Map<String, dynamic>>[];

      for (var makeupArtist in makeupArtistsData) {
        final status = makeupArtist['status']?.toLowerCase() ?? '';

        if (status == 'pending') {
          pendingMakeupArtists.add(makeupArtist);
        }
        allMakeupArtists.add(makeupArtist);
      }

      // Sort by studio name
      pendingMakeupArtists.sort((a, b) {
        final studioA = a['studio_name'] ?? '';
        final studioB = b['studio_name'] ?? '';
        return studioA.compareTo(studioB);
      });

      allMakeupArtists.sort((a, b) {
        final studioA = a['studio_name'] ?? '';
        final studioB = b['studio_name'] ?? '';
        return studioA.compareTo(studioB);
      });

      setState(() {
        _allMakeupArtists = makeupArtistsData;
        _filteredMakeupArtists = makeupArtistsData;
        _pendingMakeupArtists = pendingMakeupArtists;
        _allStatusMakeupArtists = allMakeupArtists;
        _hasInitialized = true; // Mark as initialized
        _isLoading = false;
      });

      print('Fetched ${makeupArtistsData.length} makeup artists');
      print('DEBUG: Pending makeup artists: ${pendingMakeupArtists.length}');
      print('DEBUG: All makeup artists: ${allMakeupArtists.length}');
    } catch (e) {
      print('Error fetching makeup artists: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error loading makeup artists: ${e.toString()}')),
      );
    }
  }

  Widget _buildToggleButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showPending = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _showPending ? const Color(0xFFB968C7) : Colors
                      .transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'Pending Requests',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _showPending ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showPending = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_showPending ? const Color(0xFFB968C7) : Colors
                      .transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'All Artists',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !_showPending ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMakeupArtistCard(Map<String, dynamic> makeupArtist) {
    print(
        '🃏 DEBUG: Building card for makeup artist: ${makeupArtist['makeup_artist_id']}');
    print('🃏 DEBUG: Card makeup artist status: "${makeupArtist['status']}"');
    print('🃏 DEBUG: Card studio name: "${makeupArtist['studio_name']}"');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
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
        children: [
          // Makeup Artist Info Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Profile Picture
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB347),
                  ),
                  child: ClipOval(
                    child: makeupArtist['profile_picture'] != null &&
                        makeupArtist['profile_picture'].isNotEmpty
                        ? Image.network(
                      makeupArtist['profile_picture'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person, size: 30, color: Colors
                            .white);
                      },
                    )
                        : const Icon(
                        Icons.person, size: 30, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                // Makeup Artist Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Studio: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              makeupArtist['studio_name'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Category: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              makeupArtist['category'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Phone: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              makeupArtist['phone_number'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Email: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              makeupArtist['email'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Status: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            makeupArtist['status'] ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 14,
                              color: _getStatusColor(
                                  makeupArtist['status'] ?? ''),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Details Button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: () async {
                // Navigate to details page and refresh when coming back
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminMakeUpArtistDetails(
                      makeupArtistId: makeupArtist['makeup_artist_id'],
                    ),
                  ),
                );
                // Refresh data when returning from details page
                _refreshData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB968C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    if (_isLoading) {
      return _buildLoadingIndicator();
    }

    final makeupArtists = _showPending
        ? _pendingMakeupArtists
        : _allStatusMakeupArtists;

    print('📱 DEBUG: Building makeup artists list');
    print('📱 DEBUG: Show pending: $_showPending');
    print('📱 DEBUG: Makeup artists count: ${makeupArtists.length}');
    print('📱 DEBUG: Is searching: $_isSearching');

    if (_isSearching) {
      return _buildLoadingIndicator();
    }

    if (makeupArtists.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.face_retouching_natural,
                size: 48,
                color: Colors.black.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _showPending
                    ? 'No makeup artist requests'
                    : 'No makeup artists found',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: makeupArtists.map((makeupArtist) =>
          _buildMakeupArtistCard(makeupArtist)).toList(),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB968C7)),
              strokeWidth: 6,
            ),
            const SizedBox(height: 20),
            Text(
              'Loading makeup artists...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/purple_background.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Content Layer
          SafeArea(
            child: _currentUserId == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _refreshData,
              color: const Color(0xFFB968C7),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fixed Header Section
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Makeup Artist Management",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Fixed Toggle Button
                    _buildToggleButton(),
                    const SizedBox(height: 24),

                    // Dynamic Content Area (this is what gets replaced with loading or content)
                    _buildContentArea(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}