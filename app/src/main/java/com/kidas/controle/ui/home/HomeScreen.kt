package com.kidas.controle.ui.home

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Analytics
import androidx.compose.material.icons.outlined.Assignment
import androidx.compose.material.icons.outlined.Facebook
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.kidas.controle.ui.components.KiCard
import com.kidas.controle.ui.components.SectionTitle
import com.kidas.controle.ui.components.Shimmer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onNavigate: (String) -> Unit
) {
    val state by viewModel.state.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(viewModel, lifecycleOwner) {
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            viewModel.refresh()
            while (true) {
                delay(30_000L)
                viewModel.refresh()
            }
        }
    }

    PullToRefreshBox(
        isRefreshing = state.refreshing,
        onRefresh = viewModel::refresh,
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("KI DAS", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    Text("Tableau de bord", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = viewModel::refresh, enabled = !state.refreshing) {
                    Icon(Icons.Outlined.Refresh, contentDescription = "Actualiser le tableau de bord")
                }
            }

            if (state.loading) {
                LoadingDashboard()
            } else {
                AnimatedVisibility(visible = true) {
                    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        StatusRing(state.botStatus, state.botDetail, onManage = { onNavigate("bot") })

                        if (state.tokenDaysRemaining != null && state.tokenDaysRemaining!! <= 30) {
                            TokenExpiryWarning(state.tokenDaysRemaining!!)
                        }

                        if (!state.error.isNullOrBlank()) {
                            Text(
                                text = state.error!!,
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodySmall
                            )
                        }

                        SectionTitle("Vue d’ensemble")
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                CounterCard("Abonnés", state.followers, Icons.Outlined.Groups, Modifier.weight(1f), 0) { onNavigate("stats") }
                                CounterCard("J’aime la Page", state.pageLikes, Icons.Outlined.Facebook, Modifier.weight(1f), 1) { onNavigate("stats") }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                CounterCard("Commentaires sans réponse", state.unansweredComments.toLong(), Icons.Outlined.Forum, Modifier.weight(1f), 2) { onNavigate("reviews") }
                                CounterCard("Actions en attente", state.pendingActions.toLong(), Icons.Outlined.Assignment, Modifier.weight(1f), 3) { onNavigate("publish") }
                            }
                        }

                        SectionTitle("Performances · 7 derniers jours")
                        MetricChartCard("Interactions", state.interactions, Modifier.fillMaxWidth())
                        MetricChartCard("Vues du contenu", state.views, Modifier.fillMaxWidth())
                        MetricChartCard("Visites de la Page", state.visits, Modifier.fillMaxWidth())
                        MetricChartCard("Abonnés", state.followersHistory, Modifier.fillMaxWidth())
                        MetricChartCard("Nouveaux abonnés par jour", state.dailyFollowers, Modifier.fillMaxWidth(), bars = true)

                        SectionTitle("Actions rapides")
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                QuickAction("Audit complet", "audit", Modifier.weight(1f), state, viewModel)
                                QuickAction("Statistiques", "stats", Modifier.weight(1f), state, viewModel)
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                QuickAction("Surveiller", "surveiller", Modifier.weight(1f), state, viewModel)
                                QuickAction("Traiter les files", "files", Modifier.weight(1f), state, viewModel)
                            }
                            state.actionError?.let {
                                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                            }
                        }

                        SectionTitle("Dernières exécutions")
                        if (state.executions.isEmpty()) {
                            KiCard(Modifier.fillMaxWidth()) {
                                Text("Aucune exécution récente", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        } else {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                state.executions.take(10).forEach { execution ->
                                    ExecutionRow(execution)
                                }
                            }
                        }
                        state.lastUpdated?.let {
                            Text("Dernière actualisation à $it", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingDashboard() {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Shimmer(Modifier.fillMaxWidth(), 118.dp)
        repeat(2) { Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Shimmer(Modifier.weight(1f), 92.dp)
            Shimmer(Modifier.weight(1f), 92.dp)
        } }
        repeat(3) { Shimmer(Modifier.fillMaxWidth(), 160.dp) }
    }
}

@Composable
fun StatusRing(state: BotStatus, detail: String, onManage: () -> Unit) {
    val color = when (state) {
        BotStatus.RUNNING -> Color(0xFF20B879)
        BotStatus.IDLE -> Color(0xFFE6A23C)
        BotStatus.STOPPED -> MaterialTheme.colorScheme.error
    }
    val transition = rememberInfiniteTransition(label = "bot-pulse")
    val pulse by transition.animateFloat(
        initialValue = 0.72f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1500, easing = FastOutSlowInEasing), repeatMode = androidx.compose.animation.core.RepeatMode.Reverse),
        label = "pulse"
    )
    KiCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(66.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    drawCircle(color.copy(alpha = .12f * pulse), radius = size.minDimension * .49f)
                    drawCircle(color.copy(alpha = .25f * pulse), radius = size.minDimension * .36f)
                    drawCircle(color, radius = size.minDimension * .22f)
                    drawCircle(MaterialTheme.colorScheme.surface, radius = size.minDimension * .10f)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    when (state) {
                        BotStatus.RUNNING -> "Le bot est en marche"
                        BotStatus.IDLE -> "Le bot est actif, en attente"
                        BotStatus.STOPPED -> "Le bot est arrêté"
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onManage) { Text("Gérer") }
        }
    }
}

