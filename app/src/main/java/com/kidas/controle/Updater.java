package com.kidas.controle;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Mise à jour de l'application depuis les Releases GitHub du dépôt de l'appli.
 * Vérification, téléchargement (reprise possible), contrôle SHA-256 + signature, installation.
 */
final class Updater {
    static final String REPO = "kidasniger/kidas-controle";
    static final String APK_NAME = "kidas-controle.apk";
    static final String SHA_NAME = "kidas-controle.apk.sha256";
    static final String ACTION = "com.kidas.controle.INSTALL_RESULT";

    static final class Info {
        int code, current;
        String name = "", curName = "", notes = "";
        boolean mandatory, available;
        String apkWeb = "", apkApi = "", shaWeb = "", shaApi = "";
        long size;
    }

    static final class Cancelled extends Exception {
        Cancelled() { super("Téléchargement annulé."); }
    }

    interface Progress { void on(long done, long total); }

    interface Result { void on(int status, String msg); }

    static volatile Result listener;
    private static final AtomicBoolean BUSY = new AtomicBoolean(false);
    private static volatile boolean cancel = false;
    private static volatile HttpURLConnection live;
    private static boolean autoDone = false;

    private Updater() { }

    /* ---------- version installée ---------- */

    private static PackageInfo self(Context c, int flags) throws Exception {
        return c.getPackageManager().getPackageInfo(c.getPackageName(), flags);
    }

    @SuppressWarnings("deprecation")
    static int versionCode(Context c) {
        try {
            PackageInfo p = self(c, 0);
            return Build.VERSION.SDK_INT >= 28 ? (int) p.getLongVersionCode() : p.versionCode;
        } catch (Exception e) {
            return 0;
        }
    }

    static String versionName(Context c) {
        try {
            String n = self(c, 0).versionName;
            return n == null ? "" : n;
        } catch (Exception e) {
            return "";
        }
    }

    /* ---------- vérification ---------- */

    static Info check(Context c) throws Exception {
        JSONObject j = latest();
        String tag = j.optString("tag_name", "");
        Matcher m = Pattern.compile("(\\d+)\\s*$").matcher(tag);
        if (!m.find() || m.group(1).length() > 9) throw new Exception("Numéro de version illisible (" + tag + ").");
        Info i = new Info();
        i.code = Integer.parseInt(m.group(1));
        i.current = versionCode(c);
        i.name = "1.0." + i.code;
        i.curName = versionName(c);
        String body = j.optString("body", "");
        i.mandatory = Pattern.compile("\\[obligatoire\\]", Pattern.CASE_INSENSITIVE).matcher(body).find();
        i.notes = body.replaceAll("(?i)\\[obligatoire\\]", "").trim();
        JSONArray as = j.optJSONArray("assets");
        if (as != null) {
            for (int k = 0; k < as.length(); k++) {
                JSONObject a = as.optJSONObject(k);
                if (a == null) continue;
                String n = a.optString("name", "");
                if (APK_NAME.equals(n)) {
                    i.apkWeb = a.optString("browser_download_url", "");
                    i.apkApi = a.optString("url", "");
                    i.size = a.optLong("size", 0);
                } else if (SHA_NAME.equals(n)) {
                    i.shaWeb = a.optString("browser_download_url", "");
                    i.shaApi = a.optString("url", "");
                }
            }
        }
        if (i.apkWeb.isEmpty()) throw new Exception("Cette version ne contient pas d'APK.");
        i.available = i.code > i.current;
        return i;
    }

