import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:email_validator/email_validator.dart';

enum UserType { user, makeupArtist }

class EditProfilePage extends StatefulWidget {
  final String name;
  final String phone;
  final String profilePicture;
  final UserType userType;

// Additional fields for makeup artist
  final String? artistPhone;  //nullable
  final String? artistEmail;
  final String? studioName;
  final String? address;
  final String? about;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final String? workingDayFrom;
  final String? workingDayTo;
  final String? workingSlotHour;
  final String? workingSlotPerson;
  final String? category;
  final String? price;
  final List<String>? portfolioImages;

  const EditProfilePage({
    Key? key,
    required this.name,
    this.studioName,
    required this.phone,
    this.artistPhone,
    required this.profilePicture,
    required this.userType,
    this.artistEmail,
    this.address,
    this.about,
    this.startTime,
    this.endTime,
    this.workingDayFrom,
    this.workingDayTo,
    this.workingSlotHour,
    this.workingSlotPerson,
    this.category,
    this.price,
    this.portfolioImages,
  }) : super(key: key);

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  bool _isLoading = false;
  String? _errorMessage;

  // Basic fields
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Makeup artist specific fields
  final TextEditingController _studioNameController = TextEditingController();
  final TextEditingController _artistPhoneController = TextEditingController();
  final TextEditingController _artistEmailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  File? _newProfileImage;
  final picker = ImagePicker();

  // Dropdown values
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String? _workingDayFrom;
  String? _workingDayTo;
  String? _workingSlotHour;
  String? _workingSlotPerson;
  String? _category;

  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final List<String> _categories = ['Wedding', 'Cosplay', 'Korean Style'];
  final List<String> _hourSlots = ['1 Hour', '2 Hours', '3 Hours', '4 Hours'];
  final List<String> _personSlots = ['1 Person', '2 Persons', '3 Persons', '4 Persons', '5 Persons'];
  static const int MAX_PORTFOLIO_IMAGES = 6;

  // Portfolio management variables
  List<String> _existingPortfolioUrls = []; // Track original URLs
  List<String> _deletedPortfolioUrls = []; // Track deleted images
  List<File> _newPortfolioImages = []; // New images to upload
  Map<int, File> _replacedImages = {}; // Track replaced images by index

  @override
  void initState() {
    super.initState();
    _initializeFields();

    // Initialize portfolio URLs
    if (widget.portfolioImages != null) {
      _existingPortfolioUrls = List<String>.from(widget.portfolioImages!);
    }
  }

  void _initializeFields() {
    _nameController.text = widget.name;
    _phoneController.text = widget.phone;

    if (widget.userType == UserType.makeupArtist) {
      _studioNameController.text = widget.studioName ?? '';
      // Make sure artistPhone is initialized properly
      _artistPhoneController.text = widget.artistPhone ?? '';
      _artistEmailController.text = widget.artistEmail ?? '';
      _addressController.text = widget.address ?? '';
      _aboutController.text = widget.about ?? '';
      _priceController.text = widget.price ?? '';
      _startTime = widget.startTime;
      _endTime = widget.endTime;
      _workingDayFrom = widget.workingDayFrom;
      _workingDayTo = widget.workingDayTo;
      _workingSlotHour = widget.workingSlotHour;
      _workingSlotPerson = widget.workingSlotPerson;
      _category = widget.category;
    }
  }

  // Email validation
  bool _isValidEmailWithPackage(String email) {
    return EmailValidator.validate(email);
  }

// Price validation
  bool _isValidPriceRange(String price) {
    // Remove all spaces and convert to uppercase for consistency
    String cleanPrice = price.replaceAll(' ', '').toUpperCase();

    // Check if it starts with RM
    if (!cleanPrice.startsWith('RM')) return false;

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

  bool _validateFields() {
    // Reset error message
    setState(() {
      _errorMessage = null;
    });

    // Common validation for both user types
    if (_nameController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Name is required';
      });
      return false;
    }

