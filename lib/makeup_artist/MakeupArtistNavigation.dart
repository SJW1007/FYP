import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'MakeupAritistHome.dart';
import 'MakeupArtistAppointments.dart';
import '../all user/Profile Page.dart';
import '../all user/ChatListPage.dart';
import 'package:rxdart/rxdart.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({super.key, this.initialIndex = 0});

  @override
  State<MainNavigation> createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation> {
  late int _selectedIndex;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUserId;
  DocumentReference? _currentUserRef;

  // Add these properties to control appointments page state
  bool _appointmentsShowUpcoming = true;
  bool _appointmentsStartWithListView = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _initializeUser();
  }

  void _initializeUser() {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      setState(() {
        _currentUserId = currentUser.uid;
        _currentUserRef = _firestore.collection('users').doc(currentUser.uid);
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // Reset appointments page to default when navigating via bottom nav
      if (index == 2) {
        _appointmentsShowUpcoming = true;
        _appointmentsStartWithListView = false;
      }
    });
  }

  // Add this method to navigate to appointments page with specific settings
  void navigateToAppointmentsPage({
    required bool showUpcoming,
    bool startWithListView = true,
  }) {
    setState(() {
      _selectedIndex = 2; // Index for appointments page
      _appointmentsShowUpcoming = showUpcoming;
      _appointmentsStartWithListView = startWithListView;
    });
  }

  Stream<int> _getTotalUnreadCountStreamAlternative() {
    if (_currentUserRef == null) return Stream<int>.value(0);

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: _currentUserRef)
        .snapshots()
        .asyncExpand((chatsSnapshot) {
      List<Stream<int>> unreadStreams = [];

      for (var chatDoc in chatsSnapshot.docs) {
        final unreadStream = _firestore
            .collection('chats')
            .doc(chatDoc.id)
            .collection('messages')
            .where('receiverRef', isEqualTo: _currentUserRef)
            .where('isRead', isEqualTo: false)
            .snapshots()
            .map((messagesSnapshot) {
          print('🔔 Unread messages in chat ${chatDoc.id}: ${messagesSnapshot.docs.length}');
          return messagesSnapshot.docs.length;
        });

        unreadStreams.add(unreadStream);
      }

      if (unreadStreams.isEmpty) {
        return Stream<int>.value(0);
      }

      return CombineLatestStream.list<int>(unreadStreams)
          .map<int>((List<int> counts) {
        final total = counts.fold<int>(0, (sum, count) => sum + count);
        print('🔴 Total unread messages: $total');
        return total;
      });
    }).handleError((error) {
      print('Error getting total unread count: $error');
      return 0;
    });
  }

  Widget _buildBadgedIcon(IconData icon, int unreadCount) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (unreadCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Create pages dynamically with current settings
    final List<Widget> pages = [
      const MakeupArtistHomePage(),
      const ChatListPage(),
      MakeupArtistAppointmentsPage(
        key: ValueKey('appointments_${_appointmentsShowUpcoming}_${_appointmentsStartWithListView}'),
        initialShowUpcoming: _appointmentsShowUpcoming,
        startWithListView: _appointmentsStartWithListView,
      ),
      const ProfilePage(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: StreamBuilder<int>(
        stream: _getTotalUnreadCountStreamAlternative(),
        builder: (context, snapshot) {
          final unreadCount = snapshot.data ?? 0;
          print('Navigation bar unread count: $unreadCount');

          return BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: const Color(0xFFDA9BF5),
            unselectedItemColor: Colors.grey,
            backgroundColor: Colors.white,
            type: BottomNavigationBarType.fixed,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: _buildBadgedIcon(Icons.chat_bubble, unreadCount),
                label: 'Chat',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.event_available),
                label: 'Booking',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}