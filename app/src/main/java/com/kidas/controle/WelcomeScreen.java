package com.kidas.controle;

import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

final class WelcomeScreen extends Screen {
    WelcomeScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Bienvenue"; }

    @Override
    void build() {
        LinearLayout c = Ui.card(host);
        PulseDot dot = new PulseDot(host);
        dot.set(Ui.ACCENT, true);
        c.addView(dot, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 8));
        c.addView(Ui.tv(host, "Bienvenue", 22, Ui.INK, true));
        c.addView(Ui.tv(host, "Cette appli pilote ton bot : publication, commentaires, médias, statistiques. Elle utilise un jeton GitHub, chiffré dans le coffre du téléphone.", 14.5f, Ui.MUTED, false), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 14));
        c.addView(Ui.h2(host, "Droits du jeton (fine-grained)"), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 8));
        String[] rights = {"Contents : Read and write", "Actions : Read and write", "Variables : Read and write", "Metadata : Read-only (automatique)"};
        for (String r : rights) {
            TextView t = Ui.tv(host, "•  " + r, 14.5f, Ui.INK, false);
            c.addView(t, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 2, 0, 2));
        }
        c.addView(Ui.tv(host, "Sur les deux dépôts : facebook-data et facebook-manager.", 13, Ui.MUTED, false), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 14));
        Ui.Btn b = Ui.btn(host, "Ouvrir les réglages", R.drawable.ic_gear, 1);
        b.setOnClickListener(v -> host.go(MainActivity.SETTINGS));
        c.addView(b, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        add(c);
    }
}
