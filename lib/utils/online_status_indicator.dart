import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/user_status_utils.dart';

class OnlineStatusIndicator extends StatelessWidget {
  final String userId;
  final double size;
  final bool showText;

  const OnlineStatusIndicator({
    Key? key,
    required this.userId,
    this.size = 10.0,
    this.showText = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        if (userData == null) {
          return SizedBox();
        }

        final isOnline = userData['isOnline'] ?? false;
        final lastSeen = userData['lastSeen'] as Timestamp?;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? Colors.green : Colors.grey,
                border: Border.all(
                  color: Colors.white,
                  width: size / 5,
                ),
              ),
            ),
            if (showText) ...[
              SizedBox(width: 6),
              Text(
                isOnline ? 'Online' : UserStatusUtils.formatLastSeen(lastSeen),
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
