package com.kidas.controle.security

import com.kidas.controle.data.GitHubTokenProvider
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Sole runtime owner of the decrypted GitHub token. Never expose it to UI state or logs. */
class SecureTokenRepository(private val vault: TokenVault) : GitHubTokenProvider {
    private val mutex = Mutex()
    @Volatile private var session: TokenVault.VaultPayload? = null

    suspend fun acceptAuthenticated(cipher: javax.crypto.Cipher) = mutex.withLock {
        session = vault.readAuthenticated(cipher)
    }
    suspend fun storeAuthenticated(
        cipher: javax.crypto.Cipher, token: String, dataRepository: String,
        managerRepository: String, expiresAt: Long?
    ) = mutex.withLock {
        require(token.isNotBlank()) { "Colle de nouveau ton jeton" }
        vault.saveAuthenticated(cipher, TokenVault.VaultPayload(
            token.trim(), dataRepository.trim(), managerRepository.trim(), expiresAt
        ))
        session = null
        session = vault.readAuthenticated(vault.createDecryptCipher()) // only after fresh user authentication
    }
    override suspend fun getToken(): String = mutex.withLock {
        val current = session ?: throw IllegalStateException("Déverrouille l’application pour continuer")
        if (current.expiresAt != null && current.expiresAt <= System.currentTimeMillis()) {
            session = null
            throw IllegalStateException("Le jeton GitHub a expiré")
        }
        current.token
    }
    suspend fun lock() = mutex.withLock { session = null }
    suspend fun repositories(): Pair<String, String>? = mutex.withLock {
        session?.let { it.dataRepository to it.managerRepository }
    }
}
