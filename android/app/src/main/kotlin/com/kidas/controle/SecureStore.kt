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
 * Auto-réparation : quand le Keystore rend la clé inutilisable (erreur
 * « Keystore operation failed » après une mise à jour du système, une
 * restauration de sauvegarde ou un TEE défaillant), le coffre se réinitialise
 * — clé et contenu chiffré effacés, nouvelle clé générée au prochain accès.
 * Le seul secret conservé est le jeton GitHub, resaisissable en quelques
 * secondes : mieux vaut un coffre sain qu'une erreur irrécupérable en boucle.
 */
internal class SecureStore(context: Context) {
    private val prefs = context.getSharedPreferences("kidas_secure_native", Context.MODE_PRIVATE)

    /** Signalée à Dart après une réinitialisation : le secret est perdu, pas l'app. */
    class VaultReset : Exception()

    @Synchronized
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing

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

    /** Repart d'un coffre vierge : clé Keystore et contenu chiffré effacés. */
    @Synchronized
    fun reset() {
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS)
        } catch (e: Exception) {
            // La clé est de toute façon inutilisable : on repart du coffre vierge.
        }
        prefs.edit().clear().commit()
    }

    @Synchronized
    fun get(name: String): String {
        val encoded = prefs.getString(name, null) ?: return ""
        return try {
            decrypt(encoded, name)
        } catch (e: Exception) {
            // Clé inutilisable ou données illisibles : le contenu est
            // irrécupérable. Réinitialiser puis le signaler, plutôt que
            // de boucler sur l'erreur à chaque ouverture.
            reset()
            throw VaultReset()
        }
    }

    @Synchronized
    fun set(name: String, value: String) {
        try {
            putEncrypted(name, value)
            return
        } catch (e: IllegalStateException) {
            // Échec d'écriture Android : réinitialiser le coffre n'y changerait rien.
            throw e
        } catch (e: Exception) {
            // Clé Keystore inutilisable : réinitialiser puis réessayer une fois.
            reset()
        }
        try {
            putEncrypted(name, value)
        } catch (e: Exception) {
            throw IllegalStateException(
                "Le Keystore reste indisponible après réinitialisation : ${e.message}"
            )
        }
    }

    @Synchronized
    fun delete(name: String) {
        if (!prefs.edit().remove(name).commit()) {
            throw IllegalStateException("Android n'a pas confirmé la suppression sécurisée.")
        }
    }

    private fun putEncrypted(name: String, value: String) {
        val all = encrypt(value)
        if (!prefs.edit().putString(name, Base64.encodeToString(all, Base64.NO_WRAP)).commit()) {
            throw IllegalStateException("Android n'a pas confirmé l'enregistrement sécurisé.")
        }
    }

    private fun encrypt(value: String): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return cipher.iv + cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
    }

    private fun decrypt(encoded: String, name: String): String {
        val all = Base64.decode(encoded, Base64.NO_WRAP)
        if (all.size <= IV_LENGTH) {
            throw IllegalStateException("Donnée chiffrée invalide pour $name.")
        }
        val iv = all.copyOfRange(0, IV_LENGTH)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
        return String(cipher.doFinal(all, IV_LENGTH, all.size - IV_LENGTH), StandardCharsets.UTF_8)
    }

    private companion object {
        const val ALIAS = "kidas_controle_flutter_aes"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
