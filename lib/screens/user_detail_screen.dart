import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/user_status_utils.dart';
import 'chat_screen.dart';

class UserDetailScreen extends StatefulWidget {
  final String userId;

  const UserDetailScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Primary theme color (matching your existing app)
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  // User data
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  bool _isFollowing = false;
  int _followerCount = 0;
  int _followingCount = 0;
  int _postCount = 0;
  List<Map<String, dynamic>> _userPosts = [];

  // Stream subscription for real-time updates
  StreamSubscription<DocumentSnapshot>? _userStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialUserData();
    _setupUserStream();
  }

  @override
  void dispose() {
    _userStreamSubscription?.cancel();
    super.dispose();
  }

  // Load initial user data
  Future<void> _loadInitialUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadUserPosts();
      await _checkFollowingStatus();
    } catch (e) {
      print('Error loading initial user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load user data: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Setup real-time stream for user data
  void _setupUserStream() {
    _userStreamSubscription = _firestore
        .collection('users')
        .doc(widget.userId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _userData = snapshot.data() as Map<String, dynamic>;
          _followerCount = List.from(_userData?['followers'] ?? []).length;
          _followingCount = List.from(_userData?['following'] ?? []).length;
        });
      }
    }, onError: (error) {
      print('Error with user stream: $error');
    });
  }

  // Check following status
  Future<void> _checkFollowingStatus() async {
    if (_auth.currentUser != null) {
      final currentUserDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();
      final following = List.from(currentUserDoc.data()?['following'] ?? []);
      setState(() {
        _isFollowing = following.contains(widget.userId);
      });
    }
  }

  // Load user posts
  Future<void> _loadUserPosts() async {
    try {
      final postsSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .get();

      final posts = postsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _userPosts = List<Map<String, dynamic>>.from(posts);
        _postCount = posts.length;
      });
    } catch (e) {
      print('Error loading user posts: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (_auth.currentUser == null || _userData == null) return;

    final currentUserUid = _auth.currentUser!.uid;
    final name = _userData!['name'] ?? 'this user';
    final isCurrentlyFollowing = _isFollowing;

    // Optimistically update UI
    setState(() {
      _isFollowing = !isCurrentlyFollowing;
      _followerCount += isCurrentlyFollowing ? -1 : 1;
    });

    try {
      final batch = _firestore.batch();

      // Current user document reference
      final currentUserRef = _firestore.collection('users').doc(currentUserUid);

      // Target user document reference
      final targetUserRef = _firestore.collection('users').doc(widget.userId);

      if (isCurrentlyFollowing) {
        // Unfollow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayRemove([widget.userId])
        });

        batch.update(targetUserRef, {
          'followers': FieldValue.arrayRemove([currentUserUid])
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You unfollowed $name'),
            backgroundColor: primaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                // Undo unfollow action
                _toggleFollow();
              },
            ),
          ),
        );
      } else {
        // Follow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayUnion([widget.userId])
        });

        batch.update(targetUserRef, {
          'followers': FieldValue.arrayUnion([currentUserUid])
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are now following $name'),
            backgroundColor: primaryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                // Undo follow action
                _toggleFollow();
              },
            ),
          ),
        );
      }

      await batch.commit();
    } catch (e) {
      // Revert state on error
      setState(() {
        _isFollowing = isCurrentlyFollowing;
        _followerCount += isCurrentlyFollowing ? 0 : -1;
      });

      print('Error toggling follow: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to ${isCurrentlyFollowing ? 'unfollow' : 'follow'} $name'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF8),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _userData?['name'] ?? 'User Profile',
          style: const TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: primaryColor,
        ),
        actions: [
          if (_auth.currentUser != null &&
              _auth.currentUser!.uid != widget.userId &&
              !_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: InkWell(
                onTap: _userData == null ? null : _toggleFollow,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _isFollowing
                        ? Colors.grey[100]
                        : primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isFollowing
                          ? Colors.grey[300]!
                          : primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFollowing ? Icons.check : Icons.person_add_outlined,
                        color: _isFollowing ? Colors.grey[600] : primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isFollowing ? 'Following' : 'Follow',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _isFollowing ? Colors.grey[600] : primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            )
          : _userData == null
              ? _buildUserNotFound()
              : _buildUserProfile(),
    );
  }

  Widget _buildUserNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 72,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'User not found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF424242),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'This user may have deleted their account or does not exist',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF757575),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfile() {
    final name = _userData!['name'] ?? 'No Name';
    final email = _userData!['email'] ?? 'No Email';
    final bio = _userData!['bio'] ?? '';
    final profilePicture = _userData!['profilePicture'] ?? '';
    final joinDate = _userData!['createdAt'] != null
        ? ((_userData!['createdAt'] as Timestamp).toDate())
        : null;

    // Online status data
    final isOnline = _userData!['isOnline'] == true;
    final lastSeen = _userData!['lastSeen'] as Timestamp?;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Profile picture with online status indicator
                Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(
                          color: primaryColor.withOpacity(0.2),
                          width: 3,
                        ),
                      ),
                      child: profilePicture.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(50),
                              child: CachedNetworkImage(
                                imageUrl: profilePicture,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        primaryColor),
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Icon(
                                  Icons.person,
                                  color: Colors.grey[400],
                                  size: 50,
                                ),
                              ),
                            )
                          : Icon(Icons.person,
                              color: Colors.grey[400], size: 50),
                    ),
                    // Online status indicator
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? Colors.green : Colors.grey,
                          border: Border.all(
                            color: Colors.white,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // User name
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),

                const SizedBox(height: 4),

                // User email
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF757575),
                  ),
                ),

                const SizedBox(height: 6),

                // Online status text
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      UserStatusUtils.getOnlineStatusText(isOnline, lastSeen),
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: isOnline ? Colors.green : Colors.grey[600],
                      ),
                    ),
                  ],
                ),

                if (bio.isNotEmpty) const SizedBox(height: 12),

                // Bio
                if (bio.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      bio,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF424242),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 20),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem('Postingan', _postCount),
                    _buildStatItem('Pengikut', _followerCount),
                    _buildStatItem('Mengikuti', _followingCount),
                  ],
                ),

                // Replace the existing Container for "Kirim pesan" button with this:
                Container(
                  margin: EdgeInsets.only(top: 20),
                  width: MediaQuery.sizeOf(context).width,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Color.fromARGB(255, 153, 51, 0),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            userId: widget.userId,
                            userName: _userData!['name'] ?? 'User',
                            isOnline: _userData!['isOnline'] == true,
                            lastSeen: _userData!['lastSeen'] as Timestamp?,
                            profilePicture: _userData!['profilePicture'],
                          ),
                        ),
                      );
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.chat_bubble_2,
                          color: Colors.white,
                        ),
                        SizedBox(
                          width: 10,
                        ),
                        Text(
                          "Kirim pesan",
                          style: TextStyle(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (joinDate != null) const SizedBox(height: 16),

                // Join date
                if (joinDate != null)
                  Text(
                    'Joined ${DateFormat.yMMMd().format(joinDate)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9E9E9E),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Posts section title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Postingan Terakhir',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121),
                  ),
                ),
                const Spacer(),
                // Refresh posts button
                IconButton(
                  icon: Icon(Icons.refresh, color: primaryColor),
                  onPressed: _loadUserPosts,
                  tooltip: 'Refresh posts',
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Posts list
          _userPosts.isEmpty
              ? _buildNoPosts()
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _userPosts.length,
                  itemBuilder: (context, index) {
                    return _buildPostItem(_userPosts[index]);
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF757575),
          ),
        ),
      ],
    );
  }

  Widget _buildNoPosts() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'Tidak ada postingan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF424242),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pengguna ini tidak memposting apapun',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> post) {
    final timestamp = (post['timestamp'] as Timestamp).toDate();
    final content = post['content'] ?? '';
    final imageUrl = post['imageUrl'] ?? '';
    final likes = post['likes'] != null ? (post['likes'] as List).length : 0;
    final comments = post['commentCount'] ?? 0;

    return Container(
      // margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        // borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[200],
                    border: Border.all(
                      color: primaryColor.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: _userData?['profilePicture'] != null &&
                          _userData!['profilePicture'].isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CachedNetworkImage(
                            imageUrl: _userData!['profilePicture'],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(primaryColor),
                                strokeWidth: 2,
                              ),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              Icons.person,
                              color: Colors.grey[400],
                              size: 24,
                            ),
                          ),
                        )
                      : Icon(Icons.person, color: Colors.grey[400], size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userData?['name'] ?? 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF212121),
                        ),
                      ),
                      Text(
                        DateFormat.yMMMd().add_jm().format(timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Post content
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF424242),
                ),
              ),
            ),

          // Post image if any
          if (imageUrl.isNotEmpty)
            Container(
              constraints: const BoxConstraints(
                maxHeight: 300,
              ),
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    strokeWidth: 2,
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Icon(Icons.error, color: Colors.grey[400]),
                ),
              ),
            ),

          // Post stats
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '$likes',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF757575),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.comment,
                  color: Colors.grey[600],
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '$comments',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF757575),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