    if (widget.userType == UserType.user) {
      // For regular users - validate personal phone number
      if (_phoneController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Phone number is required';
        });
        return false;
      }

      if (!_isValidMalaysianPhone(_phoneController.text)) {
        setState(() {
          _errorMessage = 'Please enter a valid phone number (10-11 digits)';
        });
        return false;
      }
    } else if (widget.userType == UserType.makeupArtist) {
      // For makeup artists - validate all required fields
      if (_studioNameController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Studio name is required';
        });
        return false;
      }

      // Validate artist's business phone number
      if (_artistPhoneController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Business phone number is required';
        });
        return false;
      }

      if (!_isValidMalaysianPhone(_artistPhoneController.text)) {
        setState(() {
          _errorMessage = 'Please enter a valid business phone number (10-11 digits)';
        });
        return false;
      }

      if (_addressController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Address is required';
        });
        return false;
      }

      if (_aboutController.text.isEmpty) {
        setState(() {
          _errorMessage = 'About information is required';
        });
        return false;
      }

      if (_startTime == null || _endTime == null) {
        setState(() {
          _errorMessage = 'Working hours are required';
        });
        return false;
      }

      if (_workingDayFrom == null || _workingDayTo == null) {
        setState(() {
          _errorMessage = 'Working days are required';
        });
        return false;
      }

      if (_workingSlotHour == null || _workingSlotPerson == null) {
        setState(() {
          _errorMessage = 'Working slots are required';
        });
        return false;
      }

      if (_category == null) {
        setState(() {
          _errorMessage = 'Category is required';
        });
        return false;
      }

      if (_artistEmailController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Email is required';
        });
        return false;
      } else if (!_isValidEmailWithPackage(_artistEmailController.text)) {
        setState(() {
          _errorMessage = 'Please enter a valid email address';
        });
        return false;
      }

      if (_priceController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Price is required';
        });
        return false;
      } else if (!_isValidPriceRange(_priceController.text)) {
        setState(() {
          _errorMessage = 'Please enter a valid price format (e.g., RM400 or RM400-600)';
        });
        return false;
      }
    }

    return true;
  }

  bool _isValidMalaysianPhone(String phone) {
    // Remove all non-digits
    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Check if it's between 10-11 digits
    return digitsOnly.length >= 10 && digitsOnly.length <= 11;
  }

