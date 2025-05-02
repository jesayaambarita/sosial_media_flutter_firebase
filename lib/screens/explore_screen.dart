import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_status_manager.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({Key? key}) : super(key: key);

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _posts = [];
  DocumentSnapshot? _lastDocument;
  // Add the user status manager instance
  final UserStatusManager _userStatusManager = UserStatusManager();
  int _postsPerLoad = 15;
  bool _isLoading = false;
  bool _hasMorePosts = true;

  // Primary theme color
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _scrollController.addListener(_scrollListener);
    // Initialize the user status manager
    // _userStatusManager.initialize();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    // Dispose the user status manager
    // _userStatusManager.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _fetchMorePosts();
    }
  }

  Future<void> _fetchPosts() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('posts')
          .orderBy('timestamp', descending: true)
          // .limit(_postsPerLoad)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _posts = snapshot.docs;
          _lastDocument = snapshot.docs.last;
        });
      } else {
        setState(() {
          _hasMorePosts = false;
        });
      }
    } catch (e) {
      print('Error fetching posts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMorePosts() async {
    if (_isLoading || !_hasMorePosts || _lastDocument == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocument!)
          // .limit(_postsPerLoad)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _posts.addAll(snapshot.docs);
          _lastDocument = snapshot.docs.last;
        });
      } else {
        setState(() {
          _hasMorePosts = false;
        });
      }
    } catch (e) {
      print('Error fetching more posts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _posts = [];
      _lastDocument = null;
      _hasMorePosts = true;
    });

    await _fetchPosts();
    return Future.delayed(Duration(milliseconds: 1000));
  }

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      return userDoc.data() as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching user data: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFFBF8),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          "Explore",
          style: TextStyle(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: primaryColor),
            onPressed: () {},
          ),
          SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPosts,
        color: primaryColor,
        child: _posts.isEmpty && !_isLoading
            ? _buildEmptyState()
            : _buildPostsGrid(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore_off_outlined,
            size: 72,
            color: primaryColor.withOpacity(0.7),
          ),
          SizedBox(height: 24),
          Text(
            "Tidak ada postingan",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 12),
          Text(
            "Cek kembali konten terbaru",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _posts.length + (_hasMorePosts ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _posts.length) {
          return _buildLoadingIndicator();
        }

        final post = _posts[index].data() as Map<String, dynamic>;
        final userId = post['userId'] as String?;
        final imageUrl = post['imageUrl'] as String?;

        if (userId == null) {
          return SizedBox.shrink();
        }

        return FutureBuilder<Map<String, dynamic>?>(
          future: _getUserData(userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildPostSkeleton();
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return SizedBox.shrink();
            }

            final userData = snapshot.data!;
            final userProfilePic = userData['profilePicture'] as String?;

            return GestureDetector(
              onTap: () {
                // Navigate to post detail screen
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Post background
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      image: imageUrl != null && imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                      gradient: imageUrl == null || imageUrl.isEmpty
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                primaryColor.withOpacity(0.3),
                                primaryColor.withOpacity(0.1),
                              ],
                            )
                          : null,
                    ),
                  ),

                  // Profile picture centered
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                        image:
                            userProfilePic != null && userProfilePic.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(userProfilePic),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                      ),
                      child: userProfilePic == null || userProfilePic.isEmpty
                          ? Icon(Icons.person,
                              color: Colors.grey[400], size: 36)
                          : null,
                    ),
                  ),

                  // Gradient overlay for better visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                        ],
                        stops: [0.7, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPostSkeleton() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey[300],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          strokeWidth: 2,
        ),
      ),
    );
  }
}
