import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'MakeupArtistAppointmentDetails.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class MakeupArtistAppointmentsPage extends StatefulWidget {
  const MakeupArtistAppointmentsPage({super.key});

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
        print('DEBUG: Time from Firebase: "${appointmentData['time']}"');

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
            'appointment_time': appointmentData['time'],
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
        _isLoading = false; // ✅ SET LOADING TO FALSE AFTER DATA IS LOADED
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
    print('DEBUG: Formatting time: "$time" (Type: ${time.runtimeType})');

    if (time is String && time.isNotEmpty) {
      try {
        // If it already contains AM/PM, return as-is (it's already formatted)
        if (time.toUpperCase().contains('AM') ||
            time.toUpperCase().contains('PM')) {
          print('DEBUG: Time already has AM/PM, returning as-is: "$time"');
          return time;
        }
        // Handle 24-hour format (e.g., "14:30")
        if (time.contains(':')) {
          final parts = time.split(':');
          print('DEBUG: Time parts after split: ${parts.toString()}');
          if (parts.length >= 2) {
            // Parse hour and minute separately
            int hour;
            int minute;
            try {
              hour = int.parse(parts[0].trim());
              // Handle the minute part - remove any AM/PM if present
              String minutePart = parts[1].trim();
              if (minutePart.contains(' ')) {
                minutePart =
                minutePart.split(' ')[0]; // Take only the number part
              }
              minute = int.parse(minutePart);
              print('DEBUG: Parsed hour: $hour, minute: $minute');
            } catch (e) {
              print('DEBUG: Error parsing hour/minute: $e');
              return time; // Return original if parsing fails
            }
            // Convert to 12-hour format with AM/PM
            String period = hour >= 12 ? 'PM' : 'AM';
            if (hour > 12) {
              hour -= 12;
            } else if (hour == 0) {
              hour = 12;
            }
            final formattedTime = '${hour.toString()}:${minute
                .toString()
                .padLeft(2, '0')} $period';
            print('DEBUG: Final formatted time: "$formattedTime"');
            return formattedTime;
          }
        }

        print('DEBUG: Time format unexpected, returning as-is: "$time"');
        return time; // Return as-is if format is unexpected
      } catch (e) {
        print('DEBUG: Error parsing time: $time, Error: $e');
        return time;
      }
    }
    print('DEBUG: Time is null/empty, returning N/A');
    return 'N/A';
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

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    print(
        '🃏 DEBUG: Building card for appointment: ${appointment['appointment_id']}');
    print('🃏 DEBUG: Card appointment status: "${appointment['status']}"');
    print(
        '🃏 DEBUG: Card appointment time: "${appointment['appointment_time']}"');

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
          // Customer Info Section
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
                    child: appointment['customer_profile_pic'] != null &&
                        appointment['customer_profile_pic'].isNotEmpty
                        ? Image.network(
                      appointment['customer_profile_pic'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person, size: 30, color: Colors
                            .white);
                      },
                    )
                        : const Icon(
                        Icons.person, size: 30, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                // Customer Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Name: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              appointment['customer_name'] ?? 'Unknown',
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
                            'Styles: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              appointment['category'] ?? 'Unknown',
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
                            'Time: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            _formatTime(appointment['appointment_time']),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Date: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            _formatDate(appointment['appointment_date']),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Status: ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            appointment['status'] ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 14,
                              color: _getStatusColor(
                                  appointment['status'] ?? ''),
                              fontWeight: FontWeight.w600,
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
          // Details Button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: () {
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
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB968C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Details',
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
  }

  Widget _buildAppointmentsList() {
    final appointments = _showUpcoming
        ? _upcomingAppointments
        : _pastAppointments;

    print('📱 DEBUG: Building appointments list');
    print('📱 DEBUG: Show upcoming: $_showUpcoming');
    print('📱 DEBUG: Appointments count: ${appointments.length}');
    print('📱 DEBUG: Is searching: $_isSearching');

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
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today,
                size: 48,
                color: Colors.black.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _showUpcoming
                    ? 'No upcoming appointments'
                    : 'No past appointments',
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

    return Column(
      children: appointments.map((appointment) =>
          _buildAppointmentCard(appointment)).toList(),
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
                : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Booking Request",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Toggle Button
                  _buildToggleButton(),
                  const SizedBox(height: 24),
                  _isLoading
    ? _buildLoadingIndicator()
        : _buildAppointmentsList(),
                ],
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