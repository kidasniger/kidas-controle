package com.kidas.controle.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import android.animation.ValueAnimator

@Composable
fun KiCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier = modifier, shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(
        containerColor = MaterialTheme.colorScheme.surface
    )) { Column(Modifier.fillMaxWidth().padding(16.dp), content = content) }
}

@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        action?.invoke()
    }
}

enum class OperationStatus { SUCCESS, FAILURE, RUNNING, CANCELLED }

@Composable
fun StatusChip(label: String, status: OperationStatus, modifier: Modifier = Modifier) {
    val (foreground, background) = when (status) {
        OperationStatus.SUCCESS -> Color(0xFF16834A) to Color(0xFF16834A).copy(alpha = .14f)
        OperationStatus.FAILURE -> Color(0xFFD43B45) to Color(0xFFD43B45).copy(alpha = .14f)
        OperationStatus.RUNNING -> Color(0xFFCC7A12) to Color(0xFFCC7A12).copy(alpha = .16f)
        OperationStatus.CANCELLED -> Color(0xFF748096) to Color(0xFF748096).copy(alpha = .16f)
    }
    Surface(modifier, shape = RoundedCornerShape(50), color = background) {
        Text(label, Modifier.padding(horizontal = 12.dp, vertical = 6.dp), color = foreground,
            style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun ErrorBanner(message: String, detail: String? = null, modifier: Modifier = Modifier) {
    Surface(modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.errorContainer,
        shape = RoundedCornerShape(12.dp)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(message, color = MaterialTheme.colorScheme.onErrorContainer)
            if (!detail.isNullOrBlank()) Text(detail, color = MaterialTheme.colorScheme.onErrorContainer,
                style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
fun EmptyState(title: String, description: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun Shimmer(modifier: Modifier = Modifier, height: androidx.compose.ui.unit.Dp = 18.dp) {
    val view = LocalView.current
    val animations = ValueAnimator.areAnimatorsEnabled()
    val transition = rememberInfiniteTransition(label = "shimmer")
    val progress by transition.animateFloat(
        initialValue = if (animations) -1f else 0f,
        targetValue = if (animations) 2f else 0f,
        animationSpec = infiniteRepeatable(tween(if (animations) 1100 else 0, easing = LinearEasing)),
        label = "shimmer-progress"
    )
    val base = MaterialTheme.colorScheme.surfaceVariant
    val brush = if (animations) Brush.linearGradient(
        listOf(base, MaterialTheme.colorScheme.onSurface.copy(alpha = .10f), base),
        start = androidx.compose.ui.geometry.Offset(progress * 600f, 0f),
        end = androidx.compose.ui.geometry.Offset((progress + 1f) * 600f, 0f)
    ) else Brush.linearGradient(listOf(base, base))
    Spacer(modifier.height(height).clip(RoundedCornerShape(8.dp)).background(brush)
        .semantics { contentDescription = "Chargement" })
}

@Composable
fun ConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String = "Confirmer",
    dismissLabel: String = "Annuler",
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirmLabel) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(dismissLabel) } }
    )
}
