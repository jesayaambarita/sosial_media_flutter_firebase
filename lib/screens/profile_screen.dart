import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/shared_preferences_service.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({
    Key? key,
    this.userId,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;

  // Primary theme color (matching your existing app)
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  // State variables
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  List<DocumentSnapshot> _userPosts = [];
  List<DocumentSnapshot> _likedPosts = []; // Added for liked posts
  bool _isCurrentUser = false;
  bool _isFollowing = false;
  int _followerCount = 0;
  int _followingCount = 0;
  int _postCount = 0;
  int _likedPostsCount = 0; // Added for liked posts count

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final String uid = widget.userId ?? _auth.currentUser!.uid;
      _isCurrentUser = uid == _auth.currentUser!.uid;

      // Fetch user data
      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (userDoc.exists) {
        setState(() {
          _userData = userDoc.data();
        });

        // Check if the current user is following this profile
        if (!_isCurrentUser && _auth.currentUser != null) {
          final currentUserDoc = await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .get();

          final following =
              List<String>.from(currentUserDoc.data()?['following'] ?? []);
          setState(() {
            _isFollowing = following.contains(uid);
          });
        }

        // Get follower and following counts
        final followers = List<String>.from(_userData?['followers'] ?? []);
        final following = List<String>.from(_userData?['following'] ?? []);

        setState(() {
          _followerCount = followers.length;
          _followingCount = following.length;
        });

        // Get user posts
        final postsQuery = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: uid)
            .get();

        setState(() {
          _userPosts = postsQuery.docs;
          _postCount = _userPosts.length;
        });

        // Get liked posts
        await _loadLikedPosts(uid);
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // New method to load liked posts
  Future<void> _loadLikedPosts(String uid) async {
    try {
      // First, get the user's liked posts IDs
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final likedPostIds = List<String>.from(userDoc.data()?['likes'] ?? []);

      // If there are no liked posts, return early
      if (likedPostIds.isEmpty) {
        setState(() {
          _likedPosts = [];
          _likedPostsCount = 0;
        });
        return;
      }

      // Fetch the posts in batches (Firestore has a limit on 'in' queries)
      List<DocumentSnapshot> allLikedPosts = [];

      // Process in batches of 10 (Firestore limitation)
      for (int i = 0; i < likedPostIds.length; i += 10) {
        final end =
            (i + 10 < likedPostIds.length) ? i + 10 : likedPostIds.length;
        final batch = likedPostIds.sublist(i, end);

        if (batch.isNotEmpty) {
          final batchQuery = await _firestore
              .collection('posts')
              .where(FieldPath.documentId, whereIn: batch)
              .get();

          allLikedPosts.addAll(batchQuery.docs);
        }
      }

      setState(() {
        _likedPosts = allLikedPosts;
        _likedPostsCount = allLikedPosts.length;
      });
    } catch (e) {
      print('Error loading liked posts: $e');
      setState(() {
        _likedPosts = [];
        _likedPostsCount = 0;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_auth.currentUser == null || _userData == null) return;

    final String uid = widget.userId!;
    final currentUserUid = _auth.currentUser!.uid;

    try {
      final batch = _firestore.batch();

      // Current user document reference
      final currentUserRef = _firestore.collection('users').doc(currentUserUid);

      // Target user document reference
      final targetUserRef = _firestore.collection('users').doc(uid);

      if (_isFollowing) {
        // Unfollow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayRemove([uid])
        });

        batch.update(targetUserRef, {
          'followers': FieldValue.arrayRemove([currentUserUid])
        });

        setState(() {
          _isFollowing = false;
          _followerCount--;
        });
      } else {
        // Follow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayUnion([uid])
        });

        batch.update(targetUserRef, {
          'followers': FieldValue.arrayUnion([currentUserUid])
        });

        setState(() {
          _isFollowing = true;
          _followerCount++;
        });
      }

      await batch.commit();
    } catch (e) {
      // Revert state on error
      setState(() {
        _isFollowing = !_isFollowing;
        _followerCount = _isFollowing ? _followerCount + 1 : _followerCount - 1;
      });
      print('Error toggling follow: $e');
    }
  }

  void _editProfile() {
    // Navigate to edit profile screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(),
      ),
    );

    // For now, show a snackbar
    // ScaffoldMessenger.of(context).showSnackBar(
    //   SnackBar(
    //     content: Text('Edit profile functionality to be implemented'),
    //     backgroundColor: primaryColor,
    //   ),
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFFBF8),
      body: _isLoading
          ? _buildLoadingSkeleton()
          : _userData == null
              ? _buildUserNotFound()
              : _buildProfileContent(),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
      ),
    );
  }

  Widget _buildUserNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 72,
            color: primaryColor,
          ),
          SizedBox(height: 16),
          Text(
            'User not found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'The user profile you are looking for doesn\'t exist',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          _buildAppBar(innerBoxIsScrolled),
          SliverToBoxAdapter(
            child: _buildProfileHeader(),
          ),
          SliverPersistentHeader(
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: primaryColor,
                indicatorWeight: 3,
                tabs: [
                  Tab(icon: Icon(Icons.grid_on_rounded)),
                  Tab(icon: Icon(Icons.bookmarks_outlined)),
                  Tab(
                      icon: Icon(Icons
                          .favorite_outlined)), // Changed to filled icon to show it's functional
                ],
              ),
            ),
            pinned: true,
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsGrid(),
          _buildSavedContent(),
          _buildLikedPostsGrid(), // Updated to show actual liked posts
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      backgroundColor: Colors.white,
      iconTheme: IconThemeData(
        color: primaryColor,
      ),
      title: Text(
        _userData?['name'] ?? 'Profile',
        style: TextStyle(
          color: Color(0xFF212121),
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: Icon(Icons.more_vert),
          onPressed: () {
            // Show options menu
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (context) => _buildOptionsBottomSheet(),
            );
          },
        ),
      ],
      floating: true,
      forceElevated: innerBoxIsScrolled,
      elevation: innerBoxIsScrolled ? 4 : 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Profile picture
              _buildProfilePicture(),

              SizedBox(width: 24),

              // Stats
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat("Postingan", _postCount),
                    _buildStat("Pengikut", _followerCount),
                    _buildStat("Mengikuti", _followingCount),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Name and bio
          Text(
            _userData?['name'] ?? 'User',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF212121),
            ),
          ),

          if (_userData?['bio'] != null && _userData!['bio'].isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                _userData!['bio'],
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF616161),
                  height: 1.4,
                ),
              ),
            ),

          if (_userData?['location'] != null &&
              _userData!['location'].isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Color(0xFF9E9E9E),
                  ),
                  SizedBox(width: 4),
                  Text(
                    _userData!['location'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(height: 16),

          // Action buttons
          _isCurrentUser ? _buildEditProfileButton() : _buildFollowButton(),
        ],
      ),
    );
  }

  Widget _buildProfilePicture() {
    final profileUrl = _userData?['profilePicture'] ?? '';

    return Stack(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[200],
            border: Border.all(
              color: primaryColor.withOpacity(0.2),
              width: 3,
            ),
            image: profileUrl.isNotEmpty
                ? DecorationImage(
                    image: CachedNetworkImageProvider(profileUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: profileUrl.isEmpty
              ? Icon(Icons.person, color: Colors.grey[400], size: 48)
              : null,
        ),
        // if (_isCurrentUser)
        //   Positioned(
        //     bottom: 0,
        //     right: 0,
        //     child: Container(
        //       padding: EdgeInsets.all(4),
        //       decoration: BoxDecoration(
        //         color: primaryColor,
        //         shape: BoxShape.circle,
        //         border: Border.all(color: Colors.white, width: 2),
        //       ),
        //       child: Icon(
        //         Icons.add_a_photo,
        //         color: Colors.white,
        //         size: 14,
        //       ),
        //     ),
        //   ),
      ],
    );
  }

  Widget _buildStat(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF212121),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF757575),
          ),
        ),
      ],
    );
  }

  Widget _buildEditProfileButton() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _editProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF212121),
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              elevation: 0,
            ),
            child: Text(
              'Edit Profile',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFollowButton() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ElevatedButton(
            onPressed: _toggleFollow,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFollowing ? Colors.white : primaryColor,
              foregroundColor: _isFollowing ? Color(0xFF212121) : Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _isFollowing ? Colors.grey[300]! : primaryColor,
                ),
              ),
              elevation: 0,
            ),
            child: Text(
              _isFollowing ? 'Following' : 'Follow',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: ElevatedButton(
            onPressed: () {
              // Send message
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF212121),
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              elevation: 0,
            ),
            child: Icon(Icons.message_outlined, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildPostsGrid() {
    if (_userPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No Posts Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF424242),
              ),
            ),
            SizedBox(height: 8),
            Text(
              _isCurrentUser
                  ? 'Share your first post with the community!'
                  : 'This user hasn\'t posted anything yet.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF757575),
              ),
            ),
          ],
        ),
      );
    } else {
      return GridView.builder(
        padding: EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: _userPosts.length,
        itemBuilder: (context, index) {
          final post = _userPosts[index].data() as Map<String, dynamic>;
          final hasImage =
              post['imageUrl'] != null && post['imageUrl'].isNotEmpty;

          return InkWell(
            onTap: () {
              // Navigate to post detail
            },
            child: Container(
              color: Colors.grey[200],
              child: hasImage
                  ? CachedNetworkImage(
                      imageUrl: post['imageUrl'],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(primaryColor),
                          strokeWidth: 2,
                        ),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.image_not_supported,
                            color: Colors.grey[400]),
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          post['content'] ?? '',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF616161),
                          ),
                        ),
                      ),
                    ),
            ),
          );
        },
      );
    }
  }

  Widget _buildSavedContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'Saved Posts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF424242),
            ),
          ),
          SizedBox(height: 8),
          Text(
            _isCurrentUser
                ? 'Posts you save will appear here'
                : 'This user\'s saved posts are private',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  // Updated to display actual liked posts
  Widget _buildLikedPostsGrid() {
    // If viewing another user's profile and they have privacy settings or not current user
    if (!_isCurrentUser) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'Liked Posts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF424242),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This user\'s liked posts are private',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF757575),
              ),
            ),
          ],
        ),
      );
    }

    // For current user
    if (_likedPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No Liked Posts Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF424242),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Posts you like will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF757575),
              ),
            ),
          ],
        ),
      );
    } else {
      return GridView.builder(
        padding: EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: _likedPosts.length,
        itemBuilder: (context, index) {
          final post = _likedPosts[index].data() as Map<String, dynamic>;
          final hasImage =
              post['imageUrl'] != null && post['imageUrl'].isNotEmpty;

          return InkWell(
            onTap: () {
              // Navigate to post detail
              // You could add navigation to the post detail here
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.grey[200],
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: post['imageUrl'],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Center(
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(primaryColor),
                              strokeWidth: 2,
                            ),
                          ),
                          errorWidget: (context, url, error) => Center(
                            child: Icon(Icons.image_not_supported,
                                color: Colors.grey[400]),
                          ),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              post['content'] ?? '',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF616161),
                              ),
                            ),
                          ),
                        ),
                ),
                // Optional: Show a heart icon overlay to indicate it's a liked post
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildOptionsBottomSheet() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 24),
          if (_isCurrentUser) ...[
            _buildOptionTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                // Navigate to settings
              },
            ),
            _buildOptionTile(
              icon: Icons.person_add_outlined,
              title: 'Find People to Follow',
              onTap: () {
                Navigator.pop(context);
                // Navigate to suggestions
              },
            ),
            _buildOptionTile(
              icon: Icons.share_outlined,
              title: 'Share Profile',
              onTap: () {
                Navigator.pop(context);
                // Share profile
              },
            ),
            _buildOptionTile(
              icon: Icons.logout,
              title: 'Log Out',
              isDestructive: true,
              onTap: () async {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) {
                    return LoginScreen();
                  },
                ));
                // await _auth.signOut();
                // Hapus data dari SharedPreferences
                await SharedPreferencesService.logout();
              },
            ),
          ] else ...[
            _buildOptionTile(
              icon: Icons.block_outlined,
              title: 'Block User',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                // Block user
              },
            ),
            _buildOptionTile(
              icon: Icons.flag_outlined,
              title: 'Report User',
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                // Report user
              },
            ),
            _buildOptionTile(
              icon: Icons.share_outlined,
              title: 'Share Profile',
              onTap: () {
                Navigator.pop(context);
                // Share profile
              },
            ),
          ],
          SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[100],
                foregroundColor: Color(0xFF212121),
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : Color(0xFF616161),
              size: 24,
            ),
            SizedBox(width: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDestructive ? Colors.red : Color(0xFF212121),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// For the sticky tab bar
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
