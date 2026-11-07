package com.kidas.controle.security

import com.kidas.controle.data.GitHubTokenProvider
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Sole runtime owner of plaintext credentials; Compose never owns a persisted token state. */
class SecureTokenRepository(private val vault: TokenVault) : GitHubTokenProvider {
    private val mutex = Mutex()
    @Volatile private var session: TokenVault.VaultPayload? = null
    @Volatile private var pending: TokenVault.VaultPayload? = null

    fun prepareCredential(
        token: String, dataRepository: String, managerRepository: String, expiresAt: Long?
    ) {
        require(token.isNotBlank()) { "Colle de nouveau ton jeton" }
        require(dataRepository.contains("/") && managerRepository.contains("/")) { "Nom de dépôt invalide" }
        pending = TokenVault.VaultPayload(
            token.trim(), dataRepository.trim(), managerRepository.trim(), expiresAt
        )
    }

    suspend fun storePreparedAuthenticated(cipher: javax.crypto.Cipher) = mutex.withLock {
        val payload = pending ?: throw IllegalStateException("Aucun jeton à enregistrer")
        vault.saveAuthenticated(cipher, payload)
        session = payload
        pending = null
    }

    suspend fun discardPending() = mutex.withLock { pending = null }

    suspend fun acceptAuthenticated(cipher: javax.crypto.Cipher) = mutex.withLock {
        session = vault.readAuthenticated(cipher)
    }

    override suspend fun getToken(): String = mutex.withLock {
        val current = session ?: throw IllegalStateException("Déverrouille l’application pour continuer")
        if (current.expiresAt != null && current.expiresAt <= System.currentTimeMillis()) {
            session = null
            throw IllegalStateException("Le jeton GitHub a expiré")
        }
        current.token
    }

    suspend fun lock() = mutex.withLock { session = null; pending = null }
    suspend fun credentialExpiry(): Long? = mutex.withLock { session?.expiresAt }

    suspend fun repositories(): Pair<String, String>? = mutex.withLock {
        session?.let { it.dataRepository to it.managerRepository }
    }
}
