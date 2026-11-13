import 'package:flutter_test/flutter_test.dart';

import 'package:kidas_controle/core/api.dart';
import 'package:kidas_controle/core/palette.dart';

void main() {
  test('palettes : les deux thèmes exposent les mêmes jetons', () {
    const dark = Palette.dark;
    const light = Palette.light;
    expect(dark.accent, light.accent); // bleu Facebook identique
    expect(dark.bg, isNot(light.bg));
    expect(dark.ink, isNot(light.ink));
  });

  test('dayLabel : JJ/MM depuis les clés de date', () {
    expect(Api.dayLabel({'date': '2026-11-14T00:00:00Z'}), '14/11');
    expect(Api.dayLabel({'fin': '2026-01-02'}), '02/01');
    expect(Api.dayLabel({'sans_date': true}), isNull);
  });

  test('hint : messages d\'erreur parlants', () {
    expect(Api.hint(ApiError(401, 'Bad credentials', '/x')),
        'Jeton invalide ou expiré. Va dans Réglages.');
    expect(Api.hint(ApiError(403, 'Forbidden', '/repos/a/b/contents/posts/queue.json')),
        contains('Droit manquant'));
  });

  test('cp : encodage des segments de chemin', () {
    expect(Api.cp('posts/queue.json'), 'posts/queue.json');
    expect(Api.cp('media/a b.png'), 'media/a%20b.png');
  });
}
