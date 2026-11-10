package com.kidas.controle;

import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/** Premier lancement : 3 écrans d'introduction, puis la fiche jeton. */
final class WelcomeScreen extends Screen {
    private int step = 0;
    private boolean intro;

    WelcomeScreen(MainActivity h) {
        super(h);
        intro = !"1".equals(h.store.get("onb"));
    }

    @Override
    String title() { return "Bienvenue"; }

    @Override
    void build() {
        clearAll();
        if (intro) slides(); else tokenCard();
    }

    private void slides() {
        String[][] S = {
                {"Votre bot, sous contrôle", "Publications, commentaires, réponses : suis l'activité de Kidas sur ta Page Facebook, en temps réel."},
                {"Règles et réponses auto", "Like, réponse IA, Messenger : les règles du bot se gèrent dans l'onglet Réponses."},
                {"Statistiques en direct", "Abonnés, vues, interactions : tout ce que le bot accomplit est mesuré dans l'onglet Stats."}
        };
        LinearLayout logoBox = Ui.vbox(host);
        logoBox.setGravity(Gravity.CENTER_HORIZONTAL);
        TextView logo = Ui.tv(host, "K", 34, Ui.BG, true);
        logo.setGravity(Gravity.CENTER);
        logo.setBackground(Ui.round(Ui.INK, 22));
        logoBox.addView(logo, Ui.lp(Ui.dp(76), Ui.dp(76), 0, Ui.dp(40), 0, Ui.dp(6)));
        add(logoBox);

        TextView title = Ui.tv(host, S[step][0], 22, Ui.INK, true);
        title.setGravity(Gravity.CENTER);
        add(title);
        TextView txt = Ui.tv(host, S[step][1], 14.5f, Ui.MUTED, false);
        txt.setGravity(Gravity.CENTER);
        txt.setLineSpacing(0f, 1.25f);
        add(txt);

        /* points */
        LinearLayout dots = new LinearLayout(host);
        dots.setOrientation(LinearLayout.HORIZONTAL);
        dots.setGravity(Gravity.CENTER);
        for (int i = 0; i < 3; i++) {
            View d = new View(host);
            d.setBackground(Ui.round(i == step ? Ui.INK : Ui.SOFT, 99));
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(Ui.dp(i == step ? 24 : 8), Ui.dp(8));
            p.setMargins(Ui.dp(4), 0, Ui.dp(4), 0);
            dots.addView(d, p);
        }
        add(dots);

        /* boutons */
        LinearLayout row = new LinearLayout(host);
        row.setOrientation(LinearLayout.HORIZONTAL);
        Ui.Btn skip = Ui.btn(host, "Passer", 0, 0);
        skip.setOnClickListener(v -> finish());
        row.addView(skip, Ui.lp(0, Ui.WRAP, 0, 0, 6, 0));
        ((LinearLayout.LayoutParams) skip.getLayoutParams()).weight = 1f;
        final Ui.Btn next = Ui.btn(host, step < 2 ? "Suivant" : "Commencer", 0, 1);
        next.setOnClickListener(v -> {
            if (step < 2) {
                step++;
                build();
            } else {
                finish();
            }
        });
        row.addView(next, Ui.lp(0, Ui.WRAP, 6, 0, 0, 0));
        ((LinearLayout.LayoutParams) next.getLayoutParams()).weight = 1.4f;
        add(row);

        TextView hint = Ui.tv(host, "L'appli pilote le bot via GitHub. Ton jeton restera chiffré dans le téléphone.", 12.5f, Ui.MUTED, false);
        hint.setGravity(Gravity.CENTER);
        add(hint);
    }

    private void finish() {
        intro = false;
        host.store.set("onb", "1");
        build();
    }

    private void tokenCard() {
        LinearLayout c = Ui.card(host);
        PulseDot dot = new PulseDot(host);
        dot.set(Ui.ACCENT, true);
        c.addView(dot, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 8));
        c.addView(Ui.tv(host, "Connecte le bot", 22, Ui.INK, true));
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

        TextView again = Ui.tv(host, "Revoir l'introduction", 13, Ui.MUTED, true);
        again.setGravity(Gravity.CENTER);
        again.setPadding(0, Ui.dp(8), 0, Ui.dp(8));
        again.setClickable(true);
        Ui.press(again);
        again.setOnClickListener(v -> {
            intro = true;
            step = 0;
            build();
        });
        add(again);
    }
}
