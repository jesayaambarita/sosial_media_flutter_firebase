import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class MessageListScreen extends StatelessWidget {
  const MessageListScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    // Mendapatkan ID pengguna saat ini
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text('Silakan login terlebih dahulu'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Pesan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: ChatUsersList(currentUserId: currentUserId),
    );
  }
}

class ChatUsersList extends StatelessWidget {
  final String currentUserId;

  const ChatUsersList({Key? key, required this.currentUserId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUserId)
          // .orderBy('lastMessageTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('Belum ada pesan'));
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var chatDoc = snapshot.data!.docs[index];
            var chatData = chatDoc.data() as Map<String, dynamic>;

            // Mendapatkan ID lawan bicara
            List<dynamic> participants = chatData['participants'] ?? [];
            String otherUserId = participants
                .firstWhere((id) => id != currentUserId, orElse: () => '');

            if (otherUserId.isEmpty) {
              return SizedBox.shrink();
            }

            // Mengambil data lawan bicara
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUserId)
                  .get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey[300],
                      child: Icon(Icons.person, color: Colors.grey[600]),
                    ),
                    title: Text('Memuat...'),
                  );
                }

                var userData =
                    userSnapshot.data!.data() as Map<String, dynamic>?;
                if (userData == null) {
                  return SizedBox.shrink();
                }

                String userName = userData['name'] ?? 'Pengguna';

                // Mengambil profilePicture dari Firestore
                String? profilePicture = userData['profilePicture'];
                bool isOnline = userData['isOnline'] ?? false;
                Timestamp? lastSeen = userData['lastSeen'];

                String lastMessage = chatData['lastMessage'] ?? '';
                Timestamp lastMessageTime =
                    chatData['lastMessageTimestamp'] ?? Timestamp.now();
                bool unread =
                    (chatData['unreadBy'] ?? []).contains(currentUserId);

                return ListTile(
                  leading: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.grey[300],
                    // Menggunakan CachedNetworkImage untuk profilePicture
                    backgroundImage:
                        profilePicture != null && profilePicture.isNotEmpty
                            ? CachedNetworkImageProvider(profilePicture)
                            : null,
                    child: (profilePicture == null || profilePicture.isEmpty)
                        ? Icon(Icons.person, color: Colors.grey[600])
                        : null,
                  ),
                  title: Text(
                    userName,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                      color: unread ? Colors.black87 : Colors.grey[600],
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTimestamp(lastMessageTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: unread ? Colors.blue : Colors.grey[500],
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          userId: chatDoc.id,
                          userName: userName,
                          isOnline: isOnline,
                          lastSeen: lastSeen,
                          profilePicture: profilePicture,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(Duration(days: 1));
    DateTime messageDate =
        DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat.Hm().format(dateTime); // Format: 14:23
    } else if (messageDate == yesterday) {
      return 'Kemarin';
    } else if (now.difference(dateTime).inDays < 7) {
      return DateFormat.E().format(dateTime); // Format: Sen, Sel, dsb.
    } else {
      return DateFormat.yMd().format(dateTime); // Format: 23/04/2025
    }
  }
}
