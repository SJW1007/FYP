import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MakeupArtistAppointmentDetailsPage extends StatefulWidget {
  final String appointmentId;
  final String customerId;
  const MakeupArtistAppointmentDetailsPage({
    super.key,
    required this.appointmentId,
    required this.customerId,
  });

  @override
  State<MakeupArtistAppointmentDetailsPage> createState() =>
      _MakeupArtistAppointmentDetailsPageState();
}

class _MakeupArtistAppointmentDetailsPageState
    extends State<MakeupArtistAppointmentDetailsPage> {
  Map<String, dynamic>? appointmentData;
  Map<String, dynamic>? customerData;
  Map<String, dynamic>? makeupArtistData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppointmentDetails();
  }

  Future<void> _loadAppointmentDetails() async {
    try {
      // Get current user ID
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Get appointment details
      final appointmentDoc = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .get();

      if (appointmentDoc.exists) {
        final appointment = appointmentDoc.data()!;

        // Get customer details
        final customerRef = appointment['customerId'] as DocumentReference?;
        Map<String, dynamic>? customer;
        if (customerRef != null) {
          final customerDoc = await customerRef.get();
          if (customerDoc.exists) {
            customer = customerDoc.data() as Map<String, dynamic>?;
          }
        }

        // Get makeup artist details using artist_id from appointment
        Map<String, dynamic>? makeupArtist;
        final artistRef = appointment['artist_id'] as DocumentReference?;
        if (artistRef != null) {
          print('Artist reference path: ${artistRef.path}');
          final artistDoc = await artistRef.get();
          if (artistDoc.exists) {
            makeupArtist = artistDoc.data() as Map<String, dynamic>?;
            print('Makeup artist data: $makeupArtist');
          } else {
            print('Artist document does not exist');
          }
        }

        setState(() {
          appointmentData = appointment;
          customerData = customer;
          makeupArtistData = makeupArtist;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading appointment details: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (date is String) {
      try {
        final dateTime = DateTime.parse(date);
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      } catch (e) {
        return date;
      }
    }
    return 'N/A';
  }

  String _formatTime(dynamic time) {
    if (time is String) {
      return time;
    }
    return 'N/A';
  }

  String _getPrice() {
    // Get price from makeup artist data using artist_id reference
    if (makeupArtistData != null && makeupArtistData!['price'] != null) {
      final price = makeupArtistData!['price'];
      // Handle both string and number types
      if (price is String) {
        return price.startsWith('RM') ? price : 'RM$price';
      } else {
        return 'RM$price';
      }
    }
    return 'RM0';
  }

  String _getAddress() {
    // Get address from makeup artist data using artist_id reference
    if (makeupArtistData != null && makeupArtistData!['address'] != null) {
      return makeupArtistData!['address'].toString();
    }
    return 'Address not available';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (appointmentData == null || customerData == null) {
      return Scaffold(
        appBar: AppBar(
          //backgroundColor: const Color(0xFFFDEBEB),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text("Request Details", style: TextStyle(color: Colors.black)),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Appointment not found'),
        ),
      );
    }

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
            ),Column(
              children: [
                // Add extra spacing to avoid front camera
                const SizedBox(height: 60),

                // Header with close button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'Request Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the close button
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Info Section - Made transparent
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.transparent, // Made transparent
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.transparent,
                            ),
                          ),
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
                                  child: customerData!['profile pictures'] != null &&
                                      customerData!['profile pictures'].isNotEmpty
                                      ? Image.network(
                                    customerData!['profile pictures'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.person,
                                        size: 30,
                                        color: Colors.white,
                                      );
                                    },
                                  )
                                      : const Icon(
                                    Icons.person,
                                    size: 30,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Customer Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customerData!['name'] ?? 'Unknown Customer',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.phone,
                                          size: 16,
                                          color: Colors.black87,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          customerData!['phone number'] ?? 'No phone',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.email,
                                          size: 16,
                                          color: Colors.black87,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            customerData!['email'] ?? 'No email',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
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
                        ),

                        const SizedBox(height: 24),

                        // Appointment Details Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E5F5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow('Category', appointmentData!['category'] ?? 'N/A'),
                              _buildDetailRow('Time', _formatTime(appointmentData!['time'])),
                              _buildDetailRow('Date', _formatDate(appointmentData!['date'])),
                              _buildDetailRow('Price', _getPrice()),
                              _buildDetailRow('Address', _getAddress()),
                              _buildDetailRow('Remarks', appointmentData!['remarks'] ?? 'None', isLast: true),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Preferred Makeup Section
                        const Text(
                          'Preferred Makeup:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E5F5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              // Check if preferred makeup image exists
                              if (appointmentData!['preferred_makeup'] != null &&
                                  appointmentData!['preferred_makeup'].toString().isNotEmpty)
                                Container(
                                  width: 120,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.grey[300],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      appointmentData!['preferred_makeup'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[300],
                                          child: const Icon(
                                            Icons.image,
                                            size: 40,
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              else
                              // Show "No preferred makeup image" when no image is available
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

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ]
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isLast = false}) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        if (!isLast) const SizedBox(height: 16),
      ],
    );
  }
}