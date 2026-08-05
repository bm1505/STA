import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/ride_provider.dart';
import '../utils/theme.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String senderId;
  final String senderName;

  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.senderId,
    required this.senderName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  // Create a unique chat ID based on both users (sorted to ensure consistency)
  String get _chatId {
    List<String> ids = [widget.senderId, widget.receiverId];
    ids.sort();
    return ids.join('_');
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final msg = _messageController.text.trim();
    _messageController.clear();

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
        'senderId': widget.senderId,
        'receiverId': widget.receiverId,
        'senderName': widget.senderName,
        'message': msg,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update last message in the main chat document for a "conversations" list if needed
      await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'lastMessage': msg,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'participants': [widget.senderId, widget.receiverId],
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppTheme.primaryGold, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.receiverName,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGold)),
            Text("STA Premium Chat",
                style: GoogleFonts.poppins(
                    fontSize: 10, color: Colors.white38, letterSpacing: 1.2)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryGold));
                }

                final docs = snapshot.data?.docs ?? [];
                final messages = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return ChatMessage(
                    senderId: data['senderId'] ?? '',
                    senderName: data['senderName'] ?? 'Unknown',
                    message: data['message'] ?? '',
                    timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
                  );
                }).toList();

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == widget.senderId;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppTheme.primaryGold
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Text(
                          msg.message,
                          style: GoogleFonts.poppins(
                            color: isMe ? Colors.black : Colors.white,
                            fontSize: 14,
                            fontWeight:
                                isMe ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 15, 20, 15),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              border: Border(
                  top: BorderSide(
                      color: AppTheme.primaryGold.withValues(alpha: 0.1))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.poppins(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: GoogleFonts.poppins(color: Colors.white24),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide(
                                color: AppTheme.primaryGold
                                    .withValues(alpha: 0.3))),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.black, size: 24),
                    ),
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
