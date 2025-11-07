import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> with TickerProviderStateMixin {
  late TabController _tabController;
  String _selectedSort = 'newest_first';
  String _searchQuery = '';
  bool _isAscending = true;
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _cachedDocs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // New method to fetch user names from references
  Future<Map<String, dynamic>> _fetchUserNames(
      Map<String, dynamic> reportData) async {
    final Map<String, dynamic> data = {};

    try {
      // Fetch reporter name and email from users collection
      final reporterId = reportData['reporter_id'];
      if (reporterId != null) {
        DocumentReference reporterRef;
        String reporterIdString;

        if (reporterId is DocumentReference) {
          reporterRef = reporterId;
          reporterIdString = reporterId.id;
        } else {
          reporterRef = FirebaseFirestore.instance.collection('users').doc(
              reporterId.toString());
          reporterIdString = reporterId.toString();
        }

        final reporterDoc = await reporterRef.get();
        if (reporterDoc.exists) {
          final reporterData = reporterDoc.data() as Map<String, dynamic>?;
          data['reporterName'] = reporterData?['name'] ?? 'Unknown User';
          data['reporterEmail'] = reporterData?['email'] ?? 'No email';
        }
        data['reporterId'] = reporterIdString;
      }

      // Fetch reported user name from makeup_artists collection
      final artistId = reportData['artist_id'];
      if (artistId != null) {
        DocumentReference artistRef;
        String artistIdString;

        if (artistId is DocumentReference) {
          artistRef = artistId;
          artistIdString = artistId.id;
        } else {
          artistRef =
              FirebaseFirestore.instance.collection('makeup_artists').doc(
                  artistId.toString());
          artistIdString = artistId.toString();
        }

        final artistDoc = await artistRef.get();
        if (artistDoc.exists) {
          final artistData = artistDoc.data() as Map<String, dynamic>?;
          data['reportedUserName'] =
              artistData?['studio_name'] ?? 'Unknown Studio';
        }
        data['artistId'] = artistIdString;
      }
    } catch (e) {
      print('Error fetching user data: $e');
      // Return default values in case of error
      data['reporterName'] = 'Error loading name';
      data['reportedUserName'] = 'Error loading name';
      data['reporterEmail'] = 'Error loading email';
    }

    return data;
  }

  String _getSortField() {
    switch (_selectedSort) {
      case 'newest_first':
      case 'oldest_first':
        return 'created_at';
      case 'reporter_name':
        return 'created_at'; // Fallback to created_at since we'll sort by name after fetching
      default:
        return 'created_at';
    }
  }
  Future<List<Map<String, dynamic>>> _processReportsWithNames(List<DocumentSnapshot> docs) async {
    List<Map<String, dynamic>> processedReports = [];

    for (var doc in docs) {
      final reportData = doc.data() as Map<String, dynamic>;
      final names = await _fetchUserNames(reportData);

      // Apply search filtering
      if (_searchQuery.isNotEmpty) {
        final searchLower = _searchQuery.toLowerCase();
        final reporterName = names['reporterName']?.toLowerCase() ?? '';
        final reportedUserName = names['reportedUserName']?.toLowerCase() ?? '';
        final reason = reportData['reason']?.toLowerCase() ?? '';
        final reportId = doc.id.toLowerCase();
        final complaintDetails = reportData['complaint_details']?.toLowerCase() ?? '';

        final searchableText = '$reporterName $reportedUserName $reason $reportId $complaintDetails';

        if (!searchableText.contains(searchLower)) {
          continue;
        }
      }

      processedReports.add({
        'doc': doc,
        'reportData': reportData,
        'reporterName': names['reporterName'],
        'reportedUserName': names['reportedUserName'],
        'reporterEmail': names['reporterEmail'],
        'reporterId': names['reporterId'],
        'artistId': names['artistId'],
      });
    }

    return processedReports;
  }

  bool _getSortDescending() {
    return _selectedSort == 'newest_first';
  }

  Stream<QuerySnapshot> _getReportsStream(String status) {
    try {
      Query query = FirebaseFirestore.instance.collection('reports');

      // Add status filter first if not 'all'
      if (status != 'all') {
        // Map 'Active' tab to 'under_review' in database
        String dbStatus = status == 'active' ? 'under_review' : status;
        query = query.where('status', isEqualTo: dbStatus);
      }

      // Then add ordering
      String sortField = _getSortField();
      bool descending = _getSortDescending();

      query = query.orderBy(sortField, descending: descending);

      return query.snapshots();
    } catch (e) {
      print('Error creating reports stream: $e');
      return Stream.fromIterable([]);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute
        .toString().padLeft(2, '0')}';
  }

  Future<void> _updateReportStatus(String reportId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
        'status': newStatus,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report status updated to $newStatus'),
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resolveReport(String reportId) async {
    _showResolutionDialog(reportId, 'resolved');
  }

  Future<void> _dismissReport(String reportId) async {
    _showResolutionDialog(reportId, 'dismissed');
  }
  Future<void> _finalizeReportResolution(String reportId, String status,
      String notes) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
        'status': status,
        'admin_response': notes,
        'resolved_by': currentUser?.uid,
        'resolved_at': FieldValue.serverTimestamp(),
      });

      // Hide loading snackbar by clearing all snackbars
      ScaffoldMessenger.of(context).clearSnackBars();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report ${status} successfully'),
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      // Hide loading snackbar
      ScaffoldMessenger.of(context).clearSnackBars();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error ${status} report: $e'),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
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
              // Close button - always on top and visible
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
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
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
              // Optional: Add a bottom instruction text
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      ),
    );
  }

  void _showResolutionDialog(String reportId, String action) {
    final TextEditingController notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        // Use StatefulBuilder to rebuild dialog when text changes
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Check if text field has content
            bool hasText = notesController.text.trim().isNotEmpty;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    action == 'resolved' ? Icons.check_circle : Icons.cancel,
                    color: action == 'resolved' ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text('${action == 'resolved' ? 'Resolve' : 'Dismiss'} Report'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure you want to ${action == 'resolved' ? 'resolve' : 'dismiss'} this report?',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 4,
                    onChanged: (value) {
                      // Update dialog state when text changes
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: '${action == 'resolved' ? 'Resolution' : 'Dismissal'} notes *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // hintText: 'Explain how this case was settled and any actions taken...',
                      // helperText: 'This will be visible to the user who reported',
                      // helperStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      // Add error text when empty and user tries to submit
                      errorText: notesController.text.isEmpty && !hasText
                          ? null
                          : null,
                    ),
                  ),
                  // Optional: Add character counter
                  if (notesController.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${notesController.text.length} characters',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  // DISABLE BUTTON when text is empty
                  onPressed: hasText ? () async {
                    // Close dialog first
                    Navigator.pop(context);

                    // Show loading snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text('${action == 'resolved' ? 'Resolving' : 'Dismissing'} report...'),
                          ],
                        ),
                        backgroundColor: Colors.blue,
                        duration: const Duration(seconds: 30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );

                    // Process the resolution
                    await _finalizeReportResolution(
                        reportId, action, notesController.text.trim());
                  } : null, // null makes button disabled
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasText
                        ? (action == 'resolved' ? Colors.green : Colors.red)
                        : Colors.grey, // Grey when disabled
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    // Add disabled styling
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!hasText)
                        Padding(
                          padding: const EdgeInsets.only(right: 4.0)
                        ),
                      Text(action == 'resolved' ? 'Resolve' : 'Dismiss'),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/purple_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar with background
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Reports Management',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                width: MediaQuery.of(context).size.width * 0.9,
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
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.toLowerCase();
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: "Search reporter/artist name/report ID/reason",
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _searchQuery.isNotEmpty
                          ? const Icon(Icons.clear, color: Colors.grey)
                          : const Icon(Icons.search, color: Colors.grey),
                      onPressed: () {
                        if (_searchQuery.isNotEmpty) {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Tab Bar with transparent background
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.grey,
                  indicator: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  tabs: const [
                    Tab(text: 'Pending'),
                    Tab(text: 'Verifying'),
                    Tab(text: 'Resolved'),
                    Tab(text: 'All'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Sort Filter
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.only(left: 16, right: 8),
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
                          DropdownMenuItem(value: 'newest_first', child: Text('Newest First')),
                          DropdownMenuItem(value: 'oldest_first', child: Text('Oldest First')),
                          DropdownMenuItem(value: 'reporter_name', child: Text('Reporter Name')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedSort = value!;
                          });
                        },
                      ),
                    ),
                  ),
                  if (_selectedSort == 'reporter_name')
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isAscending = !_isAscending;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 16, left: 8),
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

              const SizedBox(height: 16),

              // Reports List
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildReportsList('pending'),
                    _buildReportsList('under_review'),
                    _buildReportsList('resolved'),
                    _buildReportsList('all'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Widget _buildReportCardFromProcessed(Map<String, dynamic> processedReport) {
  //   final doc = processedReport['doc'] as DocumentSnapshot;
  //   final reportData = processedReport['reportData'] as Map<String, dynamic>;
  //   final reportId = doc.id;
  //
  //   final status = reportData['status'] ?? 'pending';
  //   final reason = reportData['reason'] ?? 'Unknown';
  //   final createdAt = reportData['created_at'] as Timestamp?;
  //   final evidenceUrls = List<String>.from(reportData['evidence_urls'] ?? []);
  //
  //   final reporterName = processedReport['reporterName'] ?? 'Unknown User';
  //   final reportedUserName = processedReport['reportedUserName'] ?? 'Unknown User';
  //   final reporterEmail = processedReport['reporterEmail'] ?? 'No email';
  //   final reporterId = processedReport['reporterId'];
  //   final artistId = processedReport['artistId'];
  //
  //   return Card(
  //     margin: const EdgeInsets.only(bottom: 16),
  //     elevation: 8,
  //     shape: RoundedRectangleBorder(
  //       borderRadius: BorderRadius.circular(16),
  //     ),
  //     child: InkWell(
  //       borderRadius: BorderRadius.circular(16),
  //       child: Container(
  //         decoration: BoxDecoration(
  //           borderRadius: BorderRadius.circular(16),
  //           gradient: LinearGradient(
  //             colors: [
  //               Colors.white.withOpacity(0.95),
  //               Colors.white.withOpacity(0.85),
  //             ],
  //             begin: Alignment.topLeft,
  //             end: Alignment.bottomRight,
  //           ),
  //         ),
  //         child: Padding(
  //           padding: const EdgeInsets.all(16),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               // Header with status, date
  //               Row(
  //                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                 children: [
  //                   _buildStatusChip(status),
  //                   Row(
  //                     children: [
  //                       Text(
  //                         createdAt != null
  //                             ? _formatDate(createdAt.toDate())
  //                             : 'Unknown date',
  //                         style: TextStyle(
  //                           color: Colors.grey.shade600,
  //                           fontSize: 12,
  //                           fontWeight: FontWeight.w500,
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ],
  //               ),
  //
  //               const SizedBox(height: 16),
  //
  //               // Reporter and Reported User Info
  //               Container(
  //                 padding: const EdgeInsets.all(12),
  //                 decoration: BoxDecoration(
  //                   color: Colors.purple.shade50,
  //                   borderRadius: BorderRadius.circular(10),
  //                   border: Border.all(color: Colors.purple.shade200),
  //                 ),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         Icon(Icons.person, color: Colors.purple.shade600, size: 18),
  //                         const SizedBox(width: 8),
  //                         Text(
  //                           'Reporter: ',
  //                           style: TextStyle(
  //                             fontWeight: FontWeight.bold,
  //                             color: Colors.purple.shade700,
  //                             fontSize: 13,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             reporterName,
  //                             style: TextStyle(
  //                               color: Colors.purple.shade600,
  //                               fontSize: 13,
  //                             ),
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 6),
  //                     Row(
  //                       children: [
  //                         Icon(Icons.report, color: Colors.red.shade600, size: 18),
  //                         const SizedBox(width: 8),
  //                         Text(
  //                           'Reported Artist: ',
  //                           style: TextStyle(
  //                             fontWeight: FontWeight.bold,
  //                             color: Colors.red.shade700,
  //                             fontSize: 13,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: Text(
  //                             reportedUserName,
  //                             style: TextStyle(
  //                               color: Colors.red.shade600,
  //                               fontSize: 13,
  //                             ),
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //
  //               const SizedBox(height: 12),
  //
  //               // ID Information and Contact Details
  //               Container(
  //                 padding: const EdgeInsets.all(12),
  //                 decoration: BoxDecoration(
  //                   color: Colors.blue.shade50,
  //                   borderRadius: BorderRadius.circular(10),
  //                   border: Border.all(color: Colors.blue.shade200),
  //                 ),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     // Report ID
  //                     Row(
  //                       children: [
  //                         Icon(Icons.fingerprint, color: Colors.blue.shade600, size: 16),
  //                         const SizedBox(width: 8),
  //                         Text(
  //                           'Report ID: ',
  //                           style: TextStyle(
  //                             fontWeight: FontWeight.bold,
  //                             color: Colors.blue.shade700,
  //                             fontSize: 12,
  //                           ),
  //                         ),
  //                         Expanded(
  //                           child: SelectableText(
  //                             reportId,
  //                             style: TextStyle(
  //                               color: Colors.blue.shade600,
  //                               fontSize: 12,
  //                               fontFamily: 'monospace',
  //                             ),
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 6),
  //                     // User ID and Email
  //                     if (reporterId != null) ...[
  //                       Row(
  //                         children: [
  //                           Icon(Icons.person_outline, color: Colors.blue.shade600, size: 16),
  //                           const SizedBox(width: 8),
  //                           Text(
  //                             'User ID: ',
  //                             style: TextStyle(
  //                               fontWeight: FontWeight.bold,
  //                               color: Colors.blue.shade700,
  //                               fontSize: 12,
  //                             ),
  //                           ),
  //                           Expanded(
  //                             child: SelectableText(
  //                               reporterId,
  //                               style: TextStyle(
  //                                 color: Colors.blue.shade600,
  //                                 fontSize: 12,
  //                                 fontFamily: 'monospace',
  //                               ),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                       const SizedBox(height: 6),
  //                       Row(
  //                         children: [
  //                           Icon(Icons.email_outlined, color: Colors.blue.shade600, size: 16),
  //                           const SizedBox(width: 8),
  //                           Text(
  //                             'User Email: ',
  //                             style: TextStyle(
  //                               fontWeight: FontWeight.bold,
  //                               color: Colors.blue.shade700,
  //                               fontSize: 12,
  //                             ),
  //                           ),
  //                           Expanded(
  //                             child: SelectableText(
  //                               reporterEmail,
  //                               style: TextStyle(
  //                                 color: Colors.blue.shade600,
  //                                 fontSize: 12,
  //                               ),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                     ],
  //                     const SizedBox(height: 6),
  //                     // Artist ID
  //                     if (artistId != null)
  //                       Row(
  //                         children: [
  //                           Icon(Icons.brush_outlined, color: Colors.blue.shade600, size: 16),
  //                           const SizedBox(width: 8),
  //                           Text(
  //                             'Artist ID: ',
  //                             style: TextStyle(
  //                               fontWeight: FontWeight.bold,
  //                               color: Colors.blue.shade700,
  //                               fontSize: 12,
  //                             ),
  //                           ),
  //                           Expanded(
  //                             child: SelectableText(
  //                               artistId,
  //                               style: TextStyle(
  //                                 color: Colors.blue.shade600,
  //                                 fontSize: 12,
  //                                 fontFamily: 'monospace',
  //                               ),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                   ],
  //                 ),
  //               ),
  //
  //               const SizedBox(height: 12),
  //
  //               // Report reason
  //               Text(
  //                 'Reason: $reason',
  //                 style: const TextStyle(
  //                   fontWeight: FontWeight.bold,
  //                   fontSize: 16,
  //                 ),
  //               ),
  //
  //               // Complaint details
  //               if (reportData['complaint_details'] != null) ...[
  //                 const SizedBox(height: 8),
  //                 Container(
  //                   width: double.infinity,
  //                   padding: const EdgeInsets.all(12),
  //                   decoration: BoxDecoration(
  //                     color: Colors.grey.shade50,
  //                     borderRadius: BorderRadius.circular(8),
  //                     border: Border.all(color: Colors.grey.shade200),
  //                   ),
  //                   child: Text(
  //                     reportData['complaint_details'],
  //                     style: TextStyle(
  //                       color: Colors.grey.shade700,
  //                       fontSize: 14,
  //                     ),
  //                     maxLines: 2,
  //                     overflow: TextOverflow.ellipsis,
  //                   ),
  //                 ),
  //               ],
  //
  //               // Evidence photos preview
  //               if (evidenceUrls.isNotEmpty) ...[
  //                 const SizedBox(height: 12),
  //                 Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     Row(
  //                       children: [
  //                         Icon(Icons.photo_library, size: 16, color: Colors.blue.shade600),
  //                         const SizedBox(width: 6),
  //                         Text(
  //                           'Evidence Photos (${evidenceUrls.length})',
  //                           style: TextStyle(
  //                             color: Colors.blue.shade600,
  //                             fontSize: 12,
  //                             fontWeight: FontWeight.w500,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                     const SizedBox(height: 8),
  //                     SizedBox(
  //                       height: 60,
  //                       child: ListView.builder(
  //                         scrollDirection: Axis.horizontal,
  //                         itemCount: evidenceUrls.length,
  //                         itemBuilder: (context, index) {
  //                           return GestureDetector(
  //                             onTap: () => _showImageDialog(evidenceUrls[index]),
  //                             child: Container(
  //                               width: 60,
  //                               height: 60,
  //                               margin: const EdgeInsets.only(right: 8),
  //                               decoration: BoxDecoration(
  //                                 borderRadius: BorderRadius.circular(8),
  //                                 border: Border.all(color: Colors.grey.shade300),
  //                               ),
  //                               child: ClipRRect(
  //                                 borderRadius: BorderRadius.circular(8),
  //                                 child: Image.network(
  //                                   evidenceUrls[index],
  //                                   fit: BoxFit.cover,
  //                                   errorBuilder: (context, error, stackTrace) {
  //                                     return Container(
  //                                       color: Colors.grey.shade200,
  //                                       child: Icon(Icons.error, color: Colors.grey.shade400, size: 20),
  //                                     );
  //                                   },
  //                                   loadingBuilder: (context, child, loadingProgress) {
  //                                     if (loadingProgress == null) return child;
  //                                     return Container(
  //                                       color: Colors.grey.shade100,
  //                                       child: Center(
  //                                         child: CircularProgressIndicator(
  //                                           strokeWidth: 2,
  //                                           value: loadingProgress.expectedTotalBytes != null
  //                                               ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
  //                                               : null,
  //                                         ),
  //                                       ),
  //                                     );
  //                                   },
  //                                 ),
  //                               ),
  //                             ),
  //                           );
  //                         },
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ],
  //
  //               // Admin Notes
  //               if (reportData['admin_response'] != null) ...[
  //                 const SizedBox(height: 12),
  //                 Container(
  //                   width: double.infinity,
  //                   padding: const EdgeInsets.all(12),
  //                   decoration: BoxDecoration(
  //                     color: Colors.green.shade50,
  //                     borderRadius: BorderRadius.circular(8),
  //                     border: Border.all(color: Colors.green.shade200),
  //                   ),
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Row(
  //                         children: [
  //                           Icon(Icons.admin_panel_settings, color: Colors.green.shade600, size: 16),
  //                           const SizedBox(width: 6),
  //                           Text(
  //                             'Admin Resolution:',
  //                             style: TextStyle(
  //                               fontWeight: FontWeight.bold,
  //                               color: Colors.green.shade700,
  //                               fontSize: 14,
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                       const SizedBox(height: 6),
  //                       Text(
  //                         reportData['admin_response'],
  //                         style: TextStyle(
  //                           color: Colors.green.shade600,
  //                           fontSize: 14,
  //                         ),
  //                         maxLines: 2,
  //                         overflow: TextOverflow.ellipsis,
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //
  //               const SizedBox(height: 16),
  //
  //               // Action buttons - Only show for pending and under_review
  //               if (status == 'pending' || status == 'under_review')
  //                 _buildActionButtons(reportId, status),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }

  Widget _buildReportsList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getReportsStream(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading reports: ${snapshot.error}',
                    style: TextStyle(fontSize: 16, color: Colors.red.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.report_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No reports found',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }

        _cachedDocs = snapshot.data!.docs;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _processReportsWithNames(_cachedDocs),
          builder: (context, processedSnapshot) {
            if (!processedSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            List<Map<String, dynamic>> processedReports = processedSnapshot.data!;

            // Apply sorting for reporter name
            if (_selectedSort == 'reporter_name') {
              processedReports.sort((a, b) {
                final nameA = a['reporterName']?.toLowerCase() ?? '';
                final nameB = b['reporterName']?.toLowerCase() ?? '';
                return _isAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
              });
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: processedReports.length,
              itemBuilder: (context, index) {
                final processedReport = processedReports[index];
                final doc = processedReport['doc'] as DocumentSnapshot;
                final reportData = processedReport['reportData'] as Map<String, dynamic>;
                final reportId = doc.id;

                final status = reportData['status'] ?? 'pending';
                final reason = reportData['reason'] ?? 'Unknown';
                final createdAt = reportData['created_at'] as Timestamp?;
                final evidenceUrls = List<String>.from(reportData['evidence_urls'] ?? []);

                final reporterName = processedReport['reporterName'] ?? 'Unknown User';
                final reportedUserName = processedReport['reportedUserName'] ?? 'Unknown User';
                final reporterEmail = processedReport['reporterEmail'] ?? 'No email';
                final reporterId = processedReport['reporterId'];
                final artistId = processedReport['artistId'];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.95),
                            Colors.white.withOpacity(0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with status, date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildStatusChip(status),
                                Row(
                                  children: [
                                    Text(
                                      createdAt != null
                                          ? _formatDate(createdAt.toDate())
                                          : 'Unknown date',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Reporter and Reported User Info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.purple.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.person, color: Colors.purple.shade600, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Reporter: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          reporterName,
                                          style: TextStyle(
                                            color: Colors.purple.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.report, color: Colors.red.shade600, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Reported Artist: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          reportedUserName,
                                          style: TextStyle(
                                            color: Colors.red.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // ID Information and Contact Details
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Report ID
                                  Row(
                                    children: [
                                      Icon(Icons.fingerprint, color: Colors.blue.shade600, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Report ID: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Expanded(
                                        child: SelectableText(
                                          reportId,
                                          style: TextStyle(
                                            color: Colors.blue.shade600,
                                            fontSize: 12,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // User ID and Email
                                  if (reporterId != null) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.person_outline, color: Colors.blue.shade600, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'User ID: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            reporterId,
                                            style: TextStyle(
                                              color: Colors.blue.shade600,
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.email_outlined, color: Colors.blue.shade600, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'User Email: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            reporterEmail,
                                            style: TextStyle(
                                              color: Colors.blue.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  // Artist ID
                                  if (artistId != null)
                                    Row(
                                      children: [
                                        Icon(Icons.brush_outlined, color: Colors.blue.shade600, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Artist ID: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            artistId,
                                            style: TextStyle(
                                              color: Colors.blue.shade600,
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Report reason
                            Text(
                              'Reason: $reason',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),

                            // Complaint details
                            if (reportData['complaint_details'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  reportData['complaint_details'],
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],

                            // Evidence photos preview
                            if (evidenceUrls.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.photo_library, size: 16, color: Colors.blue.shade600),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Evidence Photos (${evidenceUrls.length})',
                                        style: TextStyle(
                                          color: Colors.blue.shade600,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 60,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: evidenceUrls.length,
                                      itemBuilder: (context, index) {
                                        return GestureDetector(
                                          onTap: () => _showImageDialog(evidenceUrls[index]),
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                evidenceUrls[index],
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.grey.shade200,
                                                    child: Icon(Icons.error, color: Colors.grey.shade400, size: 20),
                                                  );
                                                },
                                                loadingBuilder: (context, child, loadingProgress) {
                                                  if (loadingProgress == null) return child;
                                                  return Container(
                                                    color: Colors.grey.shade100,
                                                    child: Center(
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        value: loadingProgress.expectedTotalBytes != null
                                                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                            : null,
                                                      ),
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
                            ],

                            // Admin Notes
                            if (reportData['admin_response'] != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.admin_panel_settings, color: Colors.green.shade600, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Admin Resolution:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      reportData['admin_response'],
                                      style: TextStyle(
                                        color: Colors.green.shade600,
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            // Action buttons - Only show for pending and under_review
                            if (status == 'pending' || status == 'under_review')
                              _buildActionButtons(reportId, status),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActionButtons(String reportId, String status) {
    if (status == 'pending') {
      return Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(
          onPressed: () => _updateReportStatus(reportId, 'under_review'),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start Review', style: TextStyle(fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            minimumSize: const Size(120, 45),
          ),
        ),
      );
    }

    if (status == 'under_review') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Bigger Resolve button
          ElevatedButton(
            onPressed: () => _resolveReport(reportId),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              minimumSize: const Size(100, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check, size: 18),
                SizedBox(width: 6),
                Text('Resolve', style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Bigger Dismiss button
          ElevatedButton(
            onPressed: () => _dismissReport(reportId),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              minimumSize: const Size(100, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.close, size: 18),
                SizedBox(width: 6),
                Text('Dismiss', style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
  //Pending status and more
  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        label = 'Pending';
        icon = Icons.schedule;
        break;
      case 'under_review':
        color = Colors.blue;
        label = 'Verifying';
        icon = Icons.search;
        break;
      case 'resolved':
        color = Colors.green;
        label = 'Resolved';
        icon = Icons.check_circle;
        break;
      case 'dismissed':
        color = Colors.grey;
        label = 'Dismissed';
        icon = Icons.cancel;
        break;
      default:
        color = Colors.grey;
        label = 'Unknown';
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

}