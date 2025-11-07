import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blush_up/admin/AdminMakeupArtistDetails.dart';
import 'package:blush_up/admin/AdminNavigation.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allMakeupArtists = [];
  List<Map<String, dynamic>> _pendingMakeupArtists = [];
  List<Map<String, dynamic>> _filteredPendingMakeupArtists = [];
  String? _currentUserId;
  bool _isSearching = false;
  bool _isLoading = false;

  // Statistics
  Map<String, int> _statusCounts = {
    'pending': 0,
    'approved': 0,
    'rejected': 0,
    'total': 0,
  };

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
    _searchController.addListener(() {
      setState(() {});
    });
    _getCurrentUser();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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

  Future<void> _refreshData() async {
    if (_currentUserId != null && mounted) {
      await fetchMakeupArtists();
    }
  }

  Future<void> _onRefresh() async {
    await _refreshData();
  }

  Future<void> _navigateToArtistDetails(Map<String, dynamic> artist) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AdminMakeUpArtistDetails(
              makeupArtistId: artist['artist_id'],
            ),
      ),
    );
    _refreshData();
  }

  void _navigateToFullList(String status) {
    final navigationState = context.findAncestorStateOfType<
        AdminMainNavigationState>();
    navigationState?.navigateToList(status);
  }

  Future<void> _handleTextSearch(BuildContext context, String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final lowerQuery = query.toLowerCase();
      List<Map<String, dynamic>> filteredPending = _pendingMakeupArtists.where((
          artist) {
        final studioName = artist['studio_name']?.toLowerCase() ?? '';
        final categories = artist['category'] as List<String>? ?? [];
        final categoryMatch = categories.any((cat) =>
            cat.toLowerCase().contains(lowerQuery));
        return studioName.contains(lowerQuery) || categoryMatch;
      }).toList();

      setState(() {
        _filteredPendingMakeupArtists = filteredPending;
        _isSearching = false;
      });
    } catch (e) {
      print('❌ Error searching makeup artists: $e');
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> fetchMakeupArtists() async {
    if (_currentUserId == null || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final makeupArtistsSnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .get();

      List<Map<String, dynamic>> allMakeupArtistsData = [];
      List<Map<String, dynamic>> pendingMakeupArtistsData = [];

      Map<String, int> statusCounts = {
        'pending': 0,
        'approved': 0,
        'rejected': 0,
        'total': 0,
      };

      for (var artistDoc in makeupArtistsSnapshot.docs) {
        final artistData = artistDoc.data();
        final artistId = artistDoc.id;

        final userRef = artistData['user_id'] as DocumentReference?;
        String? profilePicture;

        if (userRef != null) {
          try {
            final userDoc = await userRef.get();
            final userData = userDoc.data() as Map<String, dynamic>?;
            profilePicture = userData?['profile pictures'] ?? '';
          } catch (e) {
            profilePicture = '';
          }
        }

        List<String> categories = [];
        final categoryData = artistData['category'];

        if (categoryData is List) {
          categories = categoryData.map((item) => item.toString()).toList();
        } else if (categoryData is String) {
          categories = [categoryData];
        }

        final artistMap = {
          'artist_id': artistId,
          'studio_name': artistData['studio_name'] ?? 'Unknown Studio',
          'category': categories,
          'category_display': _formatCategoriesForDisplay(categories),
          'status': artistData['status'] ?? 'Unknown',
          'profile_picture': profilePicture ?? '',
          'user_id': userRef?.id ?? '',
        };

        allMakeupArtistsData.add(artistMap);
        statusCounts['total'] = statusCounts['total']! + 1;

        final status = artistData['status']?.toLowerCase() ?? '';
        switch (status) {
          case 'pending':
            pendingMakeupArtistsData.add(artistMap);
            statusCounts['pending'] = statusCounts['pending']! + 1;
            break;
          case 'approved':
            statusCounts['approved'] = statusCounts['approved']! + 1;
            break;
          case 'rejected':
          case 'disabled':
            statusCounts['rejected'] = statusCounts['rejected']! + 1;
            break;
        }
      }

      if (mounted) {
        setState(() {
          _allMakeupArtists = allMakeupArtistsData;
          _pendingMakeupArtists = pendingMakeupArtistsData;
          _filteredPendingMakeupArtists = pendingMakeupArtistsData;
          _statusCounts = statusCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error fetching makeup artists: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatCategoriesForDisplay(List<String> categories) {
    if (categories.isEmpty) return 'No Category';
    if (categories.length == 1) return categories[0];
    if (categories.length <= 2) return categories.join(' & ');
    return '${categories.take(2).join(', ')} & ${categories.length - 2} more';
  }

//   // Simplified Statistics Overview
//   Widget _buildStatsOverview() {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       margin: const EdgeInsets.symmetric(horizontal: 16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.1),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Dashboard Overview',
//             style: TextStyle(
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               color: Colors.grey[800],
//             ),
//           ),
//           const SizedBox(height: 20),
//           Row(
//             children: [
//               Expanded(
//                 child: _buildStatItem(
//                   'Total Artists',
//                   _statusCounts['total']!,
//                   Colors.blue,
//                   Icons.people,
//                 ),
//               ),
//               Container(width: 1, height: 50, color: Colors.grey[300]),
//               Expanded(
//                 child: _buildStatItem(
//                   'Approved',
//                   _statusCounts['approved']!,
//                   Colors.green,
//                   Icons.check_circle,
//                 ),
//               ),
//               Container(width: 1, height: 50, color: Colors.grey[300]),
//               Expanded(
//                 child: _buildStatItem(
//                   'Pending',
//                   _statusCounts['pending']!,
//                   Colors.orange,
//                   Icons.hourglass_empty,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildStatItem(String title, int count, Color color, IconData icon) {
//     return Column(
//       children: [
//         Icon(icon, color: color, size: 24),
//         const SizedBox(height: 8),
//         Text(
//           count.toString(),
//           style: TextStyle(
//             fontSize: 24,
//             fontWeight: FontWeight.bold,
//             color: color,
//           ),
//         ),
//         Text(
//           title,
//           style: TextStyle(
//             fontSize: 12,
//             color: Colors.grey[600],
//             fontWeight: FontWeight.w500,
//           ),
//           textAlign: TextAlign.center,
//         ),
//       ],
//     );
//   }
//
//   // Simplified Reports Overview
//   Widget _buildReportsOverview() {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance.collection('reports').snapshots(),
//       builder: (context, snapshot) {
//         if (!snapshot.hasData) {
//           return Container(
//             height: 120,
//             margin: const EdgeInsets.symmetric(horizontal: 16),
//             child: Center(child: CircularProgressIndicator()),
//           );
//         }
//
//         final reports = snapshot.data!.docs;
//         final pendingReports = reports.where((doc) =>
//         (doc.data() as Map<String, dynamic>)['status'] == 'pending').length;
//         final totalReports = reports.length;
//
//         return Container(
//           padding: const EdgeInsets.all(20),
//           margin: const EdgeInsets.symmetric(horizontal: 16),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(16),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.1),
//                 blurRadius: 10,
//                 offset: const Offset(0, 4),
//               ),
//             ],
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(Icons.report_problem, color: Colors.red, size: 24),
//                   const SizedBox(width: 12),
//                   Text(
//                     'Reports',
//                     style: TextStyle(
//                       fontSize: 20,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.grey[800],
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               Row(
//                 children: [
//                   Expanded(
//                     child: Column(
//                       children: [
//                         Text(
//                           totalReports.toString(),
//                           style: TextStyle(
//                             fontSize: 24,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.red,
//                           ),
//                         ),
//                         Text(
//                           'Total Reports',
//                           style: TextStyle(
//                             fontSize: 12,
//                             color: Colors.grey[600],
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   Container(width: 1, height: 40, color: Colors.grey[300]),
//                   Expanded(
//                     child: Column(
//                       children: [
//                         Text(
//                           pendingReports.toString(),
//                           style: TextStyle(
//                             fontSize: 24,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.orange,
//                           ),
//                         ),
//                         Text(
//                           'Pending',
//                           style: TextStyle(
//                             fontSize: 12,
//                             color: Colors.grey[600],
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
  Widget _buildHorizontalMakeupArtistList(
    List<Map<String, dynamic>> makeupArtists,
    {int? limit, bool showShowAllCard = false}
    ) {
  // Apply limit if specified
  final displayArtists = limit != null && makeupArtists.length > limit
      ? makeupArtists.take(limit).toList()
      : makeupArtists;

  return SizedBox(
    height: 280,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: showShowAllCard && makeupArtists.length > (limit ?? 0)
          ? displayArtists.length + 1  // Add 1 for "Show All" card
          : displayArtists.length,
      itemBuilder: (context, index) {
        // Check if this is the "Show All" card
        if (showShowAllCard &&
            makeupArtists.length > (limit ?? 0) &&
            index == displayArtists.length) {
          return _buildShowMoreCard(makeupArtists.length);
        }

        final artist = displayArtists[index];
        return Container(
          width: 180,
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
                            artist['category_display'] ?? 'No Category',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange,
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

// method for the "Show More" card:
Widget _buildShowMoreCard(int totalCount) {
  return Container(
    width: 180,
    margin: const EdgeInsets.only(right: 16),
    child: GestureDetector(
      onTap: () => _navigateToFullList('pending'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.arrow_forward,
              size: 50,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'Show More',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$totalCount requests',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
//
//   // Simplified Request List
//   Widget _buildRequestsList() {
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 16),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.1),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Padding(
//             padding: const EdgeInsets.all(20),
//             child: Row(
//               children: [
//                 Icon(Icons.pending_actions, color: Colors.orange, size: 24),
//                 const SizedBox(width: 12),
//                 Text(
//                   'Pending Requests',
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.grey[800],
//                   ),
//                 ),
//                 const Spacer(),
//                 Text(
//                   '${_filteredPendingMakeupArtists.length}',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.orange,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           if (_filteredPendingMakeupArtists.isEmpty)
//             Container(
//               height: 100,
//               child: Center(
//                 child: Text(
//                   'No pending requests',
//                   style: TextStyle(
//                     color: Colors.grey[600],
//                     fontSize: 16,
//                   ),
//                 ),
//               ),
//             )
//           else
//             Padding(
//               padding: const EdgeInsets.only(bottom: 20),
//               child: _buildHorizontalMakeupArtistList(_filteredPendingMakeupArtists.take(5).toList()),
//             ),
//           if (_filteredPendingMakeupArtists.length > 5)
//             Padding(
//               padding: const EdgeInsets.only(bottom: 16),
//               child: Center(
//                 child: TextButton(
//                   onPressed: () => _navigateToFullList('pending'),
//                   child: Text(
//                     'View All ${_filteredPendingMakeupArtists.length} Requests',
//                     style: TextStyle(
//                       color: Colors.orange,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           // Background
//           Container(
//             decoration: const BoxDecoration(
//               image: DecorationImage(
//                 image: AssetImage('assets/purple_background.png'),
//                 fit: BoxFit.cover,
//               ),
//             ),
//           ),
//           // Content
//           SafeArea(
//             child: _currentUserId == null
//                 ? const Center(child: CircularProgressIndicator())
//                 : RefreshIndicator(
//               onRefresh: _onRefresh,
//               child: SingleChildScrollView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Header
//                     Padding(
//                       padding: const EdgeInsets.all(16),
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Row(
//                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                             children: [
//                               Text(
//                                 "Admin Dashboard",
//                                 style: TextStyle(
//                                   fontSize: 28,
//                                   fontWeight: FontWeight.bold,
//                                   color: Colors.black,
//                                 ),
//                               ),
//                               if (_isLoading)
//                                 SizedBox(
//                                   width: 20,
//                                   height: 20,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                                   ),
//                                 ),
//                             ],
//                           ),
//                           const SizedBox(height: 16),
//                           // Search Bar
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 16),
//                             decoration: BoxDecoration(
//                               color: Colors.white,
//                               borderRadius: BorderRadius.circular(25),
//                               boxShadow: [
//                                 BoxShadow(
//                                   color: Colors.black.withOpacity(0.1),
//                                   blurRadius: 8,
//                                   offset: const Offset(0, 2),
//                                 ),
//                               ],
//                             ),
//                             child: Row(
//                               children: [
//                                 Expanded(
//                                   child: TextField(
//                                     controller: _searchController,
//                                     decoration: const InputDecoration(
//                                       hintText: "Search pending requests...",
//                                       border: InputBorder.none,
//                                       hintStyle: TextStyle(color: Colors.grey),
//                                     ),
//                                     onChanged: (text) {
//                                       if (text.isEmpty) {
//                                         setState(() {
//                                           _filteredPendingMakeupArtists = _pendingMakeupArtists;
//                                         });
//                                       } else {
//                                         _handleTextSearch(context, text.trim());
//                                       }
//                                     },
//                                     onSubmitted: (text) {
//                                       if (text.trim().isNotEmpty) {
//                                         _handleTextSearch(context, text.trim());
//                                       }
//                                     },
//                                   ),
//                                 ),
//                                 IconButton(
//                                   icon: _searchController.text.isNotEmpty
//                                       ? const Icon(Icons.clear, color: Colors.grey)
//                                       : const Icon(Icons.search, color: Colors.grey),
//                                   onPressed: () {
//                                     if (_searchController.text.isNotEmpty) {
//                                       _searchController.clear();
//                                       setState(() {
//                                         _filteredPendingMakeupArtists = _pendingMakeupArtists;
//                                       });
//                                     } else {
//                                       final query = _searchController.text.trim();
//                                       if (query.isNotEmpty) {
//                                         _handleTextSearch(context, query);
//                                       }
//                                     }
//                                   },
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//
//                     // Content
//                     if (_isLoading)
//                       Container(
//                         height: 300,
//                         child: Center(
//                           child: CircularProgressIndicator(
//                             valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                           ),
//                         ),
//                       )
//                     else ...[
//                       const SizedBox(height: 8),
//                       // Stats Overview
//                       _buildStatsOverview(),
//                       const SizedBox(height: 16),
//                       // Reports Overview
//                       _buildReportsOverview(),
//                       const SizedBox(height: 16),
//                       // Requests List
//                       _buildRequestsList(),
//                       const SizedBox(height: 24),
//                     ],
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/purple_background.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Content
          SafeArea(
            child: _currentUserId == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Admin Dashboard",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              if (_isLoading)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
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
                                      hintText: "Search pending requests...",
                                      border: InputBorder.none,
                                      hintStyle: TextStyle(color: Colors.grey),
                                    ),
                                    onChanged: (text) {
                                      if (text.isEmpty) {
                                        setState(() {
                                          _filteredPendingMakeupArtists =
                                              _pendingMakeupArtists;
                                        });
                                      } else {
                                        _handleTextSearch(context, text.trim());
                                      }
                                    },
                                    onSubmitted: (text) {
                                      if (text
                                          .trim()
                                          .isNotEmpty) {
                                        _handleTextSearch(context, text.trim());
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: _searchController.text.isNotEmpty
                                      ? const Icon(
                                      Icons.clear, color: Colors.grey)
                                      : const Icon(
                                      Icons.search, color: Colors.grey),
                                  onPressed: () {
                                    if (_searchController.text.isNotEmpty) {
                                      _searchController.clear();
                                      setState(() {
                                        _filteredPendingMakeupArtists =
                                            _pendingMakeupArtists;
                                      });
                                    } else {
                                      final query = _searchController.text
                                          .trim();
                                      if (query.isNotEmpty) {
                                        _handleTextSearch(context, query);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    if (_isLoading)
                      Container(
                        height: 300,
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        ),
                      )
                    else
                      ...[
                        const SizedBox(height: 8),

                        // Stats Overview
                        Container(
                          padding: const EdgeInsets.all(20),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dashboard Overview',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Icon(Icons.people, color: Colors.blue,
                                            size: 24),
                                        const SizedBox(height: 8),
                                        Text(
                                          _statusCounts['total']!.toString(),
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        Text(
                                          'Total Artists',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1,
                                      height: 50,
                                      color: Colors.grey[300]),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.green, size: 24),
                                        const SizedBox(height: 8),
                                        Text(
                                          _statusCounts['approved']!.toString(),
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        Text(
                                          'Approved',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1,
                                      height: 50,
                                      color: Colors.grey[300]),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Icon(Icons.hourglass_empty,
                                            color: Colors.orange, size: 24),
                                        const SizedBox(height: 8),
                                        Text(
                                          _statusCounts['pending']!.toString(),
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange,
                                          ),
                                        ),
                                        Text(
                                          'Pending',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Reports Overview
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection(
                              'reports').snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Container(
                                height: 120,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }

                            final reports = snapshot.data!.docs;
                            final pendingReports = reports.where((doc) =>
                            (doc.data() as Map<String, dynamic>)['status'] ==
                                'pending').length;
                            final totalReports = reports.length;

                            return Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.report_problem,
                                          color: Colors.red, size: 24),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Reports',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text(
                                              totalReports.toString(),
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red,
                                              ),
                                            ),
                                            Text(
                                              'Total Reports',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(width: 1,
                                          height: 40,
                                          color: Colors.grey[300]),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            Text(
                                              pendingReports.toString(),
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            Text(
                                              'Pending',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Requests List
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.pending_actions, color: Colors.orange, size: 24),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Pending',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_filteredPendingMakeupArtists.isNotEmpty)
                                      Text(
                                        "Swipe to see more →",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black.withOpacity(0.8),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_filteredPendingMakeupArtists.isEmpty)
                                Container(
                                  height: 100,
                                  child: Center(
                                    child: Text(
                                      'No pending requests',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: _buildHorizontalMakeupArtistList(
                                    _filteredPendingMakeupArtists,
                                    limit: 10,
                                    showShowAllCard: _filteredPendingMakeupArtists.length > 10,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
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