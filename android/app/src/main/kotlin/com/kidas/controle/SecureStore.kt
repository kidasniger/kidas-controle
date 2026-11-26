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
import java.util.UUID

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

    private fun key(alias: String, createIfMissing: Boolean): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        if (!createIfMissing) {
            throw IllegalStateException(
                "Clé Android Keystore absente ($alias). Les données chiffrées ont été conservées."
            )
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    fun get(name: String): String = synchronized(LOCK) {
        val encoded = prefs.getString(name, null) ?: return@synchronized ""
        try {
            val alias = prefs.getString(aliasName(name), ALIAS) ?: ALIAS
            decrypt(encoded, alias)
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
        // Une nouvelle clé est créée à chaque remplacement explicite du secret.
        // Cela permet de récupérer d'une ancienne clé Keystore devenue inutilisable
        // sans la supprimer ni toucher au ciphertext précédent avant le commit.
        val newAlias = "${ALIAS}_${UUID.randomUUID().toString().replace("-", "")}"
        val encrypted = encrypt(value, newAlias)
        val encoded = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        val saved = prefs.edit()
            .putString(name, encoded)
            .putString(aliasName(name), newAlias)
            .commit()
        if (!saved) {
            throw IllegalStateException(
                "Android n'a pas confirmé l'enregistrement sécurisé. L'ancienne donnée et sa clé sont conservées."
            )
        }
    }

    fun delete(name: String) = synchronized(LOCK) {
        if (!prefs.edit().remove(name).remove(aliasName(name)).commit()) {
            throw IllegalStateException("Android n'a pas confirmé la suppression sécurisée.")
        }
    }

    private fun encrypt(value: String, alias: String): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(alias, createIfMissing = true))
        return cipher.iv + cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
    }

    private fun decrypt(encoded: String, alias: String): String {
        val all = Base64.decode(encoded, Base64.NO_WRAP)
        if (all.size <= IV_LENGTH) {
            throw IllegalStateException("Donnée chiffrée incomplète.")
        }
        val iv = all.copyOfRange(0, IV_LENGTH)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(alias, createIfMissing = false),
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
        fun aliasName(name: String) = "${name}__key_alias"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
