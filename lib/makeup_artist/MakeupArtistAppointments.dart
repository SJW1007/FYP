import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'MakeupArtistAppointmentDetails.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class MakeupArtistAppointmentsPage extends StatefulWidget {
  final bool initialShowUpcoming;
  final bool startWithListView;
  const MakeupArtistAppointmentsPage({
    super.key,
  this.initialShowUpcoming = true,
    this.startWithListView = false,
  });

  @override
  State<MakeupArtistAppointmentsPage> createState() => _MakeupArtistAppointmentsPageState();
}

class _MakeupArtistAppointmentsPageState extends State<MakeupArtistAppointmentsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allAppointments = [];
  List<Map<String, dynamic>> _filteredAppointments = [];
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _pastAppointments = [];
  final ImagePicker _picker = ImagePicker();
  String? _makeupArtistDocId;
  String? _currentUserId;
  bool _isSearching = false;
  bool _showUpcoming = true; // Toggle between upcoming and past
  bool _isLoading = true;
  bool _isCalendarView = true; // Toggle between calendar and list view
  DateTime _selectedDate = DateTime.now();
  DateTime _currentWeekStart = DateTime.now();
  bool _isAscending = true;
  String _selectedSort = 'newest'; // default sort

  //variables for search functionality
  DateTime? _selectedMonth;
  DateTime? _selectedSearchDate;
  String _searchQuery = '';
  bool _showSearchFilters = false;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  Map<String, String> _customerNames = {}; // Cache for customer names

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Set initial tab from widget parameter
    _showUpcoming = widget.initialShowUpcoming;

    // Set initial view mode from widget parameter
    _isCalendarView = !widget.startWithListView; // If startWithListView is true, set calendar to false

    _currentWeekStart = _getWeekStart(DateTime.now());
    _selectedDate = DateTime.now();

    final now = DateTime.now();
    _selectedStartDate = DateTime(now.year, now.month, 1);
    _selectedEndDate = DateTime(now.year, now.month + 1, 0);

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

  // Helper method to get color with debug
  Color _getStatusColor(String status) {
    print('DEBUG: Getting color for status: "$status"');
    switch (status.toLowerCase()) {
      case 'completed':
        print(' DEBUG: Status color -> GREEN');
        return Colors.green;
      case 'cancelled':
        print('DEBUG: Status color -> RED');
        return Colors.red;
      case 'in progress':
        print('DEBUG: Status color -> ORANGE');
        return Colors.orange;
      case 'pending':
        print('DEBUG: Status color -> BLUE');
        return Colors.blue;
      case 'confirmed':
        print('DEBUG: Status color -> TEAL');
        return Colors.teal;
      default:
        print('DEBUG: Status color -> GREY (default for: "$status")');
        return Colors.grey;
    }
  }

  DateTime _getWeekStart(DateTime date) {
    int daysFromMonday = date.weekday - 1;
    return date.subtract(Duration(days: daysFromMonday));
  }

  void _previousWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    });
  }

  void _goToToday() {
    setState(() {
      _currentWeekStart = _getWeekStart(DateTime.now());
      _selectedDate = DateTime.now();
    });
  }

  String _formatDateForHeader(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _getWeekdayName(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  }

  List<Map<String, dynamic>> _getAppointmentsForDate(DateTime date) {
    return _allAppointments.where((appointment) {
      DateTime? appointmentDate = _parseStringToDateTime(appointment['appointment_date']);
      if (appointmentDate == null) return false;

      return appointmentDate.year == date.year &&
          appointmentDate.month == date.month &&
          appointmentDate.day == date.day;
    }).toList();
  }

  Future<void> fetchMakeupArtistAppointments() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true; // Set loading to true when starting
    });

    try {
      final makeupArtistSnapshot = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id',
          isEqualTo: FirebaseFirestore.instance.doc('users/$_currentUserId'))
          .limit(1)
          .get();

      if (makeupArtistSnapshot.docs.isEmpty) {
        print('No makeup artist found for current user');
        setState(() {
          _isLoading = false; // Set loading to false when no data found
        });
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
      final now = DateTime.now();
      final upcomingAppointments = <Map<String, dynamic>>[];
      final pastAppointments = <Map<String, dynamic>>[];

      for (var appointmentDoc in appointmentsSnapshot.docs) {
        final appointmentData = appointmentDoc.data();
        final appointmentId = appointmentDoc.id;

        // DEBUG: Print appointment data
        print('DEBUG: Processing appointment $appointmentId');
        print('DEBUG: Raw appointment data: ${appointmentData.toString()}');
        print('DEBUG: Status from Firebase: "${appointmentData['status']}"');
        print('DEBUG: Time from Firebase: "${appointmentData['time_range']}"');

        final customerRef = appointmentData['customerId'] as DocumentReference?;
        if (customerRef != null) {
          final customerDoc = await customerRef.get();
          final customerData = customerDoc.data() as Map<String, dynamic>?;

          String currentStatus = appointmentData['status'] ?? '';

          final processedAppointment = {
            'appointment_id': appointmentId,
            'customer_id': customerRef.id,
            'customer_name': customerData?['name'] ?? 'Unknown Customer',
            'customer_profile_pic': customerData?['profile pictures'] ?? '',
            'category': appointmentData['category'] ?? '',
            'appointment_date': appointmentData['date'],
            'appointment_time': appointmentData['time_range'],
            'price': makeupArtistData['price'] ?? '',
            'notes': appointmentData['remarks'] ?? '',
            'status': currentStatus,
          };

          // Parse appointment date and time
          final appointmentDate = appointmentData['date'];
          final appointmentTime = appointmentData['time'];
          DateTime? bookingDateTime;

          if (appointmentDate is Timestamp) {
            bookingDateTime = appointmentDate.toDate();
          } else if (appointmentDate is String && appointmentDate.isNotEmpty) {
            try {
              if (appointmentDate.contains('/')) {
                final parts = appointmentDate.split('/');
                if (parts.length == 3) {
                  // Parse date
                  DateTime dateOnly = DateTime(
                    int.parse(parts[2]), // year
                    int.parse(parts[1]), // month
                    int.parse(parts[0]), // day
                  );

                  // If we have time, add it to the date
                  if (appointmentTime is String && appointmentTime.isNotEmpty) {
                    try {
                      // Parse time - handle different formats
                      TimeOfDay timeOfDay = _parseTimeString(appointmentTime);
                      bookingDateTime = DateTime(
                        dateOnly.year,
                        dateOnly.month,
                        dateOnly.day,
                        timeOfDay.hour,
                        timeOfDay.minute,
                      );
                    } catch (e) {
                      print('Error parsing time, using date only: $e');
                      bookingDateTime = dateOnly;
                    }
                  } else {
                    bookingDateTime = dateOnly;
                  }
                }
              } else {
                bookingDateTime = DateTime.parse(appointmentDate);
              }
            } catch (e) {
              print('Error parsing appointment date: $appointmentDate, Error: $e');
              // If parsing fails, treat as upcoming to be safe
              bookingDateTime = DateTime.now().add(const Duration(days: 1));
            }
          }

          // Apply the new sorting logic
          if (bookingDateTime != null) {
            String status = currentStatus.toLowerCase();

            if (status == 'cancelled' || status == 'completed') {
              // Both cancelled and completed appointments go to past
              pastAppointments.add(processedAppointment);
              print('DEBUG: Added to past (cancelled/completed): $appointmentId - Status: $status');
            } else if (bookingDateTime.isAfter(now)) {
              // Future appointments that are not cancelled/completed go to upcoming
              upcomingAppointments.add(processedAppointment);
              print('DEBUG: Added to upcoming (future): $appointmentId - Date: $bookingDateTime');
            } else {
              // Past appointments that are still pending - update status to 'Completed'
              try {
                await FirebaseFirestore.instance
                    .collection('appointments')
                    .doc(appointmentId)
                    .update({'status': 'Completed'});
                processedAppointment['status'] = 'Completed';
                print('📊 DEBUG: Updated past pending appointment to completed: $appointmentId');
              } catch (e) {
                print("Failed to update status for $appointmentId: $e");
              }
              pastAppointments.add(processedAppointment);
              print('📊 DEBUG: Added to past (auto-completed): $appointmentId');
            }
          } else {
            // If date is null, treat as upcoming to be safe
            upcomingAppointments.add(processedAppointment);
            print('📊 DEBUG: Added to upcoming (null date): $appointmentId');
          }

          appointmentsData.add(processedAppointment);
        }
      }

      // Sort appointments
      upcomingAppointments.sort((a, b) {
        final dateAStr = a['appointment_date'];
        final dateBStr = b['appointment_date'];

        DateTime? dateA = _parseStringToDateTime(dateAStr);
        DateTime? dateB = _parseStringToDateTime(dateBStr);

        if (dateA == null || dateB == null) return 0;
        return dateA.compareTo(dateB);
      });

      pastAppointments.sort((a, b) {
        final dateAStr = a['appointment_date'];
        final dateBStr = b['appointment_date'];

        DateTime? dateA = _parseStringToDateTime(dateAStr);
        DateTime? dateB = _parseStringToDateTime(dateBStr);

        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA); // Reverse order for past appointments
      });

      setState(() {
        _allAppointments = appointmentsData;
        _filteredAppointments = appointmentsData;
        _upcomingAppointments = upcomingAppointments;
        _pastAppointments = pastAppointments;
      });

      // Cache customer names AFTER setting appointments data
      await _fetchCustomerNames();

      setState(() {
        _isLoading = false; // Update loading state after names are cached
      });

      print('Fetched ${appointmentsData.length} appointments');
      print('DEBUG: Upcoming appointments: ${upcomingAppointments.length}');
      print('DEBUG: Past appointments: ${pastAppointments.length}');
    } catch (e) {
      print('Error fetching appointments: $e');
      setState(() {
        _isLoading = false; // ✅ SET LOADING TO FALSE EVEN ON ERROR
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading appointments: ${e.toString()}')),
      );
    }
  }

  // Helper method to parse string dates consistently
  DateTime? _parseStringToDateTime(dynamic dateStr) {
    if (dateStr is Timestamp) {
      return dateStr.toDate();
    } else if (dateStr is String && dateStr.isNotEmpty) {
      try {
        if (dateStr.contains('/')) {
          final parts = dateStr.split('/');
          if (parts.length == 3) {
            return DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        } else {
          return DateTime.parse(dateStr);
        }
      } catch (e) {
        print('Error parsing date string: $dateStr');
      }
    }
    return null;
  }

// Helper method to parse time string to TimeOfDay
  TimeOfDay _parseTimeString(String timeString) {
    try {
      // Remove any leading/trailing whitespace
      timeString = timeString.trim();
      // Check if it already contains AM/PM
      bool hasAmPm = timeString.toUpperCase().contains('AM') || timeString.toUpperCase().contains('PM');
      if (hasAmPm) {
        // Parse 12-hour format
        final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
        final match = timeRegex.firstMatch(timeString.toUpperCase());
        if (match != null) {
          int hour = int.parse(match.group(1)!);
          int minute = int.parse(match.group(2)!);
          String period = match.group(3)!;
          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }
          return TimeOfDay(hour: hour, minute: minute);
        }
      } else {
        // Parse 24-hour format
        if (timeString.contains(':')) {
          final parts = timeString.split(':');
          if (parts.length >= 2) {
            int hour = int.parse(parts[0]);
            int minute = int.parse(parts[1]);
            return TimeOfDay(hour: hour, minute: minute);
          }
        }
      }

      throw FormatException('Unable to parse time: $timeString');
    } catch (e) {
      print('Error parsing time string: $timeString, Error: $e');
      // Return current time as fallback
      return TimeOfDay.now();
    }
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month
          .toString().padLeft(2, '0')}/${dateTime.year}';
    } else if (date is String) {
      try {
        // Handle different string date formats
        DateTime dateTime;

        // Check if it's already in dd/mm/yyyy format
        if (date.contains('/')) {
          final parts = date.split('/');
          if (parts.length == 3) {
            // Assume dd/mm/yyyy format
            dateTime = DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          } else {
            return date; // Return as-is if format is unexpected
          }
        } else {
          // Try parsing ISO format or other standard formats
          dateTime = DateTime.parse(date);
        }

        return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month
            .toString().padLeft(2, '0')}/${dateTime.year}';
      } catch (e) {
        print('Error parsing date: $date, Error: $e');
        return date; // Return original string if parsing fails
      }
    }
    return 'N/A';
  }

  String _formatTime(dynamic time) {
    if (time is String && time.isNotEmpty) {
      // If it's a time_range (e.g., "10:00 AM - 11:00 AM"), return as-is
      if (time.contains('-')) {
        return time;
      }
      // ... rest of the existing code
    }
    return 'N/A';
  }

  Future<void> _onRefresh() async {
    if (_currentUserId != null && mounted) {
      await fetchMakeupArtistAppointments();
    }
  }

  void _applySort() {
    final ascending = _selectedSort == 'oldest';

    setState(() {
      _upcomingAppointments.sort((a, b) {
        final dateA = _parseStringToDateTime(a['appointment_date']);
        final dateB = _parseStringToDateTime(b['appointment_date']);
        if (dateA == null || dateB == null) return 0;
        return ascending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      });

      _pastAppointments.sort((a, b) {
        final dateA = _parseStringToDateTime(a['appointment_date']);
        final dateB = _parseStringToDateTime(b['appointment_date']);
        if (dateA == null || dateB == null) return 0;
        return ascending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      });
    });
  }

  // Method to fetch and cache customer names
  Future<void> _fetchCustomerNames() async {
    Map<String, String> newCustomerNames = {};

    for (var appointment in _allAppointments) {
      String customerId = appointment['customer_id'];
      if (!_customerNames.containsKey(customerId)) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(customerId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            newCustomerNames[customerId] = userData['name'] ?? 'Unknown Customer';
          } else {
            newCustomerNames[customerId] = 'Unknown Customer';
          }
        } catch (e) {
          print("Error fetching customer name: $e");
          newCustomerNames[customerId] = 'Unknown Customer';
        }
      }
    }

    // Update the map
    _customerNames.addAll(newCustomerNames);
  }

