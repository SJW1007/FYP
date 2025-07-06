import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'MakeupArtistAppointmentDetails.dart';

class MakeupArtistHomePage extends StatefulWidget {
  const MakeupArtistHomePage({super.key});

  @override
  State<MakeupArtistHomePage> createState() => _MakeupArtistHomePageState();
}

class _MakeupArtistHomePageState extends State<MakeupArtistHomePage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allAppointments = [];
  List<Map<String, dynamic>> _filteredAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  String? _makeupArtistDocId;
  String? _currentUserId;
  bool _isSearching = false;
  bool _isLoading = true;

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

  void _getCurrentUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      fetchMakeupArtistAppointments();
    } else {
      print('No user logged in');
    }
  }

  Future<void> fetchMakeupArtistAppointments() async {
    if (_currentUserId == null) return;

    setState(() => _isLoading = true);

    try {
      final makeupArtistSnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id',
          isEqualTo: FirebaseFirestore.instance.doc('users/$_currentUserId'))
          .limit(1)
          .get();

      if (makeupArtistSnapshot.docs.isEmpty) {
        print('No makeup artist found for current user');
        return;
      }

      _makeupArtistDocId = makeupArtistSnapshot.docs.first.id;
      final makeupArtistData = makeupArtistSnapshot.docs.first.data();

      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: FirebaseFirestore.instance.doc(
          'makeup_artists/$_makeupArtistDocId'))
          .get();

      List<Map<String, dynamic>> appointmentsData = [];

      for (var appointmentDoc in appointmentsSnapshot.docs) {
        final appointmentData = appointmentDoc.data();
        final appointmentId = appointmentDoc.id;

        final customerRef = appointmentData['customerId'] as DocumentReference?;
        if (customerRef != null) {
          final customerDoc = await customerRef.get();
          final customerData = customerDoc.data() as Map<String, dynamic>?;

          appointmentsData.add({
            'appointment_id': appointmentId,
            'customer_id': customerRef.id,
            'customer_name': customerData?['name'] ?? 'Unknown Customer',
            'customer_profile_pic': customerData?['profile pictures'] ?? '',
            'category': appointmentData['category'] ??
                makeupArtistData['category'] ?? '',
            'appointment_date': appointmentData['date'] ??
                appointmentData['appointment_date'], // Handle both field names
            'appointment_time': appointmentData['time'] ??
                appointmentData['appointment_time'], // Handle both field names
            'status': appointmentData['status'] ?? 'pending',
            'price': appointmentData['price'] ?? makeupArtistData['price'] ??
                '',
            'location': appointmentData['location'] ?? '',
            'notes': appointmentData['notes'] ?? '',
          });
        }
      }

      setState(() {
        _allAppointments = appointmentsData;
        _filteredAppointments = appointmentsData;
        setState(() => _isLoading = false);
      });

      // Separate appointments by date and time
      _separateAppointmentsByDateTime(appointmentsData);

      print('✅ Fetched ${appointmentsData.length} appointments');
      print('   - Upcoming: ${_upcomingAppointments.length}');
      print('   - Past: ${_pastAppointments.length}');
    } catch (e) {
      print('❌ Error fetching appointments: $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading appointments: ${e.toString()}')),
      );
    }
  }

  // Method to update appointment status to completed
  Future<void> _updateAppointmentStatus(String appointmentId,String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({'status': newStatus});
      print('✅ Updated appointment $appointmentId status to $newStatus');
    } catch (e) {
      print('❌ Error updating appointment status: $e');
    }
  }

  // Method to separate appointments based on date and time
  void _separateAppointmentsByDateTime(List<Map<String, dynamic>> appointments) {
    final now = DateTime.now();
    final upcomingAppointments = <Map<String, dynamic>>[];
    final pastAppointments = <Map<String, dynamic>>[];
    final List<Future<void>> statusUpdates = [];

    for (var appointment in appointments) {
      // Use consistent field names - check both possible field names
      final appointmentDate = appointment['date'] ??
          appointment['appointment_date'];
      final appointmentTime = appointment['time'] ??
          appointment['appointment_time'];

      final combinedDateTime = _combineDateTime(
          appointmentDate, appointmentTime);

      // Get the current status from the appointment
      final currentStatus = appointment['status']?.toString().toLowerCase() ??
          'pending';

      print('Processing appointment: ${appointment['appointment_id']}');
      print('Date: $appointmentDate, Time: $appointmentTime');
      print('Combined DateTime: $combinedDateTime');
      print('Current Status: $currentStatus');
      print('Now: $now');

      if (combinedDateTime != null) {
        // Check if appointment is in the past or future
        bool isPastDateTime = combinedDateTime.isBefore(now);

        if (isPastDateTime) {
          // Past appointment - should go to past list
          if (currentStatus != 'completed') {
            // Update status to completed if it's past and not already completed
            appointment['status'] = 'Completed';
            statusUpdates.add(_updateAppointmentStatus(
                appointment['appointment_id'],
                'Completed'
            ));
            print('Updating past appointment to completed');
          }
          pastAppointments.add(appointment);
          print('Added to past appointments');
        } else {
          // Future appointment
          if (currentStatus == 'completed' || currentStatus == 'cancelled') {
            // Even if it's future, if status is completed/cancelled, put in past
            pastAppointments.add(appointment);
            print('Added to past appointments (completed/cancelled status)');
          } else {
            // Future appointment with pending/in progress status
            upcomingAppointments.add(appointment);
            print('Added to upcoming appointments');
          }
        }
      } else {
        // If we can't parse the date/time, use status to determine placement
        print('Could not parse date/time, using status for placement');
        if (currentStatus == 'completed' || currentStatus == 'cancelled') {
          pastAppointments.add(appointment);
          print('Added to past appointments (status-based)');
        } else {
          upcomingAppointments.add(appointment);
          print('Added to upcoming appointments (status-based)');
        }
      }
    }

    // Execute all status updates
    Future.wait(statusUpdates).then((_) {
      print('✅ All appointment statuses updated');
    }).catchError((error) {
      print('❌ Error updating some appointment statuses: $error');
    });

    // Sort upcoming appointments by date/time (earliest first)
    upcomingAppointments.sort((a, b) {
      final dateTimeA = _combineDateTime(
          a['date'] ?? a['appointment_date'],
          a['time'] ?? a['appointment_time']
      );
      final dateTimeB = _combineDateTime(
          b['date'] ?? b['appointment_date'],
          b['time'] ?? b['appointment_time']
      );
      if (dateTimeA == null || dateTimeB == null) return 0;
      return dateTimeA.compareTo(dateTimeB);
    });

    // Sort past appointments by date/time (most recent first)
    pastAppointments.sort((a, b) {
      final dateTimeA = _combineDateTime(
          a['date'] ?? a['appointment_date'],
          a['time'] ?? a['appointment_time']
      );
      final dateTimeB = _combineDateTime(
          b['date'] ?? b['appointment_date'],
          b['time'] ?? b['appointment_time']
      );
      if (dateTimeA == null || dateTimeB == null) return 0;
      return dateTimeB.compareTo(dateTimeA);
    });

    setState(() {
      _upcomingAppointments = upcomingAppointments;
      _pastAppointments = pastAppointments;
    });

    print('Final separation results:');
    print('Upcoming appointments: ${_upcomingAppointments.length}');
    print('Past appointments: ${_pastAppointments.length}');
  }

