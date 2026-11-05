import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportAssistantScreen extends StatefulWidget {
  const SupportAssistantScreen({super.key});

  @override
  State<SupportAssistantScreen> createState() => _SupportAssistantScreenState();
}

class _SupportAssistantScreenState extends State<SupportAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() {
      _messages.add({'role': 'user', 'text': message});
      _controller.clear();
      _sending = true;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'sta-ai',
        body: {'action': 'support_assistant', 'message': message},
      );
      if (response.status != 200 || response.data is! Map) {
        throw StateError('STA AI support is unavailable.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final answer = data['answer']?.toString().trim() ?? '';
      if (answer.isEmpty) throw StateError('STA AI returned no answer.');
      if (!mounted) return;
      setState(() => _messages.add({'role': 'assistant', 'text': answer}));
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add({
        'role': 'assistant',
        'text': 'I could not retrieve a verified answer right now. Please use the human support chat.',
      }));
    } finally {
      if (mounted) setState(() => _sending = false);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: Text('STA AI Support', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Human support',
            icon: const Icon(Icons.support_agent, color: Color(0xFFFFD166)),
            onPressed: () => Navigator.pushNamed(context, '/support'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'Ask about your STA account or recent rides. Answers use your verified ride records where available.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, height: 1.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final isUser = item['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 320),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF245B79) : const Color(0xFF1D2B36),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(item['text'] ?? '',
                            style: const TextStyle(color: Colors.white, height: 1.45)),
                        ),
                      );
                    },
                  ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Write your question...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1D2B36),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
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
