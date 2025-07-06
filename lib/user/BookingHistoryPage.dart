import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'HistoryDetails.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  Future<Map<String, List<Map<String, dynamic>>>>? _bookingFuture;

  @override
  void initState() {
    super.initState();
    _bookingFuture = fetchBookings(); // Load data once at the start
  }

  void _refreshBookings() {
    setState(() {
      _bookingFuture = fetchBookings(); // Trigger reload
    });
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

    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd h:mm a');

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
      String timeStr = data['time'] ?? '';
      final category = data['category'] ?? '';
      final artistRef = data['artist_id'];
      final status = data['status'] ?? '';

      if (dateStr.isEmpty || timeStr.isEmpty || artistRef is! DocumentReference) {
        print("Skipping due to missing or invalid fields (date, time, or artist_id).");
        continue;
      }

      // Normalize time string
      timeStr = timeStr.replaceAll(' ', ' ').replaceAll(' ', ' ').trim();

      DateTime bookingDateTime;
      try {
        bookingDateTime = dateFormat.parse('$dateStr $timeStr');
      } catch (e) {
        print("Error parsing date/time: $e");
        continue;
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

      final booking = {
        'appointment_id': doc.id,
        'category': category,
        'time': bookingDateTime,
        'avatar': avatarUrl,
        'status': status,
        'artist_id': artistRef.id,
      };

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

    print("Upcoming: $upcoming");
    print("Past: $past");

    return {'upcoming': upcoming, 'past': past};
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

  Widget buildBookingTile(BuildContext context, Map<String, dynamic> booking) {
    // Determine AM/PM
    String ampm = booking['time'].hour >= 12 ? 'PM' : 'AM';
    // Format hour to 12-hour format (e.g., 1 PM instead of 13 PM)
    int displayHour = booking['time'].hour % 12;
    if (displayHour == 0) {
      displayHour = 12; // 0 o'clock is 12 AM/PM
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundImage: NetworkImage(booking['avatar']),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Format the date and time using DateFormat for consistent display
                  "${DateFormat('MM/dd/yyyy').format(booking['time'])} • "
                      "${displayHour}:${booking['time'].minute
                      .toString()
                      .padLeft(2, '0')} $ampm",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['category'],
                  // Assuming 'category' is always available
                  style: const TextStyle(color: Color(0xFF994D66)),
                ),
                const SizedBox(height: 4),
                Text(
                  booking['status'],
                  style: TextStyle(
                    color: booking['status'] == 'In Progress'
                        ? Colors.orange
                        : booking['status'] == 'Completed'
                        ? Colors.green
                        // : booking['status'] == 'Rejected'
                        // ? Colors.red
                        : booking['status'] == 'Cancelled'
                        ? Colors.red
                        : Colors.black, // default color if none match
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
                _refreshBookings(); // Always refresh when coming back
              });
            },

            color: Colors.black, // Optional: change icon color
            tooltip: 'View Details', // Optional: adds a hover tooltip
          ),

        ],
      ),
    );
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
            // Main content with transparent background
            Container(
              child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _bookingFuture!,
                builder: (context, snapshot) {
                  if (_bookingFuture == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error loading bookings: ${snapshot.error}",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    );
                  }

                  final upcoming = snapshot.data!['upcoming']!;
                  final past = snapshot.data!['past']!;

                  if (upcoming.isEmpty && past.isEmpty) {
                    return const Center(
                      child: Text(
                        "No Booking History found.",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight
                            .w500),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(
                          child: Text(
                            "Bookings History",
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (upcoming.isNotEmpty) ...[
                          buildSectionTitle("Upcoming"),
                          ...upcoming.map((booking) => buildBookingTile(context, booking)).toList(),
                        ],
                        if (upcoming.isNotEmpty && past.isNotEmpty)
                          const Divider(height: 40, thickness: 1, color: Colors
                              .grey),
                        if (past.isNotEmpty) ...[
                          buildSectionTitle("Past"),
                          ...past.map((booking) => buildBookingTile(context, booking)).toList(),

                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}