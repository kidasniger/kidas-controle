package com.kidas.controle.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-256-GCM vault. Preferences contain ciphertext and IV only. */
class TokenVault(private val context: Context) {
    private val prefs = context.getSharedPreferences("kidas_secure_vault", Context.MODE_PRIVATE)
    private val alias = "kidas_native_key"
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    data class VaultPayload(
        val token: String,
        val dataRepository: String,
        val managerRepository: String,
        val expiresAt: Long?
    )

    fun hasCredential(): Boolean = prefs.contains("ciphertext") && prefs.contains("iv")
    fun canUseDeviceAuthentication(): Boolean = runCatching {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        keyguard.isDeviceSecure
    }.getOrDefault(false)

    fun createEncryptCipher(): Cipher = cipher(Cipher.ENCRYPT_MODE)
    fun createDecryptCipher(): Cipher {
        val iv = prefs.getString("iv", null)?.let { Base64.decode(it, Base64.NO_WRAP) }
            ?: throw IllegalStateException("Aucun jeton enregistré")
        return cipher(Cipher.DECRYPT_MODE, iv)
    }

    fun saveAuthenticated(cipher: Cipher, payload: VaultPayload) {
        val plain = encode(payload).toByteArray(Charsets.UTF_8)
        try {
            val encrypted = cipher.doFinal(plain)
            prefs.edit()
                .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .apply()
        } finally { plain.fill(0) }
    }

    fun readAuthenticated(cipher: Cipher): VaultPayload {
        val encrypted = prefs.getString("ciphertext", null)
            ?: throw IllegalStateException("Aucun jeton enregistré")
        val plain = cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP))
        return try { decode(String(plain, Charsets.UTF_8)) } finally { plain.fill(0) }
    }

    private fun cipher(mode: Int, iv: ByteArray? = null): Cipher {
        val key = getOrCreateKey()
        return Cipher.getInstance("AES/GCM/NoPadding").apply {
            if (mode == Cipher.ENCRYPT_MODE) init(mode, key)
            else init(mode, key, GCMParameterSpec(128, requireNotNull(iv)))
        }
    }

    private fun getOrCreateKey(): SecretKey {
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val builder = KeyGenParameterSpec.Builder(
            alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0, KeyProperties.AUTH_BIOMETRIC_STRONG
            ).setInvalidatedByBiometricEnrollment(false)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(60)
        }
        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun encode(p: VaultPayload) = listOf(
        b64(p.token), b64(p.dataRepository), b64(p.managerRepository), p.expiresAt?.toString().orEmpty()
    ).joinToString("|")
    private fun decode(value: String): VaultPayload {
        val p = value.split("|")
        require(p.size == 4) { "Données sécurisées invalides" }
        return VaultPayload(unb64(p[0]), unb64(p[1]), unb64(p[2]), p[3].toLongOrNull())
    }
    private fun b64(s: String) = Base64.encodeToString(s.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
    private fun unb64(s: String) = String(Base64.decode(s, Base64.NO_WRAP), Charsets.UTF_8)
}
