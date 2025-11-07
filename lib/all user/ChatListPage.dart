import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:blush_up/all%20user/ChatPage.dart';
import 'package:flutter/services.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  DocumentReference? _currentUserRef;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
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

  Future<Map<String, dynamic>?> _getOtherUserData(List<DocumentReference> participants) async {
    if (_currentUserRef == null) return null;

    DocumentReference? otherUserRef;
    for (DocumentReference participantRef in participants) {
      if (participantRef.id != _currentUserRef!.id) {
        otherUserRef = participantRef;
        break;
      }
    }

    if (otherUserRef == null) return null;

    // Rest of your method remains the same
    try {
      final userDoc = await otherUserRef.get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        return {
          'ref': otherUserRef,
          'id': otherUserRef.id,
          'name': userData?['name'] ?? 'Unknown User',
          'profilePic': userData?['profile pictures'] ?? '',
        };
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }

    return {
      'ref': otherUserRef,
      'id': otherUserRef.id,
      'name': 'Unknown User',
      'profilePic': '',
    };
  }

  String _formatLastMessageTime(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final messageTime = timestamp.toDate();
    final difference = now.difference(messageTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${difference.inDays}d ago';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Updated to use real-time stream instead of future
  Stream<int> _getUnreadCountStream(String chatId) {
    if (_currentUserRef == null) return Stream.value(0);

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverRef', isEqualTo: _currentUserRef)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .handleError((error) {
      print('Error getting unread count: $error');
      return 0;
    });
  }

  Widget _buildChatTile(DocumentSnapshot chatDoc) {
    final chatData = chatDoc.data() as Map<String, dynamic>;

    // Handle both string IDs and DocumentReferences
    List<DocumentReference> participants = [];
    final rawParticipants = chatData['participants'] ?? [];

    for (var participant in rawParticipants) {
      if (participant is DocumentReference) {
        participants.add(participant);
      } else if (participant is String) {
        participants.add(_firestore.collection('users').doc(participant));
      }
    }

    final lastMessage = chatData['lastMessage']?.toString() ?? '';
    final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;

    // Rest of your method remains the same
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getOtherUserData(participants),
      builder: (context, snapshot) {
        print('FutureBuilder state: ${snapshot.connectionState}');
        print('FutureBuilder data: ${snapshot.data}');
        print('FutureBuilder error: ${snapshot.error}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Loading...'),
            ),
          );
        }

        if (snapshot.hasError) {
          print('Error in FutureBuilder: ${snapshot.error}');
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(Icons.error, color: Colors.white),
              ),
              title: Text('Error loading user'),
            ),
          );
        }

        final otherUser = snapshot.data;
        if (otherUser == null) {
          print('Other user is null, not showing tile');
          return const SizedBox.shrink();
        }

        // Handle empty or null last message
        String displayMessage = 'No messages yet';
        bool isEmpty = true;

        if (lastMessage.isNotEmpty && lastMessage.trim().isNotEmpty) {
          displayMessage = lastMessage.trim();
          isEmpty = false;
        }

        print('Displaying chat tile for: ${otherUser['name']}');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: otherUser['profilePic'] != null &&
                  otherUser['profilePic'].toString().isNotEmpty
                  ? NetworkImage(otherUser['profilePic'])
                  : null,
              backgroundColor: const Color(0xFFDA9BF5),
              child: otherUser['profilePic'] == null ||
                  otherUser['profilePic'].toString().isEmpty
                  ? Text(
                otherUser['name'].toString().isNotEmpty
                    ? otherUser['name'][0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              )
                  : null,
            ),
            title: Text(
              otherUser['name'] ?? 'Unknown User',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              displayMessage,
              style: TextStyle(
                color: isEmpty ? Colors.grey[600] : Colors.grey[700],
                fontSize: 14,
                fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: StreamBuilder<int>(
              stream: _getUnreadCountStream(chatDoc.id),
              builder: (context, unreadSnapshot) {
                final unreadCount = unreadSnapshot.data ?? 0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatLastMessageTime(lastMessageTime),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                );
              },
            ),
            onTap: () async {
              // Navigate to chat page and wait for return
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatPage(
                    artistRef: otherUser['ref'],
                    artistId: otherUser['id'],
                    artistName: otherUser['name'],
                    artistProfilePic: otherUser['profilePic'] ?? '',
                  ),
                ),
              );
              // No need to manually refresh since we're using StreamBuilder
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        body: FutureBuilder<DocumentSnapshot>(
          future: _firestore.collection('users').doc(_auth.currentUser?.uid).get(),
          builder: (context, snapshot) {
            String backgroundImage;

            if (snapshot.hasData && snapshot.data?.exists == true) {
              final userData = snapshot.data!.data() as Map<String, dynamic>;
              backgroundImage = userData['role'] == 'makeup artist'
                  ? 'assets/purple_background.png'
                  : 'assets/image_4.png';
            } else {
              backgroundImage = 'assets/purple_background.png'; // default
            }

            return Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(backgroundImage),
                  fit: BoxFit.cover,
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Text(
            'Messages',
            style: TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
        body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('users').doc(_currentUserId).get(),
    builder: (context, userSnapshot) {
    String backgroundImage = 'assets/image_4.png'; // Default for non-makeup artists

    if (userSnapshot.hasData && userSnapshot.data!.exists) {
    final userData = userSnapshot.data!.data() as Map<String, dynamic>;
    if (userData['role'] == 'makeup artist') {
    backgroundImage = 'assets/purple_background.png';
    }
    }

    return Container(
    decoration: BoxDecoration(
    image: DecorationImage(
    image: AssetImage(backgroundImage),
    fit: BoxFit.cover,
    ),
    ),
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('chats')
              .where('participants', arrayContains: _currentUserRef)
              .orderBy('lastMessageTime', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            print('StreamBuilder state: ${snapshot.connectionState}');
            print('StreamBuilder has data: ${snapshot.hasData}');
            print('StreamBuilder error: ${snapshot.error}');

            if (snapshot.hasError) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading chats',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              );
            }

            final chats = snapshot.data?.docs ?? [];
            print('Number of chats: ${chats.length}');

            if (chats.isEmpty) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  margin: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No conversations yet',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start chatting with artists to see your conversations here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return RefreshIndicator(
              color: Colors.white,
              onRefresh: () async {
                _initializeUser(); // Reset user data
                setState(() {});   // Rebuild the widget
                await Future.delayed(const Duration(milliseconds: 300));
              },
              child: ListView.builder(
                padding: EdgeInsets.only(
                  top: kToolbarHeight + 60,
                  bottom: 8,
                ),
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  return _buildChatTile(chats[index]);
                },
              ),
            );

          },
        ),
      );
    }
    )
    );

  }
}