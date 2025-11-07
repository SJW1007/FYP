import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'BookingDetails.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  Future<Map<String, List<Map<String, dynamic>>>>? _bookingFuture;
  DateTime _selectedDate = DateTime.now();
  DateTime _currentWeekStart = DateTime.now();
  List<Map<String, dynamic>> _allBookings = [];
  bool _isCalendarView = true;
  bool _showUpcoming = true; // for toggle
  String _selectedSort = 'newest'; // default
  bool _isAscending = true;

  // for search
  String _searchQuery = '';
  bool _showSearchFilters = false;
  DateTime? _selectedMonth;
  DateTime? _selectedSearchDate;
  Map<String, String> _artistNames = {}; // Cache for artist names
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getWeekStart(DateTime.now());

    // Add these lines to set current month bounds as default
    final now = DateTime.now();
    _selectedStartDate = DateTime(now.year, now.month, 1); // First day of current month
    _selectedEndDate = DateTime(now.year, now.month + 1, 1).subtract(Duration(days: 1)); // Last day of current month

    _bookingFuture = fetchBookings().then((value) {
      _applySort();
      return value;
    });
  }

  String _formatDateForHeader(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  Future<void> _refreshBookings() async {
    try {
      final bookings = await fetchBookings();
      _applySort();
      setState(() {
        _bookingFuture = Future.value(bookings);
      });
    } catch (e) {
      // Handle error if needed
      print("Error refreshing bookings: $e");
    }
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
  Future<String> checkReviewStatus(String appointmentId, String customerId) async {
    try {
      final reviewSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('customer_id', isEqualTo: FirebaseFirestore.instance.doc('users/$customerId'))
          .where('appointment_id', isEqualTo: FirebaseFirestore.instance.doc('appointments/$appointmentId'))
          .get();

      return reviewSnapshot.docs.isNotEmpty ? 'Reviewed' : 'Haven\'t Review';
    } catch (e) {
      print("Error checking review status: $e");
      return 'Haven\'t Review';
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchBookings() async {
    print("Fetching bookings...");

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception("User not logged in");
    }

    final bookingSnapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .get();

    List<Map<String, dynamic>> upcoming = [];
    List<Map<String, dynamic>> past = [];
    List<Map<String, dynamic>> allBookings = [];

    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd h:mm a');
    final dateFormatNoMinutes = DateFormat('yyyy-MM-dd h a'); // For times like "1:00 PM"

    for (var doc in bookingSnapshot.docs) {
      // Explicitly cast data to Map<String, dynamic>
      final data = doc.data() as Map<String, dynamic>;
      print("Appointment Data: $data");

      // Filter by customerId
      final customerRef = data['customerId'];
      if (customerRef is! DocumentReference || customerRef.id != currentUser.uid) {
        print("Skipping booking not for current user.");
        continue;
      }

      final dateStr = data['date'] ?? '';
      // Support both old 'time' field and new 'time_range' field
      String timeRangeStr = data['time_range'] ?? data['time'] ?? '';
      final category = data['category'] ?? '';
      final artistRef = data['artist_id'];
      final status = data['status'] ?? '';

      if (dateStr.isEmpty || timeRangeStr.isEmpty || artistRef is! DocumentReference) {
        print("Skipping due to missing or invalid fields (date, time_range, or artist_id).");
        continue;
      }

      // Extract start time from time_range (e.g., "9:00 AM - 11:00 AM" -> "9:00 AM")
      String timeStr = timeRangeStr.split('-')[0].trim();

// ALL whitespace and rebuild with single spaces
      timeStr = timeStr.replaceAll(RegExp(r'\s+'), ' ').trim();

      DateTime bookingDateTime;
      try {
        bookingDateTime = dateFormat.parse('$dateStr $timeStr');
      } catch (e) {
        try {
          bookingDateTime = dateFormatNoMinutes.parse('$dateStr $timeStr');
        } catch (e2) {
          print("Error parsing date/time: $e2. Date: '$dateStr', Time: '$timeStr'");
          continue;
        }
      }
      // Get makeup artist data using the DocumentReference
      final artistDoc = await artistRef.get(); // Use artistRef directly
      if (!artistDoc.exists) {
        print("Makeup artist not found for artist_id: ${artistRef.id}");
        continue;
      }

      // Explicitly cast artistData to Map<String, dynamic>
      final artistData = artistDoc.data() as Map<String, dynamic>;
      DocumentReference? userRefFromArtist;
      if (artistData['user_id'] is DocumentReference) {
        userRefFromArtist = artistData['user_id'] as DocumentReference;
      } else {
        print("user_id missing or invalid in artistData: $artistData");
        continue;
      }

      final userDoc = await userRefFromArtist.get(); // DocumentReference
      if (!userDoc.exists) {
        print("User document not found for userId: ${userRefFromArtist.id}");
        continue;
      }

      // Explicitly cast userData to Map<String, dynamic>
      final userData = userDoc.data() as Map<String, dynamic>;
      final avatarUrl = userData['profile pictures'];

      String reviewStatus = '';
      if (status == 'Completed') {
        reviewStatus = await checkReviewStatus(doc.id, currentUser.uid);
      }

      final booking = {
        'appointment_id': doc.id,
        'category': category,
        'time': bookingDateTime,
        'time_range': timeRangeStr,
        'avatar': avatarUrl,
        'status': status,
        'artist_id': artistRef.id,
        'review_status': reviewStatus,
      };

      allBookings.add(booking);

      print("Booking added: $booking");



      if (status == 'Cancelled' || status == 'Completed') {
        // Both cancelled and completed appointments go to past
        past.add(booking);
      } else if (bookingDateTime.isAfter(now)) {
        // Future appointments that are not cancelled/completed go to upcoming
        upcoming.add(booking);
      } else {
        // Past appointments that are still pending - update status to 'Completed'
        try {
          await FirebaseFirestore.instance
              .collection('appointments')
              .doc(doc.id)
              .update({'status': 'Completed'});
          booking['status'] = 'Completed';
        } catch (e) {
          print("Failed to update status: $e");
        }
        past.add(booking);
      }
    }
    _allBookings = allBookings;
    await _fetchArtistNames(); // Cache artist names

    print("Upcoming: $upcoming");
    print("Past: $past");

    return {'upcoming': upcoming, 'past': past};
  }

  List<Map<String, dynamic>> _getBookingsForDate(DateTime date) {
    return _allBookings.where((booking) {
      final bookingDate = booking['time'] as DateTime;
      return bookingDate.year == date.year &&
          bookingDate.month == date.month &&
          bookingDate.day == date.day;
    }).toList();
  }

  void _applySort() {
    setState(() {
      _isAscending = _selectedSort == 'oldest';

      _allBookings.sort((a, b) {
        DateTime aTime = a['time'];
        DateTime bTime = b['time'];
        return _isAscending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
      });
    });
  }

  //method to fetch and cache artist names
  Future<void> _fetchArtistNames() async {
    Map<String, String> newArtistNames = {};

    for (var booking in _allBookings) {
      String artistId = booking['artist_id'];
      if (!_artistNames.containsKey(artistId)) {
        try {
          final artistDoc = await FirebaseFirestore.instance
              .collection('makeup_artists')
              .doc(artistId)
              .get();

          if (artistDoc.exists) {
            final artistData = artistDoc.data() as Map<String, dynamic>;
            final userRef = artistData['user_id'] as DocumentReference?;

            if (userRef != null) {
              final userDoc = await userRef.get();
              if (userDoc.exists) {
                final userData = userDoc.data() as Map<String, dynamic>;
                newArtistNames[artistId] = userData['studio_name'] ?? artistData['studio_name'] ?? 'Unknown Artist';
              } else {
                newArtistNames[artistId] = artistData['studio_name'] ?? 'Unknown Artist';
              }
            } else {
              newArtistNames[artistId] = artistData['studio_name'] ?? 'Unknown Artist';
            }
          } else {
            newArtistNames[artistId] = 'Unknown Artist';
          }
        } catch (e) {
          print("Error fetching artist name: $e");
          newArtistNames[artistId] = 'Unknown Artist';
        }
      }
    }

    // Update the map without setState since this is called from fetchBookings
    _artistNames.addAll(newArtistNames);
  }

// Add this method to filter bookings based on search criteria
  List<Map<String, dynamic>> _getFilteredBookings(List<Map<String, dynamic>> bookings) {
    List<Map<String, dynamic>> filtered = bookings;

    // Filter by search query (artist name) only
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((booking) {
        String artistId = booking['artist_id'];
        String artistName = _artistNames[artistId]?.toLowerCase() ?? '';
        return artistName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Filter by selected month
    if (_selectedMonth != null) {
      filtered = filtered.where((booking) {
        DateTime bookingDate = booking['time'] as DateTime;
        return bookingDate.year == _selectedMonth!.year &&
            bookingDate.month == _selectedMonth!.month;
      }).toList();
    }

    // Filter by date range (start month to end month OR start date to end date)
    if (_selectedStartDate != null && _selectedEndDate != null) {
      filtered = filtered.where((booking) {
        DateTime bookingDate = booking['time'] as DateTime;
        return bookingDate.isAfter(_selectedStartDate!.subtract(const Duration(days: 1))) &&
            bookingDate.isBefore(_selectedEndDate!.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
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
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  "${_formatDateForHeader(_currentWeekStart)} - ${_formatDateForHeader(_currentWeekStart.add(const Duration(days: 6)))}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _nextWeek,
                icon: const Icon(Icons.chevron_right),
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
                  backgroundColor: const Color(0xFFFB81EE),
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
              final bookingsForDay = _getBookingsForDate(date);
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
                          ? const Color(0xFFFB81EE)
                          : isToday
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: bookingsForDay.isNotEmpty
                          ? Border.all(color: Colors.orange, width: 2)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(date),
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
                        if (bookingsForDay.isNotEmpty)
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

  Widget _buildSelectedDateBookings() {
    final bookingsForSelectedDate = _getBookingsForDate(_selectedDate);

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
            ),
          ),
        ),
        if (bookingsForSelectedDate.isEmpty)
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
          ...bookingsForSelectedDate.map((booking) =>
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: buildBookingTile(context, booking, showDate: false), // Don't show date in calendar view
              )
          ).toList(),
      ],
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget buildBookingTile(BuildContext context, Map<String, dynamic> booking, {bool showDate = true}) {
    final bookingTime = booking['time'] as DateTime;

    // Format date as day/month/year (e.g., "31/10/2025")
    final dateStr = '${bookingTime.day.toString().padLeft(2, '0')}/${bookingTime.month.toString().padLeft(2, '0')}/${bookingTime.year}';

    // Use time_range directly from database
    final timeStr = booking['time_range'];

    // Get artist name
    String artistId = booking['artist_id'];
    String artistName = _artistNames[artistId] ?? 'Loading...';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage: NetworkImage(booking['avatar']),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Artist name at the top
                Text(
                  artistName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                // Show date and time together in list view, only time in calendar view
                Text(
                  showDate ? "$dateStr • $timeStr" : timeStr,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['category'],
                  style: const TextStyle(color: Color(0xFF994D66)),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['status'] == 'Completed' && booking['review_status'] == 'Reviewed'
                      ? 'Completed • Reviewed'
                      : booking['status'] == 'Completed' && booking['review_status'] == 'Haven\'t Review'
                      ? 'Completed • Not Reviewed'
                      : booking['status'],
                  style: TextStyle(
                    color: booking['status'] == 'In Progress'
                        ? Colors.orange
                        : booking['status'] == 'Completed'
                        ? (booking['review_status'] == 'Reviewed' ? Colors.green : Colors.blue)
                        : booking['status'] == 'Cancelled'
                        ? Colors.red
                        : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistoryDetailsPage(
                    appointmentId: booking['appointment_id'],
                  ),
                ),
              ).then((_) {
                _refreshBookings();
              });
            },
            color: Colors.black,
            tooltip: 'View Details',
          ),
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

  Widget _buildSearchSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Search bar
          Container(
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
              decoration: InputDecoration(
                hintText: 'Search by artist name...',
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
              padding: const EdgeInsets.all(16),
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
                  // Replace this part in _buildSearchSection():
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedStartDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: _selectedEndDate ?? DateTime.now().add(const Duration(days: 365)), // ← Restrict to end date if selected
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedStartDate = picked;
                                _selectedMonth = null;
                                _selectedSearchDate = null;
                                // Auto-adjust end date if it's before start date
                                if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) {
                                  _selectedEndDate = picked; // Set end date same as start date
                                }
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
                              initialDate: _selectedEndDate ?? (_selectedStartDate ?? DateTime.now()),
                              firstDate: _selectedStartDate ?? DateTime(2020), // ← Restrict to start date if selected
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() {
                                _selectedEndDate = picked;
                                _selectedMonth = null;
                                _selectedSearchDate = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image_4.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Added SafeArea to push content lower
          SafeArea(
            child: Column(
              children: [
                // Header with view toggle - moved lower with extra padding
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), // Added top padding
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Bookings History",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                              color: _isCalendarView ? const Color(0xFFE147D1) : Colors.grey,
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
                              color: !_isCalendarView ? const Color(0xFFE147D1) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content with RefreshIndicator
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshBookings,
                    child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                      future: _bookingFuture!,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              "Error loading bookings: ${snapshot.error}",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          );
                        }
                        // Get current month bounds
                        final now = DateTime.now();
                        final currentMonthStart = DateTime(now.year, now.month, 1);
                        final currentMonthEnd = DateTime(now.year, now.month + 1, 1).subtract(Duration(days: 1));

                      //upcoming and past filtering with current month filter
                        // Check if custom date range is selected
                        var upcomingBase = _allBookings.where((b) {
                          final bookingTime = b['time'] as DateTime;
                          return (b['status'] != 'Cancelled' && b['status'] != 'Completed') &&
                              bookingTime.isAfter(DateTime.now());
                        }).toList();

                        var pastBase = _allBookings.where((b) {
                          final bookingTime = b['time'] as DateTime;
                          return ((b['status'] == 'Cancelled' || b['status'] == 'Completed') ||
                              (b['status'] != 'Cancelled' && b['status'] != 'Completed' &&
                                  !bookingTime.isAfter(DateTime.now())));
                        }).toList();
                        // Apply search filters
                        final upcoming = _getFilteredBookings(upcomingBase);
                        final past = _getFilteredBookings(pastBase);

                        // Check if there are any bookings at all (before filtering)
                        final hasAnyBookings = _allBookings.isNotEmpty;

                        if (!hasAnyBookings) {
                          return const SingleChildScrollView(
                            physics: AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: 400,
                              child: Center(
                                child: Text(
                                  "No Booking History found.",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          );
                        }

                        if (_isCalendarView) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                _buildWeekCalendar(),
                                const SizedBox(height: 16),
                                _buildSelectedDateBookings(),
                              ],
                            ),
                          );
                        } else {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: _buildToggleButton()
                                  ),
                              _buildSearchSection(), // Add this line
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
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
                                  ),
                                SingleChildScrollView(
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 8,
                                    bottom: MediaQuery.of(context).padding.bottom + 80, // Add bottom padding for nav bar
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_showUpcoming) ...[
                                        if (upcoming.isNotEmpty) ...[
                                          ...upcoming.map((booking) => buildBookingTile(context, booking, showDate: true)).toList(),
                                        ] else ...[
                                          const Padding(
                                            padding: EdgeInsets.only(top: 20),
                                            child: Center(
                                              child: Text(
                                                "No upcoming bookings found.",
                                                style: TextStyle(fontSize: 16, color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ]
                                      ] else ...[
                                        if (past.isNotEmpty) ...[
                                          ...past.map((booking) => buildBookingTile(context, booking, showDate: true)).toList(),
                                        ] else ...[
                                          const Padding(
                                            padding: EdgeInsets.only(top: 20),
                                            child: Center(
                                              child: Text(
                                                "No past bookings found.",
                                                style: TextStyle(fontSize: 16, color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ]
                                      ],
                                    ],
                                  ),
                                ),
                                ],
                              ),
                            );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}