package com.kidas.controle.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.kidas.controle.data.*
import com.kidas.controle.security.SecureTokenRepository
import com.kidas.controle.ui.theme.KiDasThemeMode
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(credentials: SecureTokenRepository, themeMode: KiDasThemeMode, onThemeModeChange: (KiDasThemeMode)->Unit, version: String) {
    val scope = rememberCoroutineScope()
    var visible by remember { mutableStateOf(false) }
    var revealedToken by remember { mutableStateOf<String?>(null) }
    var repos by remember { mutableStateOf<Pair<String,String>?>(null) }
    var expiry by remember { mutableStateOf<Long?>(null) }
    var datePicker by remember { mutableStateOf(false) }
    var tests by remember { mutableStateOf<List<Pair<String,Boolean>>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var forgetConfirm by remember { mutableStateOf(false) }
    LaunchedEffect(credentials) { repos = credentials.repositories(); expiry = credentials.credentialExpiry() }
    val dateText = expiry?.let { SimpleDateFormat("dd/MM/yyyy", Locale.FRANCE).format(Date(it)) } ?: "Non renseignée"
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("Réglages", style = MaterialTheme.typography.headlineMedium)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Sécurité GitHub", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(value = if (visible) (revealedToken ?: "Jeton indisponible") else "••••••••••••••••••••", onValueChange = {}, readOnly = true, modifier = Modifier.fillMaxWidth(), label = { Text("Jeton GitHub") }, visualTransformation = if (visible) VisualTransformation.None else PasswordVisualTransformation())
                TextButton(onClick = { visible = !visible; if (visible) scope.launch { revealedToken = runCatching { credentials.revealToken() }.getOrNull() } else revealedToken = null }) { Text(if (visible) "Masquer" else "Afficher") }
                Text("Dépôt de données : ${repos?.first ?: "—"}")
                Text("Dépôt manager : ${repos?.second ?: "—"}")
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("Expiration : $dateText", modifier = Modifier.weight(1f))
                    TextButton(onClick = { datePicker = true }) { Text("Modifier") }
                }
                Text("Le jeton reste chiffré dans Android Keystore et n’est affiché qu’après une demande explicite.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(enabled = !busy, onClick = {
                    scope.launch {
                        busy = true; tests = emptyList(); error = null; message = null
                        try {
                            val r = repos ?: throw IllegalStateException("Dépôts non configurés")
                            val api = GitHubApiClient(credentials)
                            val data = GitHubDataRepository(api, r.first, r.second)
                            val failures = mutableListOf<String>()
                            suspend fun check(label: String, requiredRight: String, action: suspend () -> Unit): Pair<String, Boolean> {
                                val ok = runCatching { action(); true }.getOrElse {
                                    failures += "$label — ${it.message ?: "Droit manquant : $requiredRight"}"
                                    false
                                }
                                return label to ok
                            }
                            val results = listOf(
                                check("Lecture des données", "Contents: read") { data.getFile(chemin = "inbox/commentaires.json") },
                                check("Lecture des Actions", "Actions: read") { data.workflows(true) },
                                check("Lecture des Variables", "Variables: read") { data.getVar("GLM_LIVE") }
                            )
                            tests = results
                            if (results.all { it.second }) message = "Connexion GitHub testée avec succès ✓"
                            else error = failures.joinToString("\n")
                        } catch (e: Exception) { error = e.message ?: "Test impossible" }
                        finally { busy = false }
                    }
                }, modifier = Modifier.fillMaxWidth()) { Text("Enregistrer et tester") }
                tests.forEach { (name, ok) -> Text((if (ok) "● OK  " else "● Échec  ") + name, color = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error) }
                message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                OutlinedButton(onClick = { forgetConfirm = true }, modifier = Modifier.fillMaxWidth()) { Text("Oublier le jeton") }
            }
        }
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Thème", style = MaterialTheme.typography.titleMedium)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf(KiDasThemeMode.SYSTEM to "Automatique", KiDasThemeMode.LIGHT to "Clair", KiDasThemeMode.DARK to "Sombre").forEachIndexed { i, pair ->
                        SegmentedButton(selected = themeMode == pair.first, onClick = { onThemeModeChange(pair.first) }, shape = SegmentedButtonDefaults.itemShape(i, 3)) { Text(pair.second) }
                    }
                }
            }
        }
        Text("Version $version", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (datePicker) {
        val picker = rememberDatePickerState(initialSelectedDateMillis = expiry ?: System.currentTimeMillis())
        DatePickerDialog(onDismissRequest = { datePicker = false }, confirmButton = {
            TextButton(onClick = { expiry = picker.selectedDateMillis?.let { it + 86_399_999L }; scope.launch { runCatching { credentials.updateCredentialExpiry(expiry) }.onSuccess { message = "Expiration enregistrée ✓" }.onFailure { error = it.message } }; datePicker = false }) { Text("Valider") }
        }, dismissButton = { TextButton(onClick = { datePicker = false }) { Text("Annuler") } }) { DatePicker(state = picker) }
    }
    if (forgetConfirm) AlertDialog(onDismissRequest = { forgetConfirm = false }, title = { Text("Oublier le jeton ?") }, text = { Text("Le coffre local sera effacé. Tu devras reconfigurer l’application avec un nouveau jeton.") }, confirmButton = {
        TextButton(onClick = { forgetConfirm = false; scope.launch { credentials.forgetCredential(); error = "Jeton oublié. Ferme et relance l’application pour refaire la configuration." } }) { Text("Oublier") }
    }, dismissButton = { TextButton(onClick = { forgetConfirm = false }) { Text("Annuler") } })
}
