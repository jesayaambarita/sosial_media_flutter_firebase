import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../utils/user_status_utils.dart';
// import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final bool isOnline;
  final Timestamp? lastSeen;
  final String? profilePicture;

  const ChatScreen({
    Key? key,
    required this.userId,
    required this.userName,
    required this.isOnline,
    this.lastSeen,
    this.profilePicture,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // App theme colors
  final Color primaryColor = const Color(0xFF5E35B1); // Deep purple
  final Color secondaryColor = const Color(0xFF9575CD); // Lighter purple
  final Color backgroundColor = const Color(0xFFF5F5F5); // Light background
  final Color accentColor = const Color(0xFF4CAF50); // Green for online status

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  StreamSubscription? _messagesSubscription;
  String? _chatId;
  AnimationController? _sendButtonController;

  // Message selection state
  bool _isSelectionMode = false;
  Set<String> _selectedMessageIds = {};
  AnimationController? _selectionController;
  Animation<double>? _selectionAnimation;

  @override
  void initState() {
    super.initState();
    _setupChat();
    _sendButtonController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Selection mode animation controller
    _selectionController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _selectionAnimation = CurvedAnimation(
      parent: _selectionController!,
      curve: Curves.easeInOut,
    );

    _messageController.addListener(() {
      setState(() {
        _isTyping = _messageController.text.trim().isNotEmpty;
      });
      if (_isTyping) {
        _sendButtonController!.forward();
      } else {
        _sendButtonController!.reverse();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    _sendButtonController?.dispose();
    _selectionController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Create or find existing chat
  Future<void> _setupChat() async {
    if (_auth.currentUser == null) return;

    final currentUserId = _auth.currentUser!.uid;

    setState(() {
      _isLoading = true;
    });

    try {
      // Find if chat already exists between these two users
      final existingChatQuery = await _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUserId)
          .get();

      // Look for a chat that has both current user and target user
      for (var doc in existingChatQuery.docs) {
        final participants = List<String>.from(doc['participants'] ?? []);
        if (participants.contains(widget.userId)) {
          _chatId = doc.id;
          break;
        }
      }

      // If no chat exists, create a new one
      if (_chatId == null) {
        final newChatRef = _firestore.collection('chats').doc();

        await newChatRef.set({
          'participants': [currentUserId, widget.userId],
          'lastMessage': null,
          'lastMessageTime': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _chatId = newChatRef.id;
      }

      // Setup messages listener
      _listenToMessages();

      // Mark messages as read
      _markMessagesAsRead();
    } catch (e) {
      print('Error setting up chat: $e');
      _showSnackBar('Failed to load chat', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _listenToMessages() {
    if (_chatId == null) return;

    _messagesSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _messages = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });

        // Scroll to bottom with slight delay to ensure list is built
        if (_messages.isNotEmpty) {
          _scrollToBottom(animate: true);
        }
      }
    });
  }

  void _markMessagesAsRead() async {
    if (_chatId == null || _auth.currentUser == null) return;

    final currentUserId = _auth.currentUser!.uid;
    final batch = _firestore.batch();

    try {
      // Modified query to avoid the index issue
      // Remove the order by senderId, which is causing the problem
      final unreadMessages = await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId)
          .where('read', isEqualTo: false)
          .get();

      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {'read': true});
      }

      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
      // Do not show error to user as this is a background operation
    }
  }

  void _scrollToBottom({bool animate = false}) {
    if (!_scrollController.hasClients) return;

    if (animate) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    } else {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty ||
        _chatId == null ||
        _auth.currentUser == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Haptic feedback
    HapticFeedback.lightImpact();

    try {
      final currentUserId = _auth.currentUser!.uid;
      final timestamp = FieldValue.serverTimestamp();

      // Optimistic update - show the message immediately
      setState(() {
        _messages.insert(0, {
          'senderId': currentUserId,
          'text': messageText,
          'timestamp': Timestamp.now(),
          'read': false,
          'id': 'temp-${DateTime.now().millisecondsSinceEpoch}',
          'sending': true,
        });
      });

      // Add message to the chat
      final docRef = await _firestore
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'text': messageText,
        'timestamp': timestamp,
        'read': false,
      });

      // Update the last message in the chat document
      await _firestore.collection('chats').doc(_chatId).update({
        'lastMessage': messageText,
        'lastMessageTime': timestamp,
        'lastSenderId': currentUserId,
        'updatedAt': timestamp,
      });

      // Remove the optimistic message and let the stream update
      setState(() {
        _messages.removeWhere((msg) => msg['sending'] == true);
      });
    } catch (e) {
      print('Error sending message: $e');
      _showSnackBar('Failed to send message', isError: true);

      // Remove the optimistic message on error
      setState(() {
        _messages.removeWhere((msg) => msg['sending'] == true);
      });
    }
  }

  // Message selection methods
  void _toggleMessageSelection(String messageId) {
    HapticFeedback.mediumImpact();

    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _exitSelectionMode();
        }
      } else {
        if (!_isSelectionMode) {
          _enterSelectionMode();
        }
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
    });
    _selectionController!.forward();
  }

  void _exitSelectionMode() {
    _selectionController!.reverse().then((_) {
      setState(() {
        _isSelectionMode = false;
        _selectedMessageIds.clear();
      });
    });
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty || _chatId == null) return;

    final messagesToDelete = List<String>.from(_selectedMessageIds);

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Pesan'),
        content: Text(
          'Apakah Anda yakin ingin menghapus ${messagesToDelete.length} pesan terpilih?',
        ),
        actions: [
          TextButton(
            child: const Text('BATAL'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text(
              'HAPUS',
              style: TextStyle(color: Colors.red),
            ),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );

    if (shouldDelete != true) return;

    try {
      final batch = _firestore.batch();

      for (var messageId in messagesToDelete) {
        final messageRef = _firestore
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .doc(messageId);

        batch.delete(messageRef);
      }

      await batch.commit();

      // If we deleted the most recent message, update the chat's lastMessage
      if (_messages.any(
          (m) => messagesToDelete.contains(m['id']) && m == _messages.first)) {
        // Find the next most recent message that wasn't deleted
        final remainingMessages = _messages
            .where((m) => !messagesToDelete.contains(m['id']))
            .toList();

        if (remainingMessages.isNotEmpty) {
          final lastMessage = remainingMessages.first;
          await _firestore.collection('chats').doc(_chatId).update({
            'lastMessage': lastMessage['text'],
            'lastMessageTime': lastMessage['timestamp'],
            'lastSenderId': lastMessage['senderId'],
          });
        } else {
          // No messages left
          await _firestore.collection('chats').doc(_chatId).update({
            'lastMessage': null,
            'lastMessageTime': null,
            'lastSenderId': null,
          });
        }
      }

      _exitSelectionMode();
      _showSnackBar('Pesan berhasil dihapus');
    } catch (e) {
      print('Error deleting messages: $e');
      _showSnackBar('Gagal menghapus pesan', isError: true);
    }
  }

  void _copySelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    // Get all selected messages text
    final selectedMessages = _messages
        .where((m) => _selectedMessageIds.contains(m['id']))
        .map((m) => m['text'] as String)
        .toList();

    // Sort by their position in the original messages list
    selectedMessages.sort((a, b) {
      final indexA = _messages.indexWhere((m) => m['text'] == a);
      final indexB = _messages.indexWhere((m) => m['text'] == b);
      return indexB.compareTo(
          indexA); // Reverse because messages are in descending order
    });

    // Join with newlines
    final textToCopy = selectedMessages.join('\n\n');

    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: textToCopy));

    _exitSelectionMode();
    _showSnackBar('Pesan disalin ke clipboard');
  }

  void _shareSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    // Get all selected messages text
    final selectedMessages = _messages
        .where((m) => _selectedMessageIds.contains(m['id']))
        .map((m) => m['text'] as String)
        .toList();

    // Join with newlines
    final textToShare = selectedMessages.join('\n\n');

    // For now, just copy to clipboard as share functionality would require a plugin
    Clipboard.setData(ClipboardData(text: textToShare));

    _exitSelectionMode();
    _showSnackBar(
        'Fitur bagikan akan datang segera. Pesan disalin ke clipboard.');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildAppBar(),
        body: _isLoading
            ? _buildLoadingIndicator()
            : Column(
                children: [
                  // Chat date header
                  if (_messages.isNotEmpty) _buildDateHeader(),

                  // Messages list
                  Expanded(
                    child: _messages.isEmpty
                        ? _buildEmptyChat()
                        : _buildMessageList(),
                  ),

                  // Message input
                  if (!_isSelectionMode) _buildMessageInput(),
                ],
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: primaryColor),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          // User avatar with online indicator
          Stack(
            children: [
              Hero(
                tag: 'profile-${widget.userId}',
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: widget.profilePicture != null &&
                          widget.profilePicture!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: CachedNetworkImage(
                            imageUrl: widget.profilePicture!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                      : Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ),
              // Online status indicator
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isOnline ? accentColor : Colors.grey,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // User name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Color(0xFF212121),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  UserStatusUtils.getOnlineStatusText(
                      widget.isOnline, widget.lastSeen),
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isOnline ? accentColor : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (context) {
              //       return CallScreen(
              //         userId: widget.userId,
              //         userName: widget.userName,
              //         isVideo: false,
              //       );
              //     },
              //   ),
              // );
            },
            child: Icon(
              Icons.call,
              color: primaryColor,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.more_vert, color: primaryColor),
          onPressed: () {
            _showChatOptions();
          },
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: primaryColor,
      elevation: 4,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '${_selectedMessageIds.length} terpilih',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy, color: Colors.white),
          onPressed: _copySelectedMessages,
          tooltip: 'Salin',
        ),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white),
          onPressed: _shareSelectedMessages,
          tooltip: 'Bagikan',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white),
          onPressed: _deleteSelectedMessages,
          tooltip: 'Hapus',
        ),
      ],
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
              margin: const EdgeInsets.only(bottom: 20),
            ),
            _buildOptionTile(
              icon: Icons.search,
              title: 'Cari Pesan',
              onTap: () {
                Navigator.pop(context);
                // Implement search functionality
              },
            ),
            _buildOptionTile(
              icon: Icons.notifications_off_outlined,
              title: 'Bisukan Notifikasi',
              onTap: () {
                Navigator.pop(context);
                // Implement mute functionality
              },
            ),
            _buildOptionTile(
              icon: Icons.delete_outline,
              title: 'Hapus Percakapan',
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteChat();
              },
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : primaryColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _confirmDeleteChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Percakapan'),
        content: const Text(
          'Apakah Anda yakin ingin menghapus seluruh riwayat percakapan? Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            child: const Text('BATAL'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text(
              'HAPUS',
              style: TextStyle(color: Colors.red),
            ),
            onPressed: () {
              Navigator.pop(context);
              // Implement delete functionality
              _showSnackBar('Fitur hapus percakapan akan datang segera');
            },
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Memuat pesan...',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader() {
    // Show date for the first message that's visible
    if (_messages.isEmpty) return const SizedBox.shrink();

    final firstMsgTimestamp = _messages.first['timestamp'] as Timestamp?;
    if (firstMsgTimestamp == null) return const SizedBox.shrink();

    final date = firstMsgTimestamp.toDate();
    final now = DateTime.now();

    String dateText;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      dateText = 'Hari Ini';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      dateText = 'Kemarin';
    } else {
      dateText = DateFormat('d MMMM yyyy').format(date);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            dateText,
            style: TextStyle(
              color: primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withOpacity(0.1),
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 60,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Belum ada pesan',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Mulai percakapan dengan ${widget.userName} sekarang',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              _focusNode.requestFocus();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
            ),
            child: const Text(
              'Mulai Chat',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isFirstMessage = index == _messages.length - 1;
        final isLastMessage = index == 0;
        final messageId = message['id'] as String;
        final isSelected = _selectedMessageIds.contains(messageId);

        // Check if previous message is from same sender
        bool showAvatar = true;
        if (index < _messages.length - 1) {
          final prevMessage = _messages[index + 1];
          if (prevMessage['senderId'] == message['senderId']) {
            showAvatar = false;
          }
        }

        // Check if next message is from same sender (for grouping)
        bool isLastInGroup = true;
        if (index > 0) {
          final nextMessage = _messages[index - 1];
          if (nextMessage['senderId'] == message['senderId']) {
            isLastInGroup = false;
          }
        }

        return _buildMessageItem(
          message,
          isFirstMessage: isFirstMessage,
          isLastMessage: isLastMessage,
          showAvatar: showAvatar,
          isLastInGroup: isLastInGroup,
          isSelected: isSelected,
        );
      },
    );
  }

  Widget _buildMessageItem(
    Map<String, dynamic> message, {
    required bool isFirstMessage,
    required bool isLastMessage,
    required bool showAvatar,
    required bool isLastInGroup,
    required bool isSelected,
  }) {
    final isCurrentUser = message['senderId'] == _auth.currentUser?.uid;
    final timestamp = message['timestamp'] as Timestamp?;
    final text = message['text'] ?? '';
    final isSending = message['sending'] == true;
    final isRead = message['read'] == true;
    final messageId = message['id'] as String;

    return GestureDetector(
      onLongPress: () {
        if (!isSending) {
          _toggleMessageSelection(messageId);
        }
      },
      onTap: () {
        if (_isSelectionMode && !isSending) {
          _toggleMessageSelection(messageId);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color:
              isSelected ? primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisAlignment:
                isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for sender (only for received messages)
              if (!isCurrentUser && showAvatar)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: widget.profilePicture != null &&
                          widget.profilePicture!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: widget.profilePicture!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        )
                      : const Icon(Icons.person, color: Colors.white, size: 16),
                )
              else if (!isCurrentUser && !showAvatar)
                const SizedBox(width: 36),

              // Message bubble with selection indicator
              Flexible(
                child: Stack(
                  children: [
                    // Selection indicator
                    if (_isSelectionMode)
                      Positioned(
                        top: 0,
                        right: isCurrentUser ? 0 : null,
                        left: isCurrentUser ? null : 0,
                        child: ScaleTransition(
                          scale: _selectionAnimation!,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? primaryColor : Colors.white,
                              border: Border.all(
                                color: primaryColor,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),

                    // Message content
                    Container(
                      margin: EdgeInsets.only(
                        top: _isSelectionMode ? 12 : 0,
                        right: isCurrentUser ? 0 : 8,
                        left: isCurrentUser ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isCurrentUser ? primaryColor : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isCurrentUser
                              ? const Radius.circular(16)
                              : (isLastInGroup
                                  ? const Radius.circular(4)
                                  : const Radius.circular(16)),
                          bottomRight: isCurrentUser
                              ? (isLastInGroup
                                  ? const Radius.circular(4)
                                  : const Radius.circular(16))
                              : const Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isCurrentUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          // Message text
                          Text(
                            text,
                            style: TextStyle(
                              color:
                                  isCurrentUser ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Timestamp and read status
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timestamp != null
                                    ? DateFormat('HH:mm')
                                        .format(timestamp.toDate())
                                    : 'Mengirim...',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCurrentUser
                                      ? Colors.white.withOpacity(0.7)
                                      : Colors.black54,
                                ),
                              ),
                              if (isCurrentUser) ...[
                                const SizedBox(width: 4),
                                isSending
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                          strokeWidth: 1.5,
                                        ),
                                      )
                                    : Icon(
                                        isRead ? Icons.done_all : Icons.done,
                                        size: 14,
                                        color: isRead
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.7),
                                      ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -1),
            blurRadius: 4,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attachment button
            IconButton(
              icon: Icon(
                Icons.add_circle_outline,
                color: primaryColor,
                size: 26,
              ),
              onPressed: () {
                _showAttachmentOptions();
              },
            ),
            // Text input field
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Ketik pesan...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            // Send button with animation
            AnimatedBuilder(
              animation: _sendButtonController!,
              builder: (context, child) {
                return IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _isTyping
                        ? Icon(
                            Icons.send,
                            key: const ValueKey('send'),
                            color: primaryColor,
                            size: 26,
                          )
                        : Icon(
                            Icons.mic,
                            key: const ValueKey('mic'),
                            color: primaryColor,
                            size: 26,
                          ),
                  ),
                  onPressed: () {
                    if (_isTyping) {
                      _sendMessage();
                    } else {
                      // Voice message functionality
                      _showSnackBar('Fitur pesan suara akan datang segera');
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
              margin: const EdgeInsets.only(bottom: 24),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo,
                  color: Colors.green,
                  label: 'Foto',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur kirim foto akan datang segera');
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.camera_alt,
                  color: Colors.blue,
                  label: 'Kamera',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur kamera akan datang segera');
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.insert_drive_file,
                  color: Colors.amber,
                  label: 'Dokumen',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur kirim dokumen akan datang segera');
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.location_on,
                  color: Colors.red,
                  label: 'Lokasi',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur berbagi lokasi akan datang segera');
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.person,
                  color: Colors.purple,
                  label: 'Kontak',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur berbagi kontak akan datang segera');
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.poll,
                  color: Colors.teal,
                  label: 'Polling',
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Fitur polling akan datang segera');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}
