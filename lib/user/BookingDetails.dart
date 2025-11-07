import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../service/NotificationService.dart';
import 'WriteReview.dart';
import 'ViewReview.dart';
import 'package:flutter/services.dart';

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

  String getPriceForCategory(dynamic priceData, String category) {
    if (priceData == null) return 'Price not available';

    // If priceData is already a string (for backward compatibility)
    if (priceData is String) {
      return priceData;
    }

    // If priceData is a Map
    if (priceData is Map<String, dynamic>) {
      // Try to get the exact category match first
      if (priceData.containsKey(category)) {
        return priceData[category].toString();
      }

      // If exact match not found, try case-insensitive search
      for (String key in priceData.keys) {
        if (key.toLowerCase() == category.toLowerCase()) {
          return priceData[key].toString();
        }
      }

      // If category not found, return first available price with category name
      if (priceData.isNotEmpty) {
        String firstKey = priceData.keys.first;
        return '${priceData[firstKey]} (${firstKey})';
      }
    }

    return 'Price not available';
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
    String timeRangeStr = data['time_range'] ?? data['time'] ?? ''; // Support both fields

    // Extract start time for DateTime parsing
    String timeStr = timeRangeStr.split('-')[0].trim();
    timeStr = timeStr.replaceAll(RegExp(r'\s+'), ' ').trim();

    final dateFormat = DateFormat('yyyy-MM-dd h:mm a');
    final dateFormatNoMinutes = DateFormat('yyyy-MM-dd h a');

    DateTime bookingDateTime;
    try {
      bookingDateTime = dateFormat.parse('$dateStr $timeStr');
    } catch (e) {
      try {
        bookingDateTime = dateFormatNoMinutes.parse('$dateStr $timeStr');
      } catch (e2) {
        print("Failed to parse booking datetime: $e2");
        return null;
      }
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
    final price = artistData['price'] ;
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
    final phone = artistData['phone_number'].toString() ?? '';
    final email = artistData['email'] ?? '';
    final now = DateTime.now();
    final nowDateOnly = DateTime(now.year, now.month, now.day);
    final appointmentDateOnly = DateTime(bookingDateTime.year, bookingDateTime.month, bookingDateTime.day);
    final isPast = status == 'Completed' && bookingDateTime.isBefore(now);
    final daysDifference = appointmentDateOnly.difference(nowDateOnly).inDays;
    final canCancel = daysDifference >= 3;
    final specificPrice = getPriceForCategory(price, category);

    print("Artist Name: $name, Phone: $phone, Email: $email, Avatar: $avatarUrl");

    return {
      'category': category,
      'date': dateStr,
      'time': timeRangeStr,
      'remarks': remarks,
      'status': status,
      'preferred_makeup': preferredMakeup,
      'address': address,
      'price': specificPrice,
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

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
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

                // Close button
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
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3), width: 1),
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

                // Bottom instruction text
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
        );
      },
    );
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
                                      '0${booking['artist_phone']}',
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
                    buildBookingIdSection(widget.appointmentId),
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
                              child: GestureDetector(
                                onTap: () => _showImageDialog(
                                    context,
                                    booking['preferred_makeup']
                                ),
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
                            )else
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
                                            // Get appointment data first to extract artist info
                                            final appointmentDoc = await FirebaseFirestore.instance
                                                .collection('appointments')
                                                .doc(widget.appointmentId)
                                                .get();

                                            if (!appointmentDoc.exists) {
                                              throw Exception("Appointment not found");
                                            }

                                            final appointmentData = appointmentDoc.data()!;
                                            final artistRef = appointmentData['artist_id'] as DocumentReference?;
                                            final customerRef = appointmentData['customerId'] as DocumentReference?;

                                            if (artistRef == null || customerRef == null) {
                                              throw Exception("Invalid appointment data");
                                            }

                                            // Get artist document to get user_id
                                            final artistDoc = await artistRef.get();
                                            if (!artistDoc.exists) {
                                              throw Exception("Artist not found");
                                            }

                                            final artistData = artistDoc.data() as Map<String, dynamic>?;
                                            final artistUserRef = artistData?['user_id'] as DocumentReference?;

                                            if (artistUserRef == null) {
                                              throw Exception("Artist user reference not found");
                                            }

                                            // Update appointment status to Cancelled
                                            await FirebaseFirestore.instance
                                                .collection('appointments')
                                                .doc(widget.appointmentId)
                                                .update({'status': 'Cancelled'});

                                            // Create notification for the makeup artist
                                            await NotificationService.createCancellationNotification(
                                              artistUserId: artistUserRef.id,
                                              appointmentId: widget.appointmentId,
                                              customerId: customerRef.id,
                                            );

                                            _refreshBookingDetails();

                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text("Booking cancelled successfully. Artist has been notified."),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            print("Error cancelling booking: $e");
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text("Failed to cancel booking: $e"),
                                                  backgroundColor: Colors.red,
                                                ),
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
                                "Cancellation is only allowed at least 3 days before the appointment date.",
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
                    // Review buttons
                    if (booking['status'] == 'Completed')
                      Column(
                        children: [
                          if (!booking['reviewExists'])
                          // Write Review Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WriteReviewPage(
                                        appointmentId: widget.appointmentId,
                                      ),
                                    ),
                                  );

                                  // Refresh the page if review was written
                                  if (result == true) {
                                    _refreshBookingDetails();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF923DC3),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                child: const Text("Write Review", style: TextStyle(color: Colors.white)),
                              ),
                            )
                          else
                          // View Review Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ViewReviewPage(
                                        appointmentId: widget.appointmentId,
                                      ),
                                    ),
                                  );

                                  // Refresh the page if review was deleted
                                  if (result == 'deleted') {
                                    _refreshBookingDetails();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF923DC3),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                child: const Text("View Review", style: TextStyle(color: Colors.white)),
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

  Widget buildBookingIdSection(String appointmentId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB81EE), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB81EE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFFFB81EE),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Booking ID',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    appointmentId,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: Color(0xFF925F70),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  color: const Color(0xFFFB81EE),
                  onPressed: () {
                    // Copy to clipboard
                    final data = ClipboardData(text: appointmentId);
                    Clipboard.setData(data);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Booking ID copied to clipboard'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  tooltip: 'Copy Booking ID',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep this ID for your records and reference',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
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
