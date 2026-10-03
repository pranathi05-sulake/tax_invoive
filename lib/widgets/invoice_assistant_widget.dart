import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/assistant/invoice_assistant_service.dart';
import '../services/auth/auth_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class InvoiceAssistantWidget extends StatefulWidget {
  final Invoice? invoice;

  const InvoiceAssistantWidget({
    super.key,
    this.invoice,
  });

  @override
  State<InvoiceAssistantWidget> createState() => _InvoiceAssistantWidgetState();
}

class _InvoiceAssistantWidgetState extends State<InvoiceAssistantWidget> {
  bool _isOpen = false;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _suggestionChips = const [
    "Invoice details",
    "Why failed validation?",
    "Tax summary",
    "Sync status",
    "Missing fields",
    "How to scan?",
    "Generate report",
    "Other questions",
  ];

  String get _greetingName {
    final session = AuthService.instance.currentSession;
    if (session != null && session.username.trim().isNotEmpty) {
      final name = session.username.trim();
      final first = name.split(' ').first;
      if (first.toLowerCase() == 'admin') return 'Sheethal';
      return first[0].toUpperCase() + first.substring(1);
    }
    return 'Sheethal';
  }

  @override
  void initState() {
    super.initState();
    _resetWelcomeMessage();
  }

  @override
  void didUpdateWidget(InvoiceAssistantWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice?.id != widget.invoice?.id) {
      setState(() {
        _messages.clear();
        _resetWelcomeMessage();
      });
    }
  }

  void _resetWelcomeMessage() {
    final name = _greetingName;
    if (widget.invoice != null) {
      final invNum = widget.invoice!.invoiceNumber.trim().isNotEmpty
          ? widget.invoice!.invoiceNumber.trim()
          : 'Selected';
      _messages.add(
        ChatMessage(
          text: "Hi $name! 👋\nI can help you with invoice #$invNum.",
          isUser: false,
        ),
      );
    } else {
      _messages.add(
        ChatMessage(
          text: "Hi $name! 👋\nI can help you with your invoices.",
          isUser: false,
        ),
      );
    }
  }

  void _handleSubmitted(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(text: trimmed, isUser: true));

      final response = InvoiceAssistantService.processQuery(
        trimmed,
        invoice: widget.invoice,
      );

      _messages.add(ChatMessage(text: response, isUser: false));
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      right: 24,
      child: _isOpen ? _buildChatPanel(context) : _buildFloatingButton(),
    );
  }

  Widget _buildFloatingButton() {
    return Tooltip(
      message: 'Invoice Assistant',
      child: Material(
        elevation: 8,
        shape: const CircleBorder(),
        color: const Color(0xFF1E40AF),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            setState(() {
              _isOpen = true;
            });
            _scrollToBottom();
          },
          child: const Padding(
            padding: EdgeInsets.all(14.0),
            child: Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktopWeb = kIsWeb && screenSize.width > 600;
    final panelWidth = isDesktopWeb
        ? 340.0
        : (screenSize.width < 420 ? screenSize.width - 32 : 360.0);
    final panelHeight = isDesktopWeb
        ? 500.0
        : (screenSize.height < 600 ? screenSize.height - 100 : 520.0);

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: panelWidth,
        height: panelHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessageList()),
            _buildSuggestionChips(),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Color(0xFF2563EB),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Invoice Assistant',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Offline • Local',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _isOpen = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 14),
          ),
        ),
        child: SelectableText(
          msg.text,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF0F172A),
            fontSize: 13,
            height: 1.4,
            fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Colors.white,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _suggestionChips.map((label) {
          return InkWell(
            onTap: () => _handleSubmitted(label),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.send,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: 'Ask a question...',
                hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                ),
              ),
              onSubmitted: _handleSubmitted,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
              padding: EdgeInsets.zero,
              onPressed: () => _handleSubmitted(_textController.text),
            ),
          ),
        ],
      ),
    );
  }
}
