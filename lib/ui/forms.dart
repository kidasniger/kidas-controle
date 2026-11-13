import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart' show Api;
import '../core/fx.dart';
import '../core/palette.dart';
import 'common.dart';

/* ---------- champ de saisie (port de Ui.edit) ---------- */

class KEdit extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final String text;
  final int minLines;
  final int? maxLines;
  final int? maxLength;
  final bool obscure;
  final bool number;
  final ValueChanged<String>? onChanged;
  final FocusNode? focus;
  const KEdit({
    super.key,
    this.controller,
    this.hint = '',
    this.text = '',
    this.minLines = 1,
    this.maxLines,
    this.maxLength,
    this.obscure = false,
    this.number = false,
    this.onChanged,
    this.focus,
  });
  @override
  State<KEdit> createState() => _KEditState();
}

class _KEditState extends State<KEdit> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController(text: widget.text);
  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.text.isNotEmpty) {
      _c.text = widget.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return TextField(
      controller: _c,
      focusNode: widget.focus,
      onChanged: widget.onChanged,
      obscureText: widget.obscure,
      maxLength: widget.maxLength,
      keyboardType: widget.number ? TextInputType.number : null,
      inputFormatters:
          widget.number ? [FilteringTextInputFormatter.digitsOnly] : null,
      minLines: widget.minLines,
      maxLines: widget.maxLines ?? widget.minLines,
      style: TextStyle(fontSize: 15, height: 1.35, color: c.ink),
      cursorColor: c.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.bg,
        counterText: '',
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 15, color: c.muted),
        contentPadding: const EdgeInsets.all(12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.accBr, width: 1.4)),
      ),
    );
  }
}

/* ---------- interrupteur avec travail asynchrone (port de switchRow) ---------- */

class KSwitchRow extends StatefulWidget {
  final String label;
  final String desc;
  final bool value;
  final Future<void> Function(bool v) job;
  const KSwitchRow(this.label,
      {super.key, this.desc = '', required this.value, required this.job});
  @override
  State<KSwitchRow> createState() => _KSwitchRowState();
}

class _KSwitchRowState extends State<KSwitchRow> {
  late bool _v = widget.value;
  bool _busy = false;

  Future<void> _flip(bool nv) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _v = nv;
    });
    Fx.tick();
    try {
      await widget.job(nv);
      if (mounted) {
        kToast(context, '${widget.label} : ${nv ? 'activé' : 'désactivé'}');
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        kToast(context, Api.hint(e), bad: true);
        setState(() {
          _busy = false;
          _v = !nv;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Opacity(
      opacity: _busy ? .5 : 1,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: T.strong(c).copyWith(fontSize: 15)),
            if (widget.desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(widget.desc, style: T.caption(c)),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Transform.scale(
          scale: .9,
          child: Switch.adaptive(
            value: _v,
            activeThumbColor: c.accent,
            activeTrackColor: c.accent.withValues(alpha: .35),
            inactiveTrackColor: c.line,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: _busy ? null : _flip,
          ),
        ),
      ]),
    );
  }
}

/* ---------- sélecteur segmenté (port des listes Clair/Sombre) ---------- */

class KSegmented extends StatelessWidget {
  final List<String> labels;
  final int sel;
  final ValueChanged<int> onSelect;
  const KSegmented(this.labels,
      {super.key, required this.sel, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Press(
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: sel == i ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: sel == i ? c.onAccent : c.muted)),
              ),
            ),
          ),
      ]),
    );
  }
}

/* ---------- confirmation (port de Screen.confirm) ---------- */

Future<bool> kConfirm(BuildContext context, String msg) async {
  final c = context.p;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line)),
      content: Text(msg, style: T.body(c)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: c.muted))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('OK',
                style:
                    TextStyle(color: c.accent, fontWeight: FontWeight.w800))),
      ],
    ),
  );
  return ok ?? false;
}

/* ---------- message d'erreur (port de Screen.errBox / note) ---------- */

class ErrBox extends StatelessWidget {
  final String text;
  const ErrBox(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: Text('Erreur : $text', style: T.body(c)),
    );
  }
}

class NoteBox extends StatelessWidget {
  final String bold, rest;
  const NoteBox(this.bold, this.rest, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line)),
      child: RichText(
          text: TextSpan(children: [
        TextSpan(text: bold, style: T.strong(c)),
        TextSpan(text: rest, style: T.body(c)),
      ])),
    );
  }
}
