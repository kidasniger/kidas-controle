import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/backup.dart';
import '../core/diagnostics.dart';
import '../core/palette.dart';
import '../ui/common.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  DiagnosticReport? _report;
  bool _busy = false;
  String? _error;
  String _filter = 'Tous';

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await Diagnostics.run().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception(
          'Le diagnostic dépasse 45 secondes. Vérifie la connexion puis réessaie.',
        ),
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    final report = _report;
    final checks = report?.checks ?? const <DiagnosticCheck>[];
    final errors = checks.where((x) => x.level == CheckLevel.error).length;
    final warnings = checks.where((x) => x.level == CheckLevel.warning).length;
    final passed = checks.where((x) => x.level == CheckLevel.success).length;
    final healthy = report != null && errors == 0 && warnings == 0;
    final filtered = checks.where((check) {
      switch (_filter) {
        case 'Erreurs':
          return check.level == CheckLevel.error;
        case 'Alertes':
          return check.level == CheckLevel.warning;
        case 'Réussis':
          return check.level == CheckLevel.success;
        default:
          return true;
      }
    }).toList();

    return RefreshIndicator(
      onRefresh: _run,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
        children: [
          _diagnosticHero(
            c,
            busy: _busy,
            report: report,
            healthy: healthy,
            errors: errors,
            warnings: warnings,
            passed: passed,
          ),
          const SizedBox(height: 20),
          const KSection('État des contrôles'),
          Row(
            children: [
              Expanded(child: _metric(c, 'Réussis', passed, Colors.green, Icons.check_circle_outline_rounded)),
              const SizedBox(width: 9),
              Expanded(child: _metric(c, 'Alertes', warnings, Colors.orange, Icons.warning_amber_rounded)),
              const SizedBox(width: 9),
              Expanded(child: _metric(c, 'Erreurs', errors, Colors.red, Icons.error_outline_rounded)),
            ],
          ),
          const SizedBox(height: 22),
          KSection(
            'Résultats de vérification',
            action: report == null ? null : '${checks.length} éléments',
          ),
          if (report != null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in ['Tous', 'Erreurs', 'Alertes', 'Réussis']) ...[
                    _filterChip(c, filter),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 13),
          ],
          if (_busy && report == null)
            KCard(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Analyse des services en cours', style: T.strong(c)),
                  const SizedBox(height: 4),
                  Text(
                    'Connexion GitHub, dépôts, workflows et activité du bot.',
                    textAlign: TextAlign.center,
                    style: T.caption(c),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            )
          else if (_error != null && report == null)
            _errorCard(c)
          else if (filtered.isEmpty)
            KCard(
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      checks.isEmpty
                          ? 'Les résultats apparaîtront ici après le diagnostic.'
                          : 'Aucun résultat dans cette catégorie.',
                      style: T.body(c),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final check in filtered) ...[
              _checkTile(c, check),
              const SizedBox(height: 9),
            ],
          if (_error != null && report != null) ...[
            const SizedBox(height: 10),
            _errorCard(c),
          ],
          if (report != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: c.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Dernier contrôle : ${_formatDate(report.checkedAt.toLocal())}',
                    style: T.caption(c),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _run,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Actualiser'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _infoNote(
            c,
            icon: Icons.shield_outlined,
            title: 'Mode lecture seule',
            detail: 'Le diagnostic consulte les services et les dépôts. Il ne lance, n’arrête et ne modifie aucun workflow GitHub.',
          ),
        ],
      ),
    );
  }

  Widget _diagnosticHero(
    Palette c, {
    required bool busy,
    required DiagnosticReport? report,
    required bool healthy,
    required int errors,
    required int warnings,
    required int passed,
  }) {
    final Color stateColor = busy
        ? c.accent
        : report == null
            ? c.muted
            : healthy
                ? Colors.green
                : errors > 0
                    ? Colors.red
                    : Colors.orange;
    final String title = busy
        ? 'Analyse de votre espace'
        : report == null
            ? 'Votre espace, sous contrôle'
            : healthy
                ? 'Tous les systèmes sont opérationnels'
                : 'Des points demandent votre attention';
    final String subtitle = busy
        ? 'Vérification de GitHub, des dépôts et des services…'
        : report == null
            ? 'Lancez une vérification complète pour connaître leur état.'
            : '$passed contrôles réussis · $warnings alertes · $errors erreurs';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.accent.withValues(alpha: .19),
            c.card,
            c.card,
          ],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: c.accent.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(Icons.health_and_safety_rounded, color: c.accent, size: 27),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: stateColor.withValues(alpha: .18)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      busy ? 'ANALYSE' : report == null ? 'EN ATTENTE' : healthy ? 'SAIN' : 'À SURVEILLER',
                      style: TextStyle(color: stateColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .9),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('DIAGNOSTICS & MAINTENANCE', style: T.micro(c).copyWith(color: c.accent, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(title, style: T.title(c).copyWith(fontSize: 21, height: 1.2)),
          const SizedBox(height: 7),
          Text(subtitle, style: T.caption(c).copyWith(fontSize: 12.5, height: 1.5)),
          if (busy) ...[
            const SizedBox(height: 17),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(minHeight: 5),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : _run,
              icon: Icon(busy ? Icons.sync_rounded : Icons.play_arrow_rounded),
              label: Text(busy ? 'Vérification en cours…' : 'Lancer une vérification'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(49),
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(Palette c, String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 13, 10, 13),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 11),
          Text(
            value.toString(),
            style: T.kpi(c).copyWith(fontSize: 24, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: T.caption(c).copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _filterChip(Palette c, String label) {
    final selected = _filter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = label),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? c.onAccent : c.ink,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      selectedColor: c.accent,
      backgroundColor: c.card,
      side: BorderSide(color: selected ? c.accent : c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
  }

  Widget _checkTile(Palette c, DiagnosticCheck check) {
    final color = switch (check.level) {
      CheckLevel.success => Colors.green,
      CheckLevel.warning => Colors.orange,
      CheckLevel.error => Colors.red,
    };
    final icon = switch (check.level) {
      CheckLevel.success => Icons.check_circle_rounded,
      CheckLevel.warning => Icons.warning_amber_rounded,
      CheckLevel.error => Icons.error_rounded,
    };
    final label = switch (check.level) {
      CheckLevel.success => 'Opérationnel',
      CheckLevel.warning => 'À vérifier',
      CheckLevel.error => 'Erreur',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title, style: T.strong(c).copyWith(fontSize: 13.5)),
                const SizedBox(height: 5),
                Text(check.detail, style: T.caption(c).copyWith(height: 1.5)),
                const SizedBox(height: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(Palette c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.red, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diagnostic interrompu', style: T.strong(c).copyWith(color: Colors.red)),
                const SizedBox(height: 4),
                Text(_error ?? 'Une erreur inconnue est survenue.', style: T.caption(c)),
                TextButton(
                  onPressed: _busy ? null : _run,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoNote(Palette c, {required IconData icon, required String title, required String detail}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.muted, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.strong(c)),
                const SizedBox(height: 3),
                Text(detail, style: T.caption(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à ${two(date.hour)}:${two(date.minute)}';
  }
}

class SettingsBackupScreen extends StatefulWidget {
  const SettingsBackupScreen({super.key});

  @override
  State<SettingsBackupScreen> createState() => _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends State<SettingsBackupScreen> {
  bool _busy = false;
  String? _lastFile;

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await AppBackup.create();
      final destination = await FilePicker.saveFile(
        fileName: file.uri.pathSegments.last,
        bytes: await file.readAsBytes(),
        mimeType: 'application/json',
      );
      if (!mounted) return;
      if (destination == null) return;
      setState(() => _lastFile = destination.toString());
      kToast(context, 'Sauvegarde créée.');
    } catch (error) {
      if (mounted) kToast(context, 'Échec de la sauvegarde : $error', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (!mounted || files.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.p;
        return AlertDialog(
          backgroundColor: c.card,
          title: Text('Restaurer les paramètres ?', style: T.title(c)),
          content: Text(
            'Les préférences présentes seront remplacées par celles du fichier. Les jetons et secrets ne seront pas importés.',
            style: T.body(c),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurer')),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    File? temp;
    try {
      final bytes = await files.single.readAsBytes();
      temp = File(
        '${Directory.systemTemp.path}/kidas-restore-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await temp.writeAsBytes(bytes, flush: true);
      final count = await AppBackup.restore(temp);
      await temp.delete();
      if (!mounted) return;
      kToast(context, '$count paramètre(s) restauré(s). Redémarre l’application pour appliquer tous les réglages.');
    } catch (error) {
      if (mounted) kToast(context, 'Sauvegarde refusée : $error', bad: true);
    } finally {
      if (temp != null && await temp.exists()) {
        try { await temp.delete(); } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.p;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.cloud_sync_outlined, color: c.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sauvegarde des paramètres', style: T.title(c)),
                        const SizedBox(height: 3),
                        Text('Export et restauration locale', style: T.caption(c)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Garde une copie de tes préférences pour les retrouver après un changement d’appareil ou une réinstallation.',
                style: T.body(c),
              ),
              const SizedBox(height: 16),
              _backupFeature(c, Icons.palette_outlined, 'Apparence et préférences', 'Mode du thème, notifications et sons.'),
              const SizedBox(height: 11),
              _backupFeature(c, Icons.folder_outlined, 'Références des dépôts', 'Configuration des dépôts utilisés par l’application.'),
              const SizedBox(height: 11),
              _backupFeature(c, Icons.lock_outline_rounded, 'Secrets protégés', 'Les jetons GitHub et autres secrets restent exclus du fichier.'),
              const SizedBox(height: 19),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(_busy ? 'Préparation…' : 'Exporter les paramètres'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restaurer depuis un fichier'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(47),
                    foregroundColor: c.ink,
                    side: BorderSide(color: c.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 15),
                const LinearProgressIndicator(minHeight: 3),
              ],
              if (_lastFile != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(13)),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 19),
                      const SizedBox(width: 9),
                      Expanded(child: Text('Dernière sauvegarde : $_lastFile', style: T.caption(c))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 17),
        _infoNote(
          c,
          icon: Icons.info_outline_rounded,
          title: 'À savoir avant de restaurer',
          detail: 'La restauration remplace uniquement les paramètres pris en charge. Elle ne touche pas au token GitHub, aux mots de passe ni aux secrets. Un redémarrage est nécessaire pour appliquer tous les changements.',
        ),
      ],
    );
  }

  Widget _infoNote(Palette c, {required IconData icon, required String title, required String detail}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.muted, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.strong(c)),
                const SizedBox(height: 3),
                Text(detail, style: T.caption(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupFeature(Palette c, IconData icon, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: c.accent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.strong(c)),
              const SizedBox(height: 2),
              Text(detail, style: T.caption(c)),
            ],
          ),
        ),
      ],
    );
  }

}