// helper method to combine date and time into a single DateTime
  DateTime? _combineDateTime(dynamic appointmentDate, String? appointmentTime) {
    DateTime? date;

    // Parse the date
    if (appointmentDate is Timestamp) {
      date = appointmentDate.toDate();
    } else if (appointmentDate is String) {
      try {
        // Handle different date formats
        if (appointmentDate.contains('-')) {
          date = DateTime.parse(appointmentDate);
        } else {
          // Handle other date formats if needed
          date = DateTime.parse(appointmentDate);
        }
      } catch (e) {
        print('Error parsing date: $appointmentDate - $e');
        return null;
      }
    } else {
      print('Invalid date type: ${appointmentDate.runtimeType}');
      return null;
    }

    // Early return if date is null
    if (date == null) {
      print('Date is null after parsing');
      return null;
    }

    // Parse and combine the time
    if (appointmentTime != null && appointmentTime.isNotEmpty) {
      try {
        // Handle different time formats
        String cleanTime = appointmentTime.trim();
        bool isPM = cleanTime.toLowerCase().contains('pm');
        bool isAM = cleanTime.toLowerCase().contains('am');

        // Remove AM/PM from the string
        cleanTime = cleanTime.replaceAll(RegExp(r'[^\d:]'), '');

        final timeParts = cleanTime.split(':');
        if (timeParts.length >= 2) {
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);

          // Handle 12-hour format conversion
          if (isPM && hour != 12) {
            hour += 12;
          } else if (isAM && hour == 12) {
            hour = 0;
          }

          // Validate hour and minute ranges
          if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
            date = DateTime(date.year, date.month, date.day, hour, minute);
          } else {
            print('Invalid time values: hour=$hour, minute=$minute');
            // Return date with default time (start of day) if time is invalid
            date = DateTime(date.year, date.month, date.day, 0, 0);
          }
        }
      } catch (e) {
        print('Error parsing time: $appointmentTime - $e');
        // If time parsing fails, use the date with default time (start of day)
        date = DateTime(date!.year, date.month, date.day, 0, 0);
      }
    } else {
      // If no time provided, default to start of day for comparison
      date = DateTime(date.year, date.month, date.day, 0, 0);
    }

    return date;
  }

