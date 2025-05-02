import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../utils/user_status_manager.dart';
import '../widgets/story_list_widget.dart';
import 'activity_screen.dart';
import 'create_story_screen.dart';
import 'explore_screen.dart';
import 'message_list_screen.dart';
import 'post_screen.dart';
import 'profile_screen.dart';
import 'story_view_screen.dart';
import 'user_detail_screen.dart';
import 'user_search_screen.dart';

class HomeMobileScreen extends StatefulWidget {
  const HomeMobileScreen({super.key});

  @override
  State<HomeMobileScreen> createState() => _HomeMobileScreenState();
}

class _HomeMobileScreenState extends State<HomeMobileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  // Add the user status manager instance
  final UserStatusManager _userStatusManager = UserStatusManager();
  bool _isLoading = false;
  List<DocumentSnapshot> _posts = [];
  DocumentSnapshot? _lastDocument;
  int _postsPerLoad = 10;
  bool _hasMorePosts = true;
  int _selectedIndex = 0;

  // Primary theme color
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  @override
  void initState() {
    super.initState();
    _initializePostsStream();
    _scrollController.addListener(_scrollListener);
    // Initialize the user status manager
    _userStatusManager.initialize();
  }

  void _initializePostsStream() {
    setState(() {
      _isLoading = true;
    });

    _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(_postsPerLoad)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _posts = snapshot.docs;
          _lastDocument = snapshot.docs.last;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasMorePosts = false;
          _isLoading = false;
        });
      }
    });
  }

  void _reportPost(String postId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore.collection('reports').add({
      'postId': postId,
      'reportedBy': currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Post berhasil dilaporkan')),
    );
  }

  void _sharePost(String postId, String content) {
    final shareText =
        "Lihat postingan menarik ini di Nusantara Social!\n\n$content\n\nLink: https://nusantara.social/post/$postId";

    Clipboard.setData(ClipboardData(text: shareText)).then((_) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 48, color: primaryColor),
                SizedBox(height: 12),
                Text(
                  "Tautan berhasil disalin!",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "Bagikan postingan ini ke temanmu dengan menempelkan tautan di pesan atau media sosial favoritmu.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: shareText));
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.copy, color: Colors.white),
                        label: Text(
                          "Salin Ulang",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: primaryColor),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    });
  }

  void _fetchMorePosts() async {
    if (!_hasMorePosts || _isLoading || _lastDocument == null) return;

    setState(() {
      _isLoading = true;
    });

    _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true) // Added missing ordering
        .startAfterDocument(_lastDocument!)
        .limit(_postsPerLoad)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _posts.addAll(snapshot.docs);
          _lastDocument = snapshot.docs.last;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasMorePosts = false;
          _isLoading = false;
        });
      }
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _fetchMorePosts();
    }
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _posts = [];
      _lastDocument = null;
      _hasMorePosts = true;
      // _fetchStories();
    });
    _initializePostsStream();
    return Future.delayed(Duration(milliseconds: 1500));
  }

  Future<DocumentSnapshot> _getUserData(String userId) async {
    return await _firestore.collection('users').doc(userId).get();
  }

  Future<void> _likePost(String postId, bool isLiked, List likes) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final postRef = _firestore.collection('posts').doc(postId);

    if (isLiked) {
      // Unlike the post
      await postRef.update({
        'likes': FieldValue.arrayRemove([currentUser.uid])
      });
    } else {
      // Like the post
      await postRef.update({
        'likes': FieldValue.arrayUnion([currentUser.uid])
      });
    }
  }

  String _getFormattedTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays >= 7) {
      return DateFormat('d MMM').format(date);
    } else if (difference.inDays >= 1) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'hari' : 'hari'} yang lalu';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'jam' : 'jam'} yang lalu';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'menit' : 'menit'} yang lalu';
    } else {
      return 'Baru Saja';
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    // Dispose the user status manager
    _userStatusManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Color(0xFFFFFBF8),
        appBar: _buildAppBar(),
        body: RefreshIndicator(
          onRefresh: _refreshPosts,
          color: primaryColor,
          child: _posts.isEmpty && !_isLoading
              ? _buildEmptyState()
              : Column(
                  children: [
                    StoryList(),
                    // Divider

                    // Posts section
                    Expanded(child: _buildPostsList()),
                  ],
                ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false, // <- menghapus ikon back
      elevation: 0,
      backgroundColor: Colors.white,
      centerTitle: false,
      toolbarHeight: 70,
      title: Row(
        children: [
          Text(
            "Nusantara",
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          Text(
            "Social",
            style: TextStyle(
              color: Color(0xFF212121),
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ),
      actions: [
        _buildAppBarButton(Icons.search_rounded, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return SearchUserScreen();
              },
            ),
          );
        }),
        SizedBox(width: 8),
        _buildAppBarButton(CupertinoIcons.chat_bubble, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return MessageListScreen();
              },
            ),
          );
        }),
        SizedBox(width: 12),
      ],
    );
  }

  Widget _buildAppBarButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: primaryColor,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.article_outlined,
                size: 64,
                color: primaryColor,
              ),
            ),
            SizedBox(height: 28),
            Text(
              "Belum Ada Postingan",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF212121),
              ),
            ),
            SizedBox(height: 16),
            Text(
              "Jadilah pemosting pertama di comunity terbesar di Indonesia",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF757575),
                height: 1.5,
              ),
            ),
            SizedBox(height: 36),
            ElevatedButton(
              onPressed: () {
                // Navigate to create post screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                "Posting",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .limit(_postsPerLoad)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final posts = snapshot.data!.docs;

        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(top: 12, bottom: 80),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final postData = posts[index].data() as Map<String, dynamic>;
            final postId = posts[index].id;
            final userId = postData['userId'] ?? '';

            final timestamp =
                postData['timestamp'] as Timestamp? ?? Timestamp.now();
            final date = _getFormattedTimestamp(timestamp);

            final content = postData['content'] ?? '';
            final imageUrl = postData['imageUrl'];
            final likes = postData['likes'] ?? [];
            final comments = postData['comments'] ?? [];
            final isLiked = _auth.currentUser != null &&
                likes.contains(_auth.currentUser!.uid);

            if (userId.isEmpty) {
              return SizedBox.shrink();
            }

            return FutureBuilder<DocumentSnapshot>(
              future: _getUserData(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildPostSkeleton();
                }

                if (!snapshot.hasData || snapshot.hasError) {
                  return SizedBox.shrink();
                }

                final userData = snapshot.data!.data() as Map<String, dynamic>?;

                if (userData == null) {
                  return SizedBox.shrink();
                }

                final userName = userData['name'] ?? 'Anonymous';
                final userProfilePic = userData['profilePicture'] ?? '';
                // final userId = userData['userId'] ?? '';

                return _buildPostCard(
                  postId,
                  userId,
                  userName,
                  userProfilePic,
                  date,
                  content,
                  imageUrl,
                  likes,
                  isLiked,
                  comments,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPostCard(
    String postId,
    String userId,
    String userName,
    String userProfilePic,
    String timeAgo,
    String content,
    String? imageUrl,
    List likes,
    bool isLiked,
    List comments,
  ) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        // borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      return UserDetailScreen(
                        userId: userId,
                      );
                    },
                  ),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(
                        color: primaryColor.withOpacity(0.2),
                        width: 2,
                      ),
                      image: userProfilePic.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(userProfilePic),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: userProfilePic.isEmpty
                        ? Icon(Icons.person, color: Colors.grey[400], size: 28)
                        : null,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF212121),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {},
                      child: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'report') {
                            _reportPost(postId);
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Text('Laporkan'),
                          ),
                        ],
                        icon: Icon(Icons.more_horiz),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (content.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFF424242),
                ),
              ),
            ),
          if (imageUrl != null && imageUrl.isNotEmpty)
            GestureDetector(
              onTap: () {
                // Show full image view
              },
              child: Container(
                margin: EdgeInsets.only(top: 12),
                height: 400,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  image: DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                _buildInteractionButton(
                  icon: isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  text: likes.length > 0 ? likes.length.toString() : "Like",
                  isActive: isLiked,
                  onTap: () => _likePost(postId, isLiked, likes),
                ),
                SizedBox(width: 20),
                _buildInteractionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  text: comments.length > 0
                      ? comments.length.toString()
                      : "Comment",
                  isActive: false,
                  onTap: () {
                    _showCommentBottomSheet(postId);
                  },
                ),
                Spacer(),
                _buildInteractionButton(
                  icon: Icons.share_outlined,
                  text: "Share",
                  isActive: false,
                  onTap: () => _sharePost(postId, content),
                  showText: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentBottomSheet(String postId) {
    final TextEditingController _commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AnimatedPadding(
          duration: Duration(milliseconds: 300),
          padding: MediaQuery.of(context).viewInsets,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.95,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Komentar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream:
                        _firestore.collection('posts').doc(postId).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return Center(child: CircularProgressIndicator());
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      final comments = List.from(data['comments'] ?? []);
                      return ListView.builder(
                        padding: EdgeInsets.all(16),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  child: Text(comment['name'][0].toUpperCase()),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        comment['name'] ?? '',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 4),
                                      Text(comment['comment'] ?? ''),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Tulis komentar...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.send, color: primaryColor),
                        onPressed: () async {
                          final user = _auth.currentUser;
                          if (user != null &&
                              _commentController.text.trim().isNotEmpty) {
                            final userData = await _firestore
                                .collection('users')
                                .doc(user.uid)
                                .get();
                            final newComment = {
                              'userId': user.uid,
                              'name': userData['name'] ?? 'Anonymous',
                              'comment': _commentController.text.trim(),
                              'timestamp': Timestamp.now(),
                            };
                            await _firestore
                                .collection('posts')
                                .doc(postId)
                                .update({
                              'comments': FieldValue.arrayUnion([newComment])
                            });
                            _commentController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInteractionButton({
    required IconData icon,
    required String text,
    required bool isActive,
    required VoidCallback onTap,
    bool showText = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                isActive ? primaryColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive ? primaryColor : Color(0xFF757575),
              ),
              if (showText) SizedBox(width: 8),
              if (showText)
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isActive ? primaryColor : Color(0xFF757575),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostSkeleton() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSkeletonCircle(50),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSkeletonLine(120, 16),
                    SizedBox(height: 8),
                    _buildSkeletonLine(80, 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildSkeletonLine(double.infinity, 14),
          SizedBox(height: 8),
          _buildSkeletonLine(double.infinity, 14),
          SizedBox(height: 8),
          _buildSkeletonLine(MediaQuery.of(context).size.width * 0.7, 14),
          SizedBox(height: 16),
          _buildSkeletonRectangle(double.infinity, 200),
          SizedBox(height: 16),
          Row(
            children: [
              _buildSkeletonLine(70, 30),
              SizedBox(width: 16),
              _buildSkeletonLine(90, 30),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildSkeletonLine(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildSkeletonRectangle(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: EdgeInsets.all(24),
      alignment: Alignment.center,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        strokeWidth: 3,
      ),
    );
  }
}
