package com.kidas.controle.data

import android.net.Uri
import kotlinx.coroutines.delay
import kotlinx.serialization.json.*
import java.io.File
import java.util.concurrent.ConcurrentHashMap

data class GitHubFile(val path: String, val content: String, val sha: String, val size: Long? = null)
data class GitHubDirEntry(val name: String, val path: String, val sha: String, val type: String, val size: Long? = null)

class GitHubDataRepository(
    private val api: GitHubApiClient,
    private val dataRepo: String,
    private val managerRepo: String
) {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true; isLenient = true }
    private val workflowCache = ConcurrentHashMap<String, Any>()

    private fun repoPath(repo: String, path: String) =
        "/repos/$repo/contents/${GitHubApiClient.encodePath(path)}"

    suspend fun getFile(repo: String = dataRepo, chemin: String): GitHubFile? {
        val path = repoPath(repo, chemin)
        val response = api.request("GET", path)
        if (response.code == 404) return null
        if (!response.isSuccessful) throw GitHubApiException(response.code, path, response.body)
        val obj = json.parseToJsonElement(response.body).jsonObject
        val sha = obj["sha"]?.jsonPrimitive?.content ?: ""
        val size = obj["size"]?.jsonPrimitive?.longOrNull
        val encoded = obj["content"]?.jsonPrimitive?.contentOrNull.orEmpty().trim()
        // GitHub peut omettre le contenu Base64 pour les fichiers volumineux.
        val content = if (encoded.isNotEmpty()) {
            android.util.Base64.decode(encoded.replace("\\n", "").replace("\\r", ""), android.util.Base64.DEFAULT)
                .toString(Charsets.UTF_8)
        } else {
            val raw = api.request("GET", path, accept = "application/vnd.github.raw+json")
            if (!raw.isSuccessful) throw GitHubApiException(raw.code, path, raw.body)
            raw.body
        }
        return GitHubFile(chemin, content, sha, size)
    }

    suspend fun updateJSON(
        chemin: String,
        valeurParDefaut: JsonElement,
        modification: (JsonElement) -> JsonElement,
        message: String
    ): GitHubFile {
        val path = repoPath(dataRepo, chemin)
        var last: Throwable? = null
        repeat(5) { attempt ->
            try {
                val current = getFile(dataRepo, chemin)
                val currentJson = current?.content?.let { json.parseToJsonElement(it) } ?: valeurParDefaut
                val changed = modification(currentJson)
                val payload = buildJsonObject {
                    put("message", message)
                    put("content", android.util.Base64.encodeToString(changed.toString().toByteArray(Charsets.UTF_8), android.util.Base64.NO_WRAP))
                    if (current?.sha?.isNotBlank() == true) put("sha", current.sha)
                }.toString()
                val response = api.request("PUT", path, payload)
                if (response.isSuccessful) {
                    val result = json.parseToJsonElement(response.body).jsonObject
                    return GitHubFile(chemin, changed.toString(), result["content"]?.jsonObject?.get("sha")?.jsonPrimitive?.content ?: "", result["content"]?.jsonObject?.get("size")?.jsonPrimitive?.longOrNull)
                }
                if (response.code != 409 && response.code != 422) throw GitHubApiException(response.code, path, response.body)
                last = GitHubApiException(response.code, path, response.body)
            } catch (e: GitHubApiException) {
                if (e.httpCode != 409 && e.httpCode != 422) throw e
                last = e
            }
            if (attempt < 4) delay(700L * (attempt + 1) + kotlin.random.Random.nextLong(0, 501))
        }
        throw last ?: GitHubApiException(409, path)
    }

    suspend fun listDir(chemin: String): List<GitHubDirEntry> {
        val path = repoPath(dataRepo, chemin)
        val response = api.request("GET", path)
        if (response.code == 404) return emptyList()
        if (!response.isSuccessful) throw GitHubApiException(response.code, path, response.body)
        return json.parseToJsonElement(response.body).jsonArray.mapNotNull { item ->
            val o = item.jsonObject
            GitHubDirEntry(
                o["name"]?.jsonPrimitive?.content ?: return@mapNotNull null,
                o["path"]?.jsonPrimitive?.content ?: return@mapNotNull null,
                o["sha"]?.jsonPrimitive?.content ?: "",
                o["type"]?.jsonPrimitive?.content ?: "",
                o["size"]?.jsonPrimitive?.longOrNull
            )
        }
    }

    suspend fun uploadMedia(fileName: String, bytes: ByteArray, timestamp: Long = System.currentTimeMillis()): GitHubFile {
        require(bytes.size.toLong() <= 50L * 1024 * 1024) { "Fichier supérieur à 50 Mo" }
        val safeName = fileName.substringAfterLast('/').replace(Regex("[^a-zA-Z0-9._-]"), "_").ifBlank { "media" }
        var last: Throwable? = null
        repeat(5) { attempt ->
            // Un chemin neuf à chaque tentative évite de retomber sur le même conflit SHA.
            val unique = timestamp + attempt * 1000L + kotlin.random.Random.nextLong(0, 999)
            val path = "media/$unique-$safeName"
            val apiPath = repoPath(dataRepo, path)
            val payload = buildJsonObject {
                put("message", "Upload média $path")
                put("content", android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP))
            }.toString()
            val response = api.request("PUT", apiPath, payload)
            if (response.isSuccessful) {
                val result = json.parseToJsonElement(response.body).jsonObject
                return GitHubFile(path, "", result["content"]?.jsonObject?.get("sha")?.jsonPrimitive?.content ?: "", bytes.size.toLong())
            }
            if (response.code != 409 && response.code != 422) throw GitHubApiException(response.code, apiPath, response.body)
            last = GitHubApiException(response.code, apiPath, response.body)
            if (attempt < 4) delay(700L * (attempt + 1) + kotlin.random.Random.nextLong(0, 501))
        }
        throw last ?: GitHubApiException(409, "media")
    }

    suspend fun deleteFile(chemin: String, sha: String) {
        val path = repoPath(dataRepo, chemin)
        var last: Throwable? = null
        repeat(5) { attempt ->
            val payload = buildJsonObject {
                put("message", "Suppression $chemin")
                put("sha", sha)
            }.toString()
            val response = api.request("DELETE", path, payload)
            if (response.isSuccessful) return
            if (response.code != 409 && response.code != 422) throw GitHubApiException(response.code, path, response.body)
            last = GitHubApiException(response.code, path, response.body)
            if (attempt < 4) delay(700L * (attempt + 1) + kotlin.random.Random.nextLong(0, 501))
        }
        throw last ?: GitHubApiException(409, path)
    }

    suspend fun downloadImage(chemin: String): ByteArray {
        val path = repoPath(dataRepo, chemin)
        val response = api.request("GET", path, accept = "application/vnd.github.raw+json")
        if (!response.isSuccessful) throw GitHubApiException(response.code, path, response.body)
        return response.bytes
    }

    suspend fun dispatch(fichier: String, inputs: JsonObject = buildJsonObject {}) {
        val path = "/repos/$managerRepo/actions/workflows/${GitHubApiClient.encodePath(fichier)}/dispatches"
        val payload = buildJsonObject { put("ref", "main"); put("inputs", inputs) }.toString()
        api.requireSuccess("POST", path, payload)
    }

    suspend fun workflows(forceRefresh: Boolean = false): JsonArray {
        val key = "workflows"
        if (!forceRefresh) (workflowCache[key] as? JsonArray)?.let { return it }
        val path = "/repos/$managerRepo/actions/workflows?per_page=50"
        val response = api.requireSuccess("GET", path)
        val result = json.parseToJsonElement(response.body).jsonObject["workflows"]?.jsonArray ?: JsonArray(emptyList())
        workflowCache[key] = result
        return result
    }

    suspend fun runs(n: Int = 30): JsonArray {
        val path = "/repos/$managerRepo/actions/runs?per_page=${n.coerceIn(1, 100)}"
        val response = api.requireSuccess("GET", path)
        return json.parseToJsonElement(response.body).jsonObject["workflow_runs"]?.jsonArray ?: JsonArray(emptyList())
    }

    suspend fun glmLiveRuns(): JsonArray = JsonArray(runs(100).filter { run ->
        val o = run.jsonObject
        val workflow = o["path"]?.jsonPrimitive?.contentOrNull ?: ""
        val name = o["name"]?.jsonPrimitive?.contentOrNull ?: ""
        (workflow.endsWith("glm-live.yml") || name.contains("glm-live", true)) &&
            (o["status"]?.jsonPrimitive?.contentOrNull in setOf("in_progress", "queued"))
    })

    suspend fun cancelRun(id: Long) {
        val path = "/repos/$managerRepo/actions/runs/$id/cancel"
        api.requireSuccess("POST", path)
    }

    suspend fun setWorkflowEnabled(id: Long, enabled: Boolean) {
        val action = if (enabled) "enable" else "disable"
        val path = "/repos/$managerRepo/actions/workflows/$id/$action"
        api.requireSuccess("PUT", path)
        workflowCache.clear()
    }

    suspend fun getVar(name: String): String? {
        val path = "/repos/$managerRepo/actions/variables/${GitHubApiClient.encodePath(name)}"
        val response = api.request("GET", path)
        if (response.code == 404) return null
        if (!response.isSuccessful) throw GitHubApiException(response.code, path, response.body)
        return json.parseToJsonElement(response.body).jsonObject["value"]?.jsonPrimitive?.contentOrNull
    }

    suspend fun setVar(name: String, value: String) {
        val path = "/repos/$managerRepo/actions/variables/${GitHubApiClient.encodePath(name)}"
        val payload = buildJsonObject { put("name", name); put("value", value) }.toString()
        val patch = api.request("PATCH", path, payload)
        if (patch.isSuccessful) return
        if (patch.code != 404) throw GitHubApiException(patch.code, path, patch.body)
        val collection = "/repos/$managerRepo/actions/variables"
        val create = api.request("POST", collection, payload)
        if (!create.isSuccessful) throw GitHubApiException(create.code, collection, create.body)
    }

    suspend fun requestAudit(dateIso: String) {
        updateJSON(
            "audit/demande.json",
            buildJsonObject {},
            { buildJsonObject { put("status", "demande"); put("date", dateIso) } },
            "Demande d'audit"
        )
        dispatch("audit.yml")
    }
}
