package com.kidas.controle.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

enum class KiDasThemeMode { DARK, LIGHT, SYSTEM }

private val DarkColors = darkColorScheme(
    primary = Color(0xFF5B95FF),
    onPrimary = Color(0xFF07152F),
    secondary = Color(0xFF9AB9FF),
    background = Color(0xFF0A0F1E),
    onBackground = Color(0xFFE8ECF8),
    surface = Color(0xFF121A2F),
    onSurface = Color(0xFFE8ECF8),
    surfaceVariant = Color(0xFF202B45),
    onSurfaceVariant = Color(0xFFB8C4DC),
    error = Color(0xFFFF6B72),
    onError = Color(0xFF390006)
)
private val LightColors = lightColorScheme(
    primary = Color(0xFF2563EB),
    onPrimary = Color.White,
    secondary = Color(0xFF4779D7),
    background = Color(0xFFF4F6FB),
    onBackground = Color(0xFF172033),
    surface = Color.White,
    onSurface = Color(0xFF172033),
    surfaceVariant = Color(0xFFE9EEF8),
    onSurfaceVariant = Color(0xFF46536B),
    error = Color(0xFFB4232D),
    onError = Color.White
)

@Composable
fun KiDasTheme(
    mode: KiDasThemeMode = KiDasThemeMode.DARK,
    systemDark: Boolean = androidx.compose.foundation.isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val dark = when (mode) {
        KiDasThemeMode.DARK -> true
        KiDasThemeMode.LIGHT -> false
        KiDasThemeMode.SYSTEM -> systemDark
    }
    MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
}
