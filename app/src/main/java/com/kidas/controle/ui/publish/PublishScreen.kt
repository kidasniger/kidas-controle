package com.kidas.controle.ui.publish

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.kidas.controle.data.GitHubApiClient
import com.kidas.controle.data.GitHubDataRepository
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private data class QueueCard(
    val file: String, val index: Int, val message: String, val status: String,
    val commentId: String?, val type: String, val media: String?, val publishAt: String?
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublishScreen(credentials: SecureTokenRepository) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var message by rememberSaveable { mutableStateOf("") }
    var selectedMedia by rememberSaveable { mutableStateOf("") }
    var mediaItems by remember { mutableStateOf<List<Pair<String, Long>>>(emptyList()) }
    var queueItems by remember { mutableStateOf<List<QueueCard>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var sending by remember { mutableStateOf(false) }
    var uploading by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf(false) }
    var immediate by rememberSaveable { mutableStateOf(true) }
    var scheduledAt by rememberSaveable { mutableStateOf<Long?>(null) }
    var mediaMenu by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<QueueCard?>(null) }
    var pendingAction by remember { mutableStateOf<Pair<QueueCard, String>?>(null) }
    val dateState = rememberDatePickerState()
    val timeState = rememberTimePickerState()
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }
    val repos = remember(credentials) {
        object {
            suspend fun data(): GitHubDataRepository {
                val pair = credentials.repositories() ?: error("Session verrouillée. Déverrouille KI DAS.")
                return GitHubDataRepository(GitHubApiClient(credentials), pair.first, pair.second)
            }
        }
    }

    suspend fun refresh() {
        loading = true
        try {
            val data = repos.data()
            mediaItems = data.listDir("media").filter { it.type == "file" }
                .sortedByDescending { it.name.substringBefore("-").toLongOrNull() ?: 0L }
                .take(60).map { it.path to (it.size ?: 0L) }
            val files = listOf("posts/queue.json", "posts/avance.json", "posts/replies.json", "posts/actions.json")
            val all = mutableListOf<QueueCard>()
            files.forEach { file ->
                val raw = data.getFile(chemin = file)?.content ?: "[]"
                val arr = runCatching { Json.parseToJsonElement(raw).jsonArray }.getOrDefault(JsonArray(emptyList()))
                arr.forEachIndexed { index, el ->
                    val o = el.jsonObject
                    val status = o["status"]?.jsonPrimitive?.contentOrNull ?: "unknown"
                    val msg = o["message"]?.jsonPrimitive?.contentOrNull
                        ?: o["action"]?.jsonPrimitive?.contentOrNull ?: "Élément sans texte"
                    val media = o["image_path"]?.jsonPrimitive?.contentOrNull
                        ?: o["video_path"]?.jsonPrimitive?.contentOrNull
                    all += QueueCard(file, index, msg, status,
                        o["comment_id"]?.jsonPrimitive?.contentOrNull,
                        when { file.endsWith("replies.json") -> "Réponse"; file.endsWith("actions.json") -> "Action"; media != null -> "Média"; else -> "Publication" },
                        media, o["publish_at"]?.jsonPrimitive?.contentOrNull)
                }
            }
            queueItems = all.sortedBy { if (it.status.equals("pending", true)) 0 else 1 }
                .let { pending -> pending.filter { it.status.equals("pending", true) } + pending.filterNot { it.status.equals("pending", true) }.take(25) }
        } catch (e: Exception) {
            snackbar.showSnackbar(e.message ?: "Impossible de charger les files")
        } finally { loading = false }
    }

    LaunchedEffect(Unit) { refresh() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) scope.launch {
            uploading = true
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Impossible de lire ce fichier")
                val name = uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':') ?: "media"
                val data = repos.data()
                val uploaded = data.uploadMedia(name, bytes)
                selectedMedia = uploaded.path
                snackbar.showSnackbar("Média envoyé avec succès")
                refresh()
            } catch (e: Exception) {
                snackbar.showSnackbar("Envoi impossible : ${e.message ?: "erreur inconnue"}")
            } finally { uploading = false }
        }
    }

    suspend fun mutate(card: QueueCard, status: String) {
        val data = repos.data()
        data.updateJSON(card.file, JsonArray(emptyList()), { root ->
            val arr = root.jsonArray.toMutableList()
            val current = arr.getOrNull(card.index)?.jsonObject
                ?: error("Le fichier a changé, actualise")
            val currentMessage = current["message"]?.jsonPrimitive?.contentOrNull
            val currentComment = current["comment_id"]?.jsonPrimitive?.contentOrNull
            if (currentMessage != card.message && current["action"]?.jsonPrimitive?.contentOrNull != card.message ||
                currentComment != card.commentId) error("Le fichier a changé, actualise")
            arr[card.index] = JsonObject(current.toMutableMap().apply { put("status", JsonPrimitive(status)) })
            JsonArray(arr)
        }, if (status == "cancelled") "Annulation élément file" else "Remise en attente")
        refresh()
    }

    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = 18.dp),
            contentPadding = PaddingValues(top = 18.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Text("Publier", style = MaterialTheme.typography.headlineMedium)
                Text("Prépare et programme tes publications Facebook.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item {
                ElevatedCard {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedTextField(
                            value = message, onValueChange = { message = it },
                            modifier = Modifier.fillMaxWidth(), minLines = 4,
                            label = { Text("Texte de la publication") },
                            placeholder = { Text("Que souhaites-tu partager ?") }
                        )
                        Text("${message.length} caractères", style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        ExposedDropdownMenuBox(expanded = mediaMenu, onExpandedChange = { mediaMenu = it }) {
                            OutlinedTextField(
                                value = selectedMedia.substringAfterLast('/').replace(Regex("^\\d+-"), "").ifBlank { "Aucun média" },
                                onValueChange = {}, readOnly = true, modifier = Modifier.menuAnchor().fillMaxWidth(),
                                label = { Text("Média (facultatif)") }, trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(mediaMenu) }
                            )
                            ExposedDropdownMenu(expanded = mediaMenu, onDismissRequest = { mediaMenu = false }) {
                                DropdownMenuItem(text = { Text("Aucun média") }, onClick = { selectedMedia = ""; mediaMenu = false })
                                mediaItems.forEach { (path, size) ->
                                    DropdownMenuItem(
                                        text = { Text("${path.substringAfterLast('/').replace(Regex("^\\d+-"), "")} · ${formatSize(size)}", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                        onClick = { selectedMedia = path; mediaMenu = false }
                                    )
                                }
                            }
                        }
                        OutlinedButton(onClick = { picker.launch(arrayOf("image/*", "video/*")) }, enabled = !uploading, modifier = Modifier.fillMaxWidth()) {
                            Text(if (uploading) "Envoi du média…" else "Envoyer un fichier")
                        }
                        if (uploading) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text("Programmer", modifier = Modifier.weight(1f))
                            Switch(checked = scheduledAt != null, onCheckedChange = { if (it) showDate = true else scheduledAt = null })
                        }
                        if (scheduledAt != null) {
                            Text(DateTimeFormatter.ofPattern("dd/MM/yyyy 'à' HH:mm", Locale.FRANCE)
                                .format(LocalDateTime.ofInstant(Instant.ofEpochMilli(scheduledAt!!), ZoneId.systemDefault())))
                            TextButton(onClick = { showDate = true }) { Text("Modifier la date et l’heure") }
                        }
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text("Lancer la publication tout de suite", modifier = Modifier.weight(1f))
                            Switch(checked = immediate, onCheckedChange = { immediate = it })
                        }
                        Button(
                            onClick = {
                                scope.launch {
                                    sending = true; sent = false
                                    try {
                                        require(message.isNotBlank()) { "Saisis le texte de ta publication." }
                                        scheduledAt?.let {
                                            require(it > System.currentTimeMillis() + 10 * 60 * 1000L) { "Choisis une date à plus de 10 minutes." }
                                            require(it <= System.currentTimeMillis() + 30L * 24 * 60 * 60 * 1000) { "La programmation est limitée à 30 jours." }
                                        }
                                        val advanced = selectedMedia.isNotBlank() || scheduledAt != null
                                        val file = if (advanced) "posts/avance.json" else "posts/queue.json"
                                        val ext = selectedMedia.substringAfterLast('.', "").lowercase()
                                        val entry = buildJsonObject {
                                            put("message", message); put("status", "pending")
                                            if (selectedMedia.isNotBlank()) {
                                                if (ext in setOf("mp4", "mov", "m4v", "webm", "avi")) put("video_path", selectedMedia)
                                                else put("image_path", selectedMedia)
                                            }
                                            scheduledAt?.let { put("publish_at", DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(it))) }
                                        }
                                        val data = repos.data()
                                        data.updateJSON(file, JsonArray(emptyList()), { root ->
                                            JsonArray(root.jsonArray + entry)
                                        }, "Mise en file publication")
                                        sent = true
                                        if (immediate) {
                                            try { data.dispatch(if (advanced) "publier-avance.yml" else "publier.yml") }
                                            catch (_: Exception) {
                                                snackbar.showSnackbar("Publication mise en file. Le contrôle automatique la traitera sous 5 à 10 minutes.")
                                            }
                                        } else snackbar.showSnackbar("Publication mise en file.")
                                        message = ""; selectedMedia = ""; scheduledAt = null
                                        refresh()
                                    } catch (e: Exception) {
                                        snackbar.showSnackbar(e.message ?: "Impossible de mettre en file")
                                    } finally { sending = false }
                                }
                            },
                            enabled = !sending && message.isNotBlank(), modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(14.dp)
                        ) {
                            AnimatedContent(targetState = sending to sent, label = "publish-button") { state ->
                                Text(when { state.first -> "Mise en file…"; state.second -> "✓ Envoyé"; else -> "Mettre en file" })
                            }
                        }
                    }
                }
            }
            item {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("Files d’attente", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = { scope.launch { refresh() } }, enabled = !loading) { Text("Actualiser") }
                }
            }
            if (loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            items(queueItems, key = { "${it.file}:${it.index}:${it.message.hashCode()}" }) { card ->
                val tint by animateColorAsState(
                    when (card.status.lowercase()) {
                        "pending" -> MaterialTheme.colorScheme.primary
                        "done", "published", "replied" -> MaterialTheme.colorScheme.tertiary
                        "error", "failed" -> MaterialTheme.colorScheme.error
                        "cancelled" -> MaterialTheme.colorScheme.outline
                        else -> MaterialTheme.colorScheme.secondary
                    }, label = "status-color"
                )
                ElevatedCard(modifier = Modifier.animateItem()) {
                    Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(card.type, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                            SuggestionChip(onClick = {}, label = { Text(card.status) }, colors = SuggestionChipDefaults.suggestionChipColors(
                                labelColor = tint, iconContentColor = tint
                            ))
                        }
                        Text(card.message, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        card.publishAt?.let { Text("Programmé : $it", style = MaterialTheme.typography.bodySmall) }
                        card.media?.let { Text("Média : ${it.substringAfterLast('/')}", style = MaterialTheme.typography.bodySmall) }
                        if (card.status.equals("pending", true)) {
                            TextButton(onClick = { confirm = card }) { Text("Annuler") }
                        } else if (card.status.equals("error", true) || card.status.equals("failed", true)) {
                            TextButton(onClick = { pendingAction = card to "pending" }) { Text("Remettre en attente") }
                        }
                    }
                }
            }
        }
    }

    if (showDate) {
        DatePickerDialog(onDismissRequest = { showDate = false }, confirmButton = {
            TextButton(onClick = {
                val millis = dateState.selectedDateMillis
                showDate = false
                if (millis != null) { scheduledAt = millis; showTime = true }
            }) { Text("Continuer") }
        }, dismissButton = { TextButton(onClick = { showDate = false }) { Text("Fermer") } }) {
            DatePicker(state = dateState)
        }
    }
    if (showTime) {
        AlertDialog(onDismissRequest = { showTime = false }, title = { Text("Choisir l’heure") },
            text = { TimePicker(state = timeState) },
            confirmButton = {
                TextButton(onClick = {
                    val date = dateState.selectedDateMillis ?: System.currentTimeMillis()
                    val localDate = Instant.ofEpochMilli(date).atZone(ZoneId.of("UTC")).toLocalDate()
                    val chosen = localDate.atTime(timeState.hour, timeState.minute).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    scheduledAt = chosen; showTime = false
                }) { Text("Valider") }
            }, dismissButton = { TextButton(onClick = { showTime = false }) { Text("Annuler") } })
    }
    confirm?.let { card ->
        AlertDialog(onDismissRequest = { confirm = null }, title = { Text("Annuler cet élément ?") },
            text = { Text("L’élément sera marqué comme annulé dans la file.") },
            confirmButton = {
                TextButton(onClick = {
                    confirm = null
                    scope.launch { runCatching { mutate(card, "cancelled") }.onFailure { snackbar.showSnackbar(it.message ?: "Échec") } }
                }) { Text("Annuler l’élément") }
            }, dismissButton = { TextButton(onClick = { confirm = null }) { Text("Retour") } })
    }
    pendingAction?.let { (card, status) ->
        LaunchedEffect(card, status) {
            runCatching { mutate(card, status) }.onFailure { snackbar.showSnackbar(it.message ?: "Échec") }
            pendingAction = null
        }
    }
}

private fun formatSize(bytes: Long): String = if (bytes >= 1024L * 1024L)
    String.format(Locale.FRANCE, "%.1f Mo", bytes / (1024.0 * 1024.0))
else String.format(Locale.FRANCE, "%.0f Ko", bytes / 1024.0)
