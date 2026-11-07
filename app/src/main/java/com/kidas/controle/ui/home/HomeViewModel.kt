package com.kidas.controle.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kidas.controle.data.GitHubApiClient
import com.kidas.controle.data.GitHubDataRepository
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.serialization.json.*
import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class BotStatus { RUNNING, IDLE, STOPPED }

data class ChartPoint(val day: String, val value: Float)

data class HomeExecution(
    val id: Long,
    val name: String,
    val status: String,
    val conclusion: String?,
    val duration: String,
    val relativeTime: String,
    val url: String
)

data class HomeUiState(
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val followers: Long = 0,
    val pageLikes: Long = 0,
    val unansweredComments: Int = 0,
    val pendingActions: Int = 0,
    val botStatus: BotStatus = BotStatus.IDLE,
    val botDetail: String = "État en attente de synchronisation",
    val interactions: List<ChartPoint> = emptyList(),
    val views: List<ChartPoint> = emptyList(),
    val visits: List<ChartPoint> = emptyList(),
    val followersHistory: List<ChartPoint> = emptyList(),
    val dailyFollowers: List<ChartPoint> = emptyList(),
    val executions: List<HomeExecution> = emptyList(),
    val tokenDaysRemaining: Long? = null,
    val workflowVeilleEnabled: Boolean? = null,
    val lastUpdated: String? = null,
    val error: String? = null,
    val actionProgress: Set<String> = emptySet(),
    val actionSuccess: Set<String> = emptySet(),
    val actionError: String? = null
)

class HomeViewModel(private val credentials: SecureTokenRepository) : ViewModel() {
    private val mutableState = MutableStateFlow(HomeUiState())
    val state: StateFlow<HomeUiState> = mutableState.asStateFlow()
    private var repository: GitHubDataRepository? = null

