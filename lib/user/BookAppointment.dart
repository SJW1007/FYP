import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/NotificationService.dart';
import 'UserNavigation.dart';
import 'dart:async';

class BookAppointmentPage extends StatefulWidget {
  final String userId;

  const BookAppointmentPage({super.key, required this.userId});

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  Timer? _refreshTimer;
  DateTime _selectedDate = DateTime.now();
  String _selectedTime = '';
  final TextEditingController _remarksController = TextEditingController();
  File? _selectedImage;
  String _selectedCategory = '';
  Map<String, String> availableCategories = {};
  bool _isCategoriesLoaded = false;
  bool _isBookingInProgress = false;
  List<Map<String, String>> timeSlotRanges = [];

  Timer? _debounceTimer;
  Timer? _interactionTimer;

  List<String> workingDays = [];
  int slotPerHour = 1;
  int personPerSlot = 1;
  List<String> generatedTimeSlots = [];
  Map<String, int> slotAvailability = {};

  StreamSubscription<QuerySnapshot>? _appointmentListener;
  DocumentReference? _makeupArtistDocRef;

  bool isDataReady = false;
  StreamSubscription<DocumentSnapshot>? _artistDataListener;
  StreamSubscription<DocumentSnapshot>? _categoriesListener;
  bool _isLoadingSlots = false;
  bool _isRefreshing = false;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  String _getSelectedTimeRange() {
    if (_selectedTime.isEmpty || timeSlotRanges.isEmpty) {
      return _selectedTime;
    }

    // Find the index of the selected time
    final index = generatedTimeSlots.indexOf(_selectedTime);
    if (index >= 0 && index < timeSlotRanges.length) {
      final range = timeSlotRanges[index];
      return '${range['start']} - ${range['end']}';
    }

    return _selectedTime;
  }

  // Helper method to parse time range string into DateTime objects
  Map<String, DateTime>? _parseTimeRange(String timeRange) {
    try {
      final parts = timeRange.split(' - ');
      if (parts.length != 2) return null;

      final startTime = DateFormat.jm().parse(parts[0].trim());
      final endTime = DateFormat.jm().parse(parts[1].trim());

      return {
        'start': startTime,
        'end': endTime,
      };
    } catch (e) {
      print('Error parsing time range: $timeRange');
      return null;
    }
  }

  // Helper method to check if two time ranges overlap
  bool _doTimesOverlap(Map<String, DateTime> range1, Map<String, DateTime> range2) {
    final start1 = range1['start']!;
    final end1 = range1['end']!;
    final start2 = range2['start']!;
    final end2 = range2['end']!;

    // Two ranges overlap if:
    // - Range1 starts before Range2 ends AND
    // - Range1 ends after Range2 starts
    return start1.isBefore(end2) && end1.isAfter(start2);
  }


  // 1. Simplified loadSlotAvailability - no loading states
  Future<void> loadSlotAvailability(DateTime date, {bool showLoading = true}) async {
    if (generatedTimeSlots.isEmpty || _makeupArtistDocRef == null) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    final now = DateTime.now();

    try {
      if (showLoading && mounted) {
        setState(() {
          _isLoadingSlots = true;
        });
      }

      // Initialize with current availability
      Map<String, int> tempAvailability = Map.from(slotAvailability);

      // If this is a completely new date, initialize defaults
      if (tempAvailability.isEmpty) {
        for (String timeSlot in generatedTimeSlots) {
          final totalCapacity = slotPerHour * personPerSlot;
          tempAvailability[timeSlot] = totalCapacity;
        }
      }

      // Get ALL appointments for this date (we'll match by time_range)
      final snapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: _makeupArtistDocRef)
          .where('date', isEqualTo: formattedDate)
          .where('status', whereIn: ['Confirmed', 'In Progress', 'Completed'])
          .get();

      // Count bookings by matching time_range (including overlapping slots)
      Map<String, int> bookedCount = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final bookedTimeRange = data['time_range'] ?? data['time'] ?? ''; // Fallback to 'time' for old data

        if (bookedTimeRange.isNotEmpty) {
          // Parse the booked time range
          final bookedTimes = _parseTimeRange(bookedTimeRange);
          if (bookedTimes == null) continue;

          // Check which current slots this booking overlaps with
          for (int i = 0; i < generatedTimeSlots.length; i++) {
            final currentSlot = generatedTimeSlots[i];
            final currentRange = timeSlotRanges[i];
            final currentTimeRange = '${currentRange['start']} - ${currentRange['end']}';

            // Exact match
            if (bookedTimeRange == currentTimeRange) {
              bookedCount[currentSlot] = (bookedCount[currentSlot] ?? 0) + 1;
            } else {
              // Check for overlap
              final currentTimes = _parseTimeRange(currentTimeRange);
              if (currentTimes != null && _doTimesOverlap(bookedTimes, currentTimes)) {
                // This booking overlaps with this slot, mark as booked
                bookedCount[currentSlot] = (bookedCount[currentSlot] ?? 0) + 1;
              }
            }
          }
        }
      }

