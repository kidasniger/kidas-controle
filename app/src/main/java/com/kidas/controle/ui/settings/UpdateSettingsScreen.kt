package com.kidas.controle.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.kidas.controle.updater.AppUpdateManager
import com.kidas.controle.updater.UpdateState
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

@Composable
fun UpdateSettingsScreen(manager: AppUpdateManager, onBack: () -> Unit = {}) {
    val state by manager.state.collectAsState()
    val scope = rememberCoroutineScope()
    var promptedVersion by remember { mutableStateOf<String?>(null) }

    val available = state as? UpdateState.UpdateAvailable
    if (available != null && promptedVersion != available.release.tagName) {
        AlertDialog(
            onDismissRequest = { promptedVersion = available.release.tagName },
            title = { Text("Nouvelle version disponible 🎉") },
            text = { Text("KI DAS ${available.release.tagName} est disponible. Consultez les nouveautés dans Paramètres.") },
            confirmButton = { TextButton(onClick = { promptedVersion = available.release.tagName }) { Text("Voir") } },
            dismissButton = { TextButton(onClick = { promptedVersion = available.release.tagName }) { Text("Plus tard") } }
        )
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Paramètres", style = MaterialTheme.typography.headlineMedium)
            TextButton(onClick = onBack) { Text("Retour") }
        }
        Card {
            Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Mise à jour de l’application", style = MaterialTheme.typography.titleLarge)
                Text("Version installée : ${manager.installedVersion()}", style = MaterialTheme.typography.bodyMedium)
                when (val current = state) {
                    UpdateState.Idle -> Text("Vérifiez si une nouvelle version est disponible.")
                    UpdateState.Checking -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text("Recherche d’une mise à jour…")
                    }
                    is UpdateState.UpdateAvailable -> {
                        Text("Version disponible : ${current.release.tagName}", style = MaterialTheme.typography.titleMedium)
                        Text("Publiée le : ${current.release.publishedAt?.let(::formatDate) ?: "Date inconnue"}")
                        Text("Taille : ${formatBytes(current.release.apkSize)}")
                        if (current.release.body.isNotBlank()) {
                            Text("Nouveautés", style = MaterialTheme.typography.titleSmall)
                            Text(current.release.body)
                        }
                        Button(
                            onClick = { scope.launch { manager.download(current.release) } },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Télécharger et installer") }
                    }
                    is UpdateState.UpToDate -> Text("Votre application est à jour ✓")
                    is UpdateState.Error -> Text(current.message, color = MaterialTheme.colorScheme.error)
                    is UpdateState.Downloading -> {
                        Text("Téléchargement… ${current.percent}%")
                        LinearProgressIndicator(
                            progress = { if (current.total > 0) current.received.toFloat() / current.total else 0f },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Text("${formatBytes(current.received)} / ${if (current.total > 0) formatBytes(current.total) else "—"}")
                    }
                    is UpdateState.Downloaded -> {
                        Text("Téléchargement terminé et fichier vérifié ✓")
                        Button(onClick = { manager.install(current.apkPath, current.version) }, modifier = Modifier.fillMaxWidth()) {
                            Text("Installer la mise à jour")
                        }
                    }
                    is UpdateState.Installing -> Text("Ouverture de l’installateur Android…")
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = { scope.launch { manager.checkForUpdates() } },
                        enabled = state !is UpdateState.Checking && state !is UpdateState.Downloading,
                        modifier = Modifier.weight(1f)
                    ) { Text("Vérifier les mises à jour") }
                    if (state is UpdateState.Error) {
                        TextButton(onClick = { manager.reset() }) { Text("Réinitialiser") }
                    }
                }
            }
        }
    }
}

private fun formatBytes(bytes: Long): String = when {
    bytes <= 0 -> "Inconnue"
    bytes < 1024 -> "$bytes o"
    bytes < 1024 * 1024 -> "${bytes / 1024} Ko"
    else -> String.format(Locale.FRANCE, "%.1f Mo", bytes / (1024.0 * 1024.0))
}

private fun formatDate(value: String): String = runCatching {
    val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
    val date = parser.parse(value)
    SimpleDateFormat("dd/MM/yyyy à HH:mm", Locale.FRANCE).format(date!!)
}.getOrDefault(value)
