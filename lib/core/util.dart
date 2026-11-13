/// Formats et helpers partagés — port fidèle de Ui.java (formats).
library;

const _mois = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// 1234567 → « 1 234 567 » (séparateur fin, comme la locale FR).
String nf(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u202F');
    b.write(s[i]);
  }
  return (v.round() < 0 ? '-' : '') + b.toString();
}

/// Variation en pourcentage « +12,3 % » ; chaîne vide si stable ou base nulle.
String pct(num last, num prev) {
  if (prev == 0) return '';
  final p = (last - prev) / prev.abs() * 100.0;
  if (p.abs() < 0.05) return '';
  return (p >= 0 ? '+' : '') +
      p.toStringAsFixed(1).replaceAll('.', ',') +
      '\u00A0%';
}

/// Millisecondes depuis l'époque pour une date ISO (ou -1 si illisible).
int iso(String s) {
  if (s.isEmpty) return -1;
  final d = DateTime.tryParse(s);
  return d?.millisecondsSinceEpoch ?? -1;
}

/// Date au format ISO UTC avec millisecondes (comme isoOf de Ui.java).
String isoOf(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .toIso8601String()
        .replaceFirst('Z', '')
    + 'Z';

/// « 45 s », « 3 min », « 2 h 15 min », « 3 j 4 h ».
String dur(int ms) {
  final s = (ms / 1000.0).round();
  if (s < 60) return '$s\u00A0s';
  final m = s ~/ 60;
  if (m < 60) return '$m\u00A0min';
  final h = m ~/ 60;
  if (h < 24) return '$h\u00A0h ${(m % 60)}\u00A0min';
  return '${h ~/ 24}\u00A0j ${h % 24}\u00A0h';
}

/// « à l'instant », « il y a 5 min », ou « dans 2 h » pour le futur.
String relMs(int ms) {
  if (ms < 0) return '';
  final s = (DateTime.now().millisecondsSinceEpoch - ms) / 1000.0;
  if (s < 0) return 'dans ${dur((-s * 1000).round())}';
  if (s < 45) return "à l'instant";
  if (s < 3600) return 'il y a ${(s / 60).round()}\u00A0min';
  if (s < 86400) return 'il y a ${(s / 3600).round()}\u00A0h';
  return 'il y a ${(s / 86400).round()}\u00A0j';
}

String rel(String isoDate) => relMs(iso(isoDate));

/// « 14 nov. 09:32 ».
String fdate(int ms) {
  if (ms < 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final mm = _mois[d.month - 1];
  return '${d.day.toString().padLeft(2, '0')} $mm '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// « 3,4 Mo » ou « 210 Ko ».
String fsize(num n) {
  if (n > 1048576) {
    return (n / 1048576.0).toStringAsFixed(1).replaceAll('.', ',') + '\u00A0Mo';
  }
  return '${(n / 1024.0).round().clamp(1, 1 << 40)}\u00A0Ko';
}

/// « video » si l'extension est une vidéo, sinon « image ».
String kind(String path) {
  const vids = ['.mp4', '.mov', '.m4v', '.webm', '.3gp', '.avi', '.mkv'];
  final p = path.toLowerCase();
  for (final v in vids) {
    if (p.endsWith(v)) return 'video';
  }
  return 'image';
}

/// Retire l'horodatage « 1700000000000- » du début d'un nom de média.
String stripStamp(String name) =>
    name.replaceFirst(RegExp(r'^\d{10,}-'), '');

/// Code d'un onglet de file d'attente pour posts/{code}.json.
const queuesLibelles = {
  'queue': 'Post texte',
  'avance': 'Post média / programmé',
  'replies': 'Réponse',
  'actions': 'Action',
  'messages': 'Message Messenger',
};
