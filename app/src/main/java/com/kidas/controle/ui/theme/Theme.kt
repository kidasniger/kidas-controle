package com.kidas.controle.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val KiDasColorScheme = darkColorScheme()

@Composable
fun KiDasTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = KiDasColorScheme,
        content = content
    )
}
