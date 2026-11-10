package com.kidas.controle;

import android.app.Activity;
import android.app.Dialog;
import android.app.KeyguardManager;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.PorterDuff;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.animation.DecelerateInterpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {
    static final int HOME = 0, STATS = 1, PUBLISH = 2, COMMENTS = 3, MESSAGES = 4, MEDIA = 5, BOT = 6, SETTINGS = 7, RULES = 8;
    private static final int REQ_FILE = 1, REQ_UNLOCK = 2;
    private static final long LOCK_AFTER_MS = 60000L;

    /* onglets visibles : Accueil, Bot, bouton +, Réponses, Stats */
    private static final int FAB_IDX = 2;
    private static final int[] NAV_TABS = {HOME, BOT, -1, RULES, STATS};
    private static final String[] NAV_NAMES = {"Accueil", "Bot", "", "Réponses", "Stats"};
    private static final int[] NAV_ICONS = {R.drawable.ic_home, R.drawable.ic_bot, 0,
            R.drawable.ic_chat, R.drawable.ic_stats};

    interface Picked { void got(List<Uri> uris); }

    SecureStore store;
    private FrameLayout outer, stage, toastLayer, splash;
    private TextView subV;
    private NavBar nav;
    private Screen cur;
    private View curView;
    private int tab = -1;
    private boolean locked = true, external = false, warned = false;
    private long stoppedAt = 0;
    private Picked pending;
    private int bAvis = 0, bMsg = 0;
    private Dialog sheet;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        try {
            requestWindowFeature(android.view.Window.FEATURE_NO_TITLE);
        } catch (Exception ignored) { /* barre de titre déjà gérée par le thème */ }
        if (getActionBar() != null) getActionBar().hide();
        store = new SecureStore(this);
        Ui.init(this);
        Ui.theme(!"0".equals(store.get("dark")));
        Api.loadCfg(store);
        applyBars();

        outer = new FrameLayout(this);
        outer.setBackgroundColor(Ui.BG);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        outer.addView(col, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        col.addView(buildHeader(), new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(60)));
        View line = new View(this);
        line.setBackgroundColor(Ui.LINE);
        col.addView(line, new LinearLayout.LayoutParams(Ui.MATCH, 1));
        stage = new FrameLayout(this);
        col.addView(stage, new LinearLayout.LayoutParams(Ui.MATCH, 0, 1f));
        nav = new NavBar(this, NAV_NAMES, NAV_ICONS, FAB_IDX, this::openSheet, i -> show(NAV_TABS[i]));
        col.addView(nav, new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(62)));
        toastLayer = new FrameLayout(this);
        outer.addView(toastLayer, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        buildSplash();
        setContentView(outer);
        outer.setVisibility(View.INVISIBLE);
    }

    private void applyBars() {
        Window w = getWindow();
        if (w == null) return;
        w.setStatusBarColor(Ui.BG);
        w.setNavigationBarColor(Ui.BG);
        View d = w.getDecorView();
        int flags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        if (!Ui.DARK) d.setSystemUiVisibility(d.getSystemUiVisibility() | flags);
        else d.setSystemUiVisibility(d.getSystemUiVisibility() & ~flags);
    }

    private View buildHeader() {
        LinearLayout h = new LinearLayout(this);
        h.setOrientation(LinearLayout.HORIZONTAL);
        h.setGravity(Gravity.CENTER_VERTICAL);
        h.setPadding(Ui.dp(18), 0, Ui.dp(10), 0);
        LinearLayout t = new LinearLayout(this);
        t.setOrientation(LinearLayout.VERTICAL);
        t.addView(Ui.tv(this, "KI DAS", 19, Ui.INK, true));
        subV = Ui.tv(this, "Centre de contrôle", 12, Ui.MUTED, false);
        t.addView(subV);
        h.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        final ImageView ref = headerIcon(R.drawable.ic_refresh);
        ref.setOnClickListener(v -> {
            ref.animate().rotationBy(360f).setDuration(520).start();
            refresh();
        });
        h.addView(ref, Ui.lp(Ui.dp(44), Ui.dp(44), 0, 0, 6, 0));
        ImageView gear = headerIcon(R.drawable.ic_gear);
        gear.setOnClickListener(v -> show(SETTINGS));
        h.addView(gear, Ui.lp(Ui.dp(44), Ui.dp(44), 0, 0, 0, 0));
        return h;
    }

    private ImageView headerIcon(int res) {
        ImageView i = new ImageView(this);
        i.setImageResource(res);
        i.setColorFilter(Ui.INK, android.graphics.PorterDuff.Mode.SRC_IN);
        i.setPadding(Ui.dp(11), Ui.dp(11), Ui.dp(11), Ui.dp(11));
        i.setBackground(Ui.roundS(Ui.CARD, Ui.LINE, 12));
        i.setClickable(true);
        Ui.press(i);
        return i;
    }

    /* ---------- splash ---------- */

    private void buildSplash() {
        splash = new FrameLayout(this);
        splash.setBackgroundColor(Ui.BG);
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setGravity(Gravity.CENTER);
        splash.addView(c, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        TextView logo = Ui.tv(this, "K", 40, Ui.BG, true);
        logo.setGravity(Gravity.CENTER);
        logo.setBackground(Ui.round(Ui.INK, 26));
        c.addView(logo, Ui.lp(Ui.dp(92), Ui.dp(92), 0, 0, 0, 22));
        TextView name = Ui.tv(this, "KI DAS Contrôle", 22, Ui.INK, true);
        name.setGravity(Gravity.CENTER);
        c.addView(name, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        TextView sub = Ui.tv(this, "Ton bot, sous contrôle", 13, Ui.MUTED, false);
        sub.setGravity(Gravity.CENTER);
        c.addView(sub, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 6, 0, 0));
        ShimmerView line = new ShimmerView(this);
        LinearLayout.LayoutParams lpp = new LinearLayout.LayoutParams(Ui.dp(120), Ui.dp(4));
        lpp.topMargin = Ui.dp(34);
        c.addView(line, lpp);
        outer.addView(splash, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
    }

    private void hideSplash() {
        if (splash == null) return;
        final FrameLayout s = splash;
        splash = null;
        s.postDelayed(() -> {
            s.animate().alpha(0f).setDuration(320).withEndAction(() -> {
                if (s.getParent() != null) outer.removeView(s);
            }).start();
        }, 1100);
    }

    /* ---------- écrans ---------- */

    private Screen make(int t) {
        if (t == SETTINGS) return new SettingsScreen(this);
        if (t == RULES) return new RulesScreen(this);
        if (Api.tok.isEmpty()) return new WelcomeScreen(this);
        switch (t) {
            case STATS: return new StatsScreen(this);
            case PUBLISH: return new PublishScreen(this);
            case COMMENTS: return new CommentsScreen(this);
            case MESSAGES: return new MessagesScreen(this);
            case MEDIA: return new MediaScreen(this);
            case BOT: return new BotScreen(this);
            default: return new HomeScreen(this);
        }
    }

    void go(int t) { show(t); }

    /** À appeler avant d'ouvrir une appli système : évite le re-verrouillage au retour. */
    void markExternal() { external = true; }

    void refresh() {
        Api.wf = null;
        show(tab < 0 ? HOME : tab);
    }

    void switchTheme(boolean dark) {
        store.set("dark", dark ? "1" : "0");
        recreate();
    }

    void badge(int n) { bAvis = n; updBadge(); }

    void badgeMessages(int n) { bMsg = n; updBadge(); }

    private void updBadge() {
        int idx = -1;
        for (int i = 0; i < NAV_TABS.length; i++) if (NAV_TABS[i] == RULES) idx = i;
        nav.setBadge(idx, bAvis + bMsg);
    }

    private int navIdx(int t) {
        for (int i = 0; i < NAV_TABS.length; i++) if (NAV_TABS[i] == t) return i;
        return -1;
    }

    private void show(int t) {
        int dir = t == tab ? 0 : (t > tab ? 1 : -1);
        if (cur != null) cur.destroy();
        final View old = curView;
        ScrollView sv = new ScrollView(this);
        sv.setVerticalScrollBarEnabled(false);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(Ui.dp(16), Ui.dp(16), Ui.dp(16), Ui.dp(24));
        sv.addView(col, new ScrollView.LayoutParams(Ui.MATCH, Ui.WRAP));
        stage.addView(sv, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
        Screen s = make(t);
        s.root = col;
        cur = s;
        curView = sv;
        tab = t;
        nav.select(t == SETTINGS ? -1 : navIdx(t));
        subV.setText(s.title());
        sv.setAlpha(0f);
        sv.setTranslationX(dir * Ui.dp(32));
        sv.animate().alpha(1f).translationX(0f).setDuration(300).setInterpolator(new DecelerateInterpolator(1.5f)).start();
        if (old != null) {
            old.animate().alpha(0f).translationX(-dir * Ui.dp(32)).setDuration(160)
                    .withEndAction(() -> stage.removeView(old)).start();
        }
        s.build();
    }

    /* ---------- menu du bouton + ---------- */

    private void openSheet() {
        if (sheet != null && sheet.isShowing()) return;
        Dialog d = new Dialog(this);
        d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout box = Ui.vbox(this);
        box.setBackground(Ui.roundS(Ui.CARD, Ui.LINE, 24));
        box.setPadding(Ui.dp(18), Ui.dp(10), Ui.dp(18), Ui.dp(26));
        View handle = new View(this);
        handle.setBackground(Ui.round(Ui.SOFT, 99));
        box.addView(handle, Ui.lp(Ui.dp(40), Ui.dp(4), 0, 6, 0, 0));
        TextView t = Ui.tv(this, "Actions rapides", 16, Ui.INK, true);
        t.setPadding(0, Ui.dp(12), 0, Ui.dp(4));
        box.addView(t);
        String[][] items = {
                {String.valueOf(R.drawable.ic_pen), "Publier"},
                {String.valueOf(R.drawable.ic_image), "Médias"},
                {String.valueOf(R.drawable.ic_chat), "Avis (commentaires)"},
                {String.valueOf(R.drawable.ic_messenger), "Messages"}
        };
        final int[] targets = {PUBLISH, MEDIA, COMMENTS, MESSAGES};
        for (int i = 0; i < items.length; i++) {
            box.addView(sheetRow(Integer.parseInt(items[i][0]), items[i][1], targets[i]));
        }
        d.setContentView(box);
        Window w = d.getWindow();
        if (w != null) {
            w.setBackgroundDrawableResource(android.R.color.transparent);
            w.setLayout(Ui.MATCH, Ui.WRAP);
            w.setGravity(Gravity.BOTTOM);
        }
        sheet = d;
        d.show();
    }

    private View sheetRow(int iconRes, final String label, final int target) {
        LinearLayout r = Ui.hbox(this);
        r.setPadding(0, Ui.dp(12), 0, Ui.dp(12));
        r.setClickable(true);
        ImageView ic = new ImageView(this);
        ic.setImageResource(iconRes);
        ic.setColorFilter(Ui.INK, PorterDuff.Mode.SRC_IN);
        ic.setBackground(Ui.roundS(Ui.SOFT, Ui.LINE, 12));
        ic.setPadding(Ui.dp(10), Ui.dp(10), Ui.dp(10), Ui.dp(10));
        r.addView(ic, new LinearLayout.LayoutParams(Ui.dp(38), Ui.dp(38)));
        TextView t = Ui.tv(this, label, 14.5f, Ui.INK, true);
        t.setPadding(Ui.dp(13), 0, 0, 0);
        r.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        ImageView chev = new ImageView(this);
        chev.setImageResource(R.drawable.ic_check);
        chev.setColorFilter(Ui.MUTED, PorterDuff.Mode.SRC_IN);
        chev.setVisibility(View.GONE);
        r.addView(chev, new LinearLayout.LayoutParams(Ui.dp(18), Ui.dp(18)));
        r.setOnClickListener(v -> {
            if (sheet != null && sheet.isShowing()) sheet.dismiss();
            show(target);
        });
        Ui.press(r);
        return r;
    }

    /* ---------- messages ---------- */

    void toast(String msg, boolean bad) {
        toastLayer.removeAllViews();
        final TextView t = Ui.tv(this, msg, 14, bad ? Ui.BG : Ui.BG, true);
        t.setBackground(Ui.round(bad ? Ui.INK : Ui.INK, 14));
        t.setPadding(Ui.dp(16), Ui.dp(12), Ui.dp(16), Ui.dp(12));
        t.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams p = new FrameLayout.LayoutParams(Ui.WRAP, Ui.WRAP, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        p.bottomMargin = Ui.dp(78);
        p.leftMargin = Ui.dp(20);
        p.rightMargin = Ui.dp(20);
        toastLayer.addView(t, p);
        t.setAlpha(0f);
        t.setTranslationY(Ui.dp(24));
        t.animate().alpha(1f).translationY(0f).setDuration(240).setInterpolator(new DecelerateInterpolator()).start();
        t.postDelayed(() -> {
            if (t.getParent() != null) {
                t.animate().alpha(0f).translationY(Ui.dp(16)).setDuration(220)
                        .withEndAction(() -> toastLayer.removeView(t)).start();
            }
        }, bad ? 5000 : 2400);
    }

    void copy(String text) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null) {
            cm.setPrimaryClip(ClipData.newPlainText("KI DAS", text));
            toast("Copié.", false);
        }
    }

    void pickFiles(boolean multiple, Picked cb) {
        pending = cb;
        Intent i = new Intent(Intent.ACTION_GET_CONTENT);
        i.setType("*/*");
        i.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"image/*", "video/*"});
        i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        try {
            external = true;
            startActivityForResult(Intent.createChooser(i, "Choisir un fichier"), REQ_FILE);
        } catch (ActivityNotFoundException e) {
            external = false;
            pending = null;
            toast("Aucune appli de fichiers disponible.", true);
        }
    }

    /* ---------- verrouillage ---------- */

    @Override
    protected void onStart() {
        super.onStart();
        if (!external && (locked || SystemClock.elapsedRealtime() - stoppedAt > LOCK_AFTER_MS)) lock();
    }

    @Override
    protected void onResume() {
        super.onResume();
        external = false;
    }

    @Override
    protected void onStop() {
        super.onStop();
        stoppedAt = SystemClock.elapsedRealtime();
    }

    private void lock() {
        locked = true;
        outer.setVisibility(View.INVISIBLE);
        KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (km == null || !km.isDeviceSecure()) {
            if (!warned) {
                warned = true;
                Toast.makeText(this, "Aucun verrouillage d'écran : l'application n'est pas protégée.", Toast.LENGTH_LONG).show();
            }
            unlock();
            return;
        }
        Intent i = km.createConfirmDeviceCredentialIntent("KI DAS Contrôle", "Déverrouille pour continuer");
        if (i == null) {
            unlock();
            return;
        }
        try {
            external = true;
            startActivityForResult(i, REQ_UNLOCK);
        } catch (Exception e) {
            external = false;
            unlock();
        }
    }

    private void unlock() {
        locked = false;
        outer.setVisibility(View.VISIBLE);
        hideSplash();
        if (cur == null) show(HOME);
        Updater.autoCheck(this);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_UNLOCK) {
            if (resultCode == RESULT_OK) unlock(); else finish();
            return;
        }
        if (requestCode == REQ_FILE) {
            Picked cb = pending;
            pending = null;
            if (cb != null && resultCode == RESULT_OK && data != null) {
                List<Uri> list = new ArrayList<>();
                ClipData cd = data.getClipData();
                if (cd != null) {
                    for (int i = 0; i < cd.getItemCount(); i++) list.add(cd.getItemAt(i).getUri());
                } else if (data.getData() != null) {
                    list.add(data.getData());
                }
                if (!list.isEmpty()) cb.got(list);
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onBackPressed() {
        if (sheet != null && sheet.isShowing()) {
            sheet.dismiss();
            return;
        }
        if (!locked && tab != HOME && tab >= 0) {
            show(HOME);
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (cur != null) cur.destroy();
        super.onDestroy();
    }
}
