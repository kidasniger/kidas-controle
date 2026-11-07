package com.kidas.controle.ui.comments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kidas.controle.data.GitHubApiClient
import com.kidas.controle.data.GitHubDataRepository
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime

data class CommentUiItem(
    val id: String,
    val author: String,
    val authorId: String?,
    val createdAt: String?,
    val message: String,
    val postExcerpt: String,
    val answered: Boolean,
    val queued: Boolean = false
)

data class CommentsUiState(
    val loading: Boolean = true,
    val comments: List<CommentUiItem> = emptyList(),
    val updatedAt: String? = null,
    val error: String? = null,
    val sendingIds: Set<String> = emptySet()
) {
    val unansweredCount: Int get() = comments.count { !it.answered && !it.queued }
}

class CommentsViewModel(private val credentials: SecureTokenRepository) : ViewModel() {
    private val mutableState = MutableStateFlow(CommentsUiState())
    val state: StateFlow<CommentsUiState> = mutableState.asStateFlow()
    private var repository: GitHubDataRepository? = null

    private suspend fun data(): GitHubDataRepository {
        val repos = credentials.repositories() ?: error("Session verrouillée. Déverrouille KI DAS.")
        return repository ?: GitHubDataRepository(GitHubApiClient(credentials), repos.first, repos.second)
            .also { repository = it }
    }

    fun refresh() {
        if (mutableState.value.loading && mutableState.value.comments.isNotEmpty()) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(loading = true, error = null)
            try {
                val data = data()
                val raw = data.getFile(chemin = "inbox/commentaires.json")?.content
                    ?: error("Aucune donnée. Lance Surveiller depuis l'accueil.")
                val root = Json.parseToJsonElement(raw).jsonObject
                val pageId = root["page"]?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull
                val queuedIds = runCatching {
                    val replies = data.getFile(chemin = "posts/replies.json")?.content ?: "[]"
                    Json.parseToJsonElement(replies).jsonArray.mapNotNull { el ->
                        val obj = el.jsonObject
                        if (obj["status"]?.jsonPrimitive?.contentOrNull.equals("pending", true))
                            obj["comment_id"]?.jsonPrimitive?.contentOrNull else null
                    }.toSet()
                }.getOrDefault(emptySet())
                val flattened = mutableListOf<CommentUiItem>()
                fun walk(items: JsonArray?, postText: String) {
                    items.orEmpty().forEach { element ->
                        val obj = element.jsonObject
                        val id = obj["id"]?.jsonPrimitive?.contentOrNull
                        val text = obj["message"]?.jsonPrimitive?.contentOrNull.orEmpty()
                        if (!id.isNullOrBlank() && text.isNotBlank()) {
                            val authorObj = obj["from"]?.jsonObject
                            val authorId = authorObj?.get("id")?.jsonPrimitive?.contentOrNull
                            val author = if (authorId != null && authorId == pageId) "Ta Page"
                                else authorObj?.get("name")?.jsonPrimitive?.contentOrNull ?: "Utilisateur Facebook"
                            val queued = id in queuedIds
                            flattened += CommentUiItem(
                                id = id, author = author, authorId = authorId,
                                createdAt = obj["created_time"]?.jsonPrimitive?.contentOrNull,
                                message = text, postExcerpt = postText.ifBlank { "Publication Facebook" },
                                answered = obj["page_a_repondu"]?.jsonPrimitive?.booleanOrNull == true,
                                queued = queued
                            )
                        }
                        val nested = obj["comments"]?.let { value ->
                            when (value) {
                                is JsonArray -> value
                                is JsonObject -> value["data"]?.jsonArray
                                else -> null
                            }
                        }
                        walk(nested, postText)
                    }
                }
                root["posts"]?.jsonArray.orEmpty().forEach { post ->
                    val obj = post.jsonObject
                    val postText = obj["message"]?.jsonPrimitive?.contentOrNull
                        ?: obj["story"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    val comments = obj["comments"]?.jsonObject?.get("data")?.jsonArray
                    walk(comments, postText)
                }
                val sorted = flattened.distinctBy { it.id }.sortedByDescending { parseDate(it.createdAt) ?: Instant.EPOCH }
                mutableState.value = CommentsUiState(
                    loading = false, comments = sorted, updatedAt = root["updated"]?.jsonPrimitive?.contentOrNull
                        ?: root["date"]?.jsonPrimitive?.contentOrNull
                )
            } catch (error: Throwable) {
                mutableState.value = mutableState.value.copy(
                    loading = false,
                    error = error.message ?: "Impossible de charger les commentaires"
                )
            }
        }
    }

    fun sendReply(commentId: String, message: String) {
        if (message.isBlank() || commentId in mutableState.value.sendingIds) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(
                sendingIds = mutableState.value.sendingIds + commentId, error = null
            )
            try {
                val data = data()
                data.updateJSON(
                    "posts/replies.json", JsonArray(emptyList()),
                    { current ->
                        val entries = when (current) {
                            is JsonArray -> current.toMutableList()
                            else -> mutableListOf()
                        }
                        entries += buildJsonObject {
                            put("comment_id", commentId)
                            put("message", message.trim())
                            put("status", "pending")
                        }
                        JsonArray(entries)
                    },
                    "Mise en file réponse commentaire"
                )
                data.dispatch("repondre.yml")
                refresh()
            } catch (error: Throwable) {
                mutableState.value = mutableState.value.copy(error = error.message ?: "Impossible d’envoyer la réponse")
            } finally {
                mutableState.value = mutableState.value.copy(sendingIds = mutableState.value.sendingIds - commentId)
            }
        }
    }

    fun runSurveiller() {
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(loading = true, error = null)
            try {
                data().dispatch("surveiller.yml")
                mutableState.value = mutableState.value.copy(loading = false)
            } catch (error: Throwable) {
                mutableState.value = mutableState.value.copy(loading = false, error = error.message ?: "Impossible de lancer la surveillance")
            }
        }
    }

    private fun parseDate(value: String?): Instant? = value?.let {
        runCatching { Instant.parse(it) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull()
    }
}

fun commentRelativeTime(value: String?): String {
    val instant = value?.let {
        runCatching { Instant.parse(it) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull()
    } ?: return "Date inconnue"
    val minutes = Duration.between(instant, Instant.now()).toMinutes().coerceAtLeast(0)
    return when {
        minutes < 1 -> "À l’instant"
        minutes < 60 -> "Il y a $minutes min"
        minutes < 1440 -> "Il y a ${minutes / 60} h"
        else -> "Il y a ${minutes / 1440} j"
    }
}

fun commentAuditAge(value: String?): String {
    val instant = value?.let {
        runCatching { Instant.parse(it) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull()
    } ?: return "Date inconnue"
    val minutes = Duration.between(instant, Instant.now()).toMinutes().coerceAtLeast(0)
    return when {
        minutes < 60 -> "il y a $minutes min"
        minutes < 1440 -> "il y a ${minutes / 60} h"
        else -> "il y a ${minutes / 1440} j"
    }
}
