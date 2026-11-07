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
    error: String? = null,
    onResetSecurity: () -> Unit = {}
) {
    val colors = MaterialTheme.colorScheme

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = colors.background,
        contentColor = colors.onBackground
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 28.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "KI DAS",
                style = MaterialTheme.typography.displaySmall,
                color = colors.onBackground
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Contrôle sécurisé",
                style = MaterialTheme.typography.titleLarge,
                color = colors.onBackground
            )
            Spacer(Modifier.height(16.dp))
            Text(
                text = "Authentifie-toi avec ton empreinte ou le verrouillage de ton téléphone.",
                color = colors.onBackground,
                style = MaterialTheme.typography.bodyLarge
            )
            if (error != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = error,
                    color = colors.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Spacer(Modifier.height(24.dp))
            Button(
                onClick = onUnlock,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.primary,
                    contentColor = colors.onPrimary
                )
            ) {
                Text("Déverrouiller")
            }
            if (error != null && (error.contains("invalidée", true) || error.contains("indisponible", true) || error.contains("clé Android", true))) {
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = onResetSecurity, modifier = Modifier.fillMaxWidth()) {
                    Text("Réinitialiser la sécurité")
                }
                Text(
                    "Cette action efface uniquement le coffre local. Tu devras saisir à nouveau ton jeton GitHub.",
                    color = colors.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (showDeviceCredential) {
                TextButton(
                    onClick = onUseDeviceCredential,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = colors.primary
                    )
                ) {
                    Text("Utiliser le code du téléphone")
                }
            }
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
    val colors = MaterialTheme.colorScheme
    var token by remember { mutableStateOf("") }
    var dataRepo by remember { mutableStateOf("kidasniger/facebook-data") }
    var managerRepo by remember { mutableStateOf("kidasniger/facebook-manager") }
    var expiry by remember { mutableStateOf("") }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = colors.background,
        contentColor = colors.onBackground
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "Bienvenue sur KI DAS Contrôle 👋",
                style = MaterialTheme.typography.headlineMedium,
                color = colors.onBackground
            )
            Text(
                "Colle de nouveau ton jeton : l’ancien jeton ne peut pas être récupéré après la migration.",
                color = colors.onBackground
            )
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = colors.surface,
                    contentColor = colors.onSurface
                )
            ) {
                Column(
                    Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("Droits requis sur le jeton GitHub", style = MaterialTheme.typography.titleMedium)
                    Text("Contents : lecture et écriture")
                    Text("Actions : lecture et écriture")
                    Text("Variables : lecture et écriture")
                    Text("Metadata : lecture seule")
                }
            }
            if (!deviceSecure) {
                Text(
                    "Aucun verrouillage détecté. Configure un code PIN, un schéma ou un mot de passe dans Android. Le jeton ne peut pas être enregistré.",
                    color = colors.error
                )
            }
            if (error != null) Text(error, color = colors.error)
            OutlinedTextField(
                value = token,
                onValueChange = { token = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Jeton GitHub") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true
            )
            OutlinedTextField(
                value = dataRepo,
                onValueChange = { dataRepo = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Dépôt de données") },
                singleLine = true
            )
            OutlinedTextField(
                value = managerRepo,
                onValueChange = { managerRepo = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Dépôt manager") },
                singleLine = true
            )
            OutlinedTextField(
                value = expiry,
                onValueChange = { expiry = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Expiration (facultatif, AAAA-MM-JJ)") },
                singleLine = true
            )
            Button(
                onClick = {
                    val value = token
                    token = ""
                    onSave(value, dataRepo, managerRepo, expiry)
                },
                enabled = deviceSecure && token.isNotBlank() &&
                    dataRepo.contains("/") && managerRepo.contains("/"),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Sécuriser avec empreinte")
            }
            if (deviceSecure && android.os.Build.VERSION.SDK_INT < 30) {
                OutlinedButton(
                    onClick = {
                        val value = token
                        token = ""
                        onUseDeviceCredential(value, dataRepo, managerRepo, expiry)
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Sécuriser avec le code du téléphone")
                }
            }
        }
    }
}
