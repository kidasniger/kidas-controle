import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/data.dart';
import '../core/palette.dart';
import '../core/util.dart';
import '../ui/common.dart';
import '../ui/forms.dart';
import '../ui/shell.dart' show SubPage;

/// Fil Messenger autonome, alimenté uniquement par les relevés du bot.
class ConversationDetailScreen extends StatefulWidget {
  final String conversationId;
  const ConversationDetailScreen({super.key, required this.conversationId});
  @override
  State<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _conversation;
  List<dynamic> _queue = const [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading && _conversation != null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        Api.readObj('inbox/messages.json'),
        Api.readArr('posts/messages.json'),
      ]);
      final inbox = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic> : <String, dynamic>{};
      Map<String, dynamic>? found;
      for (final item in Api.conversations(inbox)) {
        if (item.os('id') == widget.conversationId) { found = item; break; }
      }
      if (!mounted) return;
      setState(() {
        _conversation = found;
        _queue = results[1] is List ? results[1] as List<dynamic> : const [];
        _loading = false;
        if (found == null) _error = 'Cette conversation n’est plus présente dans la boîte du bot.';
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = Api.hint(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final conv = _conversation;
    final who = asObj(conv?['with']);
    final name = who.os('name').isEmpty ? 'Contact' : who.os('name');
    final messages = conv?['messages'] is List
        ? (conv!['messages'] as List).whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m)).toList()
        : <Map<String, dynamic>>[];
    messages.sort((a, b) => Api.iso(a.os('created_time')).compareTo(Api.iso(b.os('created_time'))));
    final recipient = who.os('id');
    final windowOpen = conv != null && Api.windowOpen(conv);
    final queued = Api.lastQueued(_queue, widget.conversationId);
    final status = queued?.os('status') ?? '';

    return SubPage('Conversation', child: RefreshIndicator(
      color: c.accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
        children: [
          Row(children: [
            CircleAvatar(radius: 22, backgroundColor: c.soft,
              child: Text(name.substring(0, 1).toUpperCase(), style: T.strong(c))),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: T.strong(c).copyWith(fontSize: 16)),
              Text('Messenger · ' + messages.length.toString() + ' message(s)', style: T.caption(c)),
            ])),
            IconButton(onPressed: _loading ? null : _load, icon: Icon(Icons.refresh, color: c.ink)),
          ]),
          const SizedBox(height: 12),
          if (_loading && conv == null) const KSkeleton(100),
          if (_error != null) KCard(child: Text(_error!, style: T.body(c))),
          if (conv != null) ...[
            for (final message in messages) _bubble(c, message),
            const SizedBox(height: 14),
            _deliveryStatus(c, status, queued),
            const SizedBox(height: 12),
            if (recipient.isEmpty)
              _notice(c, 'Identifiant du contact absent : réponse indisponible.')
            else if (!windowOpen)
              _notice(c, 'Fenêtre Messenger de 24 h fermée. Le contact doit envoyer un nouveau message pour permettre une réponse.')
            else if (status == 'pending')
              _notice(c, 'Une réponse est en attente de traitement par le bot. Actualise la conversation pour suivre son statut.')
            else
              _ComposerMessage(conversationId: widget.conversationId,
                recipientId: recipient, contactName: name, onQueued: _load),
            const SizedBox(height: 10),
            Text('Actualisation automatique toutes les minutes. Les messages affichés proviennent du dernier relevé du bot.',
                style: T.caption(c)),
          ],
        ],
      ),
    ));
  }

  Widget _bubble(Palette c, Map<String, dynamic> message) {
    final mine = message.ob('from_page', false);
    final text = message.os('message');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(color: mine ? c.soft : c.card,
            borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine ? 'Page' : 'Contact',
                style: T.caption(c).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text.isEmpty ? 'Pièce jointe' : text, style: T.body(c)),
            const SizedBox(height: 4),
            Text(rel(message.os('created_time')), style: T.caption(c)),
          ]),
        ),
      ),
    );
  }

  Widget _deliveryStatus(Palette c, String status, Map<String, dynamic>? queued) {
    final label = switch (status) {
      'pending' => 'En attente du bot',
      'sent' => 'Envoi marqué réussi par le bot',
      'error' => 'Échec signalé par le bot',
      _ => 'Aucune réponse en file',
    };
    final detail = queued?.os('erreur') ?? '';
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(status == 'error' ? Icons.error_outline : Icons.info_outline, size: 17, color: c.muted),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: T.strong(c).copyWith(fontSize: 12.5)),
          if (detail.isNotEmpty) Text(detail, style: T.caption(c)),
        ])),
      ]),
    );
  }

  Widget _notice(Palette c, String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: T.body(c)),
  );
}

class _ComposerMessage extends StatefulWidget {
  final String conversationId;
  final String recipientId;
  final String contactName;
  final Future<void> Function() onQueued;
  const _ComposerMessage({required this.conversationId, required this.recipientId,
    required this.contactName, required this.onQueued});
  @override
  State<_ComposerMessage> createState() => _ComposerMessageState();
}

class _ComposerMessageState extends State<_ComposerMessage> {
  final _controller = TextEditingController();
  bool _sending = false;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Api.queueMessage(widget.conversationId, widget.recipientId, text);
      await Journal.ajoute('reponse', 'Message à ' + widget.contactName,
        detail: text.length > 120 ? text.substring(0, 120) + '…' : text);
      if (!mounted) return;
      _controller.clear();
      kToast(context, 'Réponse ajoutée à la file. Elle n’est pas encore confirmée comme publiée.');
      await widget.onQueued();
    } catch (e) {
      if (mounted) kToast(context, Api.hint(e), bad: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    KEdit(controller: _controller, hint: 'Écrire une réponse…',
      minLines: 2, maxLength: Api.messageMax),
    const SizedBox(height: 8),
    ActionBtn(_sending ? 'Mise en file…' : 'Mettre en file', height: 42, job: _send),
  ]);
}
