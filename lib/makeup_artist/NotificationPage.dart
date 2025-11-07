import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../service/NotificationService.dart';
import 'MakeupArtistAppointmentDetails.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: () async {
              await NotificationService.markAllAsRead(userId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All notifications marked as read')),
                );
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/purple_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: NotificationService.getNotificationsStream(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;

                  return _buildNotificationItem(doc.id, data);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(String docId, Map<String, dynamic> data) {
    final isRead = data['read'] ?? false;
    final type = data['type'] ?? '';
    final createdAt = data['created_at'] as Timestamp?;
    final appointmentRef = data['appointment_id'] as DocumentReference?;
    final customerRef = data['customer_id'] as DocumentReference?;

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchNotificationDetails(appointmentRef, customerRef),
      builder: (context, detailsSnapshot) {
        String title = 'Notification';
        String message = 'Loading...';

        if (detailsSnapshot.connectionState == ConnectionState.waiting) {
          message = 'Loading...';
        } else if (detailsSnapshot.hasError) {
          message = 'Error loading details';
        } else if (detailsSnapshot.hasData) {
          final details = detailsSnapshot.data!;
          final customerName = details['customerName'] ?? 'A customer';
          final category = details['category'] ?? 'an appointment';
          final date = details['date'] ?? '';
          final time = details['time'] ?? '';

          // Generate title and message based on type
          if (type == 'new_booking') {
            title = 'New Booking';
            message = 'New booking from $customerName on $date at $time for $category';
          } else if (type == 'booking_cancelled') {
            title = 'Booking Cancelled';
            message = '$customerName cancelled their booking on $date at $time for $category';
          }
        }

        return Dismissible(
          key: Key(docId),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (direction) {
            NotificationService.deleteNotification(docId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notification deleted')),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isRead ? Colors.white : Colors.pink.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRead ? Colors.grey.shade300 : Colors.pink.shade200,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: _getNotificationColor(type),
                child: detailsSnapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : Icon(
                  _getNotificationIcon(type),
                  color: Colors.white,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB968C7),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTimestamp(createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                if (!isRead) {
                  NotificationService.markAsRead(docId);
                }
                _handleNotificationTap(context, appointmentRef, customerRef);
              },
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchNotificationDetails(
      DocumentReference? appointmentRef,
      DocumentReference? customerRef,
      ) async {
    try {
      String customerName = 'A customer';
      String category = 'an appointment';
      String date = '';
      String time = '';

      // Fetch appointment details
      if (appointmentRef != null) {
        final appointmentDoc = await appointmentRef.get();
        if (appointmentDoc.exists) {
          final appointmentData = appointmentDoc.data() as Map<String, dynamic>?;

          // Get category
          category = appointmentData?['category'] ?? 'an appointment';

          // Get and format date
          final dateStr = appointmentData?['date'] as String?;
          if (dateStr != null && dateStr.isNotEmpty) {
            try {
              final parsedDate = DateTime.parse(dateStr);
              date = DateFormat('MMM dd, yyyy').format(parsedDate);
            } catch (e) {
              date = dateStr;
            }
          }

          // Get time
          time = appointmentData?['time'] ?? '';
        }
      }

      // Fetch customer name
      if (customerRef != null) {
        final customerDoc = await customerRef.get();
        if (customerDoc.exists) {
          final customerData = customerDoc.data() as Map<String, dynamic>?;
          customerName = customerData?['name'] ?? 'A customer';
        }
      }

      return {
        'customerName': customerName,
        'category': category,
        'date': date,
        'time': time,
      };
    } catch (e) {
      print('Error fetching notification details: $e');
      return {
        'customerName': 'A customer',
        'category': 'an appointment',
        'date': '',
        'time': '',
      };
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'new_booking':
        return Icons.calendar_today;
      case 'booking_cancelled':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'new_booking':
        return const Color(0xFFB968C7);
      case 'booking_cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';

    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd, yyyy').format(date);
    }
  }

  void _handleNotificationTap(
      BuildContext context,
      DocumentReference? appointmentRef,
      DocumentReference? customerRef,
      ) async {
    if (appointmentRef != null && customerRef != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MakeupArtistAppointmentDetailsPage(
            appointmentId: appointmentRef.id,
            customerId: customerRef.id,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open appointment details')),
      );
    }
  }
}