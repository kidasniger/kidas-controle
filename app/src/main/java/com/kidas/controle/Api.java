package com.kidas.controle;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/** Accès GitHub (API REST) + modèles de données partagés par les écrans. */
final class Api {
    static String tok = "";
    static String data = "kidasniger/facebook-data";
    static String mgr = "kidasniger/facebook-manager";
    static String exp = "";
    static JSONArray wf = null;

    static final ExecutorService EX = Executors.newCachedThreadPool();
    static final ExecutorService EXT = Executors.newFixedThreadPool(3);
    static final Handler MAIN = new Handler(Looper.getMainLooper());
    static final String[] QUEUES = {"queue", "avance", "replies", "actions", "messages"};

    interface Job<T> { T run() throws Exception; }
    interface Ok<T> { void ok(T v); }
    interface Err { void err(Exception e); }
    interface Call<T> { T run(int attempt) throws Exception; }
    interface Mut { Object apply(Object cur) throws Exception; }
    interface Say { void say(String s); }

    static class ApiError extends Exception {
        final int status;
        final String path;
        ApiError(int s, String m, String p) { super(m); status = s; path = p; }
    }

    static class FileData {
        final String sha;
        final String text;
        FileData(String s, String t) { sha = s; text = t; }
    }

    static void loadCfg(SecureStore s) {
        tok = s.get("gh_token");
        String d = s.get("cfg_data");
        if (!d.isEmpty()) data = d;
        String m = s.get("cfg_mgr");
        if (!m.isEmpty()) mgr = m;
        exp = s.get("cfg_exp");
    }

    /* ---------- exécution asynchrone ---------- */

    static <T> void async(final Job<T> job, final Ok<T> ok, final Err err) {
        EX.execute(() -> {
            T r = null;
            Exception ex = null;
            try {
                r = job.run();
            } catch (Exception e) {
                ex = e;
            }
            final T fr = r;
            final Exception fe = ex;
            MAIN.post(() -> {
                if (fe != null) {
                    if (err != null) err.err(fe);
                } else if (ok != null) {
                    ok.ok(fr);
                }
            });
        });
    }

    static <T> Future<T> par(Callable<T> c) { return EX.submit(c); }

    static <T> T get(Future<T> f, List<Exception> errs) {
        try {
            return f.get();
        } catch (ExecutionException e) {
            Throwable c = e.getCause();
            errs.add(c instanceof Exception ? (Exception) c : new Exception(c));
        } catch (InterruptedException e) {
            errs.add(e);
        }
        return null;
    }

    static void put(JSONObject o, String k, Object v) {
        try { o.put(k, v); } catch (JSONException e) { /* ignoré */ }
    }

    static <T> T retry(Call<T> c) throws Exception {
        Exception last = null;
        for (int i = 0; i < 5; i++) {
            try {
                return c.run(i);
            } catch (ApiError e) {
                last = e;
                if (e.status == 409 || e.status == 422) {
                    Thread.sleep(700L * (i + 1) + (long) (Math.random() * 500));
                    continue;
                }
                throw e;
            }
        }
        throw last;
    }

    /* ---------- messages d'erreur ---------- */

    static String need(String p) {
        p = p == null ? "" : p;
        int q = p.indexOf('?');
        if (q >= 0) p = p.substring(0, q);
        String repo = p.contains("/" + mgr + "/") ? mgr : data;
        if (p.contains("/actions/variables")) return "Variables : Read and write sur " + mgr;
        if (p.contains("/actions/")) return "Actions : Read and write sur " + mgr;
        return "Contents : Read and write sur " + repo;
    }

    static String hint(Exception e) {
        if (e instanceof ApiError) {
            ApiError a = (ApiError) e;
            if (a.status == 401) return "Jeton invalide ou expiré. Va dans Réglages.";
            if (a.status == 403 || a.status == 404) {
                return "Droit manquant sur le jeton : " + need(a.path) + ".";
            }
            return a.getMessage();
        }
        return e.getMessage() == null ? e.toString() : e.getMessage();
    }

    /* ---------- HTTP ---------- */

    static String cp(String path) {
        StringBuilder sb = new StringBuilder();
        String[] parts = path.split("/");
        for (int i = 0; i < parts.length; i++) {
            if (i > 0) sb.append('/');
            try {
                sb.append(URLEncoder.encode(parts[i], "UTF-8").replace("+", "%20"));
            } catch (Exception e) {
                sb.append(parts[i]);
            }
        }
        return sb.toString();
    }

