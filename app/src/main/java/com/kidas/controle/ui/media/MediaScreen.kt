package com.kidas.controle.ui.media

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.ImageLoader
import coil.disk.DiskCache
import coil.request.ImageRequest
import coil.compose.AsyncImage
import com.kidas.controle.data.GitHubApiClient
import com.kidas.controle.data.GitHubDataRepository
import com.kidas.controle.data.GitHubDirEntry
import com.kidas.controle.security.SecureTokenRepository
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import java.io.File
import java.util.Locale

private data class MediaItem(
    val name: String,
    val path: String,
    val sha: String,
    val size: Long,
    val video: Boolean
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun MediaScreen(credentials: SecureTokenRepository, onUseMedia: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val clipboard = LocalClipboardManager.current
    var items by remember { mutableStateOf<List<MediaItem>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var sending by remember { mutableStateOf(false) }
    var progressText by remember { mutableStateOf("") }
    var sentCount by remember { mutableIntStateOf(0) }
    var failedCount by remember { mutableIntStateOf(0) }
    var summary by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var deleteTarget by remember { mutableStateOf<List<MediaItem>?>(null) }
    var preview by remember { mutableStateOf<MediaItem?>(null) }
    var token by remember { mutableStateOf<String?>(null) }
    var dataRepository by remember { mutableStateOf<String?>(null) }

    suspend fun repository(): GitHubDataRepository {
        val pair = credentials.repositories() ?: error("Session verrouillée. Déverrouille KI DAS.")
        return GitHubDataRepository(GitHubApiClient(credentials), pair.first, pair.second)
    }

    suspend fun refresh() {
        loading = true
        try {
            val entries = repository().listDir("media")
                .filter { it.type == "file" }
                .sortedByDescending { it.name.substringBefore("-").toLongOrNull() ?: 0L }
                .take(60)
            items = entries.map { entry ->
                val ext = entry.name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                MediaItem(entry.name.substringAfter("-").let { if (it == entry.name) it else it },
                    entry.path, entry.sha, entry.size ?: 0L,
                    ext in setOf("mp4", "mov", "m4v", "webm", "avi", "mkv", "3gp"))
            }
            selected = selected.intersect(items.map { it.path }.toSet())
        } finally { loading = false }
    }

    LaunchedEffect(Unit) {
        try {
            token = credentials.getToken()
            dataRepository = credentials.repositories()?.first
            refresh()
        } catch (error: Throwable) {
            loading = false
            snackbar.showSnackbar(error.message ?: "Impossible de charger la bibliothèque")
        }
    }

    val imageLoader = remember(context, token) {
        token?.let { auth ->
            val client = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("Authorization", "Bearer $auth")
                    .header("Accept", "application/vnd.github.raw+json")
                    .header("X-GitHub-Api-Version", "2022-11-28")
                    .build()
                chain.proceed(request)
            }.build()
            ImageLoader.Builder(context)
                .okHttpClient(client)
                .diskCache {
                    DiskCache.Builder()
                        .directory(File(context.cacheDir, "kidas-media-thumbnails"))
                        .maxSizeBytes(60L * 1024L * 1024L)
                        .build()
                }
                .build()
        }
    }

    fun rawUrl(media: MediaItem): String {
        val repo = dataRepository ?: return ""
        return "https://api.github.com/repos/$repo/contents/" +
            GitHubApiClient.encodePath(media.path)
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) scope.launch {
            sending = true
            sentCount = 0
            failedCount = 0
            val failures = mutableListOf<String>()
            uris.forEachIndexed { index, uri ->
                val name = displayName(context, uri)
                progressText = "(${index + 1}/${uris.size}) $name : Envoi…"
                try {
                    val size = fileSize(context, uri)
                    require(size <= 50L * 1024L * 1024L) { "Fichier supérieur à 50 Mo" }
                    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("Lecture impossible")
                    require(bytes.size.toLong() <= 50L * 1024L * 1024L) { "Fichier supérieur à 50 Mo" }
                    repository().uploadMedia(name, bytes)
                    sentCount++
                } catch (error: Throwable) {
                    failedCount++
                    failures += "$name : ${error.message ?: "échec"}"
                }
            }
            sending = false
            progressText = ""
            summary = "${sentCount} envoyé(s), ${failedCount} échec(s) sur ${uris.size}"
            runCatching { refresh() }
            snackbar.showSnackbar(summary + if (failures.isNotEmpty()) " · " + failures.take(2).joinToString(" ; ") else "")
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { picker.launch(arrayOf("image/*", "video/*")) },
                icon = { Text("＋") },
                text = { Text("Envoyer des médias") },
                expanded = true,
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)) {
                Column(Modifier.weight(1f)) {
                    Text("Médias", style = MaterialTheme.typography.headlineMedium)
                    Text("${items.size} fichier(s) · 60 plus récents maximum", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { scope.launch { runCatching { refresh() }.onFailure { snackbar.showSnackbar(it.message ?: "Erreur") } } }, enabled = !loading && !sending) {
                    Text("↻")
                }
            }
            AnimatedVisibility(sending, enter = fadeIn()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        Text(progressText, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
            }
            summary?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(bottom = 8.dp)) }
            if (selected.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text("${selected.size} sélectionné(s)", modifier = Modifier.weight(1f))
                    TextButton(onClick = { deleteTarget = items.filter { it.path in selected } }) { Text("Supprimer") }
                    TextButton(onClick = { selected = emptySet() }) { Text("Annuler") }
                }
            }
            if (loading && items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Image, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(42.dp))
                        Text("Aucun média pour le moment")
                        Text("Envoie une photo ou une vidéo pour commencer.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 145.dp),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 100.dp, top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(items, key = { it.path }) { media ->
                        val isSelected = media.path in selected
                        androidx.compose.material3.ElevatedCard(
                            modifier = Modifier.animateItem().combinedClickable(
                                onClick = {
                                    if (selected.isNotEmpty()) {
                                        selected = if (isSelected) selected - media.path else selected + media.path
                                    } else if (!media.video) preview = media
                                },
                                onLongClick = {
                                    selected = if (isSelected) selected - media.path else selected + media.path
                                }
                            )
                        ) {
                            Column {
                                Box(
                                    Modifier.fillMaxWidth().height(126.dp)
                                        .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp))
                                        .background(MaterialTheme.colorScheme.surfaceVariant),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (media.video) {
                                        Icon(Icons.Default.Movie, contentDescription = "Vidéo", modifier = Modifier.size(46.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Icon(Icons.Default.PlayArrow, contentDescription = "Lire", modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp).size(28.dp), tint = MaterialTheme.colorScheme.primary)
                                    } else if (media.size < 1_572_864L && imageLoader != null) {
                                        AsyncImage(
                                            model = ImageRequest.Builder(context).data(rawUrl(media))
                                                .addHeader("Authorization", "Bearer ${token.orEmpty()}")
                                                .addHeader("Accept", "application/vnd.github.raw+json")
                                                .crossfade(true).build(),
                                            imageLoader = imageLoader,
                                            contentDescription = media.name,
                                            modifier = Modifier.fillMaxSize()
                                        )
                                    } else {
                                        Icon(Icons.Default.Image, contentDescription = "Image", modifier = Modifier.size(46.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    if (isSelected) {
                                        Surface(Modifier.align(Alignment.TopEnd).padding(7.dp), color = MaterialTheme.colorScheme.primary, shape = RoundedCornerShape(50)) {
                                            Icon(Icons.Default.CheckCircle, contentDescription = "Sélectionné", tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.padding(4.dp))
                                        }
                                    }
                                }
                                Column(Modifier.padding(9.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(media.name, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
                                    Text(formatMediaSize(media.size), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        TextButton(onClick = { onUseMedia(media.path) }, contentPadding = PaddingValues(horizontal = 4.dp)) { Text("Utiliser", maxLines = 1) }
                                        IconButton(onClick = {
                                            clipboard.setText(AnnotatedString(media.path))
                                            scope.launch { snackbar.showSnackbar("Chemin copié") }
                                        }, modifier = Modifier.size(34.dp)) {
                                            Icon(Icons.Default.ContentCopy, contentDescription = "Copier le chemin", modifier = Modifier.size(17.dp))
                                        }
                                        IconButton(onClick = { deleteTarget = listOf(media) }, modifier = Modifier.size(34.dp)) {
                                            Icon(Icons.Default.Delete, contentDescription = "Supprimer", tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(17.dp))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    deleteTarget?.let { targets ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text(if (targets.size == 1) "Supprimer ce média ?" else "Supprimer ${targets.size} médias ?") },
            text = { Text("Cette suppression est définitive dans le dépôt privé.") },
            confirmButton = {
                TextButton(onClick = {
                    deleteTarget = null
                    scope.launch {
                        var failures = 0
                        targets.forEach { media ->
                            runCatching { repository().deleteFile(media.path, media.sha) }
                                .onFailure { failures++ }
                        }
                        selected = emptySet()
                        refresh()
                        snackbar.showSnackbar(if (failures == 0) "${targets.size} média(s) supprimé(s)" else "Suppression terminée avec $failures échec(s)")
                    }
                }) { Text("Supprimer") }
            },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("Annuler") } }
        )
    }

    preview?.let { media ->
        var scale by remember(media.path) { mutableFloatStateOf(1f) }
        Dialog(
            onDismissRequest = { preview = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                if (imageLoader != null) {
                    AsyncImage(
                        model = ImageRequest.Builder(context).data(rawUrl(media))
                            .addHeader("Authorization", "Bearer ${token.orEmpty()}")
                            .addHeader("Accept", "application/vnd.github.raw+json").build(),
                        imageLoader = imageLoader,
                        contentDescription = media.name,
                        modifier = Modifier.fillMaxSize().pointerInput(media.path) {
                            detectTransformGestures { _, _, zoom, _ ->
                                scale = (scale * zoom).coerceIn(1f, 5f)
                            }
                        }.graphicsLayer(scaleX = scale, scaleY = scale)
                    )
                }
                IconButton(onClick = { preview = null }, modifier = Modifier.align(Alignment.TopEnd).padding(16.dp)) {
                    Icon(Icons.Default.Close, contentDescription = "Fermer", tint = Color.White)
                }
                Text(media.name, color = Color.White, modifier = Modifier.align(Alignment.BottomCenter).padding(18.dp))
            }
        }
    }
}

private fun displayName(context: Context, uri: Uri): String {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) return cursor.getString(0) ?: "media"
    }
    return uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':') ?: "media"
}

private fun fileSize(context: Context, uri: Uri): Long {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) return cursor.getLong(0).coerceAtLeast(0L)
    }
    return 0L
}

private fun formatMediaSize(bytes: Long): String =
    if (bytes >= 1024L * 1024L) String.format(Locale.FRANCE, "%.1f Mo", bytes / (1024.0 * 1024.0))
    else String.format(Locale.FRANCE, "%.0f Ko", bytes / 1024.0)
