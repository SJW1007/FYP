import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:blush_up/admin/email_config.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminMakeUpArtistDetails extends StatefulWidget {
  final String makeupArtistId;
  const AdminMakeUpArtistDetails({
    super.key,
    required this.makeupArtistId,
  });

  @override
  State<AdminMakeUpArtistDetails> createState() =>
      _AdminMakeUpArtistDetailsState();
}

class _AdminMakeUpArtistDetailsState
    extends State<AdminMakeUpArtistDetails> {
  Map<String, dynamic>? makeupArtistData;
  Map<String, dynamic>? userData;
  String? profilePictureUrl;
  bool isLoading = true;
  bool isProcessing = false;
  bool hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadMakeupArtistDetails();
    _initializeEmailPassword();
  }

  // Initialize email password on first run
  Future<void> _initializeEmailPassword() async {
    try {
      final hasPassword = await EmailConfig.hasStoredPassword();
      if (!hasPassword) {
        // Store your Gmail app password here
        await EmailConfig.setAdminPassword('uirm ddnd cakm dgbc');
        print('Email password stored securely');
      }
    } catch (e) {
      print('Error initializing email password: $e');
    }
  }

  Future<void> _loadMakeupArtistDetails() async {
    try {
      // Get makeup artist details using the provided ID
      final makeupArtistDoc = await FirebaseFirestore.instance
          .collection('makeup_artists')
          .doc(widget.makeupArtistId)
          .get();

      if (makeupArtistDoc.exists) {
        final makeupArtist = makeupArtistDoc.data()!;
        print('Makeup artist data: $makeupArtist');

        // Get user data from users collection using document ID
        Map<String, dynamic>? userInfo;
        String? profilePicture;
        if (makeupArtist['user_id'] != null) {
          try {
            String userId;
            // Handle DocumentReference or string user_id
            if (makeupArtist['user_id'] is DocumentReference) {
              userId = makeupArtist['user_id'].id;
            } else {
              userId = makeupArtist['user_id'].toString();
            }

            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
            if (userDoc.exists) {
              userInfo = userDoc.data()!;
              profilePicture = userInfo['profile pictures'];
            }
          } catch (e) {
            print('Error loading user data: $e');
          }
        }

        setState(() {
          makeupArtistData = makeupArtist;
          userData = userInfo;
          profilePictureUrl = profilePicture;
          isLoading = false;
        });
      } else {
        print('Makeup artist document does not exist');
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading makeup artist details: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  //_sendStatusEmail method
  Future<void> _sendStatusEmail(String recipientEmail, String artistName, String status) async {
    try {
      print('Calling Cloud Function to send email...');

      // Call the Cloud Function
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendMakeupArtistStatusEmail',
      );

      final result = await callable.call({
        'email': recipientEmail,
        'artistName': artistName,
        'status': status,
      });

      print('Cloud Function response: ${result.data}');

      if (result.data['success'] == true) {
        print('Email sent successfully via Cloud Function');
      } else {
        throw Exception('Cloud Function returned unsuccessful status');
      }
    } catch (e) {
      print('Error calling Cloud Function: $e');
      throw Exception('Failed to send email via Cloud Function: $e');
    }
  }

  String _getApproveEmailTemplate(String artistName) {
    return '''
  <!DOCTYPE html>
  <html>
  <head>
      <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #4CAF50; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
          .content { background-color: #f9f9f9; padding: 20px; border-radius: 0 0 8px 8px; }
          .status { font-weight: bold; color: #4CAF50; }
      </style>
  </head>
  <body>
      <div class="container">
          <div class="header">
              <h1>🎉 Congratulations! Application Approved</h1>
          </div>
          <div class="content">
              <p>Dear $artistName,</p>
              
              <p>We are thrilled to inform you that your makeup artist application has been <span class="status">APPROVED</span>!</p>
              
              <p><strong>Welcome to the BlushUp family!</strong> You can now start accepting bookings and showcase your talent to our clients.</p>
              
              <p><strong>What's next?</strong></p>
              <ul>
                  <li>✅ Log in to your account to access your artist dashboard</li>
                  <li>🎨 Update your portfolio with your best work</li>
                  <li>💰 Set your availability and pricing</li>
                  <li>📱 Start receiving booking requests from clients</li>
              </ul>
              
              <p>We're excited to see the amazing transformations you'll create!</p>
              
              <p>If you have any questions, our support team is here to help:</p>
              <p>📧 Email: seejiawei39@gmail.com</p>
              <p>📞 Phone: 018-3584968</p>
              
              <p>Best regards,<br>
              The BlushUp Team</p>
          </div>
      </div>
  </body>
  </html>
  ''';
  }

  String _getRejectEmailTemplate(String artistName) {
    return '''
  <!DOCTYPE html>
  <html>
  <head>
      <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #F44336; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
          .content { background-color: #f9f9f9; padding: 20px; border-radius: 0 0 8px 8px; }
          .status { font-weight: bold; color: #F44336; }
      </style>
  </head>
  <body>
      <div class="container">
          <div class="header">
              <h1>Application Status Update</h1>
          </div>
          <div class="content">
              <p>Dear $artistName,</p>
              
              <p>Thank you for your interest in joining BlushUp as a makeup artist.</p>
              
              <p>After careful review, we regret to inform you that your application has been <span class="status">REJECTED</span> at this time.</p>
              
              <p><strong>This is not the end of your journey with us!</strong> We encourage you to reapply in the future once you have enhanced the following areas:</p>
              
              <ul>
                  <li>📸 Portfolio quality and variety - showcase diverse makeup styles</li>
                  <li>💼 Professional experience and certifications</li>
                  <li>🗺️ Service area coverage and availability</li>
                  <li>📋 Complete profile information</li>
              </ul>
              
              <p>We believe in supporting aspiring makeup artists and would love to see you succeed. Please don't hesitate to reach out if you need guidance on improving your application.</p>
              
              <p>For support and guidance:</p>
              <p>📧 Email: seejiawei39@gmail.com</p>
              <p>📞 Phone: 018-3584968</p>
              
              <p>Thank you for your understanding.</p>
              
              <p>Best regards,<br>
              The BlushUp Team</p>
          </div>
      </div>
  </body>
  </html>
  ''';
  }

  String _getDisableEmailTemplate(String artistName) {
    return '''
  <!DOCTYPE html>
  <html>
  <head>
      <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background-color: #FF9800; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
          .content { background-color: #f9f9f9; padding: 20px; border-radius: 0 0 8px 8px; }
          .warning { color: #FF9800; font-weight: bold; }
      </style>
  </head>
  <body>
      <div class="container">
          <div class="header">
              <h1>⚠️ Account Temporarily Disabled</h1>
          </div>
          <div class="content">
              <p>Dear $artistName,</p>
              
              <p>We are writing to inform you that your BlushUp account has been <span class="warning">TEMPORARILY DISABLED</span>.</p>
              
              <p><strong>What this means:</strong></p>
              <ul>
                  <li>🚫 Your account access has been suspended</li>
                  <li>🔒 You cannot log in to the platform temporarily</li>
                  <li>👁️ Your profile is not visible to clients</li>
                  <li>📅 No new bookings can be made</li>
              </ul>
              
              <p><strong>Next Steps:</strong></p>
              <p>This action may be temporary. Please contact our support team immediately to discuss your account status and potential reactivation.</p>
              
              <p>Our team is here to help resolve any issues:</p>
              <p>📧 Email: seejiawei39@gmail.com</p>
              <p>📞 Phone: 018-3584968</p>
              
              <p>We value your partnership and hope to resolve this matter quickly.</p>
              
              <p>Best regards,<br>
              The BlushUp Team</p>
          </div>
      </div>
  </body>
  </html>
  ''';
  }

  Future<void> _updateMakeupArtistStatus(String status) async {
    setState(() {
      isProcessing = true;
    });

    try {
      // Update makeup artist status in Firestore
      await FirebaseFirestore.instance
          .collection('makeup_artists')
          .doc(widget.makeupArtistId)
          .update({'status': status});

      // Get artist email and name for email notification
      final artistEmail = makeupArtistData!['email'] ?? '';
      final artistName = makeupArtistData!['studio_name'] ?? 'Makeup Artist';

      // Send email via Cloud Function based on status
      if (artistEmail.isNotEmpty) {
        try {
          await _sendStatusEmail(artistEmail, artistName, status);
        } catch (emailError) {
          print('Failed to send email: $emailError');
          // Continue with the process even if email fails
        }
      }

      // Update local data to reflect the change in UI
      setState(() {
        makeupArtistData!['status'] = status;
        isProcessing = false;
      });

      // Show appropriate success message based on status
      String successMessage;
      Color backgroundColor;

      switch (status.toLowerCase()) {
        case 'approved':
        case 'accepted':
          successMessage =
          'Makeup artist approved successfully${artistEmail.isNotEmpty ? ' and email sent' : ''}';
          backgroundColor = Colors.green;
          break;
        case 'rejected':
          successMessage =
          'Makeup artist rejected successfully${artistEmail.isNotEmpty ? ' and email sent' : ''}';
          backgroundColor = Colors.red;
          break;
        case 'disabled':
          successMessage =
          'Account disabled successfully${artistEmail.isNotEmpty ? ' and email sent' : ''}';
          backgroundColor = Colors.orange;
          break;
        default:
          successMessage =
          'Status updated to $status successfully${artistEmail.isNotEmpty ? ' and email sent' : ''}';
          backgroundColor = const Color(0xFFB968C7);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: backgroundColor,
        ),
      );
    } catch (e) {
      print('Error updating status: $e');
      setState(() {
        isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<String> _getPortfolioImages() {
    if (makeupArtistData != null && makeupArtistData!['portfolio'] != null) {
      final portfolio = makeupArtistData!['portfolio'];
      if (portfolio is List) {
        // Convert to List<String> and take max 6 images
        return portfolio
            .where((item) =>
        item != null && item
            .toString()
            .isNotEmpty)
            .map((item) => item.toString())
            .take(6)
            .toList();
      }
    }
    return [];
  }

  String _getWorkingDays() {
    if (makeupArtistData != null && makeupArtistData!['working day'] != null) {
      final workingDay = makeupArtistData!['working day'];
      if (workingDay is Map<String, dynamic>) {
        final from = workingDay['From'] ?? 'N/A';
        final to = workingDay['To'] ?? 'N/A';
        return '$from - $to';
      }
    }
    return 'N/A';
  }

  String _getWorkingHours() {
    if (makeupArtistData != null && makeupArtistData!['working hour'] != null) {
      return makeupArtistData!['working hour'].toString();
    }
    return 'N/A';
  }

  String _getStatus() {
    if (makeupArtistData != null && makeupArtistData!['status'] != null) {
      return makeupArtistData!['status'].toString();
    }
    return 'N/A';
  }

  Color _getStatusColor() {
    final status = _getStatus().toLowerCase();
    switch (status) {
      case 'accepted':
      case 'approved':
        return Colors.green;
      case 'rejected':
      case 'disabled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showConfirmationDialog({
    required String action,
    required String studioName,
    required VoidCallback onConfirm,
  }) async {
    String title;
    String content;

    switch (action.toLowerCase()) {
      case 'accept':
      case 'approve':
        title = 'Confirm Approval';
        content =
        'Are you sure you want to approve "$studioName" as a makeup artist? This will allow them to start accepting bookings.';
        break;
      case 'reject':
        title = 'Confirm Rejection';
        content =
        'Are you sure you want to reject "$studioName"\'s application? This will disable their account and they won\'t be able to access the platform.';
        break;
      case 'disable':
        title = 'Confirm Account Disable';
        content =
        'Are you sure you want to disable "$studioName"\'s account? This will prevent them from accessing the platform and accepting new bookings.';
        break;
      default:
        title = 'Confirm Action';
        content =
        'Are you sure you want to perform this action on "$studioName"?';
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              child: Text(action.toUpperCase()),
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowActionButtons() {
    final status = _getStatus().toLowerCase();
    return status == 'pending' || status == 'approved' || status == 'accepted';
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
                            padding: const EdgeInsets.all(20),
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
    if (isLoading) {
      return Scaffold(
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (makeupArtistData == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
              "Makeup Artist Details", style: TextStyle(color: Colors.black)),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(
          child: Text('Makeup artist not found'),
        ),
      );
    }

    // Get portfolio images inline
    List<String> portfolioImages = _getPortfolioImages();

    // Get categories and prices inline
    List<String> categories = [];
    if (makeupArtistData != null && makeupArtistData!['category'] != null) {
      final categoryData = makeupArtistData!['category'];
      if (categoryData is List) {
        categories = categoryData.map((item) => item.toString()).toList();
      }
    }

    Map<String, String> prices = {};
    if (makeupArtistData != null && makeupArtistData!['price'] != null) {
      final priceData = makeupArtistData!['price'];
      if (priceData is Map<String, dynamic>) {
        prices = priceData.map((key, value) => MapEntry(key, value.toString()));
      }
    }

    // Create formatted category-price rows
    List<Widget> categoryPriceWidgets = [];
    for (int i = 0; i < categories.length; i++) {
      String category = categories[i];
      String price = prices[category] ?? 'Price not set';

      // Ensure price starts with RM
      if (price != 'Price not set' && !price.startsWith('RM')) {
        price = 'RM$price';
      }

      categoryPriceWidgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: i == categories.length - 1 ? 0 : 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  price,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
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
          ),
          Column(
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
                        'Artist Details',
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
                      // Makeup Artist Info Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
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
                                child: profilePictureUrl != null &&
                                    profilePictureUrl!.isNotEmpty
                                    ? Image.network(
                                  profilePictureUrl!,
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

                            // Makeup Artist Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    makeupArtistData!['studio_name'] ??
                                        'Unknown Artist',
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
                                        color: Colors.deepPurpleAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        ('0${makeupArtistData!['phone_number']
                                            .toString()}') ?? 'No phone',
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
                                        color: Colors.deepPurpleAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          makeupArtistData!['email'] ??
                                              'No email',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 12,
                                        color: _getStatusColor(),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getStatus(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _getStatusColor(),
                                          fontWeight: FontWeight.w500,
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

                      // Personal Information Section (inline)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E5F5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personal Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Name detail row inline
                            Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Name',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        userData?['name'] ?? 'N/A',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // Email detail row inline
                            Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Email',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        userData?['email'] ?? 'N/A',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // Phone Number detail row inline (last one, no spacing)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    'Phone Number',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    ('0${userData?['phone number']
                                        .toString()}') ?? 'N/A',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Makeup Artist Details Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E5F5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Studio Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Services & Pricing',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: categoryPriceWidgets.isEmpty
                                          ? const Text(
                                        'No services available',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      )
                                          : Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start,
                                        children: categoryPriceWidgets,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // Address detail row inline
                            Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Address',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        makeupArtistData!['address'] ??
                                            'Address not available',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // Working Days detail row inline
                            Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Working Days',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _getWorkingDays(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // Working Hours detail row inline
                            Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Text(
                                        'Working Hours',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _getWorkingHours(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                            // About detail row inline (last one, no spacing)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: Text(
                                    'About',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    makeupArtistData!['about'] ??
                                        'About not available',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Portfolio Section (inline)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Portfolio:',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                            portfolioImages.isEmpty
                                ? Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'No portfolio images available',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            )
                                : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: portfolioImages.length,
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                    onTap: () => _showImageDialog(
                                        context,
                                        portfolioImages[index]
                                    ),
                                    child: Container(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          portfolioImages[index],
                                      width: 160,
                                      height: 160,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error,
                                          stackTrace) {
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: const Center(
                                            child: Icon(
                                              Icons.image_not_supported,
                                              color: Colors.grey,
                                              size: 40,
                                            ),
                                          ),
                                        );
                                      },
                                      loadingBuilder: (context, child,
                                          loadingProgress) {
                                        if (loadingProgress == null)
                                          return child;
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Action Buttons - Show based on status
                      if (_shouldShowActionButtons())
                        Column(
                          children: [
                            if (_getStatus().toLowerCase() == 'pending')
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isProcessing ? null : () =>
                                          _showConfirmationDialog(
                                            action: 'Approve',
                                            studioName: makeupArtistData!['studio_name'] ??
                                                'this makeup artist',
                                            onConfirm: () =>
                                                _updateMakeupArtistStatus(
                                                    'Approved'),
                                          ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              12),
                                        ),
                                      ),
                                      child:
                                      const Text(
                                        'Approve',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: isProcessing ? null : () =>
                                          _showConfirmationDialog(
                                            action: 'Reject',
                                            studioName: makeupArtistData!['studio_name'] ??
                                                'this makeup artist',
                                            onConfirm: () =>
                                                _updateMakeupArtistStatus(
                                                    'Rejected'),
                                          ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              12),
                                        ),
                                      ),
                                      child: const Text(
                                        'Reject',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              if (_getStatus().toLowerCase() == 'approved' ||
                                  _getStatus().toLowerCase() == 'accepted')
                                Container(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: isProcessing ? null : () =>
                                        _showConfirmationDialog(
                                          action: 'Disable',
                                          studioName: makeupArtistData!['studio_name'] ??
                                              'this makeup artist',
                                          onConfirm: () =>
                                              _updateMakeupArtistStatus(
                                                  'Disabled'),
                                        ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Disable Account',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            const SizedBox(height: 24),
                          ],
                        )
                      else
                        Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatus() == 'Accepted' ||
                                    _getStatus() == 'Approved'
                                    ? 'Application Approved'
                                    :
                                _getStatus() == 'Rejected'
                                    ? 'Application Rejected'
                                    :
                                'Application ${_getStatus()}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isProcessing)
          // Loading overlay inline
            Container(
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFDA9BF5)),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Processing...',
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
                      // Animated dots
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (index) {
                          return AnimatedContainer(
                            duration: Duration(
                                milliseconds: 600 + (index * 200)),
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
            ),
        ],
      ),
    );
  }
}

//   Widget _buildPortfolioSection() {
//     List<String> portfolioImages = _getPortfolioImages();
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text(
//           'Portfolio:',
//           style: TextStyle(
//             fontSize: 18,
//             color: Colors.black,
//           ),
//         ),
//         portfolioImages.isEmpty
//             ? Container(
//           width: double.infinity,
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: const Center(
//             child: Text(
//               'No portfolio images available',
//               style: TextStyle(
//                 color: Colors.grey,
//                 fontSize: 16,
//               ),
//             ),
//           ),
//         )
//             : GridView.builder(
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),
//           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//             crossAxisCount: 2,
//             crossAxisSpacing: 12,
//             mainAxisSpacing: 12,
//             childAspectRatio: 1.0,
//           ),
//           itemCount: portfolioImages.length,
//           itemBuilder: (context, index) {
//             return Container(
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(12),
//                 child: Image.network(
//                   portfolioImages[index],
//                   width: 160,
//                   height: 160,
//                   fit: BoxFit.cover,
//                   errorBuilder: (context, error, stackTrace) {
//                     return Container(
//                       color: Colors.grey.shade200,
//                       child: const Center(
//                         child: Icon(
//                           Icons.image_not_supported,
//                           color: Colors.grey,
//                           size: 40,
//                         ),
//                       ),
//                     );
//                   },
//                   loadingBuilder: (context, child, loadingProgress) {
//                     if (loadingProgress == null) return child;
//                     return Container(
//                       color: Colors.grey.shade200,
//                       child: const Center(
//                         child: CircularProgressIndicator(),
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             );
//           },
//         ),
//       ],
//     );
//   }
//
//   Widget _buildCategoryPriceSection() {
//     List<Widget> categoryPriceWidgets = [];
//
//     // Get categories
//     List<String> categories = [];
//     if (makeupArtistData != null && makeupArtistData!['category'] != null) {
//       final categoryData = makeupArtistData!['category'];
//       if (categoryData is List) {
//         categories = categoryData.map((item) => item.toString()).toList();
//       }
//     }
//
//     // Get prices
//     Map<String, String> prices = {};
//     if (makeupArtistData != null && makeupArtistData!['price'] != null) {
//       final priceData = makeupArtistData!['price'];
//       if (priceData is Map<String, dynamic>) {
//         prices = priceData.map((key, value) => MapEntry(key, value.toString()));
//       }
//     }
//
//     // Create formatted category-price rows
//     for (int i = 0; i < categories.length; i++) {
//       String category = categories[i];
//       String price = prices[category] ?? 'Price not set';
//
//       // Ensure price starts with RM
//       if (price != 'Price not set' && !price.startsWith('RM')) {
//         price = 'RM$price';
//       }
//
//       categoryPriceWidgets.add(
//         Padding(
//           padding: EdgeInsets.only(bottom: i == categories.length - 1 ? 0 : 8),
//           child: Row(
//             children: [
//               Expanded(
//                 flex: 3,
//                 child: Text(
//                   category,
//                   style: const TextStyle(
//                     fontSize: 14,
//                     color: Colors.black87,
//                   ),
//                 ),
//               ),
//               Expanded(
//                 flex: 2,
//                 child: Text(
//                   price,
//                   style: const TextStyle(
//                     fontSize: 14,
//                     color: Colors.black87,
//                     fontWeight: FontWeight.w500,
//                   ),
//                   textAlign: TextAlign.right,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     }
//
//     if (categoryPriceWidgets.isEmpty) {
//       return const Text(
//         'No services available',
//         style: TextStyle(
//           fontSize: 14,
//           color: Colors.black87,
//         ),
//       );
//     }
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: categoryPriceWidgets,
//     );
//   }
//
//   Widget _buildPersonalInfoSection() {
//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFFF3E5F5),
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Personal Information',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.w600,
//               color: Colors.black,
//             ),
//           ),
//           const SizedBox(height: 16),
//           _buildDetailRow('Name', userData?['name'] ?? 'N/A'),
//           _buildDetailRow('Email', userData?['email'] ?? 'N/A'),
//           _buildDetailRow('Phone Number', ('0${userData?['phone number'].toString()}') ?? 'N/A', isLast: true),
//         ],
//       ),
//     );
//   }
//   Widget _buildLoading() {
//     return Container(
//       color: Colors.black54,
//       child: Center(
//         child: Container(
//           padding: const EdgeInsets.all(24),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(16),
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const CircularProgressIndicator(
//                 valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDA9BF5)),
//                 strokeWidth: 3,
//               ),
//               const SizedBox(height: 16),
//               const Text(
//                 'Processing...',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                   color: Colors.black87,
//                 ),
//               ),
//               const SizedBox(height: 8),
//               const Text(
//                 'Please wait',
//                 style: TextStyle(
//                   fontSize: 14,
//                   color: Colors.grey,
//                 ),
//               ),
//               const SizedBox(height: 16),
//               // Animated dots
//               Row(
//                 mainAxisSize: MainAxisSize.min,
//                 children: List.generate(3, (index) {
//                   return AnimatedContainer(
//                     duration: Duration(milliseconds: 600 + (index * 200)),
//                     curve: Curves.easeInOut,
//                     margin: const EdgeInsets.symmetric(horizontal: 2),
//                     height: 8,
//                     width: 8,
//                     decoration: BoxDecoration(
//                       color: Color(0xFFDA9BF5).withOpacity(0.7),
//                       shape: BoxShape.circle,
//                     ),
//                   );
//                 }),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (isLoading) {
//       return Scaffold(
//         body: const Center(
//           child: CircularProgressIndicator(),
//         ),
//       );
//     }
//
//     if (makeupArtistData == null) {
//       return Scaffold(
//         appBar: AppBar(
//           leading: IconButton(
//             icon: const Icon(Icons.arrow_back, color: Colors.black),
//             onPressed: () => Navigator.of(context).pop(),
//           ),
//           title: const Text("Makeup Artist Details", style: TextStyle(color: Colors.black)),
//           centerTitle: true,
//           elevation: 0,
//         ),
//         body: const Center(
//           child: Text('Makeup artist not found'),
//         ),
//       );
//     }
//
//     return Scaffold(
//       body: Stack(
//         children: [
//           Container(
//             decoration: const BoxDecoration(
//               image: DecorationImage(
//                 image: AssetImage('assets/purple_background.png'),
//                 fit: BoxFit.cover,
//               ),
//             ),
//           ),
//           Column(
//             children: [
//               // Add extra spacing to avoid front camera
//               const SizedBox(height: 60),
//
//               // Header with close button
//               Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Row(
//                   children: [
//                     IconButton(
//                       icon: const Icon(Icons.close, color: Colors.black),
//                       onPressed: () => Navigator.of(context).pop(),
//                     ),
//                     const Expanded(
//                       child: Text(
//                         'Makeup Artist Details',
//                         textAlign: TextAlign.center,
//                         style: TextStyle(
//                           fontSize: 20,
//                           fontWeight: FontWeight.w600,
//                           color: Colors.black,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 48), // Balance the close button
//                   ],
//                 ),
//               ),
//
//               Expanded(
//                 child: SingleChildScrollView(
//                   padding: const EdgeInsets.symmetric(horizontal: 20),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // Makeup Artist Info Section
//                       Container(
//                         padding: const EdgeInsets.all(20),
//                         decoration: BoxDecoration(
//                           color: Colors.transparent,
//                           borderRadius: BorderRadius.circular(16),
//                           border: Border.all(
//                             color: Colors.transparent,
//                           ),
//                         ),
//                         child: Row(
//                           children: [
//                             // Profile Picture
//                             Container(
//                               width: 60,
//                               height: 60,
//                               decoration: BoxDecoration(
//                                 shape: BoxShape.circle,
//                                 color: const Color(0xFFFFB347),
//                               ),
//                               child: ClipOval(
//                                 child: profilePictureUrl != null && profilePictureUrl!.isNotEmpty
//                                     ? Image.network(
//                                   profilePictureUrl!,
//                                   fit: BoxFit.cover,
//                                   errorBuilder: (context, error, stackTrace) {
//                                     return const Icon(
//                                       Icons.person,
//                                       size: 30,
//                                       color: Colors.white,
//                                     );
//                                   },
//                                 )
//                                     : const Icon(
//                                   Icons.person,
//                                   size: 30,
//                                   color: Colors.white,
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(width: 16),
//
//                             // Makeup Artist Details
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     makeupArtistData!['studio_name'] ?? 'Unknown Artist',
//                                     style: const TextStyle(
//                                       fontSize: 18,
//                                       fontWeight: FontWeight.w600,
//                                       color: Colors.black,
//                                     ),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   Row(
//                                     children: [
//                                       const Icon(
//                                         Icons.phone,
//                                         size: 16,
//                                         color: Colors.deepPurpleAccent,
//                                       ),
//                                       const SizedBox(width: 4),
//                                       Text(
//                                         ('0${makeupArtistData!['phone_number'].toString()}') ?? 'No phone',
//                                         style: const TextStyle(
//                                           fontSize: 14,
//                                           color: Colors.black87,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                   const SizedBox(height: 4),
//                                   Row(
//                                     children: [
//                                       const Icon(
//                                         Icons.email,
//                                         size: 16,
//                                         color: Colors.deepPurpleAccent,
//                                       ),
//                                       const SizedBox(width: 4),
//                                       Expanded(
//                                         child: Text(
//                                           makeupArtistData!['email'] ?? 'No email',
//                                           style: const TextStyle(
//                                             fontSize: 14,
//                                             color: Colors.black87,
//                                           ),
//                                           overflow: TextOverflow.ellipsis,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                   const SizedBox(height: 4),
//                                   Row(
//                                     children: [
//                                       Icon(
//                                         Icons.circle,
//                                         size: 12,
//                                         color: _getStatusColor(),
//                                       ),
//                                       const SizedBox(width: 4),
//                                       Text(
//                                         _getStatus(),
//                                         style: TextStyle(
//                                           fontSize: 14,
//                                           color: _getStatusColor(),
//                                           fontWeight: FontWeight.w500,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//
//                       const SizedBox(height: 24),
//                       _buildPersonalInfoSection(),
//                       const SizedBox(height: 24),
//
//                       // Makeup Artist Details Section
//                       Container(
//                         padding: const EdgeInsets.all(20),
//                         decoration: BoxDecoration(
//                           color: const Color(0xFFF3E5F5),
//                           borderRadius: BorderRadius.circular(16),
//                         ),
//                         child: Column(
//                           children: [
//                             Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 const Text(
//                                   'Studio Information',
//                                   style: TextStyle(
//                                     fontSize: 18,
//                                     fontWeight: FontWeight.w600,
//                                     color: Colors.black,
//                                   ),
//                                 ),
//                                 const SizedBox(height: 16),
//                                 Row(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     const SizedBox(
//                                       width: 150,
//                                       child: Text(
//                                         'Services & Pricing',
//                                         style: TextStyle(
//                                           fontSize: 14,
//                                           fontWeight: FontWeight.w500,
//                                           color: Colors.black87,
//                                         ),
//                                       ),
//                                     ),
//                                     Expanded(
//                                       child: _buildCategoryPriceSection(),
//                                     ),
//                                   ],
//                                 ),
//                                 const SizedBox(height: 16),
//                               ],
//                             ),
//                             _buildDetailRow('Address', makeupArtistData!['address'] ?? 'Address not available'),
//                             _buildDetailRow('Working Days', _getWorkingDays()),
//                             _buildDetailRow('Working Hours', _getWorkingHours()),
//                             _buildDetailRow('About', makeupArtistData!['about'] ?? 'About not available', isLast: true),
//                           ],
//                         ),
//                       ),
//                       // Portfolio Section
//                       Container(
//                         padding: const EdgeInsets.all(20),
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(16),
//                         ),
//                         child: _buildPortfolioSection(),
//                       ),
//
//                       const SizedBox(height: 24),
//
//                       // Action Buttons - Show based on status
//                       if (_shouldShowActionButtons())
//                         Column(
//                           children: [
//                             if (_getStatus().toLowerCase() == 'pending')
//                               Row(
//                                 children: [
//                                   Expanded(
//                                     child: ElevatedButton(
//                                       onPressed: isProcessing ? null : () => _showConfirmationDialog(
//                                         action: 'Approve',
//                                         studioName: makeupArtistData!['studio_name'] ?? 'this makeup artist',
//                                         onConfirm: () => _updateMakeupArtistStatus('Approved'),
//                                       ),
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: Colors.green,
//                                         foregroundColor: Colors.white,
//                                         padding: const EdgeInsets.symmetric(vertical: 16),
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.circular(12),
//                                         ),
//                                       ),
//                                       child:
//                                       const Text(
//                                         'Approve',
//                                         style: TextStyle(
//                                           fontSize: 16,
//                                           fontWeight: FontWeight.w600,
//                                         ),
//                                       ),
//                                     ),
//                                   ),
//                                   const SizedBox(width: 16),
//                                   Expanded(
//                                     child: ElevatedButton(
//                                       onPressed: isProcessing ? null : () => _showConfirmationDialog(
//                                         action: 'Reject',
//                                         studioName: makeupArtistData!['studio_name'] ?? 'this makeup artist',
//                                         onConfirm: () => _updateMakeupArtistStatus('Rejected'),
//                                       ),
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: Colors.red,
//                                         foregroundColor: Colors.white,
//                                         padding: const EdgeInsets.symmetric(vertical: 16),
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.circular(12),
//                                         ),
//                                       ),
//                                       child: const Text(
//                                         'Reject',
//                                         style: TextStyle(
//                                           fontSize: 16,
//                                           fontWeight: FontWeight.w600,
//                                         ),
//                                       ),
//                                     ),
//                                   ),
//                                 ],
//                               )
//                             else if (_getStatus().toLowerCase() == 'approved' || _getStatus().toLowerCase() == 'accepted')
//                               Container(
//                                 width: double.infinity,
//                                 child: ElevatedButton(
//                                   onPressed: isProcessing ? null : () => _showConfirmationDialog(
//                                     action: 'Disable',
//                                     studioName: makeupArtistData!['studio_name'] ?? 'this makeup artist',
//                                     onConfirm: () => _updateMakeupArtistStatus('Disabled'),
//                                   ),
//                                   style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.orange,
//                                     foregroundColor: Colors.white,
//                                     padding: const EdgeInsets.symmetric(vertical: 16),
//                                     shape: RoundedRectangleBorder(
//                                       borderRadius: BorderRadius.circular(12),
//                                     ),
//                                   ),
//                                   child: const Text(
//                                     'Disable Account',
//                                     style: TextStyle(
//                                       fontSize: 16,
//                                       fontWeight: FontWeight.w600,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             const SizedBox(height: 24),
//                           ],
//                         )
//                       else
//                         Column(
//                           children: [
//                             Container(
//                               width: double.infinity,
//                               padding: const EdgeInsets.symmetric(vertical: 16),
//                               decoration: BoxDecoration(
//                                 color: Colors.grey[300],
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                               child: Text(
//                                 _getStatus() == 'Accepted' || _getStatus() == 'Approved' ? 'Application Approved' :
//                                 _getStatus() == 'Rejected' ? 'Application Rejected' :
//                                 'Application ${_getStatus()}',
//                                 textAlign: TextAlign.center,
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.w600,
//                                   color: Colors.grey[600],
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(height: 24),
//                           ],
//                         ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           if (isProcessing) _buildLoading(),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDetailRow(String label, String value, {bool isLast = false}) {
//     return Column(
//       children: [
//         Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             SizedBox(
//               width: 150,
//               child: Text(
//                 label,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.w500,
//                   color: Colors.black87,
//                 ),
//               ),
//             ),
//             Expanded(
//               child: Text(
//                 value,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   color: Colors.black87,
//                 ),
//               ),
//             ),
//           ],
//         ),
//         if (!isLast) const SizedBox(height: 16),
//       ],
//     );
//   }
// }