      // Update slot availability
      final totalCapacity = slotPerHour * personPerSlot;
      for (String timeSlot in generatedTimeSlots) {
        final booked = bookedCount[timeSlot] ?? 0;
        final available = totalCapacity - booked;

        // Check if time has passed (for today only)
        bool timeHasPassed = false;
        if (_selectedDate.day == now.day &&
            _selectedDate.month == now.month &&
            _selectedDate.year == now.year) {
          try {
            final slotTime = DateFormat.jm().parse(timeSlot);
            final slotDateTime = DateTime(
                now.year, now.month, now.day,
                slotTime.hour, slotTime.minute
            );
            timeHasPassed = slotDateTime.isBefore(now);
          } catch (e) {
            // If parsing fails, assume time hasn't passed
          }
        }

        tempAvailability[timeSlot] = timeHasPassed ? 0 : (available > 0 ? available : 0);
      }

      // Single state update at the end
      if (mounted) {
        setState(() {
          slotAvailability = tempAvailability;
          _isLoadingSlots = false;
        });
      }

      _setupRealTimeListener(date);
    } catch (e) {
      print('Error loading slot availability: $e');
      if (mounted) {
        setState(() {
          _isLoadingSlots = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Refresh all data
      await Future.wait([
        fetchTimeSlotAndWorkingDay(),
        fetchCategoriesAndPrices(),
        loadSlotAvailability(_selectedDate, showLoading: false),
      ]);

      // Small delay to show refresh completed
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('Refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to refresh. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // 2. Simplified bookAppointment method
  Future<void> bookAppointment() async {
    try {
      setState(() {
        _isBookingInProgress = true;
      });

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() {
            _isBookingInProgress = false;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to book.')),
        );
        return;
      }

      // Check if booking date is at least 3 days from now
      final now = DateTime.now();
      final nowDateOnly = DateTime(now.year, now.month, now.day);
      final selectedDateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final daysDifference = selectedDateOnly.difference(nowDateOnly).inDays;

      if (daysDifference < 3) {
        if (mounted) {
          setState(() {
            _isBookingInProgress = false;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointments must be booked at least 3 days in advance'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Get makeup artist reference
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _isBookingInProgress = false;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Makeup artist not found')),
        );
        return;
      }

      final makeupArtistDocRef = artistQuery.docs.first.reference;
      final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

      // Get the time range for this booking
      final timeRange = _getSelectedTimeRange();

      // Check availability
      final preCheckSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('artist_id', isEqualTo: makeupArtistDocRef)
          .where('date', isEqualTo: formattedDate)
          .where('time_range', isEqualTo: timeRange)
          .where('status', whereIn: ['Confirmed', 'In Progress', 'Completed'])
          .get();

      final currentBookings = preCheckSnapshot.docs.length;
      final totalCapacity = slotPerHour * personPerSlot;
      if (currentBookings >= totalCapacity) {
        throw Exception('Slot no longer available');
      }

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

      // Create appointment data
      final appointmentData = {
        'artist_id': makeupArtistDocRef,
        'customerId': currentUserRef,
        'category': _selectedCategory,
        'date': formattedDate,
        'time_range': timeRange,
        'remarks': _remarksController.text.trim().isEmpty ? 'None' : _remarksController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'status': 'In Progress',
        if (imageUrl != null) 'preferred_makeup': imageUrl,
      };

      // Transaction for the actual booking
      String? appointmentId;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final appointmentRef = FirebaseFirestore.instance.collection('appointments').doc();
        appointmentId = appointmentRef.id;
        transaction.set(appointmentRef, appointmentData);
      });

      print('Appointment created successfully');

      // Create notification for makeup artist
      if (appointmentId != null) {
        await NotificationService.createBookingNotification(
          artistUserId: widget.userId,
          appointmentId: appointmentId!,
          customerId: currentUser.uid,
        );
        print('✅ Notification created for artist');
      }

      if (mounted) {
        setState(() {
          _isBookingInProgress = false;
        });
      }

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
      if (mounted) {
        setState(() {
          _isBookingInProgress = false;
        });
      }
      print('Error booking appointment: $e');

      if (e.toString().contains('Slot no longer available')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sorry, this session has been booked by others!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        await loadSlotAvailability(_selectedDate);
      } else if (e.toString().contains('permission-denied')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied. Please check your login status.'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to book appointment. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _setupArtistDataListener() {
    if (_makeupArtistDocRef != null) {
      _artistDataListener = _makeupArtistDocRef!.snapshots().listen(
            (snapshot) {
          if (snapshot.exists && mounted) {
            // Reload categories and time slots when artist data changes
            fetchCategoriesAndPrices();
            fetchTimeSlotAndWorkingDay();
          }
        },
        onError: (error) {
          print('Artist data listener error: $error');
        },
      );
    }
  }

  void _setupCategoriesListener() {
    if (_makeupArtistDocRef != null) {
      _categoriesListener = _makeupArtistDocRef!.snapshots().listen(
            (snapshot) {
          if (snapshot.exists && mounted) {
            final artistData = snapshot.data() as Map<String, dynamic>;

            final List<dynamic> categoriesRaw = artistData['category'] ?? [];
            final List<String> categories = categoriesRaw.map((e) => e.toString()).toList();

            final Map<String, dynamic> pricesRaw = artistData['price'] ?? {};
            final Map<String, String> prices = pricesRaw.map((key, value) =>
                MapEntry(key.toString(), value.toString()));

            Map<String, String> newAvailableCategories = {};
            for (String category in categories) {
              if (prices.containsKey(category)) {
                newAvailableCategories[category] = prices[category]!;
              }
            }

            // Only update state if there are actual changes
            if (availableCategories.toString() != newAvailableCategories.toString()) {
              setState(() {
                availableCategories = newAvailableCategories;
                if (availableCategories.isNotEmpty &&
                    !availableCategories.containsKey(_selectedCategory)) {
                  _selectedCategory = availableCategories.keys.first;
                }
                _isCategoriesLoaded = true;
              });
            }
          }
        },
        onError: (error) {
          print('Categories listener error: $error');
        },
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeArtistReference().then((_) {
      fetchTimeSlotAndWorkingDay();
      fetchCategoriesAndPrices();
    });
  }
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _interactionTimer?.cancel();
    _debounceTimer?.cancel(); // Add this line
    _appointmentListener?.cancel();
    _artistDataListener?.cancel();
    _categoriesListener?.cancel();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _initializeArtistReference() async {
    try {
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isNotEmpty) {
        _makeupArtistDocRef = artistQuery.docs.first.reference;
        // Setup real-time listener for artist data changes
        _setupArtistDataListener();
      }
    } catch (e) {
      print('Error initializing artist reference: $e');
    }
  }

  void _setupRealTimeListener(DateTime date) {
    _appointmentListener?.cancel();

    if (_makeupArtistDocRef == null) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(date);

    _appointmentListener = FirebaseFirestore.instance
        .collection('appointments')
        .where('artist_id', isEqualTo: _makeupArtistDocRef)
        .where('date', isEqualTo: formattedDate)
        .where('status', whereIn: ['Confirmed', 'In Progress', 'Completed'])
        .snapshots()
        .listen(
          (snapshot) {
        // Add debouncing with longer delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _updateSlotAvailabilityFromSnapshot(snapshot);
          }
        });
      },
      onError: (error) {
        print('Real-time listener error: $error');
      },
    );
  }

  void _updateSlotAvailabilityFromSnapshot(QuerySnapshot snapshot) {
    if (!mounted || generatedTimeSlots.isEmpty) return;

    // Debounce rapid updates
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      Map<String, int> bookedCount = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final bookedTimeRange = data['time_range'] ?? data['time'] ?? '';

        if (bookedTimeRange.isNotEmpty) {
          // Parse the booked time range
          final bookedTimes = _parseTimeRange(bookedTimeRange);
          if (bookedTimes == null) continue;

          // Check which current slots this booking overlaps with
          for (int i = 0; i < generatedTimeSlots.length; i++) {
            final currentSlot = generatedTimeSlots[i];
            final currentRange = timeSlotRanges[i];
            final currentTimeRange = '${currentRange['start']} - ${currentRange['end']}';

            // Exact match
            if (bookedTimeRange == currentTimeRange) {
              bookedCount[currentSlot] = (bookedCount[currentSlot] ?? 0) + 1;
            } else {
              // Check for overlap
              final currentTimes = _parseTimeRange(currentTimeRange);
              if (currentTimes != null && _doTimesOverlap(bookedTimes, currentTimes)) {
                // This booking overlaps with this slot, mark as booked
                bookedCount[currentSlot] = (bookedCount[currentSlot] ?? 0) + 1;
              }
            }
          }
        }
      }

      final now = DateTime.now();
      final totalCapacity = slotPerHour * personPerSlot;
      Map<String, int> newSlotAvailability = {};

      for (String timeSlot in generatedTimeSlots) {
        final booked = bookedCount[timeSlot] ?? 0;
        final available = totalCapacity - booked;

        bool timeHasPassed = false;
        if (_selectedDate.day == now.day &&
            _selectedDate.month == now.month &&
            _selectedDate.year == now.year) {
          try {
            final slotTime = DateFormat.jm().parse(timeSlot);
            final slotDateTime = DateTime(
                now.year, now.month, now.day,
                slotTime.hour, slotTime.minute
            );
            timeHasPassed = slotDateTime.isBefore(now);
          } catch (e) {
            // Continue
          }
        }

        final newAvailability = timeHasPassed ? 0 : (available > 0 ? available : 0);
        newSlotAvailability[timeSlot] = newAvailability;
      }

      // Check if selected slot becomes unavailable
      if (_selectedTime.isNotEmpty &&
          slotAvailability.isNotEmpty &&
          (newSlotAvailability[_selectedTime] ?? 0) == 0 &&
          (slotAvailability[_selectedTime] ?? 0) > 0) {

        setState(() {
          _selectedTime = '';
          slotAvailability = newSlotAvailability;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your selected time slot is no longer available'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // Only update state if there are actual changes
        if (newSlotAvailability.toString() != slotAvailability.toString()) {
          setState(() {
            slotAvailability = newSlotAvailability;
          });
        }
      }
    });
  }

  Future<Map<String, dynamic>?> fetchArtistSlots(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final userRef = FirebaseFirestore.instance.doc('users/$userId');

      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return null;

      final artistData = artistQuery.docs.first.data();

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

  Future<void> fetchCategoriesAndPrices() async {
    try {
      final userRef = FirebaseFirestore.instance.doc('users/${widget.userId}');
      final artistQuery = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .where('user_id', isEqualTo: userRef)
          .limit(1)
          .get();

      if (artistQuery.docs.isEmpty) return;

      _makeupArtistDocRef = artistQuery.docs.first.reference;

      // Setup real-time listener instead of one-time fetch
      _setupCategoriesListener();

    } catch (e) {
      print('Error setting up categories listener: $e');
    }
  }

  Future<void> fetchTimeSlotAndWorkingDay() async {
    try {
      final data = await fetchArtistSlots(widget.userId);
      if (data == null) return;

      // Extract working day
      final workingDayRaw = data['working day'];
      final workingDay = workingDayRaw != null && workingDayRaw is Map
          ? workingDayRaw.map((key, value) => MapEntry(key.toString(), value.toString()))
          : <String, String>{};

      final fromDay = workingDay['From'] ?? 'Monday';
      final toDay = workingDay['To'] ?? 'Friday';

      final allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final startIndex = allDays.indexOf(fromDay);
      final endIndex = allDays.indexOf(toDay);

      if (startIndex != -1 && endIndex != -1) {
        if (startIndex <= endIndex) {
          workingDays = allDays.sublist(startIndex, endIndex + 1);
        } else {
          workingDays = [
            ...allDays.sublist(startIndex),
            ...allDays.sublist(0, endIndex + 1)
          ];
        }
      } else {
        workingDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      }

      // Extract working hour
      final workingHourStr = data['working_hour'] as String? ?? "";
      String cleanedWorkingHourStr = workingHourStr
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), ' ')
          .replaceAll(RegExp(r'[–—−]'), '-')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toUpperCase();

      final parts = cleanedWorkingHourStr.split(RegExp(r'\s*-\s*'));

      if (parts.length < 2) {
        print('Invalid working hour format');
        return;
      }

      DateTime parseTime(String timeString) {
        String cleaned = timeString
            .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u00A0\u1680\u2000-\u200F\u2028-\u202F\u205F\u3000\uFEFF]+'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();

        final RegExp timeRegex = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$', caseSensitive: false);
        final match = timeRegex.firstMatch(cleaned);

        if (match != null) {
          try {
            int hour = int.parse(match.group(1)!);
            int minute = int.parse(match.group(2) ?? '0');
            String? ampm = match.group(3)?.toUpperCase();

            if (ampm == 'PM' && hour < 12) {
              hour += 12;
            } else if (ampm == 'AM' && hour == 12) {
              hour = 0;
            }

            return DateTime(2000, 1, 1, hour, minute);
          } catch (e) {
            throw FormatException('Could not parse time components from: $timeString');
          }
        }

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

      try {
        DateTime start = parseTime(parts[0].trim());
        DateTime end = parseTime(parts[1].trim());

        // Extract time slot settings
        final timeSlotRaw = data['time slot'];
        final timeSlot = timeSlotRaw != null && timeSlotRaw is Map
            ? timeSlotRaw.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};

        slotPerHour = int.tryParse(timeSlot['hour']?.toString() ?? '1') ?? 1;
        personPerSlot = int.tryParse(timeSlot['person']?.toString() ?? '1') ?? 1;

        generateTimeSlots(startTime: start, endTime: end);

        setState(() {
          _selectedDate = _getFirstAvailableDay();
          isDataReady = true;
        });

      } catch (e) {
        print('Error parsing working hours: $e');

        // Fallback to default hours
        generateTimeSlots(
          startTime: DateTime(2000, 1, 1, 9, 0),
          endTime: DateTime(2000, 1, 1, 17, 0),
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
    timeSlotRanges.clear(); // Clear the ranges list

    // Each slot is 1 hour, slotPerHour determines total capacity for that hour
    Duration slotDuration = const Duration(hours: 1);

    DateTime currentSlotStart = startTime;

    while (currentSlotStart.isBefore(endTime)) {
      DateTime currentSlotEnd = currentSlotStart.add(slotDuration);

      // Don't create a slot if the end time exceeds the working hours
      if (currentSlotEnd.isAfter(endTime)) {
        break;
      }

      // Format the start and end times
      final formattedStart = DateFormat.jm().format(currentSlotStart);
      final formattedEnd = DateFormat.jm().format(currentSlotEnd);

      // Store the start time as the key (for backward compatibility)
      generatedTimeSlots.add(formattedStart);

      // Total capacity = slotPerHour * personPerSlot
      // Example: If studio has 2 makeup artists (slotPerHour=2) and each can handle 1 person (personPerSlot=1)
      // Then total capacity = 2 people per hour
      final totalCapacity = slotPerHour * personPerSlot;
      slotAvailability[formattedStart] = totalCapacity;

      // Store the time range
      timeSlotRanges.add({
        'start': formattedStart,
        'end': formattedEnd,
      });

      currentSlotStart = currentSlotEnd;
    }

    // Load initial availability for selected date
    if (generatedTimeSlots.isNotEmpty) {
      loadSlotAvailability(_selectedDate);
    }
  }

  bool isWorkingDay(DateTime day) {
    final dayName = DateFormat('EEEE').format(day);
    return workingDays.contains(dayName);
  }

  DateTime _getFirstAvailableDay() {
    DateTime startDate = DateTime.now();

    for (int i = 3; i < 60; i++) { // Start from day 3 (at least 3 days from now)
      final date = startDate.add(Duration(days: i));
      if (isWorkingDay(date)) return date;
    }
    return startDate.add(const Duration(days: 3));
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _takePhoto();
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDA9BF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Camera'),
                    ],
                  ),
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _pickFromGallery();
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFDA9BF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.photo_library,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Gallery'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  @override
  Widget _buildCategoryAndPriceSection() {
    if (!_isCategoriesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.pink.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category, color: Colors.pink.shade600, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Category & Price',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Text(
            'Select Category:',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableCategories.keys.map((category) {
              final isSelected = category == _selectedCategory;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = category;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.pinkAccent : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.pinkAccent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.pinkAccent,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.pink.shade300),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.attach_money, color: Colors.green.shade600, size: 18),
                    const SizedBox(width: 4),
                    const Text(
                      'Price:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Text(
                  _selectedCategory.isNotEmpty
                      ? availableCategories[_selectedCategory] ?? 'N/A'
                      : 'Select a category',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

  Widget _buildImageSearchLoading() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDA9BF5)),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Booking appointment...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 600 + (index * 200)),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      color: Color(0xFFDA9BF5).withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSlotChips() {
    if (generatedTimeSlots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isLoadingSlots) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Updating slots...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start, // Changed from center to start
        children: List.generate(generatedTimeSlots.length, (index) {
          final time = generatedTimeSlots[index];
          final timeRange = timeSlotRanges[index];
          final isSelected = time == _selectedTime;
          final available = slotAvailability[time] ?? (slotPerHour * personPerSlot);
          final totalSlots = slotPerHour * personPerSlot;
          final isUnavailable = available <= 0;

          // Create the display text with range
          String displayText = '${timeRange['start']} - ${timeRange['end']}';

          return GestureDetector(
            onTap: !isUnavailable ? () {
              setState(() {
                _selectedTime = time;
              });
            } : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 160, // Fixed width for all slots
              height: 45, // Fixed height for all slots
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUnavailable
                    ? Colors.grey.shade200
                    : isSelected
                    ? Colors.orange.shade400
                    : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnavailable
                      ? Colors.grey.shade400
                      : isSelected
                      ? Colors.orange.shade600
                      : Colors.orange.shade400,
                  width: isSelected ? 2 : 1.5,
                ),
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: Colors.orange.shade300,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
                    : [
                  BoxShadow(
                    color: Colors.orange.shade200.withOpacity(0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // if (isUnavailable) ...[
                  //   Icon(
                  //     Icons.lock,
                  //     size: 14,
                  //     color: Colors.grey.shade600,
                  //   ),
                  //   const SizedBox(width: 6),
                  // ],
                  // if (isSelected && !isUnavailable) ...[
                  //   // const Icon(
                  //   //   Icons.check_circle,
                  //   //   size: 14,
                  //   //   color: Colors.white,
                  //   // ),
                  //   // const SizedBox(width: 6),
                  // ],
                  Flexible(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        color: isUnavailable
                            ? Colors.grey.shade600
                            : isSelected
                            ? Colors.white
                            : Colors.orange.shade800,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Optional: Show availability count
                  if (!isUnavailable && available < totalSlots) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.3)
                            : Colors.orange.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$available',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // calendar with interaction tracking
  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8), // Add margin for breathing room
      padding: const EdgeInsets.all(12), // Internal padding
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: TableCalendar(
        firstDay: DateTime.now().add(const Duration(days: 3)),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _selectedDate,
        selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
        onDaySelected: (selectedDay, focusedDay) async {
          if (isWorkingDay(selectedDay)) {
            if (!isSameDay(_selectedDate, selectedDay)) {
              setState(() {
                _selectedDate = selectedDay;
                _selectedTime = '';
              });
              await loadSlotAvailability(selectedDay, showLoading: false);
            }
          }
        },
        calendarFormat: CalendarFormat.month,

        // Enhanced header style
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          leftChevronIcon: const Icon(
            Icons.chevron_left,
            color: Colors.pinkAccent,
          ),
          rightChevronIcon: const Icon(
            Icons.chevron_right,
            color: Colors.pinkAccent,
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
        ),

        // Enhanced calendar style
        calendarStyle: CalendarStyle(
          // Today's date style
          todayDecoration: BoxDecoration(
            color: Colors.pink.shade100,
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),

          // Selected date style
          selectedDecoration: const BoxDecoration(
            color: Colors.pinkAccent,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),

          // Disabled date style
          disabledTextStyle: TextStyle(
            color: Colors.grey.shade400,
          ),

          // Weekend style
          weekendTextStyle: const TextStyle(
            color: Colors.black87,
          ),

          // Default text style
          defaultTextStyle: const TextStyle(
            color: Colors.black87,
          ),

          // Cell padding
          cellPadding: const EdgeInsets.all(6),
          cellMargin: const EdgeInsets.all(4),
        ),

        // FIX: Properly configured day of week style
        daysOfWeekStyle: DaysOfWeekStyle(
          // Format the day names (Mon, Tue, Wed, etc.)
          weekdayStyle: const TextStyle(
            fontSize: 13, // Slightly smaller font
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          weekendStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          // Adjust height to prevent cutoff
          dowTextFormatter: (date, locale) {
            // Return abbreviated day names (3 letters)
            return DateFormat.E(locale).format(date).substring(0, 3);
          },
        ),

        // Make sure days are enabled based on working days
        enabledDayPredicate: isWorkingDay,

        // Add some space around the calendar
        rowHeight: 48, // Height of each date row
        daysOfWeekHeight: 32, // Height of the weekday header (Mon-Sun)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/image_4.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.userId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text("User data not found"));
              }

              return RefreshIndicator(
                key: _refreshIndicatorKey,
                onRefresh: _onRefresh,
                color: Colors.pinkAccent,
                child: Stack(
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
                        physics: const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh
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
                                Column(
                                  children: [
                                    const Text('Book Appointment',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    if (_isRefreshing)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                const SizedBox(width: 48),
                              ],
                            ),
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
                            const Text('Category & Price', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildCategoryAndPriceSection(),

                            const SizedBox(height: 16),
                            const Text('Preferred Makeup:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildMakeupPhotoWidget(
                              selectedImage: _selectedImage,
                              onAdd: _showImageSourceDialog,
                              onEdit: _showImageSourceDialog,
                              onDelete: () {
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
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.pinkAccent,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isRefreshing ? null : () {
                                  if (_selectedTime.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a time slot.')),
                                    );
                                    return;
                                  }
                                  if (_selectedCategory.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please select a category.')),
                                    );
                                    return;
                                  }
                                  _showBookingConfirmationDialog();
                                },
                                child: _isRefreshing
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : const Text('Book Appointment'),
                              ),
                            ),

                            // Pull to refresh hint
                            const SizedBox(height: 16),
                            const Center(
                              child: Text(
                                'Pull down to refresh',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (_isBookingInProgress) _buildImageSearchLoading(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  Future<void> _showBookingConfirmationDialog() async {
    final selectedDateFormatted = DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate);
    final timeRange = _getSelectedTimeRange();

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
                Text('Time: $timeRange'),
                Text('Category: $_selectedCategory'),
                Text('Price: ${availableCategories[_selectedCategory] ?? 'N/A'}'),
                if (_remarksController.text.trim().isNotEmpty)
                  Text('Remarks: ${_remarksController.text.trim()}'),
                const SizedBox(height: 16),

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
                crossAxisAlignment: CrossAxisAlignment.center, // 👈 ensures horizontal centering
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 120),
                  const SizedBox(height: 20),
                  const Text(
                    'Appointment Booked Successfully!',
                    textAlign: TextAlign.center, // 👈 centers text content
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const UserNavigation(initialIndex: 0)),
                                (route) => false,
                          );
                        },
                        child: const Text('Back to Home'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const UserNavigation(initialIndex: 2)),
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
          )

        ],
      ),
    );
  }
}