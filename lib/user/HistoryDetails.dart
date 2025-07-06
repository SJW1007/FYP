import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'WriteReview.dart';
import 'ViewReview.dart';

class HistoryDetailsPage extends StatefulWidget {
  final String appointmentId;
  const HistoryDetailsPage({super.key, required this.appointmentId});

  @override
  State<HistoryDetailsPage> createState() => _HistoryDetailsPageState();

}

class _HistoryDetailsPageState extends State<HistoryDetailsPage> {
  Future<Map<String, dynamic>?>? _bookingFuture;

  @override
  void initState() {
    super.initState();
    _bookingFuture = fetchBookingDetails();
  }

  void _refreshBookingDetails() {
    setState(() {
      _bookingFuture = fetchBookingDetails();
    });
  }
  Future<Map<String, dynamic>?> fetchBookingDetails() async {
    print("Fetching booking details for: ${widget.appointmentId}");

    final doc = await FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .get();

    if (!doc.exists) {
      print("Appointment not found.");
      return null;
    }

    final data = doc.data()!;
    print("Appointment Data: $data");

    final dateStr = data['date'] ?? '';
    String timeStr = data['time'] ?? '';
    print("Raw Date: $dateStr, Raw Time: $timeStr");

    final dateFormat = DateFormat('yyyy-MM-dd h:mm a');
    timeStr = timeStr.replaceAll(' ', ' ').replaceAll(' ', ' ').trim();

    DateTime bookingDateTime;
    try {
      bookingDateTime = dateFormat.parse('$dateStr $timeStr');
      print("Parsed Booking DateTime: $bookingDateTime");
    } catch (e) {
      print("Failed to parse booking datetime: $e");
      return null;
    }

    final artistRef = data['artist_id'];
    final customerRef = data['customerId'];
    final status = data['status'] ?? '';
    final remarks = data['remarks'] ?? 'None';
    final preferredMakeup = data['preferred_makeup'];
    final category = data['category'] ?? '';

    print("Category: $category");
    print("Status: $status");
    print("Remarks: $remarks");
    print("Preferred Makeup: $preferredMakeup");

    if (artistRef is! DocumentReference) {
      print("Invalid artist reference.");
      return null;
    }

    final artistDoc = await artistRef.get();
    if (!artistDoc.exists) {
      print("Artist document not found.");
      return null;
    }

    final artistData = artistDoc.data() as Map<String, dynamic>?;
    if (artistData == null) {
      print("Artist data is null.");
      return null;
    }
    print("Artist Data: $artistData");

    final address = artistData['address'] ?? '';
    final price = artistData['price'] ?? '';
    final userRef = artistData['user_id'];

    print("Artist Address: $address, Price Range: $price");

    if (userRef is! DocumentReference) {
      print("Invalid user reference in artist data.");
      return null;
    }

    final userDoc = await userRef.get();
    if (!userDoc.exists) {
      print("User document not found.");
      return null;
    }

    final userData = userDoc.data() as Map<String, dynamic>?;
    if (userData == null) {
      print("User data is null.");
      return null;
    }

    print("User Data: $userData");

    // Check if a review exists for this appointment
    final reviewQuery = await FirebaseFirestore.instance
        .collection('reviews')
        .where('appointment_id', isEqualTo: FirebaseFirestore.instance.collection('appointments').doc(widget.appointmentId))
        .limit(1)
        .get();

    final reviewExists = reviewQuery.docs.isNotEmpty;

    final avatarUrl = userData['profile pictures'];
    final name = artistData['studio_name'] ?? '';
    final phone = artistData['phone_number'] ?? '';
    final email = artistData['email'] ?? '';
    final now = DateTime.now();
    final isPast = status == 'Completed' && bookingDateTime.isBefore(now);
    final daysDifference = bookingDateTime.difference(now).inDays;
    final canCancel = daysDifference > 3;

    print("Artist Name: $name, Phone: $phone, Email: $email, Avatar: $avatarUrl");

    return {
      'category': category,
      'date': dateStr,
      'time': timeStr,
      'remarks': remarks,
      'status': status,
      'preferred_makeup': preferredMakeup,
      'address': address,
      'price': price,
      'artist_name': name,
      'artist_phone': phone,
      'artist_email': email,
      'avatar': avatarUrl,
      'isPastBooking': isPast,
      'reviewExists': reviewExists,
      'canCancel': canCancel,
      'daysUntilAppointment': daysDifference,
    };

  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        //backgroundColor: const Color(0xFFFDEBEB),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Booking Details", style: TextStyle(color: Colors.black)),
        centerTitle: true,
        elevation: 0,
      ),
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
          FutureBuilder<Map<String, dynamic>?>(
            future: _bookingFuture ?? fetchBookingDetails(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data == null) {
                return const Center(child: Text("No details found."));
              }

              final booking = snapshot.data!;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: NetworkImage(booking['avatar']),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking['artist_name'],
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 16, color: Color(0xFFFB81EE)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      booking['artist_phone'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.email, size: 16, color: Color(0xFFFB81EE)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      booking['artist_email'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    bookingInfoRow(Icons.style, "Category", booking['category']),
                    bookingInfoRow(Icons.location_on, "Address", booking['address']),
                    bookingInfoRow(Icons.calendar_today, "Date", booking['date']),
                    bookingInfoRow(Icons.access_time, "Time", booking['time']),
                    bookingInfoRow(Icons.attach_money, "Price", booking['price']),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(width: 12),
                          const Padding(
                            padding: EdgeInsets.only(top: 10.0),
                            child: Icon(Icons.receipt, size: 22, color: Color(0xFFFB81EE)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Status",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  booking['status'],
                                  style: TextStyle(
                                    color: booking['status'] == 'In Progress'
                                        ? Colors.orange
                                        : booking['status'] == 'Completed'
                                        ? Colors.green
                                        : booking['status'] == 'Rejected' || booking['status'] == 'Cancelled'
                                        ? Colors.red
                                        : Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    bookingInfoRow(Icons.comment, "Remarks", booking['remarks']),

                    const SizedBox(height: 16),
                    // Replace the existing preferred makeup image section with this improved version
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x80D8AEDB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Preferred Makeup:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (booking['preferred_makeup'] != null)
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  booking['preferred_makeup'],
                                  height: 200,
                                  errorBuilder: (context, error, stackTrace) {
                                    print('Image load error: $error');
                                    return Container(
                                      height: 200,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.error_outline, size: 48, color: Colors.grey),
                                          SizedBox(height: 8),
                                          Text(
                                            'Image not available',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 200,
                                      child: Center(
                                        child: CircularProgressIndicator(
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
                            )
                          else
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'No preferred makeup image',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                    // Cancel button with 3-day restriction
                    if (booking['status'] != 'Cancelled' &&
                        booking['status'] != 'Completed' &&
                        booking['isPastBooking'] == false)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: booking['canCancel'] ? () {
                                showDialog(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text("Cancel Booking"),
                                    content: const Text("Are you sure you want to cancel this booking?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext),
                                        child: const Text("No"),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.pop(dialogContext);

                                          try {
                                            await FirebaseFirestore.instance
                                                .collection('appointments')
                                                .doc(widget.appointmentId)
                                                .update({'status': 'Cancelled'});

                                            _refreshBookingDetails();

                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("Booking cancelled successfully.")),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text("Failed to cancel booking: $e")),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text("Yes"),
                                      ),
                                    ],
                                  ),
                                );
                              } : null, // Disable button if can't cancel
                              style: ElevatedButton.styleFrom(
                                backgroundColor: booking['canCancel'] ? Colors.red : Colors.grey,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text("Cancel Booking", style: TextStyle(color: Colors.white)),
                            ),
                          ),
                          // Show message if cancellation is not allowed
                          if (!booking['canCancel'])
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                "Cancellation is only allowed more than 3 days before the appointment date.",
                                style: TextStyle(
                                  color: Colors.red[600],
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget bookingInfoRow(IconData icon, String title, String value, {Color valueColor = Colors.black}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 8.0), // Shift icon down
            child: Icon(icon, size: 22, color: Color(0xFFFB81EE)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text: "$title\n",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 16,
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
