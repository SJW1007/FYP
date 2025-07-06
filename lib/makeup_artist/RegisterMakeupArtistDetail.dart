import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../all user/Login.dart';

class RegisterMakeupArtistDetailPage extends StatefulWidget {
  final String userId;

  const RegisterMakeupArtistDetailPage({
    super.key,
    required this.userId,
  });

  @override
  State<RegisterMakeupArtistDetailPage> createState() => _RegisterMakeupArtistDetailPageState();
}

class _RegisterMakeupArtistDetailPageState extends State<RegisterMakeupArtistDetailPage> {
  final _studioNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _priceController = TextEditingController();
  final _aboutController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  bool _isLoading = false;
  String? _errorMessage;

  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 19, minute: 0);

  // Working day slot variables
  String _fromDay = 'Monday';
  String _toDay = 'Friday';

  // Category dropdown variable
  String _selectedCategory = 'Wedding';

  // Time slot for customer variables
  String _workingSlotHour = '1 Hour';  // Fixed: Initialize with full string
  String _workingSlotPerson = '1 Person';  // Fixed: Initialize with full string

  // Portfolio images
  List<File?> _portfolioImages = List.filled(6, null);

  final List<String> _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  // Category options - displayed with proper capitalization
  final List<String> _categoryOptions = [
    'Wedding',
    'Cosplay',
    'Korean Style'
  ];

  // Hour slot options for customer time slot
  final List<String> _hourSlots = [
    '1 Hour',
    '2 Hours',
    '3 Hours',
    '4 Hours',
  ];

  // Person slot options for customer time slot
  final List<String> _personSlots = [
    '1 Person',
    '2 Persons',
    '3 Persons',
    '4 Persons',
    '5 Persons',
  ];

  Future<void> _pickImage(int index) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _portfolioImages[index] = File(pickedFile.path);
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hourOfPeriod;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _selectTime(bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime : _endTime,
    );

    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  bool _isValidMalaysianPhone(String phone) {
    // Remove all non-digits
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Check if it's between 10-11 digits
    return digitsOnly.length >= 10 && digitsOnly.length <= 11;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isValidPriceRange(String price) {
    // Remove all spaces and convert to uppercase for consistency
    String cleanPrice = price.replaceAll(' ', '').toUpperCase();

    // Check if it starts with RM
    if (!cleanPrice.startsWith('RM')) {
      return false;
    }

    // Remove RM prefix
    String priceWithoutRM = cleanPrice.substring(2);

    // Check if it contains a dash (for range)
    if (priceWithoutRM.contains('-')) {
      List<String> parts = priceWithoutRM.split('-');
      if (parts.length != 2) return false;

      // Check if both parts are valid numbers
      double? minPrice = double.tryParse(parts[0]);
      double? maxPrice = double.tryParse(parts[1]);

      if (minPrice == null || maxPrice == null) return false;
      if (minPrice >= maxPrice) return false; // Min should be less than max

      return true;
    } else {
      // Single price value
      double? singlePrice = double.tryParse(priceWithoutRM);
      return singlePrice != null && singlePrice > 0;
    }
  }

  bool _hasAtLeastOnePortfolioImage() {
    return _portfolioImages.any((image) => image != null);
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 50,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Registration Complete!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Message
              const Text(
                'Your makeup artist registration request has been submitted successfully.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF666666),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              const Text(
                'Please wait for BlushUp admin to review and decide whether to approve or reject your request.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // OK Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB266FF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _registerUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final studioName = _studioNameController.text.trim();
    final phoneNumber = _phoneNumberController.text.trim();
    final email = _emailController.text.trim();
    final address = _addressController.text.trim();
    final price = _priceController.text.trim();
    final about = _aboutController.text.trim();

    // Comprehensive validation
    if (studioName.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter studio/makeup artist name';
        _isLoading = false;
      });
      return;
    }

    if (phoneNumber.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter phone number';
        _isLoading = false;
      });
      return;
    }

    if (!_isValidMalaysianPhone(phoneNumber)) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number (10-11 digits)';
        _isLoading = false;
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email address';
        _isLoading = false;
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
        _isLoading = false;
      });
      return;
    }

    if (address.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter address';
        _isLoading = false;
      });
      return;
    }

    if (price.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter price';
        _isLoading = false;
      });
      return;
    }

    // Validate price format (string with RM prefix and optional range)
    if (!_isValidPriceRange(price)) {
      setState(() {
        _errorMessage = 'Please enter a valid price format (e.g., RM400 or RM400-600)';
        _isLoading = false;
      });
      return;
    }

    if (about.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter about description';
        _isLoading = false;
      });
      return;
    }

    // Validate time slot selections
    if (_workingSlotHour.isEmpty) {
      setState(() {
        _errorMessage = 'Please select working slot hour';
        _isLoading = false;
      });
      return;
    }

    if (_workingSlotPerson.isEmpty) {
      setState(() {
        _errorMessage = 'Please select working slot person';
        _isLoading = false;
      });
      return;
    }

    // Validate portfolio images
    if (!_hasAtLeastOnePortfolioImage()) {
      setState(() {
        _errorMessage = 'Please upload at least one portfolio image';
        _isLoading = false;
      });
      return;
    }

    try {
      // Get current user ID
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      // Create user reference
      final userRef = _firestore.collection('users').doc(currentUser.uid);

      // Upload portfolio images to Firebase Storage
      List<String> portfolioUrls = [];

      for (int i = 0; i < _portfolioImages.length; i++) {
        final image = _portfolioImages[i];
        if (image != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('Images')
              .child(currentUser.uid)
              .child('portfolio')
              .child('image_$i.jpg');

          await storageRef.putFile(image);
          final downloadUrl = await storageRef.getDownloadURL();
          portfolioUrls.add(downloadUrl);
        }
      }

      // Extract numeric values from dropdown selections
      int hourValue = int.parse(_workingSlotHour.split(' ')[0]);
      int personValue = int.parse(_workingSlotPerson.split(' ')[0]);

      // Save data to Firestore - price is now stored as string
      await _firestore.collection('makeup_artists').add({
        'category': _selectedCategory,
        'portfolio': portfolioUrls,
        'price': price, // Store as string to support ranges like "RM400-600"
        'time slot': {
          'hour': hourValue,
          'person': personValue,
        },
        'user_id': userRef,
        'working day': {
          'From': _fromDay,
          'To': _toDay,
        },
        'working hour': '${_formatTimeOfDay(_startTime)} - ${_formatTimeOfDay(_endTime)}',
        'studio_name': studioName,
        'phone_number': phoneNumber,
        'email': email,
        'address': address,
        'status': 'Pending',
        'about': about,
        'created_at': FieldValue.serverTimestamp(),
      });

      setState(() {
        _isLoading = false;
      });

      // Show success dialog
      _showSuccessDialog();

    } catch (e) {
      setState(() {
        _errorMessage = 'Registration failed. Please try again.';
        _isLoading = false;
      });
    }
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
          SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Column(
                      children: [
                        Text('Register As\nMakeup Artists',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('Create an Account',
                            style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Studio/Makeup Artist Name
                  _buildTextField('Studio/Makeup Artist Name', _studioNameController, Icons.store),
                  const SizedBox(height: 15),
                  _buildTextField('Phone Number', _phoneNumberController, Icons.phone),
                  const SizedBox(height: 15),
                  _buildTextField('Email', _emailController, Icons.email),
                  const SizedBox(height: 15),

                  // Working Time Slot
                  const Text('Working Time Slot',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start Time', style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildTimePickerField(
                              time: _startTime,
                              onTap: () => _selectTime(true),
                              icon: Icons.access_time,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('End Time', style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildTimePickerField(
                              time: _endTime,
                              onTap: () => _selectTime(false),
                              icon: Icons.access_time,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // Working Day Slot
                  const Text('Working Day Slot',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('From', style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildDropdown(
                              value: _fromDay,
                              items: _days,
                              onChanged: (value) => setState(() => _fromDay = value!),
                              icon: Icons.calendar_today,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('To', style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildDropdown(
                              value: _toDay,
                              items: _days,
                              onChanged: (value) => setState(() => _toDay = value!),
                              icon: Icons.calendar_today,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // Time Slot for Customer
                  const Text('Time Slot for Customer',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Hour", style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildDropdown(
                              value: _workingSlotHour,
                              items: _hourSlots,
                              onChanged: (value) => setState(() => _workingSlotHour = value!),
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Person", style: TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            _buildDropdown(
                              value: _workingSlotPerson,
                              items: _personSlots,
                              onChanged: (value) => setState(() => _workingSlotPerson = value!),
                              icon: Icons.people,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),
                  _buildTextField('Address', _addressController, Icons.location_on),
                  const SizedBox(height: 15),

                  // Category Dropdown Section
                  const Text('Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: _selectedCategory,
                    items: _categoryOptions,
                    onChanged: (value) => setState(() => _selectedCategory = value!),
                    icon: Icons.category,
                  ),

                  const SizedBox(height: 15),
                  _buildTextField('Price Range', _priceController, Icons.attach_money),
                  const SizedBox(height: 15),

                  // About field with icon beside the label
                  Row(
                    children: [
                      const Icon(Icons.description, color: Color(0xFFFB81EE)),
                      const SizedBox(width: 8),
                      const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aboutController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Write your description here....',
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFB81EE)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFB81EE)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Portfolio Photos Section
                  const Text('Portfolio:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  const Text('(At least one photo required)',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),

                  // Grid layout for portfolio photos (2x3 grid)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: 6,
                    itemBuilder: (context, index) {
                      return _buildPhotoUpload(index);
                    },
                  ),

                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red.shade600, fontSize: 14,),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                      onPressed: _registerUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC367CA),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Register',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerField({
    required TimeOfDay time,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFB81EE)),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFB81EE)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _formatTimeOfDay(time),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFFFB81EE),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUpload(int index) {
    return GestureDetector(
      onTap: () => _pickImage(index),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFB81EE), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _portfolioImages[index] != null
            ? Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                _portfolioImages[index]!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _portfolioImages[index] = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        )
            : const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              color: Color(0xFFFB81EE),
              size: 40,
            ),
            SizedBox(height: 4),
            Text(
              'Add Photo',
              style: TextStyle(
                color: Color(0xFFFB81EE),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: label == 'Phone Number' ? TextInputType.number :
          label == 'Email' ? TextInputType.emailAddress : TextInputType.text,
          inputFormatters: label == 'Phone Number' ? [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ] : null,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFFFB81EE)),
            hintText: _getHintText(label),
            hintStyle: const TextStyle(color: Colors.grey),
            helperText: _getHelperText(label),
            helperStyle: const TextStyle(color: Colors.grey, fontSize: 12),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFFB81EE)),
              borderRadius: BorderRadius.circular(30),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFFB81EE)),
              borderRadius: BorderRadius.circular(30),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  String _getHintText(String label) {
    switch (label) {
      case 'Price Range':
        return 'Enter price (e.g., RM400 or RM400-600)';
      case 'Studio/Makeup Artist Name':
        return 'Enter Your Studio Name Here';
      default:
        return 'Enter Your $label Here';
    }
  }

  String? _getHelperText(String label) {
    switch (label) {
      case 'Phone Number':
        return 'Enter 10-11 digits (e.g., 0123456789)';
      case 'Price Range':
        return 'Single price: RM400 or Price range: RM400-600';
      default:
        return null;
    }
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFB81EE)),
        borderRadius: BorderRadius.circular(30),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFFFB81EE)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        items: items.map((String item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item),
          );
        }).toList(),
        onChanged: onChanged,
        style: const TextStyle(color: Colors.black),
        dropdownColor: Colors.white,
      ),
    );
  }
}