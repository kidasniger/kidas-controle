package com.kidas.controle.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.io.InterruptedIOException
import java.util.concurrent.TimeUnit

/** Token provider is injected; credentials are never persisted by this client. */
fun interface GitHubTokenProvider {
    suspend fun getToken(): String
}

class GitHubApiException(
    val httpCode: Int,
    val path: String,
    detail: String? = null
) : IOException(buildMessage(httpCode, path, detail)) {
    companion object {
        private fun buildMessage(code: Int, path: String, detail: String?): String {
            val translated = when (code) {
                0 -> "Réseau indisponible"
                401 -> "Jeton invalide ou expiré"
                403, 404 -> {
                    val right = when {
                        path.contains("/actions/variables") -> "Variables"
                        path.contains("/actions/") || path.contains("/workflows") -> "Actions"
                        path.contains("/contents") -> "Contents"
                        else -> "accès au dépôt"
                    }
                    "Droit manquant : $right"
                }
                else -> if (code == 408 || code == 504) "Réessaie" else "Erreur GitHub ($code)"
            }
            val apiMessage = runCatching {
                detail?.takeIf { it.trimStart().startsWith("{") }
                    ?.let { org.json.JSONObject(it).optString("message") }
                    ?.takeIf { it.isNotBlank() }
            }.getOrNull()
            return if (apiMessage != null && code !in setOf(401, 403, 404, 408, 504)) "$translated : $apiMessage" else translated
        }
    }
}

data class GitHubResponse(val code: Int, val body: String, val bytes: ByteArray) {
    val isSuccessful: Boolean get() = code in 200..299
}

class GitHubApiClient(
    private val tokenProvider: GitHubTokenProvider,
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .cache(null)
        .build()
) {
    private val jsonType = "application/vnd.github+json".toMediaType()
    private val bodyType = "application/json; charset=utf-8".toMediaType()

    suspend fun request(
        method: String,
        path: String,
        payload: String? = null,
        accept: String = "application/vnd.github+json"
    ): GitHubResponse = withContext(Dispatchers.IO) {
        val token = tokenProvider.getToken().trim()
        if (token.isEmpty()) throw GitHubApiException(401, path)
        val builder = Request.Builder()
            .url("https://api.github.com" + if (path.startsWith("/")) path else "/$path")
            .header("Authorization", "Bearer $token")
            .header("Accept", accept)
            .header("X-GitHub-Api-Version", "2022-11-28")
        if (payload != null) {
            builder.method(method, payload.toRequestBody(bodyType))
        } else {
            builder.method(method, if (method in setOf("POST", "PUT", "PATCH")) "{}".toRequestBody(bodyType) else null)
        }
        try {
            http.newCall(builder.build()).execute().use { response ->
                val bytes = response.body?.bytes() ?: ByteArray(0)
                GitHubResponse(response.code, bytes.toString(Charsets.UTF_8), bytes)
            }
        } catch (e: InterruptedIOException) {
            throw GitHubApiException(408, path, "Réessaie")
        } catch (e: IOException) {
            throw GitHubApiException(0, path, "Réseau indisponible")
        }
    }

    suspend fun requireSuccess(method: String, path: String, payload: String? = null): GitHubResponse {
        val response = request(method, path, payload)
        if (!response.isSuccessful) throw GitHubApiException(response.code, path, response.body)
        return response
    }

    companion object {
        fun encodePath(value: String): String = value.split("/").joinToString("/") {
            java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20")
        }
    }
}
