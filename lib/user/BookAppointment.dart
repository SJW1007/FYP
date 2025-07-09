import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'UserNavigation.dart';
import 'dart:async';

class BookAppointmentPage extends StatefulWidget {
  final String userId;

  const BookAppointmentPage({super.key, required this.userId});

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  // Add timer variable
  Timer? _refreshTimer;
  DateTime _selectedDate = DateTime.now();
  String _selectedTime = '';
  final TextEditingController _remarksController = TextEditingController();
  File? _selectedImage;

  // New variables for better refresh management
  bool _isUserInteracting = false;
  DateTime? _lastUserInteraction;
  int _refreshInterval = 30; // Start with 30 seconds
  bool _hasSelectedSlot = false;
  Timer? _interactionTimer;

  List<String> workingDays = [];
  int slotPerHour = 1;
  int personPerSlot = 1;
  List<String> generatedTimeSlots = [];
  Map<String, int> slotAvailability = {};

  bool isDataReady = false;
  // 1. loadSlotAvailability method
  Future<void> loadSlotAvailability(DateTime date) async {
    if (generatedTimeSlots.isEmpty) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final now = DateTime.now();

    try {
      // Get the makeup artist document reference first
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return;

      final makeupArtistDocRef = artistQuery.docs.first.reference;

      // Query appointments using the makeup artist document reference
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: makeupArtistDocRef)
          .where('date', isEqualTo: formattedDate)
          .where('status', whereIn: ['Confirmed', 'In Progress', 'Pending', 'Completed'])
          .get();

      Map<String, int> bookedCount = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final time = data['time'] ?? '';
        if (time.isNotEmpty) {
          bookedCount[time] = (bookedCount[time] ?? 0) + 1;
        }
      }

      // Get working hours with robust parsing
      final workingHourStr = (await fetchArtistSlots(widget.userId))?['working_hour'] ?? '';
      print('Raw working hour string: "$workingHourStr"');

      // Use the same robust cleaning as in fetchTimeSlotAndWorkingDay
      String cleanedWorkingHourStr = workingHourStr
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), ' ')
          .replaceAll(RegExp(r'[–—−]'), '-')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toUpperCase();

      print('Cleaned working hour string: "$cleanedWorkingHourStr"');

      final parts = cleanedWorkingHourStr.split(RegExp(r'\s*-\s*'));
      if (parts.length < 2) {
        print('Invalid working hour format: $cleanedWorkingHourStr');
        return;
      }

      // Robust time parsing function (same as in fetchTimeSlotAndWorkingDay)
      DateTime parseTime(String timeString) {
        print('Parsing time: "$timeString"');

        String cleaned = timeString
            .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();

        print('Cleaned time string: "$cleaned"');

        // Manual regex parsing (most reliable)
        final RegExp timeRegex = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$', caseSensitive: false);
        final match = timeRegex.firstMatch(cleaned);

        if (match != null) {
          try {
            int hour = int.parse(match.group(1)!);
            int minute = int.parse(match.group(2) ?? '0');
            String? ampm = match.group(3)?.toUpperCase();

            // Convert to 24-hour format
            if (ampm == 'PM' && hour < 12) {
              hour += 12;
            } else if (ampm == 'AM' && hour == 12) {
              hour = 0;
            }

            return DateTime(2000, 1, 1, hour, minute);
          } catch (e) {
            print('Error parsing time components: $e');
          }
        }

        // Fallback: Try multiple DateFormat patterns
        final List<DateFormat> formats = [
          DateFormat('h:mm a'),
          DateFormat('h a'),
          DateFormat('H:mm'),
          DateFormat('H'),
          DateFormat('hh:mm a'),
          DateFormat('hh a'),
        ];

        for (final format in formats) {
          try {
            return format.parse(cleaned);
          } catch (e) {
            continue;
          }
        }

        throw FormatException('Could not parse time: "$timeString"');
      }

      DateTime start;
      DateTime end;

      try {
        start = parseTime(parts[0].trim());
        end = parseTime(parts[1].trim());
        print('Parsed working hours: ${DateFormat.jm().format(start)} to ${DateFormat.jm().format(end)}');
      } catch (e) {
        print('Error parsing working hours: $e');
        // Use fallback hours
        start = DateTime(2000, 1, 1, 9, 0);   // 9:00 AM
        end = DateTime(2000, 1, 1, 17, 0);    // 5:00 PM
        print('Using fallback hours: 9:00 AM to 5:00 PM');
      }
      // Clear and regenerate slots
      generatedTimeSlots.clear();
      slotAvailability.clear();
      Duration slotDuration = Duration(minutes: (60 / slotPerHour).round());
      while (start.isBefore(end)) {
        final formattedTime = DateFormat.jm().format(start);
        final booked = bookedCount[formattedTime] ?? 0;
        final available = personPerSlot - booked;

        // Disable slot if the time has already passed (for today only)
        if (_selectedDate.day == now.day &&
            _selectedDate.month == now.month &&
            _selectedDate.year == now.year &&
            start.isBefore(now)) {
          slotAvailability[formattedTime] = 0; // Mark as unavailable
        } else {
          slotAvailability[formattedTime] = available > 0 ? available : 0;
        }
        generatedTimeSlots.add(formattedTime);
        start = start.add(slotDuration);
      }
      setState(() {}); // Refresh UI
    } catch (e) {
      print('Error loading slot availability: $e');
    }
  }
