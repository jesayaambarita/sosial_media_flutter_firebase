// Add this StoryItem model class at the top of your file or in a separate models file
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StoryItem {
  final String id;
  final String userId;
  final String userName;
  final String userProfilePic;
  final String imageUrl;
  final Timestamp timestamp;
  final bool viewed;

  StoryItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userProfilePic,
    required this.imageUrl,
    required this.timestamp,
    required this.viewed,
  });

  factory StoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StoryItem(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userProfilePic: data['userProfilePic'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      timestamp: data['timestamp'] as Timestamp? ?? Timestamp.now(),
      viewed: (data['viewedBy'] ?? [])
          .contains(FirebaseAuth.instance.currentUser?.uid),
    );
  }
}