@Composable
private fun CounterCard(
    label: String,
    value: Long,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier,
    order: Int,
    onClick: () -> Unit
) {
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(order) {
        delay(order * 30L)
        visible = true
    }
    val alpha by animateFloatAsState(if (visible) 1f else 0f, tween(280), label = "counter-alpha")
    val offset by animateFloatAsState(if (visible) 0f else 12f, tween(280), label = "counter-offset")
    KiCard(
        modifier = modifier
            .alpha(alpha)
            .offset(y = offset.dp)
            .clickable(onClick = onClick)
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(21.dp))
        Spacer(Modifier.height(10.dp))
        AnimatedCounter(value)
        Spacer(Modifier.height(3.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun AnimatedCounter(value: Long) {
    val number = remember { Animatable(0f) }
    LaunchedEffect(value) { number.animateTo(value.toFloat(), tween(900, easing = FastOutSlowInEasing)) }
    val formatted = NumberFormat.getIntegerInstance(Locale.FRANCE).format(number.value.roundToInt())
    Text(formatted, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 1)
}

@Composable
private fun TokenExpiryWarning(days: Long) {
    Surface(
        color = Color(0xFFFFA726).copy(alpha = .15f),
        contentColor = MaterialTheme.colorScheme.onSurface,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("⚠", color = Color(0xFFE58A12), fontSize = 20.sp)
            Text(
                if (days < 0) "Le jeton GitHub a expiré." else "Le jeton GitHub expire dans $days jour(s).",
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

@Composable
private fun MetricChartCard(title: String, values: List<ChartPoint>, modifier: Modifier, bars: Boolean = false) {
    val delta = if (values.size >= 2) values.last().value - values[values.lastIndex - 1].value else 0f
    val deltaText = if (delta >= 0) "▲ ${formatMetric(delta)}" else "▼ ${formatMetric(abs(delta))}"
    val deltaColor = if (delta >= 0) Color(0xFF20B879) else MaterialTheme.colorScheme.error
    KiCard(modifier) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            Surface(color = deltaColor.copy(alpha = .12f), shape = RoundedCornerShape(50)) {
                Text(deltaText, Modifier.padding(horizontal = 9.dp, vertical = 5.dp), color = deltaColor, style = MaterialTheme.typography.labelSmall)
            }
        }
        Spacer(Modifier.height(12.dp))
        if (values.isEmpty()) {
            Text("Données en attente", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        } else if (bars) {
            BarChart(values)
        } else {
            Sparkline(values)
        }
    }
}

@Composable
fun Sparkline(values: List<ChartPoint>, modifier: Modifier = Modifier) {
    var selected by remember(values) { mutableIntStateOf(values.lastIndex) }
    val progress by animateFloatAsState(1f, tween(800, easing = FastOutSlowInEasing), label = "line-progress")
    val pulseTransition = rememberInfiniteTransition(label = "chart-point")
    val pulse by pulseTransition.animateFloat(5f, 8f, infiniteRepeatable(tween(850), repeatMode = androidx.compose.animation.core.RepeatMode.Reverse), label = "point-pulse")
    val lineColor = MaterialTheme.colorScheme.primary
    val gridColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .12f)
    val description = "${values.size} jours, dernière valeur ${formatMetric(values.last().value)}"
    Column(modifier.semantics { contentDescription = "Graphique, $description" }) {
        Text("${values[selected].day} · ${formatMetric(values[selected].value)}", style = MaterialTheme.typography.labelMedium, color = lineColor)
        Canvas(
            Modifier.fillMaxWidth().height(124.dp)
                .pointerInput(values) {
                    detectTapGestures { point ->
                        selected = indexAt(point.x, size.width, values.size)
                    }
                }
                .pointerInput(values) {
                    detectDragGestures { change, _ ->
                        selected = indexAt(change.position.x, size.width, values.size)
                    }
                }
        ) {
            val left = 8.dp.toPx()
            val right = size.width - 8.dp.toPx()
            val top = 10.dp.toPx()
            val bottom = size.height - 12.dp.toPx()
            repeat(4) { i ->
                val y = top + (bottom - top) * i / 3f
                drawLine(gridColor, Offset(left, y), Offset(right, y), 1.dp.toPx())
            }
            val min = values.minOf { it.value }.let { if (it == values.maxOf { p -> p.value }) it - 1f else it }
            val max = values.maxOf { it.value }.let { if (it == min) it + 1f else it }
            val points = values.mapIndexed { index, point ->
                Offset(
                    left + (right - left) * index / (values.size - 1).coerceAtLeast(1),
                    bottom - ((point.value - min) / (max - min).coerceAtLeast(1f)) * (bottom - top)
                )
            }
            val visibleCount = (points.size * progress).toInt().coerceAtLeast(1).coerceAtMost(points.size)
            val path = Path().apply {
                moveTo(points.first().x, points.first().y)
                points.take(visibleCount).drop(1).forEach { lineTo(it.x, it.y) }
            }
            if (visibleCount > 1) {
                val fill = Path().apply {
                    addPath(path)
                    lineTo(points[visibleCount - 1].x, bottom)
                    lineTo(points.first().x, bottom)
                    close()
                }
                drawPath(fill, Brush.verticalGradient(listOf(lineColor.copy(alpha = .25f), lineColor.copy(alpha = 0f)), top, bottom))
                drawPath(path, lineColor, style = Stroke(width = 2.6.dp.toPx(), cap = StrokeCap.Round))
            }
            val point = points[selected.coerceIn(0, points.lastIndex)]
            drawCircle(lineColor.copy(alpha = .18f), radius = pulse * 1.8f, center = point)
            drawCircle(lineColor, radius = 4.dp.toPx(), center = point)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(values.first().day, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(values.last().day, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun BarChart(values: List<ChartPoint>, modifier: Modifier = Modifier) {
    val maxValue = values.maxOfOrNull { it.value }?.coerceAtLeast(1f) ?: 1f
    Row(
        modifier.fillMaxWidth().height(140.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        values.forEach { point ->
            val target = (point.value / maxValue).coerceIn(0f, 1f)
            val animated by animateFloatAsState(target, androidx.compose.animation.core.spring(dampingRatio = .62f, stiffness = 150f), label = "bar-height")
            Column(
                Modifier.weight(1f).fillMaxHeight(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Bottom
            ) {
                Text(formatMetric(point.value), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                Spacer(Modifier.height(5.dp))
                Box(
                    Modifier.fillMaxWidth(.72f).fillMaxHeight(animated.coerceAtLeast(.025f))
                        .clip(RoundedCornerShape(topStart = 7.dp, topEnd = 7.dp))
                        .background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.primary.copy(alpha = .48f))))
                )
                Spacer(Modifier.height(6.dp))
                Text(point.day, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
    }
}

@Composable
private fun QuickAction(
    label: String,
    action: String,
    modifier: Modifier,
    state: HomeUiState,
    viewModel: HomeViewModel
) {
    val loading = action in state.actionProgress
    val success = action in state.actionSuccess
    OutlinedButton(
        onClick = { viewModel.runAction(action) },
        enabled = !loading,
        modifier = modifier.heightIn(min = 58.dp),
        shape = RoundedCornerShape(14.dp)
    ) {
        when {
            loading -> CircularProgressIndicator(Modifier.size(17.dp), strokeWidth = 2.dp)
            success -> Text("✓", color = Color(0xFF20B879), fontWeight = FontWeight.Bold)
            else -> Icon(Icons.Outlined.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelMedium, maxLines = 2)
    }
}

@Composable
private fun ExecutionRow(execution: HomeExecution) {
    val context = LocalContext.current
    val running = execution.status == "in_progress" || execution.status == "queued"
    val color = when {
        running -> Color(0xFFE6A23C)
        execution.conclusion == "success" -> Color(0xFF20B879)
        execution.conclusion == "failure" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    KiCard(
        Modifier.fillMaxWidth().clickable(enabled = execution.url.isNotBlank()) {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(execution.url))) }
        }
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(color))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(execution.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(execution.relativeTime, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(if (running) "En cours" else execution.conclusion ?: execution.status, style = MaterialTheme.typography.labelSmall, color = color)
                Text(execution.duration, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}


@Composable
fun HomeStatsScreen(viewModel: HomeViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(viewModel) { viewModel.refresh() }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("Retour") }
            Text("Statistiques", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        }
        if (state.loading) {
            repeat(4) { Shimmer(Modifier.fillMaxWidth(), 150.dp) }
        } else {
            MetricChartCard("Interactions", state.interactions, Modifier.fillMaxWidth())
            MetricChartCard("Vues du contenu", state.views, Modifier.fillMaxWidth())
            MetricChartCard("Visites de la Page", state.visits, Modifier.fillMaxWidth())
            MetricChartCard("Abonnés", state.followersHistory, Modifier.fillMaxWidth())
            MetricChartCard("Nouveaux abonnés par jour", state.dailyFollowers, Modifier.fillMaxWidth(), bars = true)
        }
    }
}

private fun indexAt(x: Float, width: Int, count: Int): Int =
    ((x / width.coerceAtLeast(1)) * count).roundToInt().coerceIn(0, count - 1)

private fun formatMetric(value: Float): String =
    NumberFormat.getIntegerInstance(Locale.FRANCE).format(value.roundToInt())
