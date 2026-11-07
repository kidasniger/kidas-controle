package com.kidas.controle.ui.bot

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import com.kidas.controle.data.GitHubApiClient
import com.kidas.controle.data.GitHubDataRepository
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import kotlinx.coroutines.launch

@Composable
fun BotScreen(credentials: SecureTokenRepository) {
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    val hold = remember { Animatable(0f) }
    var repository by remember { mutableStateOf<GitHubDataRepository?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var variables by remember { mutableStateOf<Map<String, Boolean>>(emptyMap()) }
    var configActive by remember { mutableStateOf(false) }
    var veilleActive by remember { mutableStateOf(false) }
    var workflows by remember { mutableStateOf(JsonArray(emptyList())) }
    var runs by remember { mutableStateOf(JsonArray(emptyList())) }
    var liveCount by remember { mutableIntStateOf(0) }
    var testMode by remember { mutableStateOf(true) }
    var minutes by remember { mutableIntStateOf(30) }

    suspend fun refresh() {
        val configured = credentials.repositories() ?: throw IllegalStateException("Configuration GitHub absente")
        val data = GitHubDataRepository(GitHubApiClient(credentials), configured.first, configured.second)
        repository = data
        val loaded = mutableMapOf<String, Boolean>()
        listOf("GLM_LIVE", "AUTO_REPONSES", "AUTO_PUBLICATIONS").forEach { name ->
            val value = data.getVar(name)
            loaded[name] = value.equals("true", true) || value.equals("on", true)
        }
        variables = loaded
        val config = data.getFile(chemin = "glm/config.json")?.content
            ?.let { Json.parseToJsonElement(it).jsonObject } ?: JsonObject(emptyMap())
        configActive = config["actif"]?.jsonPrimitive?.booleanOrNull == true
        workflows = data.workflows(true)
        runs = data.runs(40)
        liveCount = data.glmLiveRuns().size
        veilleActive = findWorkflow("glm-veille.yml", workflows)?.get("state")?.jsonPrimitive?.contentOrNull == "active"
    }

    fun perform(action: suspend (GitHubDataRepository) -> Unit) {
        scope.launch {
            busy = true
            error = null
            notice = null
            try {
                val data = repository ?: throw IllegalStateException("Données du Bot non chargées")
                action(data)
                refresh()
                notice = "Modification enregistrée ✓"
            } catch (e: Exception) {
                error = e.message ?: "Opération impossible"
                runCatching { refresh() }
            } finally {
                busy = false
            }
        }
    }

    fun toggle(name: String, enabled: Boolean) = perform { data ->
        when (name) {
            "GLM_LIVE" -> {
                data.setVar(name, if (enabled) "on" else "off")
                data.updateJSON("glm/config.json", buildJsonObject {}, { old ->
                    JsonObject(old.jsonObject.toMutableMap().apply { put("actif", JsonPrimitive(enabled)) })
                }, "Activation GLM")
            }
            "AUTO_PUBLICATIONS" -> {
                data.setVar(name, enabled.toString())
                data.updateJSON("glm/config.json", buildJsonObject {}, { old ->
                    val root = old.jsonObject.toMutableMap()
                    val feature = root["posts"]?.jsonObject?.toMutableMap() ?: mutableMapOf()
                    feature["actif"] = JsonPrimitive(enabled)
                    root["posts"] = JsonObject(feature)
                    JsonObject(root)
                }, "Configuration publications automatiques")
            }
            "AUTO_REPONSES" -> {
                data.setVar(name, enabled.toString())
                data.updateJSON("glm/config.json", buildJsonObject {}, { old ->
                    val root = old.jsonObject.toMutableMap()
                    val feature = root["reponses"]?.jsonObject?.toMutableMap() ?: mutableMapOf()
                    feature["actif"] = JsonPrimitive(enabled)
                    root["reponses"] = JsonObject(feature)
                    JsonObject(root)
                }, "Configuration réponses automatiques")
            }
        }
    }

    LaunchedEffect(credentials) {
        runCatching { refresh() }.onFailure { error = it.message ?: "Chargement impossible" }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text("Bot", style = MaterialTheme.typography.headlineMedium)
                Text("Contrôle GLM et workflows GitHub", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(enabled = !busy, onClick = { perform { refresh() } }) { Text("Actualiser") }
        }

        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.fillMaxWidth().padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(88.dp), contentAlignment = Alignment.Center) {
                    val active = variables["GLM_LIVE"] == true && configActive
                    val ringColor = if (active) Color(0xFF20B879) else MaterialTheme.colorScheme.error
                    Canvas(Modifier.fillMaxSize()) {
                        drawCircle(ringColor.copy(alpha = .13f), size.minDimension * .49f)
                        drawCircle(ringColor.copy(alpha = .28f), size.minDimension * .38f)
                        drawCircle(ringColor, size.minDimension * .24f)
                    }
                    Text(if (active) "ON" else "OFF", style = MaterialTheme.typography.titleLarge)
                }
                Text("$liveCount session(s) GLM Live en cours", style = MaterialTheme.typography.titleMedium)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button(enabled = !busy, onClick = {
                        perform { data ->
                            data.setVar("GLM_LIVE", "on")
                            data.setVar("AUTO_REPONSES", "on")
                            data.updateJSON("glm/config.json", buildJsonObject {}, { old ->
                                JsonObject(old.jsonObject.toMutableMap().apply { put("actif", JsonPrimitive(true)) })
                            }, "Activation GLM")
                            val veille = findWorkflow("glm-veille.yml", data.workflows(true))
                            if (veille?.get("state")?.jsonPrimitive?.contentOrNull == "active") {
                                data.dispatch("glm-veille.yml")
                            } else {
                                data.dispatch("glm-live.yml", buildJsonObject {
                                    put("dry_run", JsonPrimitive(false))
                                    put("minutes", JsonPrimitive(330))
                                })
                            }
                        }
                    }, modifier = Modifier.weight(1f)) { Text("Démarrer") }

                    Surface(
                        modifier = Modifier.weight(1f).height(50.dp).pointerInput(busy) {
                            detectTapGestures(onPress = {
                                if (busy) return@detectTapGestures
                                hold.snapTo(0f)
                                val animation = scope.launch { hold.animateTo(1f, tween(1000)) }
                                val released = tryAwaitRelease()
                                animation.cancel()
                                if (released && hold.value >= .99f) {
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                    perform { data ->
                                        data.setVar("GLM_LIVE", "off")
                                        data.setVar("AUTO_REPONSES", "off")
                                        data.updateJSON("glm/config.json", buildJsonObject {}, { config ->
                                            JsonObject(config.jsonObject.toMutableMap().apply { put("actif", JsonPrimitive(false)) })
                                        }, "Arrêt d’urgence GLM")
                                        data.glmLiveRuns().forEach { run ->
                                            run.jsonObject["id"]?.jsonPrimitive?.longOrNull?.let { data.cancelRun(it) }
                                        }
                                    }
                                }
                                hold.snapTo(0f)
                            })
                        },
                        color = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                        shape = RoundedCornerShape(14.dp)
                    ) {
                        Column(Modifier.fillMaxSize().padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                            Text("Maintenir · arrêt d’urgence", style = MaterialTheme.typography.labelMedium)
                            LinearProgressIndicator(progress = { hold.value }, modifier = Modifier.fillMaxWidth(.9f), color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                Text("Maintiens le bouton rouge pendant 1 seconde pour désactiver GLM et annuler les sessions en cours.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }

        Text("Configuration", style = MaterialTheme.typography.titleLarge)
        BotSwitch("GLM (tout)", variables["GLM_LIVE"] == true, !busy) { toggle("GLM_LIVE", it) }
        BotSwitch("Publications automatiques", variables["AUTO_PUBLICATIONS"] == true, !busy) { toggle("AUTO_PUBLICATIONS", it) }
        BotSwitch("Réponses automatiques", variables["AUTO_REPONSES"] == true, !busy) { toggle("AUTO_REPONSES", it) }
        BotSwitch("Veille GLM", veilleActive, !busy) { enabled ->
            perform { data ->
                val id = findWorkflow("glm-veille.yml", data.workflows(true))
                    ?.get("id")?.jsonPrimitive?.longOrNull
                    ?: throw IllegalStateException("Workflow glm-veille.yml introuvable")
                data.setWorkflowEnabled(id, enabled)
            }
        }

        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(18.dp)) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("GLM Live manuel", style = MaterialTheme.typography.titleMedium)
                BotSwitch("Mode test (dry run)", testMode, !busy) { testMode = it }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Durée")
                    Text("$minutes min", color = MaterialTheme.colorScheme.primary)
                }
                Slider(value = minutes.toFloat(), onValueChange = { minutes = it.toInt().coerceIn(1, 330) }, valueRange = 1f..330f, steps = 328, enabled = !busy)
                Button(enabled = !busy, onClick = {
                    perform { data ->
                        data.dispatch("glm-live.yml", buildJsonObject {
                            put("dry_run", JsonPrimitive(testMode))
                            put("minutes", JsonPrimitive(minutes))
                        })
                    }
                }, modifier = Modifier.fillMaxWidth()) { Text("Lancer GLM Live") }
            }
        }

        Text("Catalogue des workflows", style = MaterialTheme.typography.titleLarge)
        val groups = listOf(
            "Lecture" to listOf("audit.yml", "surveiller.yml", "statistiques.yml"),
            "Publication" to listOf("publier.yml", "publier-avance.yml", "repondre.yml"),
            "Maintenance" to listOf("actions-posts.yml", "glm-veille.yml", "glm-live.yml")
        )
        groups.forEach { (group, files) ->
            Text(group, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            files.forEach { file ->
                val wf = findWorkflow(file, workflows)
                val latest = runs.firstOrNull { it.jsonObject["path"]?.jsonPrimitive?.contentOrNull?.endsWith(file) == true }
                val status = latest?.jsonObject?.get("status")?.jsonPrimitive?.contentOrNull
                val conclusion = latest?.jsonObject?.get("conclusion")?.jsonPrimitive?.contentOrNull
                val dot = when {
                    status == "in_progress" || status == "queued" -> Color(0xFFE6A23C)
                    conclusion == "success" -> Color(0xFF20B879)
                    conclusion == "failure" -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                }
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) {
                    Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(9.dp).clip(CircleShape).background(dot))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(file, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                if (latest == null) (wf?.get("state")?.jsonPrimitive?.contentOrNull ?: "Aucune exécution")
                                else "Dernière exécution : ${status ?: "inconnue"} · ${conclusion ?: "en attente"}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        TextButton(enabled = !busy && wf != null, onClick = { perform { it.dispatch(file) } }) { Text("Lancer") }
                    }
                }
            }
        }

        Text("Exécutions récentes", style = MaterialTheme.typography.titleLarge)
        runs.take(15).forEach { run ->
            val item = run.jsonObject
            val status = item["status"]?.jsonPrimitive?.contentOrNull ?: "inconnu"
            val conclusion = item["conclusion"]?.jsonPrimitive?.contentOrNull
            val running = status == "queued" || status == "in_progress"
            val color = when {
                running -> Color(0xFFE6A23C)
                conclusion == "success" -> Color(0xFF20B879)
                conclusion == "failure" -> MaterialTheme.colorScheme.error
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(item["name"]?.jsonPrimitive?.contentOrNull ?: "Workflow", style = MaterialTheme.typography.bodyMedium)
                    Text("$status · ${conclusion ?: "—"}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (running) TextButton(enabled = !busy, onClick = {
                    item["id"]?.jsonPrimitive?.longOrNull?.let { id -> perform { it.cancelRun(id) } }
                }) { Text("Annuler") }
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        notice?.let { Text(it, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
private fun BotSwitch(label: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

private fun findWorkflow(file: String, workflows: JsonArray): JsonObject? =
    workflows.firstOrNull { it.jsonObject["path"]?.jsonPrimitive?.contentOrNull?.endsWith(file) == true }?.jsonObject
