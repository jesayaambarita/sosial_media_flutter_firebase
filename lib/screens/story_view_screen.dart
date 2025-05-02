import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:story_view/story_view.dart';

class StoryDetailScreen extends StatefulWidget {
  final List<DocumentSnapshot> stories;

  const StoryDetailScreen({
    Key? key,
    required this.stories,
  }) : super(key: key);

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StoryController _storyController = StoryController();
  List<StoryItem> _storyItems = [];
  bool _isLoading = true;
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _storyController.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final stories = widget.stories;
      _storyItems = [];

      for (final story in stories) {
        final storyData = story.data() as Map<String, dynamic>;
        final mediaUrl = storyData['mediaUrl'] as String? ?? '';
        final caption = storyData['caption'] as String? ?? '';
        final mediaType = storyData['mediaType'] as String? ?? 'image';

        // Null check untuk mediaUrl
        if (mediaUrl.isEmpty) {
          continue;
        }

        // Mark as viewed
        if (_auth.currentUser != null) {
          List<dynamic> views = storyData['views'] ?? [];
          if (!views.contains(_auth.currentUser!.uid)) {
            await _firestore.collection('stories').doc(story.id).update({
              'views': FieldValue.arrayUnion([_auth.currentUser!.uid]),
            });
          }
        }

        // Add story item based on media type
        if (mediaType == 'video') {
          _storyItems.add(
            StoryItem.pageVideo(
              mediaUrl,
              controller: _storyController,
              duration: const Duration(seconds: 10),
              caption: Text(
                caption,
                style: const TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.black54,
                  fontSize: 17,
                ),
              ),
            ),
          );
        } else {
          _storyItems.add(
            StoryItem.pageImage(
              url: mediaUrl,
              controller: _storyController,
              caption: Text(
                caption,
                style: const TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.black54,
                  fontSize: 17,
                ),
              ),
            ),
          );
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading stories: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
        ),
      );
    }

    if (_storyItems.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Tidak ada story yang tersedia',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // Null safety check for first story
    if (widget.stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: Text(
            'Story tidak ditemukan',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final firstStory = widget.stories.first.data() as Map<String, dynamic>;
    final userName = firstStory['userName'] ?? 'User';
    final userProfilePic = firstStory['userProfilePic'] ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Story View
          StoryView(
            storyItems: _storyItems,
            controller: _storyController,
            onComplete: () {
              if (mounted) {
                Navigator.pop(context);
              }
            },
            progressPosition: ProgressPosition.top,
            repeat: false,
            inline: false,
            onVerticalSwipeComplete: (direction) {
              if (direction == Direction.down && mounted) {
                Navigator.pop(context);
              }
            },
          ),

          // Custom Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: userProfilePic.isNotEmpty
                        ? CachedNetworkImageProvider(userProfilePic)
                        : null,
                    backgroundColor: Colors.grey[700],
                    child: userProfilePic.isEmpty
                        ? Icon(Icons.person, color: Colors.grey[300], size: 20)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
