package com.kidas.controle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Coffre AES-GCM natif. Il évite la génération d'une paire RSA par le plugin
 * flutter_secure_storage, qui échoue sur certains Keystore Android.
 *
 * Ne remplace jamais une clé manquante si des données chiffrées existent :
 * mieux vaut signaler une erreur que rendre les secrets irrécupérables.
 */
internal class SecureStore(context: Context) {
    private val prefs = context.getSharedPreferences("kidas_secure_native", Context.MODE_PRIVATE)

    @Synchronized
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing

        if (prefs.all.isNotEmpty()) {
            throw IllegalStateException(
                "La clé du coffre est absente alors que des données chiffrées existent. " +
                    "Aucune donnée n'a été effacée."
            )
        }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    @Synchronized
    fun get(name: String): String {
        val encoded = prefs.getString(name, null) ?: return ""
        val all = Base64.decode(encoded, Base64.NO_WRAP)
        if (all.size <= IV_LENGTH) {
            throw IllegalStateException("Donnée chiffrée invalide pour $name.")
        }
        val iv = all.copyOfRange(0, IV_LENGTH)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
        return String(cipher.doFinal(all, IV_LENGTH, all.size - IV_LENGTH), StandardCharsets.UTF_8)
    }

    @Synchronized
    fun set(name: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val all = ByteArray(iv.size + encrypted.size)
        System.arraycopy(iv, 0, all, 0, iv.size)
        System.arraycopy(encrypted, 0, all, iv.size, encrypted.size)
        if (!prefs.edit().putString(name, Base64.encodeToString(all, Base64.NO_WRAP)).commit()) {
            throw IllegalStateException("Android n'a pas confirmé l'enregistrement sécurisé.")
        }
    }

    @Synchronized
    fun delete(name: String) {
        if (!prefs.edit().remove(name).commit()) {
            throw IllegalStateException("Android n'a pas confirmé la suppression sécurisée.")
        }
    }

    private companion object {
        const val ALIAS = "kidas_controle_flutter_aes"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
