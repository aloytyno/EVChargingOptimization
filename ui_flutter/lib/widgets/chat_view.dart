import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../api/models.dart';
import '../theme.dart';

/// Conversation as chat bubbles; keeps the newest message in view.
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.messages});

  final List<ChatMessage> messages;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      itemCount: widget.messages.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, i) {
        final m = widget.messages[i];
        final mine = m.speaker == Speaker.driver;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 290),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine
                  ? Palette.accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 4),
                bottomRight: Radius.circular(mine ? 4 : 18),
              ),
              border: Border.all(
                color: mine
                    ? Palette.accent.withValues(alpha: 0.4)
                    : Palette.glassBorder,
              ),
            ),
            child: Text(m.text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        )
            .animate()
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.25, curve: Curves.easeOutCubic);
      },
    );
  }
}
