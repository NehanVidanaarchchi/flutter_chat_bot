import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/bot_service.dart'; 
import 'dart:math';


class ChatbotLauncherButton extends StatelessWidget {
  const ChatbotLauncherButton({super.key});

  void _openChatPopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final double dialogWidth = size.width < 520 ? size.width * 0.95 : 480;
        final double dialogHeight = size.height < 720 ? size.height * 0.85 : 640;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Stack(
                children: [
                  // The chat UI
                  const ChatScreen(),

                  // Close (X) button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: "Close",
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FloatingActionButton.extended(
            onPressed: () => _openChatPopup(context),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text("Chat"),
          ),
        ),
      ),
    );
  }
}


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  final _bot = HeartBotService();
  bool _botTyping = false;

  @override
  void initState() {
    super.initState();
    _pushBot(_greeting());
  }

  String _greeting() {
    return "Hi! Tell me your risk and I’ll give next steps.\n\n"
        "You can give a tier *or* a percentage:\n"
        "Ex: • risk=low | risk=moderate | risk=high | risk=5%\n";
  }

  void _pushBot(String text) {
    setState(() {
      _messages.add(ChatMessage(
        id: UniqueKey().toString(),
        role: "assistant",
        text: text,
      ));
    });
    _jumpToEnd();
  }

  void _pushUser(String text) {
    setState(() {
      _messages.add(ChatMessage(
        id: UniqueKey().toString(),
        role: "user",
        text: text,
      ));
    });
    _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _pushUser(text);

    setState(() => _botTyping = true);

    try {
      // demo
      if (text.toLowerCase() == 'example') {
        final inputs = {
          "age": 58,
          "sex": 1,
          "trestbps": 142,
          "chol": 238,
          "fbs": 0,
          "restecg": 1,
          "thalach": 150,
          "exang": 1,
          "oldpeak": 2.3,
          "slope": 2,
          "ca": 1,
          "thal": 3,
        };
        final reply = _bot.reportForRisk(risk: "moderate", inputs: inputs);
        setState(() => _botTyping = false);
        _pushBot("Example (risk=moderate):\n$reply");
        return;
      }

      // Try percentage first (preferred if both appear)
      final pct = _parseRiskPercentFromText(text);
      final inputs = _parseInputs(text);

      if (pct != null) {
        final reply = _bot.reportForPercent(
          riskPercent: pct,
          inputs: inputs.isEmpty ? null : inputs,
        );
        setState(() => _botTyping = false);
        _pushBot(reply);
        return;
      }

      // Then try tier
      final risk = _parseRiskFromText(text);
      if (risk == null) {
        setState(() => _botTyping = false);
        _pushBot(
          "Please include a risk tier or percentage, e.g.:\n"
              "• risk=low | risk=moderate | risk=high\n"
              "• risk=12%\n",
        );
        return;
      }

      final reply = _bot.reportForRisk(
        risk: risk,
        inputs: inputs.isEmpty ? null : inputs,
      );

      setState(() => _botTyping = false);
      _pushBot(reply);
    } catch (e) {
      setState(() => _botTyping = false);
      _pushBot("Sorry, I couldn’t process that. Error: $e");
    }
  }

  double? _parseRiskPercentFromText(String input) {
    final lower = input.toLowerCase();

    // only consider % parsing if message mentions "risk"
    if (!lower.contains('risk')) return null;

    // capture integer/decimal possibly followed by %
    final numPattern = r'(\d+(?:\.\d+)?)\s*%?';

    // 1) risk=<num>%
    final m1 = RegExp(r'\brisk\s*=\s*' + numPattern + r'\b').firstMatch(lower);
    if (m1 != null) {
      final v = double.tryParse(m1.group(1)!);
      if (v != null) return _clampTo0100(v);
    }

    // 2) "risk <num>%"
    final m2 = RegExp(r'\brisk\s+' + numPattern + r'\b').firstMatch(lower);
    if (m2 != null) {
      final v = double.tryParse(m2.group(1)!);
      if (v != null) return _clampTo0100(v);
    }

    // 3) any "<num>%" after 'risk' exists
    final m3 = RegExp(r'\b' + numPattern + r'%\b').firstMatch(lower);
    if (m3 != null) {
      final v = double.tryParse(m3.group(1)!);
      if (v != null) return _clampTo0100(v);
    }

    return null;
  }

  String? _parseRiskFromText(String input) {
    final lower = input.toLowerCase();

    // 1) risk=<value>
    final m = RegExp(r'\brisk\s*=\s*(high|moderate|medium|low)\b')
        .firstMatch(lower);
    if (m != null) {
      final val = m.group(1)!;
      if (val == 'medium') return 'moderate';
      return val;
    }

    // 2) phrases
    if (RegExp(r'\b(high)\s+risk\b').hasMatch(lower) ||
        RegExp(r'\brisk\s+high\b').hasMatch(lower)) {
      return 'high';
    }
    if (RegExp(r'\b(moderate|medium)\s+risk\b').hasMatch(lower) ||
        RegExp(r'\brisk\s+(moderate|medium)\b').hasMatch(lower)) {
      return 'moderate';
    }
    if (RegExp(r'\b(low)\s+risk\b').hasMatch(lower) ||
        RegExp(r'\brisk\s+low\b').hasMatch(lower)) {
      return 'low';
    }

    return null;
  }

  Map<String, dynamic> _parseInputs(String input) {
    final lower = input.toLowerCase();

    // split by commas or whitespace tokens that contain '='
    final parts = lower
        .replaceAll('\n', ' ')
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.contains('='))
        .toList();

    final Map<String, dynamic> out = {};

    // numeric parse
    num? toNum(String s) {
      final clean = s.replaceAll(RegExp(r'[^0-9\.\-]'), '');
      if (clean.isEmpty) return null;
      if (clean.contains('.')) return double.tryParse(clean);
      return int.tryParse(clean);
    }

    String canonical(String k) {
      k = k.trim();
      if (k == 'gender') return 'sex';
      if (k == 'bp' || k == 'sbp' || k == 'restingbp') return 'trestbps';
      if (k == 'cholesterol' || k == 'tc') return 'chol';
      if (k == 'hr' || k == 'maxhr' || k == 'heart_rate' || k == 'heartrate') {
        return 'thalach';
      }
      if (k == 'glucose') return 'glucose'; // convert to fbs below
      return k;
    }

    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      var key = canonical(p.substring(0, idx).trim());
      final val = p.substring(idx + 1).trim();

      final n = toNum(val);
      if (n == null) continue;

      if (key == 'oldpeak') {
        out['oldpeak'] = (n is num) ? n.toDouble() : 0.0;
        continue;
      }

      if (key == 'glucose') {
        final g = (n is num) ? n.toDouble() : 0.0;
        out['fbs'] = g > 120 ? 1 : 0;
        continue;
      }

      out[key] = (n is num) ? n.round() : 0;
    }

    return out;
  }

  double _clampTo0100(double x) =>
      x.isNaN ? 0.0 : (x < 0 ? 0.0 : (x > 100 ? 100.0 : x));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Heart Assistant")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_botTyping ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_botTyping && i == _messages.length) {
                  return const _TypingBubble();
                }
                final m = _messages[i];
                final isUser = m.role == "user";
                return Align(
                  alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: isUser ? cs.primary : cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: isUser ? Colors.white : null,
                        height: 1.3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Type risk (e.g., risk=12% or risk=high) and optional inputs",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _send,
                    child: const Text("Send"),
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

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text("Typing…"),
          ],
        ),
      ),
    );
  }
}
