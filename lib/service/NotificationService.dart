import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a notification for new booking
  static Future<void> createBookingNotification({
    required String artistUserId,
    required String appointmentId,
    required String customerId,
  }) async {
    try {
      final artistUserRef = _firestore.collection('users').doc(artistUserId);
      final customerRef = _firestore.collection('users').doc(customerId);
      final appointmentRef = _firestore.collection('appointments').doc(appointmentId);

      await _firestore.collection('notifications').add({
        'recipient_id': artistUserRef, // Reference type
        'customer_id': customerRef, // Reference type
        'appointment_id': appointmentRef, // Reference type
        'type': 'new_booking',
        'created_at': FieldValue.serverTimestamp(),
        'read': false,
      });
      print('✅ Notification created successfully');
    } catch (e) {
      print('❌ Error creating notification: $e');
    }
  }

  /// Create a notification for booking cancellation
  static Future<void> createCancellationNotification({
    required String artistUserId,
    required String appointmentId,
    required String customerId,
  }) async {
    try {
      final artistUserRef = _firestore.collection('users').doc(artistUserId);
      final customerRef = _firestore.collection('users').doc(customerId);
      final appointmentRef = _firestore.collection('appointments').doc(appointmentId);

      await _firestore.collection('notifications').add({
        'recipient_id': artistUserRef, // Reference type
        'customer_id': customerRef, // Reference type
        'appointment_id': appointmentRef, // Reference type
        'type': 'booking_cancelled',
        'created_at': FieldValue.serverTimestamp(),
        'read': false,
      });
      print('✅ Cancellation notification created successfully');
    } catch (e) {
      print('❌ Error creating cancellation notification: $e');
    }
  }

  /// Get unread notification count for a user
  static Stream<int> getUnreadNotificationCount(String userId) {
    final userRef = _firestore.collection('users').doc(userId);
    return _firestore
        .collection('notifications')
        .where('recipient_id', isEqualTo: userRef)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'read': true,
      });
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read for a user
  static Future<void> markAllAsRead(String userId) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('notifications')
          .where('recipient_id', isEqualTo: userRef)
          .where('read', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }

      await batch.commit();
    } catch (e) {
      print('❌ Error marking all notifications as read: $e');
    }
  }

  /// Delete a notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
    } catch (e) {
      print('❌ Error deleting notification: $e');
    }
  }

  /// Get notifications stream for a user
  static Stream<QuerySnapshot> getNotificationsStream(String userId) {
    final userRef = _firestore.collection('users').doc(userId);
    return _firestore
        .collection('notifications')
        .where('recipient_id', isEqualTo: userRef)
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots();
  }
}