// Helper method to get status color (updated)
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'in progress':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

// Helper method to get status display text
  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'in progress':
        return 'In Progress';
      case 'pending':
        return 'Pending';
      default:
        return 'Unknown';
    }
  }

  Future<void> _handleTextSearch(BuildContext context, String query) async {
    if (_makeupArtistDocId == null) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final lowerQuery = query.toLowerCase();

      // Get appointments for this makeup artist
      final appointmentsSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: FirebaseFirestore.instance.doc(
          'makeup_artists/$_makeupArtistDocId'))
          .get();

      List<Map<String, dynamic>> searchResults = [];

      for (var appointmentDoc in appointmentsSnapshot.docs) {
        final appointmentData = appointmentDoc.data();
        final appointmentId = appointmentDoc.id;

        // Get customer details
        final customerRef = appointmentData['customerId'] as DocumentReference?;
        if (customerRef == null) continue;

        final customerDoc = await customerRef.get();
        final customerData = customerDoc.data() as Map<String, dynamic>?;

        if (customerData == null) continue;

        final customerName = customerData['name']?.toLowerCase() ?? '';

        // Check if the appointment matches the search criteria
        bool matchesSearch = false;

        // Check customer name
        if (customerName.contains(lowerQuery)) {
          matchesSearch = true;
        }

        if (matchesSearch) {
          // Get makeup artist data for additional details
          final makeupArtistDoc = await FirebaseFirestore.instance
              .collection('makeup_artists')
              .doc(_makeupArtistDocId)
              .get();
          final makeupArtistData = makeupArtistDoc.data() ?? {};
          searchResults.add({
            'appointment_id': appointmentId,
            'customer_id': customerRef.id,
            'customer_name': customerData['name'] ?? 'Unknown Customer',
            'customer_profile_pic': customerData['profile pictures'] ?? '',
            'category': appointmentData['category'] ??
                makeupArtistData['category'] ?? '',
            'appointment_date': appointmentData['date'] ??
                appointmentData['appointment_date'], // Handle both field names
            'appointment_time': appointmentData['time'] ??
                appointmentData['appointment_time'], // Handle both field names
            'status': appointmentData['status'] ?? 'pending',
            'price': appointmentData['price'] ?? makeupArtistData['price'] ??
                '',
            'location': appointmentData['location'] ?? '',
            'notes': appointmentData['notes'] ?? '',
          });
        }
      }
      setState(() {
        _filteredAppointments = searchResults;
        _isSearching = false;
      });
      // Separate search results by date and time
      _separateAppointmentsByDateTime(searchResults);
      print('✅ Found ${searchResults.length} appointments matching search');
      print('   - Upcoming: ${_upcomingAppointments.length}');
      print('   - Past: ${_pastAppointments.length}');
    } catch (e) {
      print('❌ Error searching appointments: $e');
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error searching appointments: ${e.toString()}')),
      );
    }
  }

  Widget _buildHorizontalAppointmentList(
      List<Map<String, dynamic>> appointments) {
    return SizedBox(
      height: 300, // Increased height to accommodate status
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          final status = appointment['status'] ?? 'pending';
          return Container(
            width: 200, // Fixed width for each card
            margin: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        MakeupArtistAppointmentDetailsPage(
                          appointmentId: appointment['appointment_id'],
                          customerId: appointment['customer_id'],
                        ),
                  ),
                );
              },
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
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16)),
                          color: Color(0xFFFFB347),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          child: appointment['customer_profile_pic'] != null &&
                              appointment['customer_profile_pic'].isNotEmpty
                              ? Image.network(
                            appointment['customer_profile_pic'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.person, size: 50,
                                    color: Colors.white),
                              );
                            },
                          )
                              : const Center(
                            child: Icon(
                                Icons.person, size: 50, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                appointment['customer_name'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Flexible(
                              child: Text(
                                appointment['category'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Status indicator
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getStatusDisplayText(status),
                                style: const TextStyle(
                                  fontSize: 9,
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

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_filteredAppointments.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No appointments found',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: _filteredAppointments.map((appointment) {
        final status = appointment['status'] ?? 'pending';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: appointment['customer_profile_pic'] != null &&
                  appointment['customer_profile_pic'].isNotEmpty
                  ? NetworkImage(appointment['customer_profile_pic'])
                  : null,
              child: appointment['customer_profile_pic'] == null ||
                  appointment['customer_profile_pic'].isEmpty
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(appointment['customer_name'] ?? 'Unknown'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment['category'] ?? ''),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusDisplayText(status),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      MakeupArtistAppointmentDetailsPage(
                        appointmentId: appointment['appointment_id'],
                        customerId: appointment['customer_id'],
                      ),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSearchQuery = _searchController.text.isNotEmpty;
    final bool hasNoAppointments = _upcomingAppointments.isEmpty &&
        _pastAppointments.isEmpty &&
        !_isSearching;

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
                : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "My Appointments",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
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
                                hintText: "Search by customer name",
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: Colors.grey),
                              ),
                              onChanged: (text) {
                                if (text.isEmpty) {
                                  fetchMakeupArtistAppointments();
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
                    const SizedBox(height: 24),

                    if (_isLoading)
                      _buildLoadingIndicator()
                    // Show empty state when there are no appointments
                    else if (hasNoAppointments)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        margin: const EdgeInsets.symmetric(vertical: 40),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 64,
                              color: Colors.black.withOpacity(0.6),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No appointments for now',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.black.withOpacity(0.8),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your upcoming and past appointments will appear here in future',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black.withOpacity(0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // Show upcoming appointments section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            hasSearchQuery
                                ? "Upcoming Search Results"
                                : "Upcoming Appointments",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          if (_upcomingAppointments.isNotEmpty)
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

                      if (_upcomingAppointments.isEmpty)
                        Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              hasSearchQuery
                                  ? 'No upcoming appointments found for search'
                                  : 'No upcoming appointments',
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        )
                      else
                        _buildHorizontalAppointmentList(_upcomingAppointments),

                      const SizedBox(height: 40),

                      // Show past appointments section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            hasSearchQuery
                                ? "Past Search Results"
                                : "Past Appointments",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          if (_pastAppointments.isNotEmpty)
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

                      if (_pastAppointments.isEmpty)
                        Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              hasSearchQuery
                                  ? 'No past appointments found for search'
                                  : 'No past appointments',
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        )
                      else
                        _buildHorizontalAppointmentList(_pastAppointments),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB266FF)), // Purple color
            strokeWidth: 6,
          ),
          const SizedBox(height: 20),
          Text(
            'Loading appointments...',
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