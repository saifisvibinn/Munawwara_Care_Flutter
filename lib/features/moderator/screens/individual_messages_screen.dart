import 'package:flutter/material.dart';

import 'group_messages_screen.dart';

// Thin compatibility wrapper — merged into GroupMessagesScreen (Issue 1).
// All existing call sites continue to compile unchanged.

class IndividualMessagesScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String recipientId;
  final String recipientName;
  final String currentUserId;

  const IndividualMessagesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.recipientId,
    required this.recipientName,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return GroupMessagesScreen(
      groupId: groupId,
      groupName: groupName,
      currentUserId: currentUserId,
      recipientId: recipientId,
      recipientName: recipientName,
    );
  }
}
