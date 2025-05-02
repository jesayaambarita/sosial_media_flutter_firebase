import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../screens/create_story_screen.dart';
import '../screens/story_view_screen.dart';

class StoryList extends StatefulWidget {
  const StoryList({super.key});

  @override
  State<StoryList> createState() => _StoryListState();
}

class _StoryListState extends State<StoryList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Center(
          child: Text(
            'Silakan login untuk melihat stories',
            style: TextStyle(
              color: Color(0xFF757575),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      // Modified query to use a simpler approach that doesn't require compound indexes
      stream: _firestore
          .collection('stories')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .orderBy('expiresAt') // Only use one orderBy initially
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 110,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyStoryList();
        }

        // Group stories by user, and sort within groups by timestamp
        Map<String, List<DocumentSnapshot>> storiesByUser = {};

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final userId = data['userId'] as String? ?? '';

          if (userId.isNotEmpty) {
            if (!storiesByUser.containsKey(userId)) {
              storiesByUser[userId] = [];
            }
            storiesByUser[userId]!.add(doc);
          }
        }

        // Sort each user's stories by timestamp
        storiesByUser.forEach((userId, stories) {
          stories.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTimestamp = aData['timestamp'];
            final bTimestamp = bData['timestamp'];
            return bTimestamp.compareTo(aTimestamp); // Descending order
          });
        });

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.03),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  children: [
                    // Add Story Button
                    _buildAddStoryButton(context),

                    // User Stories
                    ...storiesByUser.entries.map((entry) {
                      final userStories = entry.value;
                      final mostRecentStory = userStories.first;
                      final storyData =
                          mostRecentStory.data() as Map<String, dynamic>;

                      return _buildStoryAvatar(
                        context,
                        storyData,
                        userStories,
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyStoryList() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.03),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              children: [
                _buildAddStoryButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddStoryButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return StoryCreatorScreen();
              },
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.1),
                border: Border.all(
                  color: primaryColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.add,
                color: primaryColor,
                size: 30,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Buat Story',
              style: TextStyle(
                color: Color(0xFF757575),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryAvatar(BuildContext context, Map<String, dynamic> storyData,
      List<DocumentSnapshot> userStories) {
    final hasViewed = storyData['views'] != null &&
        storyData['views'].contains(_auth.currentUser?.uid);
    final borderColor = hasViewed ? Colors.grey : primaryColor;
    final userProfilePic = storyData['userProfilePic'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StoryDetailScreen(stories: userStories),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: ClipOval(
                  child: userProfilePic.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: userProfilePic,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[200],
                            child: Icon(Icons.person, color: Colors.grey[400]),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: Icon(Icons.error, color: Colors.red[300]),
                          ),
                          fadeInDuration: const Duration(milliseconds: 200),
                          cacheKey: 'story_profile_${storyData['userId']}',
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: Icon(Icons.person, color: Colors.grey[400]),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 60,
              child: Text(
                storyData['userName'] ?? 'User',
                style: TextStyle(
                  color: Color(0xFF757575),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
