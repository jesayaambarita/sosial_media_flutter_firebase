import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'user_detail_screen.dart';
import '../utils/user_status_utils.dart'; // Import the utils we created earlier

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({Key? key}) : super(key: key);

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  List<DocumentSnapshot> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  // Track following status for each user
  Map<String, bool> _followingStatus = {};

  // Primary theme color (matching your existing app)
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  @override
  void initState() {
    super.initState();
    _checkCurrentUserFollowing();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Check which users the current user is following
  Future<void> _checkCurrentUserFollowing() async {
    if (_auth.currentUser == null) return;

    try {
      final currentUserDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      final following =
          List<String>.from(currentUserDoc.data()?['following'] ?? []);

      setState(() {
        for (var userId in following) {
          _followingStatus[userId] = true;
        }
      });
    } catch (e) {
      print('Error checking following status: $e');
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      // Convert query to lowercase for case-insensitive search
      String lowercaseQuery = query.toLowerCase();

      // Search by name (case-insensitive)
      final querySnapshot = await _firestore
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: query + '\uf8ff')
          .get();

      // Search by email if needed
      final emailQuerySnapshot = await _firestore
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: query)
          .where('email', isLessThanOrEqualTo: query + '\uf8ff')
          .get();

      // Combine results and remove duplicates
      final Set<String> userIds = {};
      final List<DocumentSnapshot> combinedResults = [];

      for (var doc in querySnapshot.docs) {
        final userId = doc.id;
        if (!userIds.contains(userId) && userId != _auth.currentUser?.uid) {
          userIds.add(userId);
          combinedResults.add(doc);
        }
      }

      for (var doc in emailQuerySnapshot.docs) {
        final userId = doc.id;
        if (!userIds.contains(userId) && userId != _auth.currentUser?.uid) {
          userIds.add(userId);
          combinedResults.add(doc);
        }
      }

      setState(() {
        _searchResults = combinedResults;
        _isLoading = false;
      });

      // Update following status for search results
      _updateFollowingStatus();
    } catch (e) {
      print('Error searching users: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateFollowingStatus() async {
    if (_auth.currentUser == null) return;

    try {
      final currentUserDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      final following =
          List<String>.from(currentUserDoc.data()?['following'] ?? []);

      setState(() {
        for (var result in _searchResults) {
          final userId = result.id;
          _followingStatus[userId] = following.contains(userId);
        }
      });
    } catch (e) {
      print('Error updating following status: $e');
    }
  }

  // Format last seen timestamp for display
  String _formatLastSeen(Timestamp? lastSeen, bool isOnline) {
    if (isOnline) {
      return 'Online';
    }

    if (lastSeen == null) {
      return '';
    }

    return UserStatusUtils.formatLastSeen(lastSeen);
  }

  Future<void> _toggleFollow(String userId, String name) async {
    if (_auth.currentUser == null) return;

    final currentUserUid = _auth.currentUser!.uid;
    final isCurrentlyFollowing = _followingStatus[userId] ?? false;

    // Optimistically update UI
    setState(() {
      _followingStatus[userId] = !isCurrentlyFollowing;
    });

    try {
      final batch = _firestore.batch();

      // Current user document reference
      final currentUserRef = _firestore.collection('users').doc(currentUserUid);

      // Target user document reference
      final targetUserRef = _firestore.collection('users').doc(userId);

      if (isCurrentlyFollowing) {
        // Unfollow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayRemove([userId])
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
            margin: EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                // Undo unfollow action
                _toggleFollow(userId, name);
              },
            ),
          ),
        );
      } else {
        // Follow logic
        batch.update(currentUserRef, {
          'following': FieldValue.arrayUnion([userId])
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
            margin: EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Undo',
              textColor: Colors.white,
              onPressed: () {
                // Undo follow action
                _toggleFollow(userId, name);
              },
            ),
          ),
        );
      }

      await batch.commit();
    } catch (e) {
      // Revert state on error
      setState(() {
        _followingStatus[userId] = isCurrentlyFollowing;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to ${isCurrentlyFollowing ? 'unfollow' : 'follow'} $name'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.all(16),
        ),
      );

      print('Error toggling follow: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFFBF8),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Temukan Teman',
          style: TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: primaryColor,
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? _buildLoadingIndicator()
                : _hasSearched && _searchResults.isEmpty
                    ? _buildNoResultsFound()
                    : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name or email...',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, color: primaryColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[400]),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchResults = [];
                      _hasSearched = false;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
        ),
        onChanged: (value) {
          if (value.length > 2) {
            // Start search after 3 characters are typed
            _searchUsers(value);
          } else if (value.isEmpty) {
            setState(() {
              _searchResults = [];
              _hasSearched = false;
            });
          }
        },
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          if (value.isNotEmpty) {
            _searchUsers(value);
          }
        },
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
      ),
    );
  }

  Widget _buildNoResultsFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 72,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF424242),
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Try searching with a different name or email',
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

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final userData = _searchResults[index].data() as Map<String, dynamic>;
        final userId = _searchResults[index].id;
        final name = userData['name'] ?? 'No Name';
        final email = userData['email'] ?? 'No Email';
        final profilePicture = userData['profilePicture'] ?? '';
        final uid = userData['userId'] ?? '';
        final isFollowing = _followingStatus[userId] ?? false;

        // Get online status and last seen
        final isOnline = userData['isOnline'] ?? false;
        final lastSeen = userData['lastSeen'] as Timestamp?;

        return _buildUserListItem(
          userId: userId,
          name: name,
          email: email,
          profilePicture: profilePicture,
          uid: uid,
          isFollowing: isFollowing,
          isOnline: isOnline,
          lastSeen: lastSeen,
        );
      },
    );
  }

  Widget _buildUserListItem({
    required String userId,
    required String name,
    required String uid,
    required String email,
    required bool isFollowing,
    String profilePicture = '',
    bool isOnline = false,
    Timestamp? lastSeen,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Navigate to user profile
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
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                // Profile picture with online status indicator
                Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(
                          color: primaryColor.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: profilePicture.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: CachedNetworkImage(
                                imageUrl: profilePicture,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    valueColor:
                                        AlwaysStoppedAnimation(primaryColor),
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Icon(
                                  Icons.person,
                                  color: Colors.grey[400],
                                  size: 32,
                                ),
                              ),
                            )
                          : Icon(Icons.person,
                              color: Colors.grey[400], size: 32),
                    ),
                    // Online status indicator
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? Colors.green : Colors.grey,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 16),
                // User info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF212121),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF757575),
                        ),
                      ),
                      SizedBox(height: 4),
                      // Last seen status
                      Text(
                        _formatLastSeen(lastSeen, isOnline),
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isOnline ? Colors.green : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Follow/Following button
                InkWell(
                  onTap: () => _toggleFollow(userId, name),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isFollowing
                          ? Colors.grey[100]
                          : primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFollowing
                            ? Colors.grey[300]!
                            : primaryColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFollowing ? Icons.check : Icons.person_add_outlined,
                          color: isFollowing ? Colors.grey[600] : primaryColor,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                isFollowing ? Colors.grey[600] : primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
