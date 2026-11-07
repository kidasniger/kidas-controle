package com.kidas.controle.ui.nav

import android.animation.ValueAnimator
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.*
import com.kidas.controle.ui.components.*
import com.kidas.controle.ui.settings.UpdateSettingsScreen
import com.kidas.controle.ui.theme.KiDasThemeMode
import com.kidas.controle.updater.AppUpdateManager
import com.kidas.controle.updater.UpdateState

private data class Tab(val route: String, val label: String, val glyph: String)
private val tabs = listOf(
    Tab("home", "Accueil", "⌂"),
    Tab("publish", "Publier", "＋"),
    Tab("reviews", "Avis", "✉"),
    Tab("media", "Médias", "▧"),
    Tab("bot", "Bot", "◈"),
    Tab("settings", "Réglages", "⚙")
)

@Composable
fun KiDasNavigation(
    manager: AppUpdateManager,
    themeMode: KiDasThemeMode,
    onThemeModeChange: (KiDasThemeMode) -> Unit,
    unansweredCount: Int = 0
) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route ?: "home"
    val duration = if (ValueAnimator.areAnimatorsEnabled()) 300 else 0
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface) {
                tabs.forEachIndexed { index, tab ->
                    val selected = currentRoute == tab.route
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Box {
                                Text(tab.glyph, modifier = Modifier.scale(if (selected) 1.16f else 1f),
                                    style = MaterialTheme.typography.titleLarge)
                                if (tab.route == "reviews" && unansweredCount > 0) {
                                    Badge(Modifier.align(Alignment.TopEnd)) {
                                        Text(if (unansweredCount > 99) "99+" else unansweredCount.toString())
                                    }
                                }
                            }
                        },
                        label = { Text(tab.label, style = MaterialTheme.typography.labelSmall) },
                        alwaysShowLabel = true
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier.fillMaxSize().padding(padding),
            enterTransition = {
                if (duration == 0) EnterTransition.None else
                    fadeIn(tween(duration)) + slideIntoContainer(
                        AnimatedContentTransitionScope.SlideDirection.Left, tween(duration)
                    )
            },
            exitTransition = {
                if (duration == 0) ExitTransition.None else fadeOut(tween(duration)) +
                    slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Left, tween(duration))
            },
            popEnterTransition = {
                if (duration == 0) EnterTransition.None else fadeIn(tween(duration)) +
                    slideIntoContainer(AnimatedContentTransitionScope.SlideDirection.Right, tween(duration))
            },
            popExitTransition = {
                if (duration == 0) ExitTransition.None else fadeOut(tween(duration)) +
                    slideOutOfContainer(AnimatedContentTransitionScope.SlideDirection.Right, tween(duration))
            }
        ) {
            composable("home") { HomeScreen(manager, onSettings = { navController.navigate("settings") }) }
            composable("publish") { FeaturePlaceholder("Publier", "Prépare et programme tes publications.") }
            composable("reviews") { FeaturePlaceholder("Avis", "Retrouve les commentaires à traiter.") }
            composable("media") { FeaturePlaceholder("Médias", "Bibliothèque des images et vidéos.") }
            composable("bot") { FeaturePlaceholder("Bot", "État et configuration de l’assistant.") }
            composable("settings") {
                Column(Modifier.fillMaxSize()) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("Apparence", style = MaterialTheme.typography.titleMedium)
                        TextButton(onClick = { navController.popBackStack() }) { Text("Retour") }
                    }
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                        listOf(KiDasThemeMode.DARK to "Sombre", KiDasThemeMode.LIGHT to "Clair", KiDasThemeMode.SYSTEM to "Système")
                            .forEachIndexed { index, pair ->
                                SegmentedButton(
                                    selected = themeMode == pair.first,
                                    onClick = { onThemeModeChange(pair.first) },
                                    shape = SegmentedButtonDefaults.itemShape(index, 3)
                                ) { Text(pair.second) }
                            }
                    }
                    HorizontalDivider(Modifier.padding(vertical = 8.dp))
                    UpdateSettingsScreen(manager) { navController.popBackStack() }
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(manager: AppUpdateManager, onSettings: () -> Unit) {
    val state by manager.state.collectAsState()
    Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("KI DAS", style = MaterialTheme.typography.headlineLarge)
        Text("Tableau de bord", style = MaterialTheme.typography.titleMedium)
        KiCard {
            Text("Bienvenue dans KI DAS Contrôle", style = MaterialTheme.typography.titleMedium)
            Text("Ton espace de gestion Facebook.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        when (val current = state) {
            is UpdateState.UpdateAvailable -> KiCard {
                Text("Mise à jour disponible", style = MaterialTheme.typography.titleMedium)
                Text("Version ${current.release.tagName}")
                Button(onClick = onSettings) { Text("Consulter") }
            }
            is UpdateState.Checking -> Text("Vérification des mises à jour…")
            is UpdateState.Error -> ErrorBanner("Impossible de vérifier les mises à jour", current.message)
            else -> StatusChip("Application prête", OperationStatus.SUCCESS)
        }
    }
}

@Composable
private fun FeaturePlaceholder(title: String, description: String) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        KiCard { EmptyState("Écran en préparation", description) }
    }
}
