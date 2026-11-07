package com.kidas.controle.security

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LockScreen(
    onUnlock: () -> Unit,
    onUseDeviceCredential: () -> Unit,
    showDeviceCredential: Boolean,
    error: String? = null
) {
    Column(Modifier.fillMaxSize().padding(28.dp), verticalArrangement = Arrangement.Center) {
        Text("KI DAS", style = MaterialTheme.typography.displaySmall)
        Text("Contrôle sécurisé", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(16.dp))
        Text("Authentifie-toi avec ton empreinte ou le verrouillage de ton téléphone.")
        if (error != null) Text(error, color = MaterialTheme.colorScheme.error)
        Spacer(Modifier.height(24.dp))
        Button(onClick = onUnlock, modifier = Modifier.fillMaxWidth()) { Text("Déverrouiller") }
        if (showDeviceCredential) TextButton(onClick = onUseDeviceCredential, modifier = Modifier.fillMaxWidth()) {
            Text("Utiliser le code du téléphone")
        }
    }
}

@Composable
fun WelcomeSetupScreen(
    deviceSecure: Boolean,
    error: String? = null,
    onSave: (String, String, String, String) -> Unit,
    onUseDeviceCredential: (String, String, String, String) -> Unit
) {
    var token by remember { mutableStateOf("") }
    var dataRepo by remember { mutableStateOf("kidasniger/facebook-data") }
    var managerRepo by remember { mutableStateOf("kidasniger/facebook-manager") }
    var expiry by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Bienvenue sur KI DAS Contrôle 👋", style = MaterialTheme.typography.headlineMedium)
        Text("Colle de nouveau ton jeton : l’ancien jeton ne peut pas être récupéré après la migration.")
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Droits requis sur le jeton GitHub", style = MaterialTheme.typography.titleMedium)
                Text("Contents : lecture et écriture")
                Text("Actions : lecture et écriture")
                Text("Variables : lecture et écriture")
                Text("Metadata : lecture seule")
            }
        }
        if (!deviceSecure) Text(
            "Aucun verrouillage détecté. Configure un code PIN, un schéma ou un mot de passe dans Android. Le jeton ne peut pas être enregistré.",
            color = MaterialTheme.colorScheme.error
        )
        if (error != null) Text(error, color = MaterialTheme.colorScheme.error)
        OutlinedTextField(token, { token = it }, Modifier.fillMaxWidth(),
            label = { Text("Jeton GitHub") }, visualTransformation = PasswordVisualTransformation(), singleLine = true)
        OutlinedTextField(dataRepo, { dataRepo = it }, Modifier.fillMaxWidth(), label = { Text("Dépôt de données") }, singleLine = true)
        OutlinedTextField(managerRepo, { managerRepo = it }, Modifier.fillMaxWidth(), label = { Text("Dépôt manager") }, singleLine = true)
        OutlinedTextField(expiry, { expiry = it }, Modifier.fillMaxWidth(),
            label = { Text("Expiration (facultatif, AAAA-MM-JJ)") }, singleLine = true)
        Button(
            onClick = { onSave(token, dataRepo, managerRepo, expiry) },
            enabled = deviceSecure && token.isNotBlank() && dataRepo.contains("/") && managerRepo.contains("/"),
            modifier = Modifier.fillMaxWidth()
        ) { Text("Sécuriser avec empreinte") }
        if (deviceSecure && android.os.Build.VERSION.SDK_INT < 30) {
            OutlinedButton(
                onClick = { onUseDeviceCredential(token, dataRepo, managerRepo, expiry) },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Sécuriser avec le code du téléphone") }
        }
    }
}