    fun refresh() {
        if (mutableState.value.refreshing) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(
                loading = mutableState.value.lastUpdated == null,
                refreshing = true,
                error = null
            )
            try {
                val repos = credentials.repositories()
                    ?: throw IllegalStateException("Session verrouillée. Déverrouille KI DAS.")
                val data = repository ?: GitHubDataRepository(
                    GitHubApiClient(credentials), repos.first, repos.second
                ).also { repository = it }

                supervisorScope {
                    val statsTask = async { runCatching { data.getFile(chemin = "inbox/statistiques.json")?.content?.let(::parseStats) } }
                    val commentsTask = async { runCatching { data.getFile(chemin = "inbox/commentaires.json")?.content?.let(::parseComments) } }
                    val queuesTask = async { runCatching { pendingCount(data) } }
                    val runsTask = async { runCatching { data.runs(10).mapNotNull(::parseRun) } }
                    val botTask = async { runCatching { loadBot(data) } }
                    val expiryTask = async { runCatching { credentials.credentialExpiry() } }

                    val stats = statsTask.await().getOrNull()
                    val comments = commentsTask.await().getOrNull()
                    val queues = queuesTask.await().getOrNull()
                    val runs = runsTask.await().getOrNull()
                    val bot = botTask.await().getOrNull()
                    val expiry = expiryTask.await().getOrNull()

                    val old = mutableState.value
                    mutableState.value = old.copy(
                        loading = false,
                        refreshing = false,
                        followers = stats?.pageFollowers ?: old.followers,
                        pageLikes = stats?.pageLikes ?: old.pageLikes,
                        unansweredComments = comments ?: old.unansweredComments,
                        pendingActions = queues ?: old.pendingActions,
                        botStatus = bot?.first ?: old.botStatus,
                        botDetail = bot?.second ?: old.botDetail,
                        interactions = stats?.charts?.get("page_post_engagements") ?: old.interactions,
                        views = stats?.charts?.get("page_media_view") ?: old.views,
                        visits = stats?.charts?.get("page_views_total") ?: old.visits,
                        followersHistory = stats?.charts?.get("page_follows") ?: old.followersHistory,
                        dailyFollowers = stats?.charts?.get("page_daily_follows_unique") ?: old.dailyFollowers,
                        executions = runs ?: old.executions,
                        tokenDaysRemaining = expiry?.let { it?.let { time -> Duration.between(Instant.now(), Instant.ofEpochMilli(time)).toDays() } },
                        workflowVeilleEnabled = bot?.third ?: old.workflowVeilleEnabled,
                        lastUpdated = DateTimeFormatter.ofPattern("HH:mm", Locale.FRANCE).format(java.time.LocalTime.now()),
                        error = listOfNotNull(
                            statsTask.await().exceptionOrNull()?.let { "Statistiques indisponibles" },
                            commentsTask.await().exceptionOrNull()?.let { "Commentaires indisponibles" },
                            queuesTask.await().exceptionOrNull()?.let { "Files indisponibles" },
                            runsTask.await().exceptionOrNull()?.let { "Exécutions indisponibles" },
                            botTask.await().exceptionOrNull()?.let { "État du bot indisponible" }
                        ).takeIf { it.isNotEmpty() }?.joinToString(" · ")
                    )
                }
            } catch (error: Throwable) {
                mutableState.value = mutableState.value.copy(
                    loading = false,
                    refreshing = false,
                    error = error.message ?: "Impossible de charger le tableau de bord"
                )
            }
        }
    }

    private data class ParsedStats(
        val pageFollowers: Long,
        val pageLikes: Long,
        val charts: Map<String, List<ChartPoint>>
    )

    private fun parseStats(raw: String): ParsedStats {
        val root = Json.parseToJsonElement(raw).jsonObject
        val page = root["page"]?.jsonObject
        val metrics = root["metriques"]?.jsonObject ?: JsonObject(emptyMap())
        val charts = metrics.mapValues { (_, metric) ->
            val series = when (metric) {
                is JsonArray -> metric.firstOrNull()?.jsonObject
                is JsonObject -> metric
                else -> null
            }
            series?.get("valeurs")?.jsonArray.orEmpty().mapNotNull { item ->
                val obj = item.jsonObject
                val value = obj["valeur"]?.jsonPrimitive?.doubleOrNull?.toFloat() ?: return@mapNotNull null
                val date = obj["date"]?.jsonPrimitive?.contentOrNull.orEmpty()
                ChartPoint(formatDay(date), value)
            }.takeLast(7)
        }
        return ParsedStats(
            pageFollowers = page?.get("followers_count")?.jsonPrimitive?.longOrNull ?: 0,
            pageLikes = page?.get("fan_count")?.jsonPrimitive?.longOrNull ?: 0,
            charts = charts
        )
    }

    private fun parseComments(raw: String): Int {
        val root = Json.parseToJsonElement(raw).jsonObject
        val pageId = root["page"]?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull
        var count = 0
        fun inspect(items: JsonArray?) {
            items.orEmpty().forEach { element ->
                val item = element.jsonObject
                val message = item["message"]?.jsonPrimitive?.contentOrNull.orEmpty()
                val author = item["from"]?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull
                val answered = item["page_a_repondu"]?.jsonPrimitive?.booleanOrNull == true
                if (!answered && message.isNotBlank() && author != null && author != pageId) count++
                inspect(item["comments"]?.jsonObject?.get("data")?.jsonArray)
            }
        }
        root["posts"]?.jsonArray.orEmpty().forEach { post ->
            inspect(post.jsonObject["comments"]?.jsonObject?.get("data")?.jsonArray)
        }
        return count
    }

    private suspend fun pendingCount(data: GitHubDataRepository): Int {
        val files = data.listDir("posts").filter { it.type == "file" && it.name.endsWith(".json") }
        var count = 0
        files.forEach { file ->
            runCatching {
                val content = data.getFile(chemin = file.path)?.content ?: return@runCatching
                val root = Json.parseToJsonElement(content)
                val entries = if (root is JsonArray) root else JsonArray(listOf(root))
                count += entries.count { it.jsonObject["status"]?.jsonPrimitive?.contentOrNull.equals("pending", true) }
            }
        }
        return count
    }

    private suspend fun loadBot(data: GitHubDataRepository): Triple<BotStatus, String, Boolean?> {
        val live = runCatching { data.getVar("GLM_LIVE") }.getOrNull()
        val auto = runCatching { data.getVar("AUTO_REPONSES") }.getOrNull()
        val config = runCatching {
            data.getFile(chemin = "glm/config.json")?.content?.let { Json.parseToJsonElement(it).jsonObject }
        }.getOrNull()
        val workflows = runCatching { data.workflows(true) }.getOrNull()
        val veille = workflows?.firstOrNull {
            val path = it.jsonObject["path"]?.jsonPrimitive?.contentOrNull.orEmpty()
            path.endsWith("glm-veille.yml") || it.jsonObject["name"]?.jsonPrimitive?.contentOrNull.orEmpty().contains("GLM Veille", true)
        }?.jsonObject
        val enabled = veille?.get("state")?.jsonPrimitive?.contentOrNull == "active"
        val sessions = runCatching { data.glmLiveRuns() }.getOrNull().orEmpty()
        val configActive = config?.get("actif")?.jsonPrimitive?.booleanOrNull != false
        val status = when {
            live.equals("off", true) || !configActive -> BotStatus.STOPPED
            sessions.isNotEmpty() -> BotStatus.RUNNING
            else -> BotStatus.IDLE
        }
        val detail = when (status) {
            BotStatus.STOPPED -> "Le bot est désactivé"
            BotStatus.RUNNING -> "Session GLM Live en cours · ${sessions.size} exécution(s)"
            BotStatus.IDLE -> buildString {
                append("En attente · surveillance ")
                append(if (enabled) "active" else "inactive")
                if (!auto.isNullOrBlank()) append(" · réponses auto ${if (auto.equals("off", true)) "désactivées" else "activées"}")
            }
        }
        return Triple(status, detail, enabled)
    }

    private fun parseRun(element: JsonElement): HomeExecution? = runCatching {
        val o = element.jsonObject
        val started = o["run_started_at"]?.jsonPrimitive?.contentOrNull
            ?: o["created_at"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val ended = o["updated_at"]?.jsonPrimitive?.contentOrNull
        val start = parseInstant(started)
        val end = ended?.let(::parseInstant) ?: Instant.now()
        val minutes = if (start != null) Duration.between(start, end).toMinutes().coerceAtLeast(0) else 0
        HomeExecution(
            id = o["id"]?.jsonPrimitive?.longOrNull ?: 0,
            name = o["name"]?.jsonPrimitive?.contentOrNull ?: "Exécution",
            status = o["status"]?.jsonPrimitive?.contentOrNull ?: "unknown",
            conclusion = o["conclusion"]?.jsonPrimitive?.contentOrNull,
            duration = if (minutes < 60) "${minutes} min" else "${minutes / 60} h ${minutes % 60} min",
            relativeTime = relativeTime(start ?: parseInstant(o["created_at"]?.jsonPrimitive?.contentOrNull.orEmpty())),
            url = o["html_url"]?.jsonPrimitive?.contentOrNull.orEmpty()
        )
    }.getOrNull()

    private fun parseInstant(value: String): Instant? = runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
    private fun relativeTime(value: Instant?): String {
        if (value == null) return "Date inconnue"
        val minutes = Duration.between(value, Instant.now()).toMinutes().coerceAtLeast(0)
        return when {
            minutes < 1 -> "à l’instant"
            minutes < 60 -> "il y a $minutes min"
            minutes < 1440 -> "il y a ${minutes / 60} h"
            else -> "il y a ${minutes / 1440} j"
        }
    }

    private fun formatDay(value: String): String = runCatching {
        val date = value.take(10)
        val parts = date.split("-")
        "${parts[2]}/${parts[1]}"
    }.getOrDefault(value.take(5))

    fun runAction(action: String) {
        if (action in mutableState.value.actionProgress) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(
                actionProgress = mutableState.value.actionProgress + action,
                actionSuccess = mutableState.value.actionSuccess - action,
                actionError = null
            )
            try {
                val repos = credentials.repositories() ?: throw IllegalStateException("Session verrouillée")
                val data = repository ?: GitHubDataRepository(GitHubApiClient(credentials), repos.first, repos.second)
                    .also { repository = it }
                when (action) {
                    "audit" -> data.requestAudit(java.time.LocalDate.now().toString())
                    "stats" -> data.dispatch("statistiques.yml")
                    "surveiller" -> data.dispatch("surveiller.yml")
                    "files" -> data.dispatch("actions-posts.yml")
                    else -> error("Action inconnue")
                }
                mutableState.value = mutableState.value.copy(actionProgress = mutableState.value.actionProgress - action)
                mutableState.value = mutableState.value.copy(actionSuccess = mutableState.value.actionSuccess + action)
                delay(1800)
                mutableState.value = mutableState.value.copy(actionSuccess = mutableState.value.actionSuccess - action)
                refresh()
            } catch (error: Throwable) {
                mutableState.value = mutableState.value.copy(
                    actionProgress = mutableState.value.actionProgress - action,
                    actionError = error.message ?: "L’action a échoué"
                )
            }
        }
    }
}