// Method to filter appointments based on search criteria
  List<Map<String, dynamic>> _getFilteredAppointments(List<Map<String, dynamic>> appointments) {
    List<Map<String, dynamic>> filtered = appointments;

    // Filter by search query (customer name)
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((appointment) {
        String customerId = appointment['customer_id'];
        String customerName = _customerNames[customerId]?.toLowerCase() ?? '';
        return customerName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Filter by date range
    if (_selectedStartDate != null && _selectedEndDate != null) {
      filtered = filtered.where((appointment) {
        DateTime? appointmentDate = _parseStringToDateTime(appointment['appointment_date']);
        if (appointmentDate == null) return false;

        return appointmentDate.isAfter(_selectedStartDate!.subtract(const Duration(days: 1))) &&
            appointmentDate.isBefore(_selectedEndDate!.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  }

  Widget _buildSearchSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by customer name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(_showSearchFilters ? Icons.filter_list : Icons.filter_list_outlined),
                  onPressed: () {
                    setState(() {
                      _showSearchFilters = !_showSearchFilters;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Filter options
          if (_showSearchFilters) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(24), // Increased from 16
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter by Date',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedStartDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedStartDate = picked;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedStartDate != null
                                  ? 'From: ${_selectedStartDate!.day.toString().padLeft(2, '0')}/${_selectedStartDate!.month.toString().padLeft(2, '0')}/${_selectedStartDate!.year}'
                                  : 'Start Date',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedEndDate ?? DateTime.now(),
                              firstDate: _selectedStartDate ?? DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedEndDate = picked;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedEndDate != null
                                  ? 'To: ${_selectedEndDate!.day.toString().padLeft(2, '0')}/${_selectedEndDate!.month.toString().padLeft(2, '0')}/${_selectedEndDate!.year}'
                                  : 'End Date',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _selectedMonth = null;
                            _selectedSearchDate = null;
                            // Reset to current month bounds
                            final now = DateTime.now();
                            _selectedStartDate = DateTime(now.year, now.month, 1); // First day of current month
                            _selectedEndDate = DateTime(now.year, now.month + 1, 0); // Last day of current month
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
                  _showUpcoming = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _showUpcoming ? const Color(0xFFB968C7) : Colors
                      .transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'Upcoming',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _showUpcoming ? Colors.white : Colors.grey,
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
                  _showUpcoming = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_showUpcoming ? const Color(0xFFB968C7) : Colors
                      .transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'Past',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: !_showUpcoming ? Colors.white : Colors.grey,
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

  Widget _buildAppointmentsList() {
    // Get base appointments
    final baseAppointments = _showUpcoming ? _upcomingAppointments : _pastAppointments;

    // Apply search filters
    final appointments = _getFilteredAppointments(baseAppointments);

    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB968C7)),
          ),
        ),
      );
    }

    if (appointments.isEmpty) {
      String message = _showUpcoming
          ? 'No upcoming appointments found'
          : 'No past appointments found';

      return Container(
        height: MediaQuery.of(context).size.height * 0.1,
        child: Center(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,//for the container of list of booking
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...appointments.map((appointment) => _buildAppointmentTile(appointment)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentTile(Map<String, dynamic> appointment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.transparent, // makes background transparent
      ),
      child: Row(
        children: [
          // Profile Picture
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFFFFB347),
            child: ClipOval(
              child: appointment['customer_profile_pic'] != null &&
                  appointment['customer_profile_pic'].isNotEmpty
                  ? Image.network(
                appointment['customer_profile_pic'],
                fit: BoxFit.cover,
                width: 80,
                height: 80,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.person, size: 30, color: Colors.white);
                },
              )
                  : const Icon(Icons.person, size: 30, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          // Appointment Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Customer name at the top
                Text(
                  appointment['customer_name'] ?? 'Unknown Customer',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // Date and time together
                Text(
                  "${_formatDate(appointment['appointment_date'])} • ${_formatTime(appointment['appointment_time'])}",
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  appointment['category'] ?? 'Unknown',
                  style: const TextStyle(color: Color(0xFF994D66)),
                ),
                const SizedBox(height: 4),
                Text(
                  appointment['status'] ?? 'Unknown',
                  style: TextStyle(
                    color: _getStatusColor(appointment['status'] ?? ''),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Details button as icon
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MakeupArtistAppointmentDetailsPage(
                    appointmentId: appointment['appointment_id'],
                    customerId: appointment['customer_id'],
                  ),
                ),
              );
            },
            color: Colors.black,
            tooltip: 'View Details',
          ),
        ],
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
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        kToolbarHeight,
                  ),
                  child: Column(
                    children: [
                      // Header with view toggle
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Booking List",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isCalendarView = true;
                                    });
                                  },
                                  icon: Icon(
                                    Icons.calendar_month,
                                    color: _isCalendarView ? const Color(0xFFB968C7) : Colors.grey,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _isCalendarView = false;
                                    });
                                  },
                                  icon: Icon(
                                    Icons.list,
                                    color: !_isCalendarView ? const Color(0xFFB968C7) : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Content based on view type
                      _isLoading
                          ? Container(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: _buildLoadingIndicator(),
                      )
                          : _isCalendarView
                          ? Column(
                        children: [
                          _buildWeekCalendar(),
                          const SizedBox(height: 16),
                          _buildSelectedDateAppointments(),
                        ],
                      )
                          : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            // Toggle Button
                            _buildToggleButton(),
                            const SizedBox(height: 16),
                            // Search Section
                            _buildSearchSection(),
                            const SizedBox(height: 16),
                            // Sort dropdown
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
                                        DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                                        DropdownMenuItem(value: 'oldest', child: Text('Oldest First')),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedSort = value!;
                                          _applySort();
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Appointments list
                            _buildAppointmentsList(),
                          ],
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
  Widget _buildWeekCalendar() {
    return Column(
      children: [
        // Week navigation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _previousWeek,
                icon: const Icon(Icons.chevron_left, color: Colors.black),
              ),
              Expanded(
                child: Text(
                  "${_formatDateForHeader(_currentWeekStart)} - ${_formatDateForHeader(_currentWeekStart.add(const Duration(days: 6)))}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              IconButton(
                onPressed: _nextWeek,
                icon: const Icon(Icons.chevron_right, color: Colors.black),
              ),
            ],
          ),
        ),

        // Today button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _goToToday,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB968C7),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Today'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Week days
        Container(
          height: 80,
          child: Row(
            children: List.generate(7, (index) {
              final date = _currentWeekStart.add(Duration(days: index));
              final appointmentsForDay = _getAppointmentsForDate(date);
              final isSelected = date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;
              final isToday = date.year == DateTime.now().year &&
                  date.month == DateTime.now().month &&
                  date.day == DateTime.now().day;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFB968C7)
                          : isToday
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: appointmentsForDay.isNotEmpty
                          ? Border.all(color: Colors.orange, width: 2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getWeekdayName(date),
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (appointmentsForDay.isNotEmpty)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDateAppointments() {
    final appointmentsForSelectedDate = _getAppointmentsForDate(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Appointments for ${_formatDateForHeader(_selectedDate)}",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        if (appointmentsForSelectedDate.isEmpty)
          Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(32.0),
            child: const Center(
              child: Text(
                "No appointments for this day.",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          )
        else
          ...appointmentsForSelectedDate.map((appointment) =>
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildCalendarAppointmentCard(appointment),
              ),
          ).toList(),
      ],
    );
  }

  Widget _buildCalendarAppointmentCard(Map<String, dynamic> appointment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFB347),
          ),
          child: ClipOval(
            child: appointment['customer_profile_pic'] != null &&
                appointment['customer_profile_pic'].isNotEmpty
                ? Image.network(
              appointment['customer_profile_pic'],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.person, size: 25, color: Colors.white);
              },
            )
                : const Icon(Icons.person, size: 25, color: Colors.white),
          ),
        ),
        title: Text(
          appointment['customer_name'] ?? 'Unknown Customer',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatTime(appointment['appointment_time'])),
            Text(
              appointment['category'] ?? 'Unknown',
              style: const TextStyle(color: Color(0xFF994D66)),
            ),
            Text(
              appointment['status'] ?? 'Unknown',
              style: TextStyle(
                color: _getStatusColor(appointment['status'] ?? ''),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MakeupArtistAppointmentDetailsPage(
                  appointmentId: appointment['appointment_id'],
                  customerId: appointment['customer_id'],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}