// 2. real-time slot checking before booking
  Future<bool> checkSlotAvailabilityRealTime(String date, String time) async {
    try {
      // Get the makeup artist document reference
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return false;

      final makeupArtistDocRef = artistQuery.docs.first.reference;

      // Count current bookings for this slot
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: makeupArtistDocRef)
          .where('date', isEqualTo: date)
          .where('time', isEqualTo: time)
          .where('status', whereIn: ['Confirmed', 'In Progress','Pending', 'Completed'])
          .get();

      final currentBookings = snapshot.docs.length;
      final available = personPerSlot - currentBookings;

      print('Real-time check: $currentBookings bookings, $available slots available');
      return available > 0;
    } catch (e) {
      print('Error checking real-time availability: $e');
      return false;
    }
  }

// 3. bookAppointment method with conflict detection
  Future<void> bookAppointment() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // ✅ Get currently logged-in user (the customer)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to book.')),
        );
        return;
      }
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 🎯 REAL-TIME SLOT AVAILABILITY CHECK
      final isAvailable = await checkSlotAvailabilityRealTime(formattedDate, _selectedTime);

      if (!isAvailable) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sorry, this session has been booked by others!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );

        // Refresh the slots to show updated availability
        await loadSlotAvailability(_selectedDate);
        return;
      }

      // Get makeup artist reference
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Makeup artist not found')),
        );
        return;
      }
      final artistData = artistQuery.docs.first.data();
      final makeupArtistDocRef = artistQuery.docs.first.reference;
      // Create customer reference
      final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
      // Upload image if available
      String? imageUrl;
      if (_selectedImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('preferred_makeup')
            .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

        final uploadTask = await storageRef.putFile(_selectedImage!);
        imageUrl = await uploadTask.ref.getDownloadURL();
      }
      // FINAL AVAILABILITY CHECK
      final finalAvailabilityCheck = await checkSlotAvailabilityRealTime(formattedDate, _selectedTime);
      if (!finalAvailabilityCheck) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sorry, this session was just booked by someone else!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        await loadSlotAvailability(_selectedDate);
        return;
      }
      // Create appointment data with references for both artist and customer
      final appointmentData = {
        'artist_id': makeupArtistDocRef,
        'customerId': currentUserRef,
        'category': artistData['category'],
        'date': formattedDate,
        'time': _selectedTime,
        'remarks': _remarksController.text.trim().isEmpty ? 'None' : _remarksController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'status': 'In Progress',
        if (imageUrl != null) 'preferred_makeup': imageUrl,
      };
      print('Attempting to create appointment with data:');
      print('customer_id: ${currentUserRef.path}');
      print('artist_id: ${makeupArtistDocRef.path}');
      print('date: $formattedDate');
      print('time: $_selectedTime');
      // CREATE APPOINTMENT
      await FirebaseFirestore.instance.collection('appointments').add(appointmentData);
      Navigator.pop(context); // Close loading dialog
      print('Appointment booked successfully!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appointment booked successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AppointmentSuccessPage()),
      );
    } catch (e) {
      Navigator.pop(context);
      print('Error booking appointment: $e');

      // Handle specific error types
      if (e.toString().contains('permission-denied')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied. Please check your login status.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (e.toString().contains('Slot no longer available')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sorry, this session has been booked by others!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        // Refresh slots
        await loadSlotAvailability(_selectedDate);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to book appointment. Please try again.')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    fetchTimeSlotAndWorkingDay();
    _startSmartAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _interactionTimer?.cancel();
    super.dispose();
  }

  // void _startAutoRefresh() {
  //   // Refresh every 30 seconds (adjust as needed)
  //   _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
  //     if (isDataReady && mounted) {
  //       loadSlotAvailability(_selectedDate);
  //     }
  //   });
  // }

  // Smart refresh strategy
  void _startSmartAutoRefresh() {
    _refreshTimer = Timer.periodic(Duration(seconds: _refreshInterval), (timer) {
      if (!mounted || !isDataReady) return;

      // Don't refresh if user is actively interacting
      if (_isUserInteracting) {
        print('Skipping refresh - user is interacting');
        return;
      }

      // Reduce refresh frequency if user has selected a slot
      if (_hasSelectedSlot && _refreshInterval < 60) {
        _refreshInterval = 60; // Slow down to 1 minute
        _restartTimer();
        return;
      }

      // Perform silent refresh
      _performSilentRefresh();
    });
  }

  void _restartTimer() {
    _refreshTimer?.cancel();
    _startSmartAutoRefresh();
  }

  // Mark user interaction
  void _markUserInteraction() {
    _lastUserInteraction = DateTime.now();

    if (!_isUserInteracting) {
      setState(() {
        _isUserInteracting = true;
      });
    }

    // Clear interaction flag after 5 seconds of no activity
    _interactionTimer?.cancel();
    _interactionTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isUserInteracting = false;
        });
      }
    });
  }

  // Silent refresh without UI disruption
  Future<void> _performSilentRefresh() async {
    try {
      final previousAvailability = Map<String, int>.from(slotAvailability);

      // Refresh data silently
      await loadSlotAvailability(_selectedDate);

      // Check if there are significant changes
      bool hasSignificantChanges = false;
      for (String slot in generatedTimeSlots) {
        final oldAvailability = previousAvailability[slot] ?? 0;
        final newAvailability = slotAvailability[slot] ?? 0;

        // Significant change: slot became unavailable or availability changed by more than 1
        if ((oldAvailability > 0 && newAvailability == 0) ||
            (oldAvailability - newAvailability).abs() > 1) {
          hasSignificantChanges = true;
          break;
        }
      }

      // Only show notification for significant changes
      if (hasSignificantChanges && mounted) {
        _showDiscreetUpdateNotification();
      }

    } catch (e) {
      print('Silent refresh failed: $e');
    }
  }

  // Discreet notification for slot changes
  void _showDiscreetUpdateNotification() {
    // Only show if user hasn't interacted recently
    if (_lastUserInteraction != null &&
        DateTime.now().difference(_lastUserInteraction!).inSeconds < 10) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Slot availability updated', style: TextStyle(fontSize: 12)),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
        backgroundColor: Colors.grey[600],
      ),
    );
  }


  Future<Map<String, dynamic>?> fetchArtistSlots(String userId) async {
    try {
      // 1. Fetch from 'users' collection
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final userRef = FirebaseFirestore.instance.doc('users/$userId');

      // 2. Fetch from 'makeup_artists' where user_id is reference to this user
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return null;

      final artistData = artistQuery.docs.first.data();

      // Debug the raw data
      print('Raw artist data: $artistData');
      print('Working day raw: ${artistData['working day']}');
      print('Working hour raw: ${artistData['working hour']}');

      // Combine user and artist data
      return {
        'working day': artistData['working day'] is Map
            ? Map<String, dynamic>.from(artistData['working day'])
            : {},
        'working_hour': artistData['working hour'] ?? 'N/A',
        'time slot': artistData['time slot'] ?? {},
      };
    } catch (e) {
      print('Error fetching artist details: $e');
      return null;
    }
  }

  Future<void> fetchTimeSlotAndWorkingDay() async {
    try {
      final data = await fetchArtistSlots(widget.userId);
      if (data == null) {
        print('No data found for user: ${widget.userId}');
        return;
      }
      // Extract working day
      final workingDayRaw = data['working day'];
      print('Raw working day data: $workingDayRaw');
      print('Working day type: ${workingDayRaw.runtimeType}');

      final workingDay = workingDayRaw != null && workingDayRaw is Map
          ? workingDayRaw.map((key, value) => MapEntry(key.toString(), value.toString()))
          : <String, String>{};

      print('Processed working day map: $workingDay');

      final fromDay = workingDay['From'] ?? 'Monday';
      final toDay = workingDay['To'] ?? 'Friday';

      print('From day: "$fromDay"');
      print('To day: "$toDay"');

      final allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final startIndex = allDays.indexOf(fromDay);
      final endIndex = allDays.indexOf(toDay);

      print('Start index: $startIndex');
      print('End index: $endIndex');

      if (startIndex != -1 && endIndex != -1) {
        if (startIndex <= endIndex) {
          // Normal case: Monday to Friday
          workingDays = allDays.sublist(startIndex, endIndex + 1);
        } else {
          // Wrap-around case: Friday to Tuesday
          workingDays = [
            ...allDays.sublist(startIndex),
            ...allDays.sublist(0, endIndex + 1)
          ];
        }
      } else {
        print('Error: Could not find day indices');
        print('Available days: $allDays');
        // Fallback to Monday-Friday
        workingDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      }

      print('Final calculated workingDays: $workingDays');

      // Extract working hour
      final workingHourStr = data['working_hour'] as String? ?? "";
      print('Raw working hour string from Firestore: "$workingHourStr"');

      // character removal
      String cleanedWorkingHourStr = workingHourStr
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), ' ') // Remove all control chars, non-breaking spaces
          .replaceAll(RegExp(r'[–—−]'), '-') // Normalize dashes
          .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
          .trim()
          .toUpperCase();

      print('Cleaned working hour string: "$cleanedWorkingHourStr"');
      print('Character codes: ${cleanedWorkingHourStr.runes.map((r) => r.toRadixString(16)).toList()}');

      final parts = cleanedWorkingHourStr.split(RegExp(r'\s*-\s*'));

      if (parts.length < 2) {
        print('Invalid working hour format after cleaning: $cleanedWorkingHourStr');
        return;
      }

      // Improved parseTime function with better error handling
      DateTime parseTime(String timeString) {
        print('Attempting to parse time: "$timeString"');

        // Extra aggressive cleaning for individual time strings
        String cleaned = timeString
            .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();

        print('Cleaned individual time string: "$cleaned"');
        print('Individual time character codes: ${cleaned.runes.map((r) => r.toRadixString(16)).toList()}');
        // Manual regex parsing approach (more reliable than DateFormat)
        final RegExp timeRegex = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$', caseSensitive: false);
        final match = timeRegex.firstMatch(cleaned);

        if (match != null) {
          try {
            int hour = int.parse(match.group(1)!);
            int minute = int.parse(match.group(2) ?? '0');
            String? ampm = match.group(3)?.toUpperCase();

            print('Parsed components - Hour: $hour, Minute: $minute, AM/PM: $ampm');

            // Convert to 24-hour format
            if (ampm == 'PM' && hour < 12) {
              hour += 12;
            } else if (ampm == 'AM' && hour == 12) {
              hour = 0; // Midnight
            }

            final result = DateTime(2000, 1, 1, hour, minute);
            print('Successfully parsed time: ${DateFormat.jm().format(result)}');
            return result;
          } catch (e) {
            print('Error parsing time components: $e');
            throw FormatException('Could not parse time components from: $timeString');
          }
        }

        final List<DateFormat> formats = [
          DateFormat('h:mm a'),   // 9:30 AM
          DateFormat('h a'),      // 9 AM
          DateFormat('H:mm'),     // 09:30
          DateFormat('H'),        // 9
          DateFormat('hh:mm a'),  // 09:30 AM
          DateFormat('hh a'),     // 09 AM
        ];

        for (final format in formats) {
          try {
            final result = format.parse(cleaned);
            print('Successfully parsed with DateFormat ${format.pattern}: ${DateFormat.jm().format(result)}');
            return result;
          } catch (e) {
            // Continue to next format
            continue;
          }
        }

        throw FormatException('Could not parse time with any format: "$timeString" (cleaned: "$cleaned")');
      }

      try {
        DateTime start = parseTime(parts[0].trim());
        DateTime end = parseTime(parts[1].trim());

        print('Final parsed working hours: ${DateFormat.jm().format(start)} to ${DateFormat.jm().format(end)}');

        // Extract time slot
        final timeSlotRaw = data['time slot'];
        final timeSlot = timeSlotRaw != null && timeSlotRaw is Map
            ? timeSlotRaw.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};
        final hourSlot = timeSlot['hour']?.toString() ?? '1';
        final personSlot = timeSlot['person']?.toString() ?? '1';

        print('Slot per hour: $hourSlot');
        print('Person per slot: $personSlot');

        generateTimeSlots(startTime: start, endTime: end);

        setState(() {
          _selectedDate = _getFirstAvailableDay();
          isDataReady = true;
        });

      } catch (e) {
        print('Error parsing working hours: $e');
        print('Parts were: ${parts.map((p) => '"$p"').toList()}');

        // Provide fallback default hours if parsing fails
        print('Using fallback working hours: 9:00 AM to 5:00 PM');
        generateTimeSlots(
          startTime: DateTime(2000, 1, 1, 9, 0),   // 9:00 AM
          endTime: DateTime(2000, 1, 1, 17, 0),    // 5:00 PM
        );

        setState(() {
          _selectedDate = _getFirstAvailableDay();
          isDataReady = true;
        });
      }

    } catch (e) {
      print('Error fetching artist slot data: $e');
    }
  }

  void generateTimeSlots({required DateTime startTime, required DateTime endTime}) {
    generatedTimeSlots.clear();
    slotAvailability.clear();

    Duration slotDuration = Duration(minutes: (60 / slotPerHour).round());

    print('Generating time slots every ${slotDuration.inMinutes} minutes between $startTime and $endTime');

    while (startTime.isBefore(endTime)) {
      final formattedTime = DateFormat.jm().format(startTime);
      generatedTimeSlots.add(formattedTime);
      slotAvailability[formattedTime] = personPerSlot;
      print('Added time slot: $formattedTime with availability: $personPerSlot');
      startTime = startTime.add(slotDuration);
    }

    print('Final generated time slots: $generatedTimeSlots');
  }

  bool isWorkingDay(DateTime day) {
    final dayName = DateFormat('EEEE').format(day);
    return workingDays.contains(dayName);
  }

  DateTime _getFirstAvailableDay() {
    DateTime startDate = DateTime.now().add(const Duration(days: 3)); // Start checking from 3 days from now
    for (int i = 0; i < 60; i++) {
      final date = startDate.add(Duration(days: i));
      if (isWorkingDay(date)) return date;
    }
    return startDate; // fallback to 3 days from now
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }



  @override
  Widget _buildMakeupPhotoWidget({
    required File? selectedImage,
    required VoidCallback onAdd,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    if (selectedImage != null) {
      return Center( // Center the entire widget
        child: Stack(
          children: [
            Container(
              width: 200, // Increased from 100 to 200
              height: 200, // Increased from 100 to 200
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16), // Slightly larger border radius
                color: Colors.grey[300],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  selectedImage,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.error, color: Colors.red, size: 40), // Bigger error icon
                    );
                  },
                ),
              ),
            ),
            // Action buttons
            Positioned(
              top: 12, // Adjusted position for bigger container
              right: 12,
              child: Column(
                children: [
                  // Delete button
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(6), // Slightly bigger padding
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20, // Increased from 16 to 20
                      ),
                    ),
                  ),
                  const SizedBox(height: 8), // More spacing
                  // Edit button
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(6), // Slightly bigger padding
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 20, // Increased from 16 to 20
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      return Center( // Center the entire widget
        child: GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.transparent,
              border: Border.all(
                color: const Color(0xFFFB81EE),
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add,
                  color: Color(0xFFFB81EE),
                  size: 60,
                ),
                SizedBox(height: 8),
                Text(
                  "Add Photo",
                  style: TextStyle(
                    color: Color(0xFFFB81EE),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildTimeSlotChips() {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: generatedTimeSlots.map((time) {
        final isSelected = time == _selectedTime;
        final available = slotAvailability[time] ?? 0;
        final totalSlots = personPerSlot;

        return GestureDetector(
          onTap: available > 0 ? () {
            _markUserInteraction();
            setState(() {
              _selectedTime = time;
              _hasSelectedSlot = true;
            });
          } : null,
          child: ChoiceChip(
            label: Text(
              available > 0
                  ? '$time ($available/$totalSlots left)'
                  : '$time (Full)',
            ),
            selected: isSelected,
            onSelected: available > 0 ? (_) {
              _markUserInteraction();
              setState(() {
                _selectedTime = time;
                _hasSelectedSlot = true;
              });
            } : null,
            selectedColor: Colors.pink.shade100,
            disabledColor: Colors.grey.shade300,
            backgroundColor: available <= 2 && available > 0
                ? Colors.orange.shade100
                : null,
          ),
        );
      }).toList(),
    );
  }

  // Enhanced calendar with interaction tracking
  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime.now().add(const Duration(days: 3)),
      lastDay: DateTime.now().add(const Duration(days: 60)),
      focusedDay: _selectedDate,
      selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
      onDaySelected: (selectedDay, focusedDay) async {
        _markUserInteraction();

        if (isWorkingDay(selectedDay)) {
          if (!isSameDay(_selectedDate, selectedDay)) {
            setState(() {
              _selectedDate = selectedDay;
              _selectedTime = ''; // Reset selected time
              _hasSelectedSlot = false;
            });

            // Show loading indicator for immediate feedback
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Loading slots...'),
                  ],
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
              ),
            );

            await loadSlotAvailability(selectedDay);

            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Slots loaded for ${DateFormat('MMM dd').format(selectedDay)}'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(bottom: 120, left: 20, right: 20),
                  backgroundColor: Colors.green[600],
                ),
              );
            }
          }
        }
      },
      calendarFormat: CalendarFormat.month,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
      ),
      calendarStyle: CalendarStyle(
        selectedDecoration: BoxDecoration(
          color: Colors.purple,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        todayDecoration: BoxDecoration(
          color: Colors.pink.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
      ),
      enabledDayPredicate: isWorkingDay,
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(widget.userId).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("User data not found"));

            return Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/image_4.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            const Text('Book Appointment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: isDataReady ? _buildCalendar() : const CircularProgressIndicator(),
                        ),
                        const SizedBox(height: 12),

                        const Text('Select Time', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildTimeSlotChips(),


                        const SizedBox(height: 16),
                        const Text('Remarks', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.pink.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TextField(
                            controller: _remarksController,
                            maxLines: 3,
                            decoration: const InputDecoration.collapsed(hintText: "Enter remarks here"),
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Text('Preferred Makeup:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildMakeupPhotoWidget(
                          selectedImage: _selectedImage,
                          onAdd: _pickImage,
                          onEdit: _pickImage,
                          onDelete: () {
                            // Show confirmation dialog before deleting
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Remove Photo'),
                                  content: const Text('Are you sure you want to remove this photo?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _selectedImage = null;
                                        });
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Photo removed'),
                                            duration: Duration(seconds: 2),
                                            behavior: SnackBarBehavior.floating,
                                            margin: EdgeInsets.only(bottom: 100, left: 20, right: 20),
                                          ),
                                        );
                                      },
                                      child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_selectedTime.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Please select a time slot.')),
                                );
                                return;
                              }
                              _showBookingConfirmationDialog();
                            },
                            child: Text('Book Appointment'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  Future<void> _showBookingConfirmationDialog() async {
    final selectedDateFormatted = DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate);

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Booking'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Date: $selectedDateFormatted'),
                Text('Time: $_selectedTime'),
                if (_remarksController.text.trim().isNotEmpty)
                  Text('Remarks: ${_remarksController.text.trim()}'),
                const SizedBox(height: 16),

                // Cancellation policy warning
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Important Notice',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Once booked, this appointment cannot be cancelled within 3 days of the scheduled date.',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Confirm Booking'),
              onPressed: () {
                Navigator.of(context).pop();
                bookAppointment();
              },
            ),
          ],
        );
      },
    );
  }
}

class AppointmentSuccessPage extends StatelessWidget {
  const AppointmentSuccessPage({super.key});

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
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 120),
                  const SizedBox(height: 20),
                  const Text(
                    'Appointment Booked Successfully!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const UserNavigation(initialIndex: 0)),
                                (route) => false,
                          );
                        },
                        child: const Text('Back to Home'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const UserNavigation(initialIndex: 1)),
                                (route) => false,
                          );
                        },
                        child: const Text('Booking History'),
                      ),
                    ],
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