    private static JSONObject latest() throws Exception {
        String url = "https://api.github.com/repos/" + REPO + "/releases/latest";
        boolean auth = !Api.tok.isEmpty();
        for (int pass = 0; pass < 2; pass++) {
            HttpURLConnection c = null;
            try {
                c = connect(url, "application/vnd.github+json", auth, 0);
                int code = c.getResponseCode();
                if (code == 200) {
                    return new JSONObject(new String(Api.readAll(c.getInputStream()), StandardCharsets.UTF_8));
                }
                if (auth && (code == 401 || code == 403 || code == 404)) {
                    auth = false;
                    continue;
                }
                if (code == 404) throw new Exception("Aucune version publiée trouvée.");
                if (code == 403) throw new Exception("Limite GitHub atteinte, réessaie plus tard.");
                throw new Exception("GitHub a répondu HTTP " + code + ".");
            } catch (SocketTimeoutException e) {
                throw new Exception("Délai dépassé, réessaie.");
            } catch (JSONException e) {
                throw new Exception("Réponse illisible.");
            } catch (IOException e) {
                throw new Exception("Réseau indisponible.");
            } finally {
                if (c != null) c.disconnect();
            }
        }
        throw new Exception("Impossible de lire la dernière version.");
    }

    /* ---------- HTTP (https seulement, redirections suivies à la main) ---------- */

    private static HttpURLConnection connect(String url, String accept, boolean auth, long from) throws IOException {
        String cur = url;
        for (int i = 0; i < 6; i++) {
            if (!cur.startsWith("https://")) throw new IOException("Lien non sécurisé refusé.");
            URL u = new URL(cur);
            HttpURLConnection c = (HttpURLConnection) u.openConnection();
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(15000);
            c.setReadTimeout(30000);
            c.setUseCaches(false);
            c.setRequestProperty("Accept", accept);
            c.setRequestProperty("User-Agent", "kidas-controle");
            if ("api.github.com".equals(u.getHost())) {
                c.setRequestProperty("X-GitHub-Api-Version", "2022-11-28");
                if (auth && !Api.tok.isEmpty()) c.setRequestProperty("Authorization", "Bearer " + Api.tok);
            }
            if (from > 0) c.setRequestProperty("Range", "bytes=" + from + "-");
            int code = c.getResponseCode();
            if (code >= 300 && code < 400 && code != 304) {
                String loc = c.getHeaderField("Location");
                c.disconnect();
                if (loc == null || loc.isEmpty()) throw new IOException("Redirection invalide.");
                cur = new URL(u, loc).toString();
                continue;
            }
            return c;
        }
        throw new IOException("Trop de redirections.");
    }

    /** Lien public d'abord ; si le dépôt est privé, lien d'API avec le jeton. */
    private static HttpURLConnection openAsset(String web, String api, long from) throws IOException {
        HttpURLConnection c = connect(web, "application/octet-stream", false, from);
        int code = c.getResponseCode();
        if ((code == 401 || code == 403 || code == 404) && !Api.tok.isEmpty() && api != null && !api.isEmpty()) {
            c.disconnect();
            c = connect(api, "application/octet-stream", true, from);
        }
        return c;
    }

    /* ---------- téléchargement ---------- */

    private static File dir(Context c) {
        File d = new File(c.getCacheDir(), "updates");
        if (!d.exists()) d.mkdirs();
        return d;
    }

    static boolean busy() { return BUSY.get(); }

    static void cancel() {
        cancel = true;
        final HttpURLConnection c = live;
        if (c != null) {
            Api.EX.execute(() -> {
                try { c.disconnect(); } catch (Exception ignored) { /* déjà fermé */ }
            });
        }
    }

    static File download(Context c, Info i, Progress p) throws Exception {
        if (!BUSY.compareAndSet(false, true)) throw new Exception("Un téléchargement est déjà en cours.");
        cancel = false;
        try {
            File d = dir(c);
            File fin = new File(d, "kidas-controle-" + i.code + ".apk");
            File part = new File(d, fin.getName() + ".part");
            if (fin.exists() && (i.size <= 0 || fin.length() == i.size)) {
                try {
                    verify(c, fin, i.code);
                    if (p != null) p.on(i.size, i.size);
                    return fin;
                } catch (Exception e) {
                    fin.delete();
                }
            } else if (fin.exists()) {
                fin.delete();
            }
            fetch(i, part, p);
            if (i.size > 0 && part.length() != i.size) {
                part.delete();
                throw new Exception("Fichier incomplet, réessaie.");
            }
            String want = fetchSha(i);
            if (!want.isEmpty() && !want.equals(sha256(part))) {
                part.delete();
                throw new Exception("Somme de contrôle invalide : fichier corrompu, réessaie.");
            }
            if (!part.renameTo(fin)) throw new Exception("Impossible d'enregistrer le fichier.");
            try {
                verify(c, fin, i.code);
            } catch (Exception e) {
                fin.delete();
                throw e;
            }
            return fin;
        } finally {
            BUSY.set(false);
        }
    }

