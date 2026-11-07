package com.kidas.controle;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Stockage clé/valeur chiffré (AES-GCM, clé dans l'Android Keystore). */
final class SecureStore {
    private static final String ALIAS = "kidas_controle_key";
    private static final int IV_LEN = 12;
    private final SharedPreferences prefs;

    SecureStore(Context c) {
        prefs = c.getSharedPreferences("kidas_secure", Context.MODE_PRIVATE);
    }

    private SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (!ks.containsAlias(ALIAS)) {
            KeyGenerator kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            kg.init(new KeyGenParameterSpec.Builder(ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build());
            return kg.generateKey();
        }
        return (SecretKey) ks.getKey(ALIAS, null);
    }

    String get(String k) {
        String v = prefs.getString(k, null);
        if (v == null) return "";
        try {
            byte[] all = Base64.decode(v, Base64.NO_WRAP);
            byte[] iv = Arrays.copyOfRange(all, 0, IV_LEN);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, iv));
            return new String(c.doFinal(all, IV_LEN, all.length - IV_LEN), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    void set(String k, String v) {
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, key());
            byte[] iv = c.getIV();
            byte[] ct = c.doFinal(v.getBytes(StandardCharsets.UTF_8));
            byte[] all = new byte[iv.length + ct.length];
            System.arraycopy(iv, 0, all, 0, iv.length);
            System.arraycopy(ct, 0, all, iv.length, ct.length);
            prefs.edit().putString(k, Base64.encodeToString(all, Base64.NO_WRAP)).apply();
        } catch (Exception e) {
            // rien n'est enregistré en cas d'échec
        }
    }

    void del(String k) {
        prefs.edit().remove(k).apply();
    }
}
