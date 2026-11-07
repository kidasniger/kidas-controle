package com.kidas.controle.ui.bot

import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kidas.controle.data.*
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*

@Composable
fun BotScreen(credentials: SecureTokenRepository) {
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    var repo by remember { mutableStateOf<GitHubDataRepository?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var vars by remember { mutableStateOf(mapOf<String, Boolean>()) }
    var veille by remember { mutableStateOf(false) }
    var glmConfig by remember { mutableStateOf(false) }
    var workflows by remember { mutableStateOf<JsonArray>(JsonArray(emptyList())) }
    var runs by remember { mutableStateOf<JsonArray>(JsonArray(emptyList())) }
    var testMode by remember { mutableStateOf(true) }
    var minutes by remember { mutableIntStateOf(30) }
    val hold = remember { Animatable(0f) }

    suspend fun refresh() {
        val repositories = credentials.repositories() ?: throw IllegalStateException("Configuration GitHub absente")
        val data = GitHubDataRepository(GitHubApiClient(credentials), repositories.first, repositories.second)
        repo = data
        vars = listOf("GLM_LIVE", "AUTO_REPONSES", "AUTO_PUBLICATIONS").associateWith {
            data.getVar(it).equals("true", true)
        }
        glmConfig = runCatching {
            data.getFile(chemin = "glm/config.json")?.content?.let {
                Json.parseToJsonElement(it).jsonObject["actif"]?.jsonPrimitive?.booleanOrNull
            } ?: false
        }.getOrDefault(false)
        workflows = data.workflows(true)
        runs = data.runs(30)
        veille = workflows.firstOrNull { it.jsonObject["path"]?.jsonPrimitive?.contentOrNull?.endsWith("glm-veille.yml") == true }
            ?.jsonObject?.get("state")?.jsonPrimitive?.contentOrNull == "active"
    }
    LaunchedEffect(credentials) { runCatching { refresh() }.onFailure { error = it.message } }

    fun perform(action: suspend (GitHubDataRepository) -> Unit) {
        scope.launch {
            busy = true; error = null; notice = null
            try { val data = repo ?: throw IllegalStateException("Dépôts non chargés"); action(data); refresh(); notice = "Modification enregistrée ✓" }
            catch (e: Exception) { error = e.message ?: "Opération impossible"; runCatching { refresh() } }
            finally { busy = false }
        }
    }
    fun toggleVariable(name: String, value: Boolean) = perform { data ->
        data.setVar(name, value.toString())
    }
    fun workflowId(suffix: String): String? = workflows.firstOrNull {
        it.jsonObject["path"]?.jsonPrimitive?.contentOrNull?.endsWith(suffix) == true
    }?.jsonObject?.get("id")?.jsonPrimitive?.contentOrNull

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Bot", style = MaterialTheme.typography.headlineMedium)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth().padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(86.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(progress = { if (vars["GLM_LIVE"] == true) 1f else .12f }, modifier = Modifier.fillMaxSize(), strokeWidth = 6.dp)
                    Text(if (vars["GLM_LIVE"] == true) "ON" else "OFF", style = MaterialTheme.typography.titleLarge)
                }
                Text("${runs.count { it.jsonObject["name"]?.jsonPrimitive?.contentOrNull?.contains("GLM", true) == true && it.jsonObject["status"]?.jsonPrimitive?.contentOrNull == "in_progress" }} session(s) GLM Live en cours")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = !busy, onClick = {
                        perform { data ->
                            data.setVar("GLM_LIVE", "true")
                            data.setVar("AUTO_REPONSES", "true")
                            data.updateJSON("glm/config.json", buildJsonObject { put("actif", true) }, { old ->
                                JsonObject(old.jsonObject.toMutableMap().apply { put("actif", JsonPrimitive(true)) })
                            }, "Activation GLM")
                            val veilleId = workflowId("glm-veille.yml")
                            if (veilleId != null && veille) data.dispatch("glm-veille.yml")
                            else data.dispatch("glm-live.yml", buildJsonObject { put("dry_run", JsonPrimitive(false)); put("minutes", JsonPrimitive(330)) })
                        }
                    }) { Text("Démarrer") }
                    OutlinedButton(enabled = !busy, onClick = { scope.launch {
                        hold.snapTo(0f)
                        val completed = hold.animateTo(1f, tween(1000))
                        if (completed.endState.value >= .99f) {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            perform { data ->
                                data.setVar("GLM_LIVE", "false"); data.setVar("AUTO_REPONSES", "false")
                                data.glmLiveRuns().forEach { run -> run.jsonObject["id"]?.jsonPrimitive?.longOrNull?.let { data.cancelRun(it) } }
                            }
                        }
                    } }) { Text("Arrêt d’urgence") }
                }
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
        Text("Configuration", style = MaterialTheme.typography.titleLarge)
        SwitchRow("GLM (tout)", vars["GLM_LIVE"] == true, !busy) { toggleVariable("GLM_LIVE", it) }
        SwitchRow("Publications automatiques", vars["AUTO_PUBLICATIONS"] == true, !busy) { toggleVariable("AUTO_PUBLICATIONS", it) }
        SwitchRow("Réponses automatiques", vars["AUTO_REPONSES"] == true, !busy) { toggleVariable("AUTO_REPONSES", it) }
        SwitchRow("Veille GLM", veille, !busy) { enabled ->
            perform { data ->
                val id = workflowId("glm-veille.yml") ?: throw IllegalStateException("Workflow glm-veille.yml introuvable")
                data.setWorkflowEnabled(id, enabled)
            }
        }
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("GLM Live manuel", style = MaterialTheme.typography.titleMedium)
                SwitchRow("Mode test (dry run)", testMode, true) { testMode = it }
                Text("Durée : $minutes min")
                Slider(value = minutes.toFloat(), onValueChange = { minutes = it.toInt() }, valueRange = 1f..330f, steps = 328)
                Button(enabled = !busy, onClick = { perform { it.dispatch("glm-live.yml", buildJsonObject {
                    put("dry_run", JsonPrimitive(testMode)); put("minutes", JsonPrimitive(minutes))
                }) } }) { Text("Lancer GLM Live") }
            }
        }
        Text("Catalogue des workflows", style = MaterialTheme.typography.titleLarge)
        val groups = listOf("Lecture" to listOf("audit.yml", "surveiller.yml"), "Publication" to listOf("publier.yml", "publier-avance.yml", "repondre.yml"), "Maintenance" to listOf("traiter-files.yml", "glm-veille.yml", "glm-live.yml"))
        groups.forEach { (group, names) ->
            Text(group, style = MaterialTheme.typography.titleMedium)
            names.forEach { name ->
                val wf = workflows.firstOrNull { it.jsonObject["path"]?.jsonPrimitive?.contentOrNull?.endsWith(name) == true }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(name)
                        Text(wf?.jsonObject?.get("state")?.jsonPrimitive?.contentOrNull ?: "Introuvable", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    TextButton(enabled = !busy && wf != null, onClick = { perform { it.dispatch(name) } }) { Text("Lancer") }
                }
            }
        }
        Text("Exécutions récentes", style = MaterialTheme.typography.titleLarge)
        runs.take(12).forEach { run ->
            val o = run.jsonObject
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(o["name"]?.jsonPrimitive?.contentOrNull ?: "Workflow")
                    Text("${o["status"]?.jsonPrimitive?.contentOrNull ?: "—"} · ${o["conclusion"]?.jsonPrimitive?.contentOrNull ?: "en cours"}", style = MaterialTheme.typography.labelSmall)
                }
                if (o["status"]?.jsonPrimitive?.contentOrNull in setOf("in_progress", "queued")) {
                    TextButton(enabled = !busy, onClick = { o["id"]?.jsonPrimitive?.longOrNull?.let { id -> perform { it.cancelRun(id) } } }) { Text("Annuler") }
                }
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        notice?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}