    private static void fetch(Info i, File part, Progress p) throws Exception {
        long have = part.exists() ? part.length() : 0;
        if (i.size > 0 && have > i.size) {
            part.delete();
            have = 0;
        }
        if (i.size > 0 && have == i.size) {
            if (p != null) p.on(have, i.size);
            return;
        }
        HttpURLConnection c = null;
        try {
            c = openAsset(i.apkWeb, i.apkApi, have);
            live = c;
            int code = c.getResponseCode();
            if (code == 416) {
                c.disconnect();
                part.delete();
                have = 0;
                c = openAsset(i.apkWeb, i.apkApi, 0);
                live = c;
                code = c.getResponseCode();
            }
            if (code != 200 && code != 206) throw new Exception("Téléchargement impossible (HTTP " + code + ").");
            boolean append = code == 206 && have > 0;
            if (!append) have = 0;
            long len = c.getContentLengthLong();
            long total = i.size > 0 ? i.size : (len > 0 ? len + have : 0);
            InputStream in = c.getInputStream();
            FileOutputStream out = new FileOutputStream(part, append);
            try {
                byte[] buf = new byte[32768];
                long done = have, last = 0;
                int n;
                while ((n = in.read(buf)) > 0) {
                    if (cancel) throw new Cancelled();
                    out.write(buf, 0, n);
                    done += n;
                    long now = System.currentTimeMillis();
                    if (p != null && now - last > 120) {
                        last = now;
                        p.on(done, total);
                    }
                }
                out.flush();
                if (p != null) p.on(done, total);
            } finally {
                try { out.close(); } catch (IOException ignored) { /* fermé */ }
                try { in.close(); } catch (IOException ignored) { /* fermé */ }
            }
        } catch (Cancelled e) {
            throw e;
        } catch (SocketTimeoutException e) {
            if (cancel) throw new Cancelled();
            throw new Exception("Connexion trop lente. Réessaie pour reprendre.");
        } catch (IOException e) {
            if (cancel) throw new Cancelled();
            throw new Exception("Connexion interrompue. Réessaie pour reprendre.");
        } finally {
            live = null;
            if (c != null) c.disconnect();
        }
        if (cancel) throw new Cancelled();
    }

    /* ---------- intégrité et signature ---------- */

    private static String fetchSha(Info i) throws Exception {
        if (i.shaWeb.isEmpty()) return "";
        HttpURLConnection c = null;
        try {
            c = openAsset(i.shaWeb, i.shaApi, 0);
            int code = c.getResponseCode();
            if (code != 200) throw new Exception("Somme de contrôle introuvable (HTTP " + code + ").");
            String t = new String(Api.readAll(c.getInputStream()), StandardCharsets.UTF_8).trim();
            String h = t.split("\\s+")[0].toLowerCase(java.util.Locale.ROOT);
            if (!h.matches("[0-9a-f]{64}")) throw new Exception("Somme de contrôle illisible.");
            return h;
        } catch (SocketTimeoutException e) {
            throw new Exception("Connexion trop lente. Réessaie.");
        } catch (IOException e) {
            throw new Exception("Connexion interrompue. Réessaie.");
        } finally {
            if (c != null) c.disconnect();
        }
    }

