import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nearby_chat_app/models/message.dart';
import 'package:nearby_chat_app/services/local_database_service.dart';
import 'package:nearby_chat_app/services/nearby_service_manager.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String? userName;

  const ChatScreen({super.key, required this.userId, this.userName});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late StreamSubscription<Message> _messageSubscription;
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();

  final _nearbyServiceManager = NearbyServiceManager();
  final _databaseService = LocalDatabaseService();

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    _nearbyServiceManager.setActiveChat('');
    super.dispose();
  }

  Future<void> _initializeChat() async {
    _nearbyServiceManager.setActiveChat(widget.userId);

    final messages = await _databaseService.loadMessages(widget.userId);
    setState(() {
      _messages.insertAll(0, messages.reversed);
    });

    _messageSubscription =
        _nearbyServiceManager.activeChatStream.listen((message) {
      if (message.senderId == widget.userId) {
        setState(() {
          _messages.insert(0, message);
        });

        _databaseService.markMessagesAsRead(widget.userId);
      }
    });
  }

  Future<void> _sendMessage(String content) async {
    final message = Message(
      messageId: UniqueKey().toString(),
      senderId: _nearbyServiceManager.localEndpointId,
      receiverId: widget.userId,
      content: content,
      messageType: 'NORMAL',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      status: 'PENDING',
    );

    setState(() {
      _messages.insert(0, message);
    });

    await _databaseService.insertMessage(message);
    _nearbyServiceManager.sendMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 6),
            const Image(
              image: AssetImage('assets/user_image.png'),
              width: 42,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.userName ?? 'Unknown',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              itemCount: _messages.length,
              reverse: true,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUserMessage =
                    message.senderId == _nearbyServiceManager.localEndpointId;

                return Align(
                  alignment: isUserMessage
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: isUserMessage
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(8),
                        topRight: const Radius.circular(8),
                        bottomLeft: isUserMessage
                            ? const Radius.circular(8)
                            : const Radius.circular(0),
                        bottomRight: isUserMessage
                            ? const Radius.circular(0)
                            : const Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isUserMessage ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey[500]),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: Colors.grey),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: () {
                  if (_controller.text.trim().isNotEmpty) {
                    _sendMessage(_controller.text.trim());
                    _controller.clear();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
