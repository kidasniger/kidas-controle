package com.kidas.controle.ui.nav

import android.animation.ValueAnimator
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SmartToy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.*
import com.kidas.controle.ui.components.*
import com.kidas.controle.security.SecureTokenRepository
import com.kidas.controle.ui.home.HomeScreen
import com.kidas.controle.ui.home.HomeStatsScreen
import com.kidas.controle.ui.home.HomeViewModel
import com.kidas.controle.ui.publish.PublishScreen
import com.kidas.controle.ui.settings.UpdateSettingsScreen
import com.kidas.controle.ui.theme.KiDasThemeMode
import com.kidas.controle.updater.AppUpdateManager
import com.kidas.controle.updater.UpdateState

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("home", "Accueil", Icons.Outlined.Home),
    Tab("publish", "Publier", Icons.Outlined.Add),
    Tab("reviews", "Avis", Icons.Outlined.MailOutline),
    Tab("media", "Médias", Icons.Outlined.Collections),
    Tab("bot", "Bot", Icons.Outlined.SmartToy),
    Tab("settings", "Réglages", Icons.Outlined.Settings)
)

@Composable
fun KiDasNavigation(
    manager: AppUpdateManager,
    tokenRepository: SecureTokenRepository,
    themeMode: KiDasThemeMode,
    onThemeModeChange: (KiDasThemeMode) -> Unit,
    unansweredCount: Int = 0
) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route ?: "home"
    val duration = if (ValueAnimator.areAnimatorsEnabled()) 260 else 0
    val snackbarHostState = remember { SnackbarHostState() }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                contentColor = MaterialTheme.colorScheme.onSurface,
                tonalElevation = 0.dp,
                windowInsets = NavigationBarDefaults.windowInsets
            ) {
                tabs.forEach { tab ->
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
                            BadgedBox(
                                badge = {
                                    if (tab.route == "reviews" && unansweredCount > 0) {
                                        Badge {
                                            Text(if (unansweredCount > 99) "99+" else unansweredCount.toString())
                                        }
                                    }
                                }
                            ) {
                                Icon(
                                    imageVector = tab.icon,
                                    contentDescription = tab.label,
                                    modifier = Modifier.size(23.dp)
                                )
                            }
                        },
                        label = {
                            Text(
                                text = tab.label,
                                maxLines = 1,
                                softWrap = false,
                                overflow = TextOverflow.Clip,
                                fontSize = 10.sp
                            )
                        },
                        alwaysShowLabel = true,
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                        )
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
            composable("home") {
                val homeViewModel: HomeViewModel = viewModel(
                    factory = object : ViewModelProvider.Factory {
                        @Suppress("UNCHECKED_CAST")
                        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                            HomeViewModel(tokenRepository) as T
                    }
                )
                HomeScreen(homeViewModel) { route -> navController.navigate(route) }
            }
            composable("stats") {
                val homeViewModel: HomeViewModel = viewModel(
                    factory = object : ViewModelProvider.Factory {
                        @Suppress("UNCHECKED_CAST")
                        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                            HomeViewModel(tokenRepository) as T
                    }
                )
                HomeStatsScreen(homeViewModel) { navController.popBackStack() }
            }
            composable("publish") { PublishScreen(tokenRepository) }
            composable("reviews") { FeaturePlaceholder("Avis", "Retrouve les commentaires à traiter.") }
            composable("media") { FeaturePlaceholder("Médias", "Bibliothèque des images et vidéos.") }
            composable("bot") { FeaturePlaceholder("Bot", "État et configuration de l’assistant.") }
            composable("settings") {
                Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 18.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Réglages", style = MaterialTheme.typography.headlineMedium)
                        Text(
                            "Personnalisation de l’application",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    KiCard {
                        Text("Apparence", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(12.dp))
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            listOf(
                                KiDasThemeMode.DARK to "Sombre",
                                KiDasThemeMode.LIGHT to "Clair",
                                KiDasThemeMode.SYSTEM to "Système"
                            ).forEachIndexed { index, pair ->
                                SegmentedButton(
                                    selected = themeMode == pair.first,
                                    onClick = { onThemeModeChange(pair.first) },
                                    shape = SegmentedButtonDefaults.itemShape(index, 3)
                                ) { Text(pair.second, maxLines = 1) }
                            }
                        }
                    }
                    UpdateSettingsScreen(manager) { navController.popBackStack() }
                }
            }
        }
    }
}

@Composable
private fun HomeScreen(manager: AppUpdateManager, onSettings: () -> Unit) {
    val state by manager.state.collectAsState()

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                "KI DAS",
                style = MaterialTheme.typography.headlineLarge,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                "Tableau de bord",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        KiCard(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Bienvenue dans KI DAS Contrôle",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Text(
                    "Ton espace de gestion Facebook.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        when (val current = state) {
            is UpdateState.UpdateAvailable -> KiCard(Modifier.fillMaxWidth()) {
                Text("Mise à jour disponible", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text(
                    "Version ${current.release.tagName}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(12.dp))
                Button(onClick = onSettings, shape = RoundedCornerShape(14.dp)) {
                    Text("Consulter")
                }
            }
            is UpdateState.Checking -> KiCard(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text("Vérification des mises à jour…", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            is UpdateState.Error -> ErrorBanner(
                "Impossible de vérifier les mises à jour",
                current.message,
                Modifier.fillMaxWidth()
            )
            else -> StatusChip("Application prête", OperationStatus.SUCCESS)
        }
    }
}

@Composable
private fun FeaturePlaceholder(title: String, description: String) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium)
        KiCard(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Écran en préparation", style = MaterialTheme.typography.titleMedium)
                Text(
                    description,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