    private static String sha256(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        InputStream in = new FileInputStream(f);
        try {
            byte[] b = new byte[65536];
            int n;
            while ((n = in.read(b)) > 0) md.update(b, 0, n);
        } finally {
            in.close();
        }
        StringBuilder sb = new StringBuilder();
        for (byte x : md.digest()) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    @SuppressWarnings("deprecation")
    private static Signature[] signers(PackageInfo p) {
        if (Build.VERSION.SDK_INT >= 28) {
            SigningInfo s = p.signingInfo;
            return s == null ? null : s.getApkContentsSigners();
        }
        return p.signatures;
    }

    private static boolean same(Signature[] a, Signature[] b) {
        if (a == null || b == null || a.length == 0 || a.length != b.length) return false;
        for (Signature x : a) {
            boolean ok = false;
            for (Signature y : b) {
                if (x.equals(y)) { ok = true; break; }
            }
            if (!ok) return false;
        }
        return true;
    }

    /** Paquet, version et signature : refuse tout APK qui n'est pas un vrai successeur de l'appli installée. */
    @SuppressWarnings("deprecation")
    private static void verify(Context c, File apk, int code) throws Exception {
        PackageManager pm = c.getPackageManager();
        int fl = Build.VERSION.SDK_INT >= 28 ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
        PackageInfo n = pm.getPackageArchiveInfo(apk.getAbsolutePath(), fl);
        if (n == null) throw new Exception("APK illisible ou corrompu.");
        if (!c.getPackageName().equals(n.packageName)) throw new Exception("Cet APK n'est pas celui de l'application.");
        long vc = Build.VERSION.SDK_INT >= 28 ? n.getLongVersionCode() : n.versionCode;
        if (vc != code) throw new Exception("La version de l'APK ne correspond pas à celle annoncée.");
        if (vc <= versionCode(c)) throw new Exception("Cet APK n'est pas plus récent que la version installée.");
        if (!same(signers(n), signers(self(c, fl)))) throw new Exception("Signature différente : installation refusée.");
    }

    /* ---------- installation ---------- */

    static boolean canInstall(Context c) {
        return c.getPackageManager().canRequestPackageInstalls();
    }

    static Intent unknownSourcesIntent(Context c) {
        return new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + c.getPackageName()));
    }

    static void install(Context c, File apk) throws Exception {
        PackageInstaller pi = c.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams sp = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        sp.setAppPackageName(c.getPackageName());
        int id = pi.createSession(sp);
        PackageInstaller.Session s = pi.openSession(id);
        try {
            OutputStream out = s.openWrite("base.apk", 0, apk.length());
            InputStream in = new FileInputStream(apk);
            try {
                byte[] b = new byte[65536];
                int n;
                while ((n = in.read(b)) > 0) out.write(b, 0, n);
                s.fsync(out);
            } finally {
                in.close();
                out.close();
            }
            Intent it = new Intent(c, InstallReceiver.class);
            it.setAction(ACTION);
            int fl = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            PendingIntent pend = PendingIntent.getBroadcast(c, id, it, fl);
            s.commit(pend.getIntentSender());
        } catch (Exception e) {
            s.abandon();
            throw e;
        } finally {
            s.close();
        }
    }

    static void notifyResult(final int status, final String msg) {
        Api.MAIN.post(() -> {
            Result r = listener;
            if (r != null) r.on(status, msg);
        });
    }

    /* ---------- ménage et vérification au démarrage ---------- */

    static void cleanup(Context c) {
        try {
            int cur = versionCode(c);
            File[] fs = dir(c).listFiles();
            if (fs == null) return;
            Pattern p = Pattern.compile("kidas-controle-(\\d+)\\.apk(\\.part)?");
            for (File f : fs) {
                Matcher m = p.matcher(f.getName());
                if (!m.matches()) { f.delete(); continue; }
                try {
                    if (Integer.parseInt(m.group(1)) <= cur) f.delete();
                } catch (NumberFormatException e) {
                    f.delete();
                }
            }
        } catch (Exception ignored) { /* ménage facultatif */ }
    }

    /** Une seule fois par lancement. Silencieux si rien de neuf ou en cas d'erreur. */
    static void autoCheck(final MainActivity a) {
        if (autoDone) return;
        autoDone = true;
        Api.EX.execute(() -> cleanup(a));
        if ("0".equals(a.store.get("upd_auto"))) return;
        Api.async(() -> check(a), info -> {
            if (info.available && !a.isFinishing() && !a.isDestroyed()) new UpdateDialog(a, info).show();
        }, e -> { /* silencieux */ });
    }
}
