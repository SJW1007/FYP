import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blush_up/admin/AdminMakeupArtistDetails.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allMakeupArtists = [];
  List<Map<String, dynamic>> _pendingMakeupArtists = [];
  List<Map<String, dynamic>> _filteredAllMakeupArtists = [];
  List<Map<String, dynamic>> _filteredPendingMakeupArtists = [];
  final ImagePicker _picker = ImagePicker();
  String? _currentUserId;
  bool _isSearching = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getCurrentUser();
  }

  // This method is called when the app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, refresh data
      _refreshData();
    }
  }

  // Add this method to handle route awareness
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This will be called every time the page is navigated to
    if (mounted && _currentUserId != null) {
      _refreshData();
    }
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

  // New refresh method
  Future<void> _refreshData() async {
    if (_currentUserId != null && mounted) {
      print('🔄 Refreshing data...');
      await fetchMakeupArtists();
    }
  }

  // Add pull-to-refresh functionality
  Future<void> _onRefresh() async {
    await _refreshData();
  }

  // Navigation method to artist details page
  Future<void> _navigateToArtistDetails(Map<String, dynamic> artist) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminMakeUpArtistDetails(
          makeupArtistId: artist['artist_id'],
        ),
      ),
    );

    // Always refresh the data when returning from details page
    // since the status might have been changed
    _refreshData(); // or whatever your refresh method is called
  }

  Future<void> _handleTextSearch(BuildContext context, String query) async {
    setState(() {
      _isSearching = true;
    });
    try {
      final lowerQuery = query.toLowerCase();

      // Filter pending makeup artists based on search query
      List<Map<String, dynamic>> filteredPending = _pendingMakeupArtists.where((artist) {
        final studioName = artist['studio_name']?.toLowerCase() ?? '';
        final category = artist['category']?.toLowerCase() ?? '';
        final status = artist['status']?.toLowerCase() ?? '';

        return studioName.contains(lowerQuery) ||
            category.contains(lowerQuery) ||
            status.contains(lowerQuery);
      }).toList();

      // Filter all makeup artists based on search query
      List<Map<String, dynamic>> filteredAll = _allMakeupArtists.where((artist) {
        final studioName = artist['studio_name']?.toLowerCase() ?? '';
        final category = artist['category']?.toLowerCase() ?? '';
        final status = artist['status']?.toLowerCase() ?? '';

        return studioName.contains(lowerQuery) ||
            category.contains(lowerQuery) ||
            status.contains(lowerQuery);
      }).toList();

      setState(() {
        _filteredPendingMakeupArtists = filteredPending;
        _filteredAllMakeupArtists = filteredAll;
        _isSearching = false;
      });

      print('✅ Found ${filteredPending.length} pending makeup artists matching search');
      print('✅ Found ${filteredAll.length} total makeup artists matching search');

    } catch (e) {
      print('❌ Error searching makeup artists: $e');
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching makeup artists: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> fetchMakeupArtists() async {
    if (_currentUserId == null || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('📡 Fetching fresh data from Firestore...');

      // Fetch ALL makeup artists (no status filter)
      final makeupArtistsSnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .get();

      List<Map<String, dynamic>> allMakeupArtistsData = [];
      List<Map<String, dynamic>> pendingMakeupArtistsData = [];

      for (var artistDoc in makeupArtistsSnapshot.docs) {
        final artistData = artistDoc.data();
        final artistId = artistDoc.id;

        // Get the user_id reference
        final userRef = artistData['user_id'] as DocumentReference?;
        String? profilePicture;

        if (userRef != null) {
          try {
            // Fetch user data to get profile picture
            final userDoc = await userRef.get();
            final userData = userDoc.data() as Map<String, dynamic>?;
            profilePicture = userData?['profile pictures'] ?? '';
          } catch (e) {
            print('Error fetching user data for artist $artistId: $e');
            profilePicture = '';
          }
        }

        final artistMap = {
          'artist_id': artistId,
          'studio_name': artistData['studio_name'] ?? 'Unknown Studio',
          'category': artistData['category'] ?? 'Unknown Category',
          'status': artistData['status'] ?? 'Unknown',
          'profile_picture': profilePicture ?? '',
          'user_id': userRef?.id ?? '',
        };

        // Add to all artists list
        allMakeupArtistsData.add(artistMap);

        // Add to pending list if status is pending
        if (artistData['status'] == 'Pending') {
          pendingMakeupArtistsData.add(artistMap);
        }
      }

      if (mounted) {
        setState(() {
          _allMakeupArtists = allMakeupArtistsData;
          _pendingMakeupArtists = pendingMakeupArtistsData;
          // Initialize filtered lists with all data
          _filteredAllMakeupArtists = allMakeupArtistsData;
          _filteredPendingMakeupArtists = pendingMakeupArtistsData;
          _isLoading = false;
        });
      }

      print('✅ Fetched ${allMakeupArtistsData.length} total makeup artists');
      print('✅ Found ${pendingMakeupArtistsData.length} pending makeup artists');
    } catch (e) {
      print('❌ Error fetching makeup artists: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading makeup artists: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildHorizontalMakeupArtistList(List<Map<String, dynamic>> makeupArtists) {
    return SizedBox(
      height: 300,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: makeupArtists.length,
        itemBuilder: (context, index) {
          final artist = makeupArtists[index];
          return Container(
            width: 200,
            margin: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => _navigateToArtistDetails(artist),
              child: Container(
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
                    Expanded(
                      flex: 3,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          color: Color(0xFFFFB347),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: artist['profile_picture'] != null &&
                              artist['profile_picture'].isNotEmpty
                              ? Image.network(
                            artist['profile_picture'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.person, size: 50, color: Colors.white),
                              );
                            },
                          )
                              : const Center(
                            child: Icon(Icons.person, size: 50, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              artist['studio_name'] ?? 'Unknown Studio',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              artist['category'] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Status indicator with different colors
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(artist['status']),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                artist['status'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected'||'disabled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSearchQuery = _searchController.text.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/purple_background.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: _currentUserId == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _onRefresh,
              child: _allMakeupArtists.isEmpty && !hasSearchQuery && !_isLoading
                  ? const Center(child: Text('No data available. Pull to refresh.'))
                  : Column(
                children: [
                  // Fixed header section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Admin Dashboard",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            if (_isLoading)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                child: TextField(
                                  controller: _searchController,
                                  decoration: const InputDecoration(
                                    hintText: "Search by name/ category / status",
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(color: Colors.grey),
                                  ),
                                  onChanged: (text) {
                                    if (text.isEmpty) {
                                      setState(() {
                                        _filteredAllMakeupArtists = _allMakeupArtists;
                                        _filteredPendingMakeupArtists = _pendingMakeupArtists;
                                      });
                                    }
                                  },
                                  onSubmitted: (text) {
                                    if (text.trim().isNotEmpty) {
                                      _handleTextSearch(context, text.trim());
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: _isSearching
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Icon(Icons.search, color: Colors.grey),
                                onPressed: _isSearching ? null : () {
                                  final query = _searchController.text.trim();
                                  if (query.isNotEmpty) {
                                    _handleTextSearch(context, query);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Scrollable content section
                  Expanded(
                    child: _isLoading
                        ? _buildContentLoadingIndicator()
                        : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),

                            // Pending Makeup Artists Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Pending Makeup Artists",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                if (_filteredPendingMakeupArtists.isNotEmpty)
                                  Text(
                                    "Swipe to see more →",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black.withOpacity(0.8),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            if (_filteredPendingMakeupArtists.isEmpty)
                              Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    hasSearchQuery
                                        ? 'No pending makeup artists found matching your search'
                                        : 'No pending makeup artists',
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                ),
                              )
                            else
                              _buildHorizontalMakeupArtistList(_filteredPendingMakeupArtists),

                            const SizedBox(height: 40),

                            // All Makeup Artists Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "All Makeup Artists",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                if (_filteredAllMakeupArtists.isNotEmpty)
                                  Text(
                                    "Swipe to see more →",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black.withOpacity(0.8),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            if (_filteredAllMakeupArtists.isEmpty)
                              Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    hasSearchQuery
                                        ? 'No makeup artists found matching your search'
                                        : 'No makeup artists found',
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                ),
                              )
                            else
                              _buildHorizontalMakeupArtistList(_filteredAllMakeupArtists),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildContentLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB266FF)),
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
    );
  }
}