import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'HomePage.dart';
import 'BookingHistoryPage.dart';
import '../all user/Profile Page.dart';
import 'package:blush_up/all%20user/ChatListPage.dart';
import 'package:rxdart/rxdart.dart';

class UserNavigation extends StatefulWidget {
  final int initialIndex;
  const UserNavigation({super.key, this.initialIndex = 0});

  @override
  State<UserNavigation> createState() => _UserNavigationState();
}

class _UserNavigationState extends State<UserNavigation> {
  late int _selectedIndex;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUserId;
  DocumentReference? _currentUserRef;
  bool _isImageSearchLoading = false; // Track loading state

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _initializeUser();
    _initializePages();
  }

  void _initializePages() {
    _pages = [
      HomePage(
        onLoadingStateChanged: (isLoading) {
          // Update loading state when HomePage notifies us
          if (mounted) {
            setState(() {
              _isImageSearchLoading = isLoading;
            });
            print('🔄 Bottom nav loading state: $isLoading');
          }
        },
      ),
      const ChatListPage(),
      const BookingHistoryPage(),
      const ProfilePage(),
    ];
  }

  void _initializeUser() {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      print('👤 Current user ID: ${currentUser.uid}');
      setState(() {
        _currentUserId = currentUser.uid;
        _currentUserRef = _firestore.collection('users').doc(currentUser.uid);
        print('📌 Current user ref: ${_currentUserRef?.path}');
      });
    }
  }

  void _onItemTapped(int index) {
    // Prevent navigation if image search is loading
    if (_isImageSearchLoading) {
      print('⚠️ Navigation blocked: Image search in progress');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for image search to complete'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedIndex = index;
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
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: StreamBuilder<int>(
        stream: _getTotalUnreadCountStreamAlternative(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('❌ Error in unread count stream: ${snapshot.error}');
          }

          final unreadCount = snapshot.data ?? 0;
          print('🔄 Current unread count: $unreadCount');

          return Stack(
            children: [
              // Bottom Navigation Bar
              IgnorePointer(
                ignoring: _isImageSearchLoading,
                child: BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: _onItemTapped,
                  selectedItemColor: const Color(0xFFDA9BF5),
                  unselectedItemColor: Colors.grey,
                  backgroundColor: Colors.white,
                  type: BottomNavigationBarType.fixed,
                  items: [
                    const BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Home'
                    ),
                    BottomNavigationBarItem(
                        icon: _buildBadgedIcon(Icons.chat_bubble, unreadCount),
                        label: 'Chat'
                    ),
                    const BottomNavigationBarItem(
                        icon: Icon(Icons.event_available),
                        label: 'Booking'
                    ),
                    const BottomNavigationBarItem(
                        icon: Icon(Icons.person),
                        label: 'Profile'
                    ),
                  ],
                ),
              ),

              // Grey overlay when loading - Same color as loading screen
              if (_isImageSearchLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54, // Same grey as the main loading overlay
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}