// Helper method to get error text
  String? _getPhoneErrorText(String phone) {
    if (phone.isEmpty) return null;

    String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 10) {
      return "Phone number must be at least 10 digits";
    } else if (digitsOnly.length > 11) {
      return "Phone number cannot exceed 11 digits";
    }

    return null; // Valid phone number
  }

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _newProfileImage = File(pickedFile.path);
      });
    }
  }

  // portfolio picking method
  Future<void> _pickPortfolioImage({int? replaceIndex}) async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        if (replaceIndex != null) {
          // Replace existing image
          _replacedImages[replaceIndex] = File(pickedFile.path);
        } else {
          // Add new image (only if under limit)
          int currentCount = _getTotalPortfolioCount();
          if (currentCount < MAX_PORTFOLIO_IMAGES) {
            _newPortfolioImages.add(File(pickedFile.path));
          }
        }
      });
    }
  }

  // Helper method to get total portfolio count
  int _getTotalPortfolioCount() {
    int existingCount = _existingPortfolioUrls.length - _deletedPortfolioUrls.length;
    int newCount = _newPortfolioImages.length;
    return existingCount + newCount;
  }

  // Method to delete portfolio image
  void _deletePortfolioImage(int index, {bool isExisting = false}) {
    setState(() {
      if (isExisting) {
        // Mark existing image for deletion
        String urlToDelete = _existingPortfolioUrls[index];
        if (!_deletedPortfolioUrls.contains(urlToDelete)) {
          _deletedPortfolioUrls.add(urlToDelete);
        }
        // Remove from replaced images if it was replaced
        _replacedImages.remove(index);
      } else {
        // Remove new image
        int newImageIndex = index - _existingPortfolioUrls.length;
        if (newImageIndex >= 0 && newImageIndex < _newPortfolioImages.length) {
          _newPortfolioImages.removeAt(newImageIndex);
        }
      }
    });
  }

  Future<void> _selectTime(bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _startTime ?? TimeOfDay.now() : _endTime ?? TimeOfDay.now(),
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

  Future<void> _saveChanges() async {
    if (!_validateFields()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        String imageUrl = widget.profilePicture;

        // Upload profile image
        if (_newProfileImage != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('Images')
              .child(user.uid)
              .child('profile_pictures.jpg');

          await storageRef.putFile(_newProfileImage!);
          imageUrl = await storageRef.getDownloadURL();
        }

        // Handle portfolio images for makeup artist
        List<String> finalPortfolioUrls = [];

        if (widget.userType == UserType.makeupArtist) {
          // Portfolio image handling code (same as before)
          for (int i = 0; i < _existingPortfolioUrls.length; i++) {
            String existingUrl = _existingPortfolioUrls[i];

            if (!_deletedPortfolioUrls.contains(existingUrl)) {
              if (_replacedImages.containsKey(i)) {
                final portfolioRef = FirebaseStorage.instance
                    .ref()
                    .child('Images')
                    .child(user.uid)
                    .child('portfolio_replaced_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

                await portfolioRef.putFile(_replacedImages[i]!);
                final newUrl = await portfolioRef.getDownloadURL();
                finalPortfolioUrls.add(newUrl);

                try {
                  await FirebaseStorage.instance.refFromURL(existingUrl).delete();
                } catch (e) {
                  print('Error deleting old image: $e');
                }
              } else {
                finalPortfolioUrls.add(existingUrl);
              }
            } else {
              try {
                await FirebaseStorage.instance.refFromURL(existingUrl).delete();
              } catch (e) {
                print('Error deleting image: $e');
              }
            }
          }

          for (int i = 0; i < _newPortfolioImages.length; i++) {
            final portfolioRef = FirebaseStorage.instance
                .ref()
                .child('Images')
                .child(user.uid)
                .child('portfolio_new_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');

            await portfolioRef.putFile(_newPortfolioImages[i]);
            final url = await portfolioRef.getDownloadURL();
            finalPortfolioUrls.add(url);
          }
        }

        // Update users collection with the correct phone number
        final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        String userPhoneNumber;
        String userName;

        if (widget.userType == UserType.makeupArtist) {
          userPhoneNumber = _phoneController.text;
          userName = _studioNameController.text;
        } else {
          userPhoneNumber = _phoneController.text;
          userName = _nameController.text;
        }

        Map<String, dynamic> basicUserData = {
          'name': userName,
          'phone number': userPhoneNumber,
          'profile pictures': imageUrl,
        };

        await userRef.update(basicUserData);

        // Update makeup_artists collection (only for makeup artists)
        if (widget.userType == UserType.makeupArtist) {
          final makeupArtistQuery = await FirebaseFirestore.instance
              .collection('makeup_artists')
              .where('user_id', isEqualTo: FirebaseFirestore.instance.collection('users').doc(user.uid))
              .get();

          if (makeupArtistQuery.docs.isNotEmpty) {
            final makeupArtistDoc = makeupArtistQuery.docs.first;

            String workingHour = '';
            if (_startTime != null && _endTime != null) {
              workingHour = '${_startTime!.format(context)} - ${_endTime!.format(context)}';
            }

            Map<String, String> workingDay = {
              'From': _workingDayFrom ?? 'Monday',
              'To': _workingDayTo ?? 'Friday',
            };

            Map<String, int> timeSlot = {
              'hour': _getHourFromSlot(_workingSlotHour ?? '1 Hour'),
              'person': _getPersonFromSlot(_workingSlotPerson ?? '1 Person'),
            };

            Map<String, dynamic> makeupArtistData = {
              'studio_name': _studioNameController.text,
              'phone_number': _artistPhoneController.text,
              'email': _artistEmailController.text,
              'address': _addressController.text,
              'about': _aboutController.text,
              'category': _category ?? 'Wedding',
              'price': _priceController.text,
              'working hour': workingHour,
              'working day': workingDay,
              'time slot': timeSlot,
              'portfolio': finalPortfolioUrls,
            };

            await makeupArtistDoc.reference.update(makeupArtistData);
          }
        }

        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Helper methods to convert slot strings to integers
  int _getHourFromSlot(String hourSlot) {
    // Extract number from "1 Hour", "2 Hours", etc.
    final match = RegExp(r'(\d+)').firstMatch(hourSlot);
    return match != null ? int.parse(match.group(1)!) : 1;
  }

  int _getPersonFromSlot(String personSlot) {
    // Extract number from "1 Person", "2 Persons", etc.
    final match = RegExp(r'(\d+)').firstMatch(personSlot);
    return match != null ? int.parse(match.group(1)!) : 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (widget.userType == UserType.user)
            Image.asset(
              'assets/image_4.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            )
          else
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/purple_background.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, size: 24),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      const Text(
                        'Edit Profile',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Profile Image
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: _newProfileImage != null
                              ? FileImage(_newProfileImage!)
                              : NetworkImage(widget.profilePicture) as ImageProvider,
                        ),
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Basic fields for both user types
                        if (widget.userType == UserType.user) ...[
                          buildLabelField("Name:", _nameController),
                          buildPhoneField("Phone Number:", _phoneController),
                        ] else if (widget.userType == UserType.makeupArtist) ...[
                          buildLabelField("Name:", _studioNameController),
                          buildPhoneField("Phone:", _artistPhoneController),
                          buildLabelField("Email:", _artistEmailController),
                          buildLabelField("Address:", _addressController),
                          buildAboutField(),
                          buildWorkingHourSection(),
                          buildWorkingDaySection(),
                          buildWorkingSlotSection(),
                          buildCategoryAndPriceSection(),
                          buildPortfolioSection(),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
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
                // Save button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Text(
                        "Save",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
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

  Widget buildLabelField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF2D7F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildAboutField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("About:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _aboutController,
          maxLines: 4,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF2D7F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildWorkingHourSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Working Hour:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Start Time", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _selectTime(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2D7F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _startTime?.format(context) ?? "10:00 am",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("End Time", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _selectTime(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2D7F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _endTime?.format(context) ?? "7:00 pm",
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildWorkingDaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Working Day:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("From", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  buildDropdown(_workingDayFrom ?? "Monday", _days, (value) => setState(() => _workingDayFrom = value)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("To", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  buildDropdown(_workingDayTo ?? "Friday", _days, (value) => setState(() => _workingDayTo = value)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildWorkingSlotSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Working Slot:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Hour", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  buildDropdown(_workingSlotHour ?? "1 Hour", _hourSlots, (value) => setState(() => _workingSlotHour = value)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Person", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  buildDropdown(_workingSlotPerson ?? "1 Person", _personSlots, (value) => setState(() => _workingSlotPerson = value)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildCategoryAndPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Category and Price", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Category", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  buildDropdown(_category ?? "Wedding", _categories, (value) => setState(() => _category = value)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Price", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2D7F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "RMxxx",
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Enhanced portfolio section widget
  Widget buildPortfolioSection() {
    List<Widget> portfolioWidgets = [];

    // 1. Add existing images (not deleted)
    for (int i = 0; i < _existingPortfolioUrls.length; i++) {
      String imageUrl = _existingPortfolioUrls[i];

      if (!_deletedPortfolioUrls.contains(imageUrl)) {
        portfolioWidgets.add(
          _buildPortfolioImageWidget(
            imageProvider: _replacedImages.containsKey(i)
                ? FileImage(_replacedImages[i]!) as ImageProvider
                : NetworkImage(imageUrl),
            onDelete: () => _deletePortfolioImage(i, isExisting: true),
            onReplace: () => _pickPortfolioImage(replaceIndex: i),
            showReplaceOption: true,
          ),
        );
      }
    }

    // 2. Add new images
    for (int i = 0; i < _newPortfolioImages.length; i++) {
      portfolioWidgets.add(
        _buildPortfolioImageWidget(
          imageProvider: FileImage(_newPortfolioImages[i]),
          onDelete: () => _deletePortfolioImage(_existingPortfolioUrls.length + i, isExisting: false),
          showReplaceOption: false,
        ),
      );
    }

    // 3. Add plus button if under limit
    int currentCount = _getTotalPortfolioCount();
    if (currentCount < MAX_PORTFOLIO_IMAGES) {
      portfolioWidgets.add(_buildAddImageWidget());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("Portfolios:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              "$currentCount/$MAX_PORTFOLIO_IMAGES",
              style: TextStyle(
                fontSize: 12,
                color: currentCount >= MAX_PORTFOLIO_IMAGES ? Colors.red : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1,
          children: portfolioWidgets,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Helper widget for portfolio images
  Widget _buildPortfolioImageWidget({
    required ImageProvider imageProvider,
    required VoidCallback onDelete,
    VoidCallback? onReplace,
    bool showReplaceOption = false,
  }) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[300],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: imageProvider,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.error, color: Colors.red),
                );
              },
            ),
          ),
        ),
        // Action buttons
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              // Delete button
              GestureDetector(
                onTap: onDelete,
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
              // Replace button (only for existing images)
              if (showReplaceOption && onReplace != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onReplace,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }



  Widget buildDropdown(String value, List<String> items, Function(String?) onChanged) {
    // Ensure the value exists in the items list, otherwise use the first item
    String validValue = items.contains(value) ? value : items.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2D7F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validValue,
          isExpanded: true,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFE91E63)),
        ),
      ),
    );
  }
  Widget _buildAddImageWidget() {
    return GestureDetector(
      onTap: () => _pickPortfolioImage(),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
              size: 40,
            ),
            SizedBox(height: 4),
            Text(
              "Add Photo",
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
  Widget buildPhoneField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly, // Only allow digits
            LengthLimitingTextInputFormatter(11), // Limit to 11 characters
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF2D7F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            hintText: "0123456789",
            errorText: _getPhoneErrorText(controller.text),
          ),
          onChanged: (value) {
            setState(() {}); // Trigger rebuild to show/hide error
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

