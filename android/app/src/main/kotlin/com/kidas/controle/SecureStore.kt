package com.kidas.controle

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Coffre AES-GCM natif.
 *
 * Règle de sécurité : une erreur de Keystore ou de déchiffrement ne déclenche
 * JAMAIS d'effacement automatique. Les données chiffrées restent intactes afin
 * qu'une panne temporaire ne détruise pas le jeton de l'utilisateur.
 */
internal class SecureStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "kidas_secure_native", Context.MODE_PRIVATE
    )

    private fun key(createIfMissing: Boolean): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing
        if (!createIfMissing) {
            throw IllegalStateException(
                "Clé Android Keystore absente. Les données chiffrées ont été conservées."
            )
        }

        try {
            val generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
            )
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
        } catch (e: Exception) {
            throw IllegalStateException(
                "Android Keystore ne peut pas créer la clé. Aucune donnée du coffre n'a été effacée.",
                e
            )
        }
    }

    fun get(name: String): String = synchronized(LOCK) {
        val encoded = prefs.getString(name, null) ?: return@synchronized ""
        try {
            decrypt(encoded)
        } catch (e: Exception) {
            val detail = if (e is AEADBadTagException) {
                "Authentification AES-GCM refusée."
            } else {
                e.message ?: e.javaClass.simpleName
            }
            throw IllegalStateException(
                "Lecture sécurisée impossible ($detail). Les données du coffre ont été conservées.",
                e
            )
        }
    }

    fun set(name: String, value: String) = synchronized(LOCK) {
        // La création est autorisée ici car l'utilisateur fournit explicitement
        // une nouvelle valeur. L'ancienne valeur chiffrée n'est remplacée
        // qu'après chiffrement réussi et commit confirmé.
        val encrypted = encrypt(value)
        val encoded = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        if (!prefs.edit().putString(name, encoded).commit()) {
            throw IllegalStateException(
                "Android n'a pas confirmé l'enregistrement sécurisé. L'ancienne donnée est conservée."
            )
        }
    }

    fun delete(name: String) = synchronized(LOCK) {
        if (!prefs.edit().remove(name).commit()) {
            throw IllegalStateException("Android n'a pas confirmé la suppression sécurisée.")
        }
    }

    private fun encrypt(value: String): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(createIfMissing = true))
        return cipher.iv + cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
    }

    private fun decrypt(encoded: String): String {
        val all = Base64.decode(encoded, Base64.NO_WRAP)
        if (all.size <= IV_LENGTH) {
            throw IllegalStateException("Donnée chiffrée incomplète.")
        }
        val iv = all.copyOfRange(0, IV_LENGTH)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(createIfMissing = false),
            GCMParameterSpec(TAG_BITS, iv)
        )
        return String(
            cipher.doFinal(all, IV_LENGTH, all.size - IV_LENGTH),
            StandardCharsets.UTF_8
        )
    }

    private companion object {
        // Verrou commun à toutes les instances créées par MainActivity.
        val LOCK = Any()
        const val ALIAS = "kidas_controle_flutter_aes"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
