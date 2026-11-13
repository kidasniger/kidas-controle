package com.kidas.controle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Stockage v1 (AES-GCM maison, ex-SecureStore.java) : lecture seule,
 * utilisée une fois pour migrer les valeurs vers flutter_secure_storage.
 */
class LegacyStore(c: Context) {
    private val prefs = c.getSharedPreferences("kidas_secure", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        if (!ks.containsAlias(ALIAS)) {
            val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            kg.init(
                KeyGenParameterSpec.Builder(
                    ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            return kg.generateKey()
        }
        return ks.getKey(ALIAS, null) as SecretKey
    }

    fun keys(): List<String> = prefs.all.keys.toList()

    fun get(k: String): String? {
        val v = prefs.getString(k, null) ?: return null
        return try {
            val all = Base64.decode(v, Base64.DEFAULT)
            val iv = all.copyOfRange(0, 12)
            val cip = Cipher.getInstance("AES/GCM/NoPadding")
            cip.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            String(cip.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val ALIAS = "kidas_controle_key"
    }
}
