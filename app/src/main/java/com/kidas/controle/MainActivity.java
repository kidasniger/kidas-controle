package com.kidas.controle;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.JsResult;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final int REQ_FILE = 1;
    private static final int REQ_UNLOCK = 2;
    private static final long LOCK_AFTER_MS = 60000L;
    private static final String PAGE = "file:///android_asset/index.html";

    private WebView web;
    private SecureStore store;
    private boolean locked = true;
    private boolean external = false;
    private boolean warned = false;
    private long stoppedAt = 0;
    private ValueCallback<Uri[]> filePending;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        store = new SecureStore(this);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#0A0F1E"));
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0A0F1E"));
        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(false);

        web.addJavascriptInterface(new Bridge(), "AndroidStore");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                String path = u.getPath();
                if ("file".equals(u.getScheme()) && path != null && path.startsWith("/android_asset/")) {
                    return false;
                }
                openExternal(u);
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                                             FileChooserParams params) {
                if (filePending != null) {
                    filePending.onReceiveValue(null);
                }
                filePending = callback;
                try {
                    external = true;
                    startActivityForResult(params.createIntent(), REQ_FILE);
                } catch (ActivityNotFoundException e) {
                    external = false;
                    filePending = null;
                    callback.onReceiveValue(null);
                }
                return true;
            }

            @Override
            public boolean onJsConfirm(WebView view, String url, String message, final JsResult result) {
                new AlertDialog.Builder(MainActivity.this)
                        .setMessage(message)
                        .setPositiveButton("OK", (d, w) -> result.confirm())
                        .setNegativeButton("Annuler", (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel())
                        .show();
                return true;
            }

            @Override
            public boolean onJsAlert(WebView view, String url, String message, final JsResult result) {
                new AlertDialog.Builder(MainActivity.this)
                        .setMessage(message)
                        .setPositiveButton("OK", (d, w) -> result.confirm())
                        .setOnCancelListener(d -> result.confirm())
                        .show();
                return true;
            }
        });

        web.setVisibility(View.INVISIBLE);
        web.loadUrl(PAGE);
    }

    @Override
    protected void onStart() {
        super.onStart();
        if (!external && (locked || SystemClock.elapsedRealtime() - stoppedAt > LOCK_AFTER_MS)) {
            lock();
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        stoppedAt = SystemClock.elapsedRealtime();
    }

    private void lock() {
        locked = true;
        web.setVisibility(View.INVISIBLE);
        KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (km == null || !km.isDeviceSecure()) {
            if (!warned) {
                warned = true;
                Toast.makeText(this, "Aucun verrouillage d'écran : l'application n'est pas protégée.",
                        Toast.LENGTH_LONG).show();
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
        web.setVisibility(View.VISIBLE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_UNLOCK) {
            external = false;
            if (resultCode == RESULT_OK) {
                unlock();
            } else {
                finish();
            }
            return;
        }
        if (requestCode == REQ_FILE) {
            external = false;
            if (filePending != null) {
                filePending.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                filePending = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onBackPressed() {
        if (!locked && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }

    private void openExternal(Uri u) {
        String sc = u.getScheme();
        if ("https".equals(sc) || "http".equals(sc)) {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, u));
            } catch (ActivityNotFoundException e) {
                // aucun navigateur disponible
            }
        }
    }

    /** Pont JavaScript : stockage chiffré et presse-papiers. */
    public class Bridge {
        @JavascriptInterface
        public String get(String k) {
            return store.get(k);
        }

        @JavascriptInterface
        public void set(String k, String v) {
            store.set(k, v);
        }

        @JavascriptInterface
        public void del(String k) {
            store.del(k);
        }

        @JavascriptInterface
        public void copy(final String t) {
            runOnUiThread(() -> {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                if (cm != null) {
                    cm.setPrimaryClip(ClipData.newPlainText("KI DAS", t));
                }
            });
        }
    }
}