    private static HttpURLConnection open(String method, String path, String accept) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL("https://api.github.com" + path).openConnection();
        c.setRequestMethod(method);
        c.setConnectTimeout(15000);
        c.setReadTimeout(40000);
        c.setUseCaches(false);
        c.setRequestProperty("Authorization", "Bearer " + tok);
        c.setRequestProperty("Accept", accept == null ? "application/vnd.github+json" : accept);
        c.setRequestProperty("X-GitHub-Api-Version", "2022-11-28");
        return c;
    }

    static byte[] readAll(InputStream in) throws IOException {
        try {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return bo.toByteArray();
        } finally {
            in.close();
        }
    }

    private static String finish(HttpURLConnection c, String path) throws ApiError, IOException {
        int code = c.getResponseCode();
        InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
        String txt = in == null ? "" : new String(readAll(in), StandardCharsets.UTF_8);
        if (code == 204) return "";
        if (code >= 400) {
            String msg = "HTTP " + code;
            try {
                String m = new JSONObject(txt).optString("message", "");
                if (!m.isEmpty()) msg = m;
            } catch (JSONException e) { /* corps non JSON */ }
            throw new ApiError(code, msg, path);
        }
        return txt;
    }

    static String req(String method, String path, String body, String accept) throws ApiError {
        HttpURLConnection c = null;
        try {
            c = open(method, path, accept);
            String b = body;
            if (b == null && ("POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method))) b = "{}";
            if (b != null) {
                byte[] bytes = b.getBytes(StandardCharsets.UTF_8);
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json");
                c.setFixedLengthStreamingMode(bytes.length);
                OutputStream o = c.getOutputStream();
                o.write(bytes);
                o.close();
            }
            return finish(c, path);
        } catch (SocketTimeoutException e) {
            throw new ApiError(0, "Délai dépassé, réessaie.", path);
        } catch (IOException e) {
            throw new ApiError(0, "Réseau indisponible.", path);
        } finally {
            if (c != null) c.disconnect();
        }
    }

    static byte[] getBytes(String path) throws ApiError {
        HttpURLConnection c = null;
        try {
            c = open("GET", path, "application/vnd.github.raw+json");
            int code = c.getResponseCode();
            if (code >= 400) throw new ApiError(code, "HTTP " + code, path);
            return readAll(c.getInputStream());
        } catch (SocketTimeoutException e) {
            throw new ApiError(0, "Délai dépassé, réessaie.", path);
        } catch (IOException e) {
            throw new ApiError(0, "Réseau indisponible.", path);
        } finally {
            if (c != null) c.disconnect();
        }
    }

    static JSONObject jobj(String txt, String path) throws ApiError {
        try {
            return new JSONObject(txt);
        } catch (JSONException e) {
            throw new ApiError(0, "Réponse illisible.", path);
        }
    }

    /* ---------- fichiers du dépôt de données ---------- */

    static FileData getFile(String repo, String path) throws ApiError {
        String url = "/repos/" + repo + "/contents/" + cp(path);
        try {
            String t = req("GET", url, null, null);
            Object j = new JSONTokener(t).nextValue();
            if (!(j instanceof JSONObject)) return null;
            JSONObject o = (JSONObject) j;
            String c = o.optString("content", "");
            String txt;
            if (!c.isEmpty()) {
                txt = new String(Base64.decode(c, Base64.DEFAULT), StandardCharsets.UTF_8);
            } else {
                txt = req("GET", url, null, "application/vnd.github.raw+json");
            }
            return new FileData(o.optString("sha"), txt);
        } catch (ApiError e) {
            if (e.status == 404) return null;
            throw e;
        } catch (JSONException e) {
            throw new ApiError(0, "Réponse illisible.", url);
        }
    }

    static Object readJson(String path) throws ApiError {
        FileData f = getFile(data, path);
        if (f == null || f.text.trim().isEmpty()) return null;
        try {
            return new JSONTokener(f.text).nextValue();
        } catch (JSONException e) {
            return null;
        }
    }

    static JSONArray readArr(String path) throws ApiError {
        Object o = readJson(path);
        return o instanceof JSONArray ? (JSONArray) o : new JSONArray();
    }

    static JSONObject readObj(String path) throws ApiError {
        Object o = readJson(path);
        return o instanceof JSONObject ? (JSONObject) o : null;
    }

    /** Lit, modifie et réécrit un fichier JSON (reprise automatique en cas de conflit). */
    static void updateJson(final String path, final boolean isArray, final Mut m, final String msg) throws Exception {
        retry((Call<Object>) i -> {
            FileData f = getFile(data, path);
            Object cur = null;
            if (f != null && !f.text.trim().isEmpty()) cur = new JSONTokener(f.text).nextValue();
            if (cur == null || cur == JSONObject.NULL) cur = isArray ? new JSONArray() : new JSONObject();
            Object out = m.apply(cur);
            if (out == null) out = cur;
            String s = out instanceof JSONArray ? ((JSONArray) out).toString(2) : ((JSONObject) out).toString(2);
            JSONObject body = new JSONObject();
            body.put("message", msg);
            body.put("content", Base64.encodeToString((s + "\n").getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
            if (f != null) body.put("sha", f.sha);
            req("PUT", "/repos/" + data + "/contents/" + cp(path), body.toString(), null);
            return null;
        });
    }

    static JSONArray listDir(String path) throws ApiError {
        try {
            String t = req("GET", "/repos/" + data + "/contents/" + cp(path), null, null);
            Object j = new JSONTokener(t).nextValue();
            return j instanceof JSONArray ? (JSONArray) j : new JSONArray();
        } catch (ApiError e) {
            if (e.status == 404) return new JSONArray();
            throw e;
        } catch (JSONException e) {
            return new JSONArray();
        }
    }

    static void deleteFile(final String path, final String name, final String sha) throws Exception {
        retry((Call<Object>) i -> {
            JSONObject b = new JSONObject();
            b.put("message", "Suppression media " + name);
            b.put("sha", sha);
            req("DELETE", "/repos/" + data + "/contents/" + cp(path), b.toString(), null);
            return null;
        });
    }

    static String[] nameSize(Context c, Uri u) {
        String name = "fichier";
        long size = -1;
        Cursor cur = null;
        try {
            cur = c.getContentResolver().query(u, null, null, null, null);
            if (cur != null && cur.moveToFirst()) {
                int i = cur.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (i >= 0 && !cur.isNull(i)) name = cur.getString(i);
                int j = cur.getColumnIndex(OpenableColumns.SIZE);
                if (j >= 0 && !cur.isNull(j)) size = cur.getLong(j);
            }
        } catch (Exception e) { /* nom par défaut */ } finally {
            if (cur != null) cur.close();
        }
        return new String[]{name, String.valueOf(size)};
    }

    private static int readFull(InputStream in, byte[] buf) throws IOException {
        int off = 0;
        while (off < buf.length) {
            int n = in.read(buf, off, buf.length - off);
            if (n <= 0) break;
            off += n;
        }
        return off;
    }

    /** Envoie un fichier dans media/ en flux (pas de copie complète en mémoire). */
    static String upload(final Context ctx, final Uri uri, String displayName, final long size, final Say say) throws Exception {
        if (size > 50L * 1024 * 1024) throw new Exception("Fichier trop gros (maximum 50 Mo).");
        final String name = System.currentTimeMillis() + "-" + displayName.replaceAll("[^a-zA-Z0-9._-]", "_");
        final String path = "media/" + name;
        retry((Call<Object>) i -> {
            if (say != null) say.say(i > 0 ? "Nouvelle tentative " + (i + 1) + "..." : "Envoi...");
            putStream(ctx, uri, size, "/repos/" + data + "/contents/" + cp(path), "Ajout media " + name);
            return null;
        });
        return path;
    }

    private static void putStream(Context ctx, Uri uri, long size, String path, String msg) throws Exception {
        byte[] pre = ("{\"message\":" + JSONObject.quote(msg) + ",\"content\":\"").getBytes(StandardCharsets.UTF_8);
        byte[] suf = "\"}".getBytes(StandardCharsets.UTF_8);
        HttpURLConnection c = null;
        try {
            c = open("PUT", path, null);
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            if (size > 0) {
                c.setFixedLengthStreamingMode(pre.length + 4L * ((size + 2) / 3) + suf.length);
            } else {
                c.setChunkedStreamingMode(65536);
            }
            OutputStream o = c.getOutputStream();
            o.write(pre);
            InputStream in = ctx.getContentResolver().openInputStream(uri);
            if (in == null) throw new IOException("Lecture du fichier impossible.");
            try {
                byte[] buf = new byte[3 * 32768];
                int n;
                while ((n = readFull(in, buf)) > 0) o.write(Base64.encode(buf, 0, n, Base64.NO_WRAP));
            } finally {
                in.close();
            }
            o.write(suf);
            o.close();
            finish(c, path);
        } catch (SocketTimeoutException e) {
            throw new ApiError(0, "Délai dépassé, réessaie.", path);
        } catch (IOException e) {
            throw new ApiError(0, "Réseau indisponible ou lecture impossible.", path);
        } finally {
            if (c != null) c.disconnect();
        }
    }

    /* ---------- GitHub Actions ---------- */

    static void dispatch(String file, JSONObject inputs) throws ApiError {
        JSONObject b = new JSONObject();
        put(b, "ref", "main");
        if (inputs != null) put(b, "inputs", inputs);
        req("POST", "/repos/" + mgr + "/actions/workflows/" + file + "/dispatches", b.toString(), null);
    }

    static JSONArray workflows(boolean force) throws ApiError {
        if (wf == null || force) {
            JSONObject j = jobj(req("GET", "/repos/" + mgr + "/actions/workflows?per_page=50", null, null), "/actions/workflows");
            JSONArray a = j.optJSONArray("workflows");
            wf = a == null ? new JSONArray() : a;
        }
        return wf;
    }

    static JSONObject wfByFile(JSONArray list, String file) {
        if (list == null) return null;
        for (int i = 0; i < list.length(); i++) {
            JSONObject w = list.optJSONObject(i);
            if (w != null && w.optString("path").endsWith("/" + file)) return w;
        }
        return null;
    }

    static JSONArray runs(int n) throws ApiError {
        JSONObject j = jobj(req("GET", "/repos/" + mgr + "/actions/runs?per_page=" + n, null, null), "/actions/runs");
        JSONArray a = j.optJSONArray("workflow_runs");
        return a == null ? new JSONArray() : a;
    }

    static String getVar(String n) throws ApiError {
        try {
            return jobj(req("GET", "/repos/" + mgr + "/actions/variables/" + n, null, null), "/actions/variables").optString("value");
        } catch (ApiError e) {
            if (e.status == 404) return null;
            throw e;
        }
    }

    static void setVar(String n, String v) throws ApiError {
        JSONObject b = new JSONObject();
        put(b, "name", n);
        put(b, "value", v);
        String base = "/repos/" + mgr + "/actions/variables";
        try {
            req("PATCH", base + "/" + n, b.toString(), null);
        } catch (ApiError e) {
            if (e.status == 404) {
                req("POST", base, b.toString(), null);
            } else if (e.status == 0) {
                try { req("DELETE", base + "/" + n, null, null); } catch (ApiError ignored) { /* absent */ }
                req("POST", base, b.toString(), null);
            } else {
                throw e;
            }
        }
    }

    static void cancelRun(long id) throws ApiError {
        req("POST", "/repos/" + mgr + "/actions/runs/" + id + "/cancel", null, null);
    }

    static void startAudit() throws Exception {
        updateJson("audit/demande.json", false, cur -> {
            JSONObject o = new JSONObject();
            put(o, "status", "demande");
            put(o, "date", Ui.isoNow());
            return o;
        }, "Demande d'audit");
        dispatch("audit.yml", null);
    }

    /* ---------- état du bot ---------- */

    static class Bot {
        JSONObject cfg = new JSONObject();
        String live, auto, veille;
        int running;
        boolean hardOff, softOff;
        String state = "wait";
        final List<Exception> errs = new ArrayList<>();
    }

    static Bot botState() {
        Bot b = new Bot();
        Future<JSONObject> fCfg = par(() -> readObj("glm/config.json"));
        Future<String> fLive = par(() -> getVar("GLM_LIVE"));
        Future<String> fAuto = par(() -> getVar("AUTO_REPONSES"));
        Future<JSONArray> fWf = par(() -> workflows(false));
        Future<JSONObject> fRuns = par(() -> jobj(req("GET", "/repos/" + mgr + "/actions/workflows/glm-live.yml/runs?per_page=10", null, null), "glm-live"));
        JSONObject cfg = get(fCfg, b.errs);
        if (cfg != null) b.cfg = cfg;
        b.live = get(fLive, b.errs);
        b.auto = get(fAuto, b.errs);
        JSONArray wl = get(fWf, b.errs);
        JSONObject v = wfByFile(wl, "glm-veille.yml");
        b.veille = v == null ? null : v.optString("state");
        JSONObject rr = get(fRuns, b.errs);
        if (rr != null) {
            JSONArray a = rr.optJSONArray("workflow_runs");
            for (int i = 0; a != null && i < a.length(); i++) {
                JSONObject r = a.optJSONObject(i);
                if (r != null && !"completed".equals(r.optString("status"))) b.running++;
            }
        }
        b.hardOff = "off".equals(b.live);
        b.softOff = b.cfg.has("actif") && !b.cfg.optBoolean("actif", true);
        b.state = (b.hardOff || b.softOff) ? "off" : (b.running > 0 ? "on" : "wait");
        return b;
    }

    /* ---------- tableau de bord (accueil + stats) ---------- */

    static class Metric {
        String key, name;
        float[] vals;
        String[] labs;
    }

    static class Dash {
        JSONObject st, cm;
        JSONArray runs = new JSONArray();
        Bot bot;
        final int[] pending = new int[QUEUES.length];
        final int[] total = new int[QUEUES.length];
        final List<Exception> errs = new ArrayList<>();
    }

    static Dash dash() {
        Dash d = new Dash();
        Future<JSONObject> fs = par(() -> readObj("inbox/statistiques.json"));
        Future<JSONObject> fc = par(() -> readObj("inbox/commentaires.json"));
        List<Future<JSONArray>> fq = new ArrayList<>();
        for (final String n : QUEUES) fq.add(par(() -> readArr("posts/" + n + ".json")));
        Future<JSONArray> fr = par(() -> runs(20));
        Future<Bot> fb = par(() -> botState());
        d.st = get(fs, d.errs);
        d.cm = get(fc, d.errs);
        for (int i = 0; i < fq.size(); i++) {
            JSONArray a = get(fq.get(i), new ArrayList<Exception>());
            if (a == null) continue;
            for (int k = 0; k < a.length(); k++) {
                JSONObject e = a.optJSONObject(k);
                if (e == null) continue;
                d.total[i]++;
                if ("pending".equals(e.optString("status"))) d.pending[i]++;
            }
        }
        JSONArray r = get(fr, d.errs);
        if (r != null) d.runs = r;
        d.bot = get(fb, new ArrayList<Exception>());
        return d;
    }

    static int sum(int[] a) {
        int s = 0;
        for (int x : a) s += x;
        return s;
    }

    private static final String[][] NAMES = {
            {"page_post_engagements", "Interactions"},
            {"page_media_view", "Vues du contenu"},
            {"page_views_total", "Visites de la Page"},
            {"page_follows", "Abonnés (total)"},
            {"page_daily_follows_unique", "Nouveaux abonnés par jour"}
    };

    static List<Metric> metrics(JSONObject st) {
        List<Metric> out = new ArrayList<>();
        if (st == null) return out;
        JSONObject ms = st.optJSONObject("metriques");
        if (ms == null) return out;
        Iterator<String> it = ms.keys();
        while (it.hasNext()) {
            String k = it.next();
            JSONArray m = ms.optJSONArray(k);
            if (m == null || m.length() == 0) continue;
            JSONObject first = m.optJSONObject(0);
            if (first == null) continue;
            JSONArray vs = first.optJSONArray("valeurs");
            if (vs == null) continue;
            List<Float> nums = new ArrayList<>();
            List<String> labs = new ArrayList<>();
            boolean allLab = true;
            for (int i = 0; i < vs.length(); i++) {
                JSONObject v = vs.optJSONObject(i);
                if (v == null) continue;
                Object o = v.opt("valeur");
                if (!(o instanceof Number)) continue;
                nums.add(((Number) o).floatValue());
                String lab = dayLabel(v);
                if (lab == null) allLab = false;
                labs.add(lab);
            }
            if (nums.isEmpty()) continue;
            Metric mt = new Metric();
            mt.key = k;
            mt.name = k;
            for (String[] nm : NAMES) if (nm[0].equals(k)) mt.name = nm[1];
            mt.vals = new float[nums.size()];
            for (int i = 0; i < mt.vals.length; i++) mt.vals[i] = nums.get(i);
            if (allLab) mt.labs = labs.toArray(new String[0]);
            out.add(mt);
        }
        return out;
    }

    private static String dayLabel(JSONObject v) {
        String[] keys = {"date", "fin", "end_time", "fin_periode", "debut"};
        for (String k : keys) {
            String s = v.optString(k, "");
            if (s.length() >= 10 && s.charAt(4) == '-') return s.substring(8, 10) + "/" + s.substring(5, 7);
        }
        return null;
    }

    /* ---------- commentaires ---------- */

    static class Cmt {
        JSONObject c, post;
    }

    static List<Cmt> flatComments(JSONObject cm) {
        final List<Cmt> out = new ArrayList<>();
        if (cm == null) return out;
        JSONArray posts = cm.optJSONArray("posts");
        for (int i = 0; posts != null && i < posts.length(); i++) {
            JSONObject p = posts.optJSONObject(i);
            if (p == null) continue;
            JSONObject cc = p.optJSONObject("comments");
            JSONArray da = cc == null ? null : cc.optJSONArray("data");
            for (int k = 0; da != null && k < da.length(); k++) {
                JSONObject c = da.optJSONObject(k);
                if (c == null) continue;
                Cmt x = new Cmt();
                x.c = c;
                x.post = p;
                out.add(x);
            }
        }
        java.util.Collections.sort(out, (a, b) -> b.c.optString("created_time").compareTo(a.c.optString("created_time")));
        return out;
    }

    static List<Cmt> unanswered(List<Cmt> all, String pageId) {
        List<Cmt> out = new ArrayList<>();
        for (Cmt x : all) {
            JSONObject from = x.c.optJSONObject("from");
            String fid = from == null ? "" : from.optString("id", "");
            if (!x.c.optString("message", "").isEmpty() && x.c.has("page_a_repondu")
                    && !x.c.optBoolean("page_a_repondu", true) && !fid.equals(pageId == null ? "" : pageId)) {
                out.add(x);
            }
        }
        return out;
    }

    /* ---------- messages (Messenger) ---------- */

    /** Messenger n'autorise la réponse que 24 h après le dernier message de la personne. */
    static final long FENETRE_MS = 24L * 3600L * 1000L;
    static final int MESSAGE_MAX = 1000;

    /** Conversations de inbox/messages.json, la plus récente d'abord. */
    static List<JSONObject> conversations(JSONObject inbox) {
        List<JSONObject> out = new ArrayList<>();
        JSONArray a = inbox == null ? null : inbox.optJSONArray("conversations");
        for (int i = 0; a != null && i < a.length(); i++) {
            JSONObject c = a.optJSONObject(i);
            if (c != null) out.add(c);
        }
        java.util.Collections.sort(out, (x, y) -> y.optString("updated_time").compareTo(x.optString("updated_time")));
        return out;
    }

    /** Vrai quand le dernier message vient de la personne (la Page n'a pas encore répondu). */
    static boolean needsReply(JSONObject conv) {
        JSONArray m = conv.optJSONArray("messages");
        return m != null && m.length() > 0 && !conv.optBoolean("repondu", true);
    }

    static boolean windowOpen(JSONObject conv) {
        long t = Ui.iso(conv.optString("last_user_time", ""));
        return t > 0 && System.currentTimeMillis() - t < FENETRE_MS;
    }

    /** Dernier élément de posts/messages.json pour cette conversation, ou null. */
    static JSONObject lastQueued(JSONArray queue, String convId) {
        JSONObject r = null;
        for (int i = 0; queue != null && i < queue.length(); i++) {
            JSONObject e = queue.optJSONObject(i);
            if (e != null && convId.equals(e.optString("conversation_id"))) r = e;
        }
        return r;
    }

    /** Met une réponse Messenger en file : le bot l'envoie à son prochain cycle (environ 1 minute). */
    static void queueMessage(final String convId, final String recipientId, final String text) throws Exception {
        updateJson("posts/messages.json", true, cur -> {
            JSONObject e = new JSONObject();
            put(e, "conversation_id", convId);
            put(e, "recipient_id", recipientId);
            put(e, "message", text);
            put(e, "status", "pending");
            put(e, "created", Ui.isoNow());
            ((JSONArray) cur).put(e);
            return cur;
        }, "Message (appli de contrôle)");
    }

    static String pageId(JSONObject st, JSONObject cm) {
        JSONObject p = st == null ? null : st.optJSONObject("page");
        if (p != null && p.has("id")) return p.optString("id");
        p = cm == null ? null : cm.optJSONObject("page");
        return p == null ? "" : p.optString("id", "");
    }
}
