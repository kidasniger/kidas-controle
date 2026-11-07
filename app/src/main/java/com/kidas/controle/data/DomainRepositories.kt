package com.kidas.controle.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable
data class StatistiquesFile(
    val date: String? = null,
    val page: PageStats? = null,
    val metriques: Map<String, List<MetricGroup>>? = null
)
@Serializable
data class PageStats(val id: String? = null, val followers_count: Long? = null, val fan_count: Long? = null)
@Serializable
data class MetricGroup(val valeurs: List<MetricValue>? = null)
@Serializable
data class MetricValue(val valeur: Double? = null)

@Serializable
data class CommentairesFile(
    val updated: String? = null,
    val page: CommentPage? = null,
    val posts: List<CommentPost>? = null
)
@Serializable
data class CommentPage(val id: String? = null)
@Serializable
data class CommentPost(val message: String? = null, val story: String? = null, val comments: CommentConnection? = null)
@Serializable
data class CommentConnection(val data: List<CommentItem>? = null)
@Serializable
data class CommentItem(
    val id: String? = null,
    val message: String? = null,
    val created_time: String? = null,
    val from: CommentAuthor? = null,
    val page_a_repondu: Boolean? = null
)
@Serializable
data class CommentAuthor(val id: String? = null, val name: String? = null)

@Serializable
data class QueueEntry(
    val status: String? = null,
    val message: String? = null,
    val comment_id: String? = null,
    val post_id: String? = null,
    val image_path: String? = null,
    val video_path: String? = null,
    val publish_at: String? = null,
    val action: String? = null
)

@Serializable
data class GlmConfig(
    val actif: Boolean? = null,
    val posts: GlmFeature? = null,
    val reponses: GlmFeature? = null
)
@Serializable
data class GlmFeature(val actif: Boolean? = null)

object DataJson {
    val format = Json { ignoreUnknownKeys = true; coerceInputValues = true; explicitNulls = false }
}

class StatsRepository(private val data: GitHubDataRepository) {
    suspend fun get(): StatistiquesFile? = withContext(Dispatchers.IO) {
        data.getFile(chemin = "inbox/statistiques.json")?.content?.let { DataJson.format.decodeFromString<StatistiquesFile>(it) }
    }
    suspend fun update(transform: (JsonElement) -> JsonElement, message: String = "Mise à jour statistiques") =
        data.updateJSON("inbox/statistiques.json", buildJsonObject {}, transform, message)
}

class CommentairesRepository(private val data: GitHubDataRepository) {
    suspend fun get(): CommentairesFile? = withContext(Dispatchers.IO) {
        data.getFile(chemin = "inbox/commentaires.json")?.content?.let { DataJson.format.decodeFromString<CommentairesFile>(it) }
    }
    suspend fun update(transform: (JsonElement) -> JsonElement, message: String = "Mise à jour commentaires") =
        data.updateJSON("inbox/commentaires.json", buildJsonObject {}, transform, message)
}

class PublicationsRepository(private val data: GitHubDataRepository) {
    private val files = setOf("posts/queue.json", "posts/avance.json", "posts/replies.json", "posts/actions.json")
    suspend fun get(file: String): List<QueueEntry>? {
        require(file in files) { "Fichier publications non autorisé" }
        return data.getFile(chemin = file)?.content?.let { DataJson.format.decodeFromString<List<QueueEntry>>(it) }
    }
    suspend fun update(file: String, transform: (JsonElement) -> JsonElement, message: String = "Mise à jour publications") = run {
        require(file in files) { "Fichier publications non autorisé" }
        data.updateJSON(file, JsonArray(emptyList()), transform, message)
    }
}

class MediasRepository(private val data: GitHubDataRepository) {
    suspend fun list(): List<GitHubDirEntry> = data.listDir("media")
    suspend fun upload(name: String, bytes: ByteArray) = data.uploadMedia(name, bytes)
    suspend fun delete(path: String, sha: String) = data.deleteFile(path, sha)
    suspend fun downloadImage(path: String): ByteArray = data.downloadImage(path)
}

class BotRepository(private val data: GitHubDataRepository) {
    suspend fun config(): JsonObject? = data.getFile(chemin = "glm/config.json")?.content?.let { DataJson.format.parseToJsonElement(it).jsonObject }
    /** JsonElement is deliberately preserved end-to-end so unknown config keys survive writes. */
    suspend fun updateConfig(transform: (JsonElement) -> JsonElement) =
        data.updateJSON("glm/config.json", buildJsonObject {}, transform, "Mise à jour configuration GLM")
    suspend fun dispatch(workflow: String, inputs: JsonObject = buildJsonObject {}) = data.dispatch(workflow, inputs)
    suspend fun liveRuns() = data.glmLiveRuns()
    suspend fun cancelRun(id: Long) = data.cancelRun(id)
    suspend fun workflows(forceRefresh: Boolean = false) = data.workflows(forceRefresh)
    suspend fun enableWorkflow(id: Long) = data.setWorkflowEnabled(id, true)
    suspend fun disableWorkflow(id: Long) = data.setWorkflowEnabled(id, false)
    suspend fun getVariable(name: String) = data.getVar(name)
    suspend fun setVariable(name: String, value: String) = data.setVar(name, value)
    suspend fun requestAudit(dateIso: String) = data.requestAudit(dateIso)
}
