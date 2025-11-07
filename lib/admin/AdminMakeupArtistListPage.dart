import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:blush_up/admin/AdminMakeupArtistDetails.dart';

class AdminMakeupArtistList extends StatefulWidget {
  final String? initialFilter;
  const AdminMakeupArtistList({super.key, required this.initialFilter});

  @override
  State<AdminMakeupArtistList> createState() => _AdminMakeupArtistListState();
}

class _AdminMakeupArtistListState extends State<AdminMakeupArtistList>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _pendingMakeupArtists = [];
  List<Map<String, dynamic>> _approvedMakeupArtists = [];
  List<Map<String, dynamic>> _rejectedMakeupArtists = [];
  List<Map<String, dynamic>> _allStatusMakeupArtists = [];
  List<Map<String, dynamic>> _filteredPendingMakeupArtists = [];
  List<Map<String, dynamic>> _filteredApprovedMakeupArtists = [];
  List<Map<String, dynamic>> _filteredRejectedMakeupArtists = [];
  List<Map<String, dynamic>> _filteredAllStatusMakeupArtists = [];
  String? _currentUserId;
  bool _isSearching = false;
  String _selectedSort = 'studio_name';
  bool _hasInitialized = false;
  bool _isLoading = false;
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Set initial tab based on initialFilter
    int initialIndex = 0;
    switch (widget.initialFilter) {
      case 'pending':
        initialIndex = 0;
        break;
      case 'approved':
        initialIndex = 1;
        break;
      case 'rejected':
        initialIndex = 2;
        break;
      case 'all':
        initialIndex = 3;
        break;
      default:
        initialIndex = 0;
    }
    _tabController.index = initialIndex;

    _searchController.addListener(() {
      setState(() {});
    });

    _getCurrentUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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

  // Helper method to format categories from array
  String _formatCategories(dynamic categoryData) {
    if (categoryData == null) return 'Unknown Category';

    if (categoryData is List) {
      // Handle array format
      List<String> categories = [];
      for (var item in categoryData) {
        if (item is String && item.isNotEmpty) {
          categories.add(item);
        }
      }
      return categories.isNotEmpty ? categories.join(', ') : 'Unknown Category';
    } else if (categoryData is String) {
      // Handle single string format
      return categoryData.isNotEmpty ? categoryData : 'Unknown Category';
    }

    return 'Unknown Category';
  }

  // Helper method to get status color
  Color _getStatusColor(String status) {
    print('🎨 DEBUG: Getting color for status: "$status"');
    switch (status.toLowerCase()) {
      case 'approved':
        print('🎨 DEBUG: Status color -> GREEN');
        return Colors.green;
      case 'rejected':
      case 'disabled':
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

  // Helper method to get status icon
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'disabled':
        return Icons.block;
      case 'pending':
        return Icons.access_time;
      default:
        return Icons.help;
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

        final userRef = makeupArtistData['user_id'] as DocumentReference?;
        if (userRef != null) {
          final userDoc = await userRef.get();
          final userData = userDoc.data() as Map<String, dynamic>?;

          final processedMakeupArtist = {
            'makeup_artist_id': makeupArtistId,
            'studio_name': makeupArtistData['studio_name'] ?? 'Unknown Studio',
            'category': makeupArtistData['category'],
            'formatted_category': _formatCategories(makeupArtistData['category']),
            'status': makeupArtistData['status'] ?? 'pending',
            'profile_picture': userData?['profile pictures'] ?? '',
            'phone_number': makeupArtistData['phone_number'].toString() ?? '',
            'email': makeupArtistData['email'] ?? '',
            'user_id': userRef.id,
          };

          makeupArtistsData.add(processedMakeupArtist);
        }
      }

      // Separate artists by status
      final pendingMakeupArtists = <Map<String, dynamic>>[];
      final approvedMakeupArtists = <Map<String, dynamic>>[];
      final rejectedMakeupArtists = <Map<String, dynamic>>[];
      final allMakeupArtists = <Map<String, dynamic>>[];

      for (var makeupArtist in makeupArtistsData) {
        final status = makeupArtist['status']?.toLowerCase() ?? '';

        switch (status) {
          case 'pending':
            pendingMakeupArtists.add(makeupArtist);
            break;
          case 'approved':
            approvedMakeupArtists.add(makeupArtist);
            break;
          case 'rejected':
          case 'disabled':
            rejectedMakeupArtists.add(makeupArtist);
            break;
        }
        allMakeupArtists.add(makeupArtist);
      }

      // Sort all lists by studio name
      pendingMakeupArtists.sort((a, b) => (a['studio_name'] ?? '').compareTo(b['studio_name'] ?? ''));
      approvedMakeupArtists.sort((a, b) => (a['studio_name'] ?? '').compareTo(b['studio_name'] ?? ''));
      rejectedMakeupArtists.sort((a, b) => (a['studio_name'] ?? '').compareTo(b['studio_name'] ?? ''));
      allMakeupArtists.sort((a, b) => (a['studio_name'] ?? '').compareTo(b['studio_name'] ?? ''));

      setState(() {
        _pendingMakeupArtists = pendingMakeupArtists;
        _approvedMakeupArtists = approvedMakeupArtists;
        _rejectedMakeupArtists = rejectedMakeupArtists;
        _allStatusMakeupArtists = allMakeupArtists;

        // Initialize filtered lists
        _filteredPendingMakeupArtists = pendingMakeupArtists;
        _filteredApprovedMakeupArtists = approvedMakeupArtists;
        _filteredRejectedMakeupArtists = rejectedMakeupArtists;
        _filteredAllStatusMakeupArtists = allMakeupArtists;

        _hasInitialized = true;
        _isLoading = false;

        _applySortingToAllLists();
      });

      print('Fetched ${makeupArtistsData.length} makeup artists');
    } catch (e) {
      print('Error fetching makeup artists: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading makeup artists: ${e.toString()}')),
      );
    }
  }

  void _handleSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredPendingMakeupArtists = _pendingMakeupArtists;
        _filteredApprovedMakeupArtists = _approvedMakeupArtists;
        _filteredRejectedMakeupArtists = _rejectedMakeupArtists;
        _filteredAllStatusMakeupArtists = _allStatusMakeupArtists;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();

    setState(() {
      _filteredPendingMakeupArtists = _pendingMakeupArtists.where((artist) =>
          _matchesSearch(artist, lowerQuery)).toList();

      _filteredApprovedMakeupArtists = _approvedMakeupArtists.where((artist) =>
          _matchesSearch(artist, lowerQuery)).toList();

      _filteredRejectedMakeupArtists = _rejectedMakeupArtists.where((artist) =>
          _matchesSearch(artist, lowerQuery)).toList();

      _filteredAllStatusMakeupArtists = _allStatusMakeupArtists.where((artist) =>
          _matchesSearch(artist, lowerQuery)).toList();
    });
  }

  bool _matchesSearch(Map<String, dynamic> artist, String query) {
    final studioName = (artist['studio_name'] ?? '').toLowerCase();
    final email = (artist['email'] ?? '').toLowerCase();
    final phone = (artist['phone_number'] ?? '').toLowerCase();
    final status = (artist['status'] ?? '').toLowerCase();
    final category = (artist['formatted_category'] ?? '').toLowerCase();

    return studioName.contains(query) ||
        email.contains(query) ||
        phone.contains(query) ||
        status.contains(query) ||
        category.contains(query);
  }

  void _applySortingToAllLists() {
    // Helper function to sort a list
    void sortList(List<Map<String, dynamic>> list) {
      list.sort((a, b) {
        int comparison = 0;

        switch (_selectedSort) {
          case 'studio_name':
            comparison = (a['studio_name'] ?? '').toString().toLowerCase()
                .compareTo((b['studio_name'] ?? '').toString().toLowerCase());
            break;
          case 'category':
            comparison = (a['formatted_category'] ?? '').toString().toLowerCase()
                .compareTo((b['formatted_category'] ?? '').toString().toLowerCase());
            break;
          default:
            return 0;
        }

        // Apply ascending or descending order
        return _isAscending ? comparison : -comparison;
      });
    }

    // Sort all lists
    sortList(_pendingMakeupArtists);
    sortList(_approvedMakeupArtists);
    sortList(_rejectedMakeupArtists);
    sortList(_allStatusMakeupArtists);

    // Sort filtered lists
    sortList(_filteredPendingMakeupArtists);
    sortList(_filteredApprovedMakeupArtists);
    sortList(_filteredRejectedMakeupArtists);
    sortList(_filteredAllStatusMakeupArtists);
  }

  // Widget _buildMakeupArtistCard(Map<String, dynamic> makeupArtist) {
  //   print('🃏 DEBUG: Building card for makeup artist: ${makeupArtist['makeup_artist_id']}');
  //   print('🃏 DEBUG: Card makeup artist status: "${makeupArtist['status']}"');
  //   print('🃏 DEBUG: Card studio name: "${makeupArtist['studio_name']}"');
  //   print('🃏 DEBUG: Card formatted category: "${makeupArtist['formatted_category']}"');
  //
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 16),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(16),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.1),
  //           blurRadius: 8,
  //           offset: const Offset(0, 2),
  //         ),
  //       ],
  //     ),
  //     child: Column(
  //       children: [
  //         // Makeup Artist Info Section
  //         Padding(
  //           padding: const EdgeInsets.all(16),
  //           child: Row(
  //             children: [
  //               // Profile Picture
  //               Container(
  //                 width: 60,
  //                 height: 60,
  //                 decoration: BoxDecoration(
  //                   shape: BoxShape.circle,
  //                   color: const Color(0xFFFFB347),
  //                 ),
  //                 child: ClipOval(
  //                   child: makeupArtist['profile_picture'] != null &&
  //                       makeupArtist['profile_picture'].isNotEmpty
  //                       ? Image.network(
  //                     makeupArtist['profile_picture'],
  //                     fit: BoxFit.cover,
  //                     errorBuilder: (context, error, stackTrace) {
  //                       return const Icon(Icons.person, size: 30, color: Colors.white);
  //                     },
  //                   )
  //                       : const Icon(Icons.person, size: 30, color: Colors.white),
  //                 ),
  //               ),
  //               const SizedBox(width: 16),
  //               // Makeup Artist Details
  //               Expanded(
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         const Text(
  //                           'Studio: ',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                             color: Colors.black,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             makeupArtist['studio_name'] ?? 'Unknown',
  //                             style: const TextStyle(
  //                               fontSize: 14,
  //                               color: Colors.grey,
  //                             ),
  //                             overflow: TextOverflow.ellipsis,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 4),
  //                     Row(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         const Text(
  //                           'Category: ',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                             color: Colors.black,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             makeupArtist['formatted_category'] ?? 'Unknown',
  //                             style: const TextStyle(
  //                               fontSize: 14,
  //                               color: Colors.grey,
  //                             ),
  //                             maxLines: 2,
  //                             overflow: TextOverflow.ellipsis,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 4),
  //                     Row(
  //                       children: [
  //                         const Text(
  //                           'Phone: ',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                             color: Colors.black,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             ('0${makeupArtist['phone_number']}') ?? 'N/A',
  //                             style: const TextStyle(
  //                               fontSize: 14,
  //                               color: Colors.grey,
  //                             ),
  //                             overflow: TextOverflow.ellipsis,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 4),
  //                     Row(
  //                       children: [
  //                         const Text(
  //                           'Email: ',
  //                           style: TextStyle(
  //                             fontSize: 14,
  //                             fontWeight: FontWeight.w500,
  //                             color: Colors.black,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             makeupArtist['email'] ?? 'N/A',
  //                             style: const TextStyle(
  //                               fontSize: 14,
  //                               color: Colors.grey,
  //                             ),
  //                             overflow: TextOverflow.ellipsis,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 8),
  //                     // Status Badge
  //                     Container(
  //                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  //                       decoration: BoxDecoration(
  //                         color: _getStatusColor(makeupArtist['status'] ?? '').withOpacity(0.1),
  //                         borderRadius: BorderRadius.circular(20),
  //                         border: Border.all(
  //                           color: _getStatusColor(makeupArtist['status'] ?? ''),
  //                           width: 1,
  //                         ),
  //                       ),
  //                       child: Row(
  //                         mainAxisSize: MainAxisSize.min,
  //                         children: [
  //                           Icon(
  //                             _getStatusIcon(makeupArtist['status'] ?? ''),
  //                             size: 16,
  //                             color: _getStatusColor(makeupArtist['status'] ?? ''),
  //                           ),
  //                           const SizedBox(width: 6),
  //                           Text(
  //                             (makeupArtist['status'] ?? 'Unknown').toUpperCase(),
  //                             style: TextStyle(
  //                               fontSize: 12,
  //                               color: _getStatusColor(makeupArtist['status'] ?? ''),
  //                               fontWeight: FontWeight.w600,
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //         // Details Button
  //         Container(
  //           width: double.infinity,
  //           margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  //           child: ElevatedButton(
  //             onPressed: () async {
  //               // Navigate to details page and refresh when coming back
  //               await Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (context) => AdminMakeUpArtistDetails(
  //                     makeupArtistId: makeupArtist['makeup_artist_id'],
  //                   ),
  //                 ),
  //               );
  //               // Refresh data when returning from details page
  //               _refreshData();
  //             },
  //             style: ElevatedButton.styleFrom(
  //               backgroundColor: const Color(0xFFB968C7),
  //               foregroundColor: Colors.white,
  //               shape: RoundedRectangleBorder(
  //                 borderRadius: BorderRadius.circular(25),
  //               ),
  //               padding: const EdgeInsets.symmetric(vertical: 12),
  //             ),
  //             child: const Text(
  //               'View Details',
  //               style: TextStyle(
  //                 fontSize: 16,
  //                 fontWeight: FontWeight.w600,
  //               ),
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildMakeupArtistsList(String status) {
    List<Map<String, dynamic>> makeupArtists;
    String emptyMessage;

    switch (status) {
      case 'pending':
        makeupArtists = _filteredPendingMakeupArtists;
        emptyMessage = 'No pending requests';
        break;
      case 'approved':
        makeupArtists = _filteredApprovedMakeupArtists;
        emptyMessage = 'No approved makeup artists';
        break;
      case 'rejected':
        makeupArtists = _filteredRejectedMakeupArtists;
        emptyMessage = 'No rejected/disabled makeup artists';
        break;
      case 'all':
        makeupArtists = _filteredAllStatusMakeupArtists;
        emptyMessage = 'No makeup artists found';
        break;
      default:
        makeupArtists = [];
        emptyMessage = 'No makeup artists found';
    }

    if (_isLoading) {
      return _buildLoadingIndicator();
    }

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
                emptyMessage,
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

    return ListView.builder(
      itemCount: makeupArtists.length,
      itemBuilder: (context, index) {
        final makeupArtist = makeupArtists[index];
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
                            return const Icon(Icons.person, size: 30, color: Colors.white);
                          },
                        )
                            : const Icon(Icons.person, size: 30, color: Colors.white),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                  makeupArtist['formatted_category'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 2,
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
                                  ('0${makeupArtist['phone_number']}') ?? 'N/A',
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
                          const SizedBox(height: 8),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(makeupArtist['status'] ?? '').withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _getStatusColor(makeupArtist['status'] ?? ''),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(makeupArtist['status'] ?? ''),
                                  size: 16,
                                  color: _getStatusColor(makeupArtist['status'] ?? ''),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  (makeupArtist['status'] ?? 'Unknown').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _getStatusColor(makeupArtist['status'] ?? ''),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
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
                    'View Details',
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
      },
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
              child: Column(
                children: [
                  // Fixed Header Section
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Artist Management",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Search Bar
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
                                    hintText: "Search name/email/phone/category",
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(color: Colors.grey),
                                  ),
                                  onChanged: _handleSearch,
                                ),
                              ),
                              IconButton(
                                icon: _searchController.text.isNotEmpty
                                    ? const Icon(Icons.clear, color: Colors.grey)
                                    : const Icon(Icons.search, color: Colors.grey),
                                onPressed: () {
                                  if (_searchController.text.isNotEmpty) {
                                    _searchController.clear();
                                    _handleSearch('');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Tab Bar
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: Colors.black,
                            unselectedLabelColor: Colors.grey,
                            indicator: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            tabs: [
                              Tab(text: 'Pending (${_pendingMakeupArtists.length})'),
                              Tab(text: 'Approved (${_approvedMakeupArtists.length})'),
                              Tab(text: 'Rejected (${_rejectedMakeupArtists.length})'),
                              Tab(text: 'All (${_allStatusMakeupArtists.length})'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Sort Filter
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  value: _selectedSort,
                                  decoration: const InputDecoration(
                                    labelText: 'Sort by',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'studio_name', child: Text('Studio Name')),
                                    DropdownMenuItem(value: 'category', child: Text('Category')),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedSort = value!;
                                      _applySortingToAllLists();
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isAscending = !_isAscending;
                                    _applySortingToAllLists();
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                        size: 20,
                                        color: Colors.black,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isAscending ? 'A-Z' : 'Z-A',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Tab Bar View
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMakeupArtistsList('pending'),
                          _buildMakeupArtistsList('approved'),
                          _buildMakeupArtistsList('rejected'),
                          _buildMakeupArtistsList('all'),
                        ],
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
}