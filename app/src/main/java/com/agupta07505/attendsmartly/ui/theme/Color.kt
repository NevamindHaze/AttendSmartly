/*
 * AttendSmartly (2026)
 * © Animesh Gupta — github.com/agupta07505
 * Licensed under the GNU GPL v3 License
 * Do not remove or alter this notice. - Per GPL-3.0 Section 4 & Section 5
 */

package com.agupta07505.attendsmartly.ui.theme

import androidx.compose.ui.graphics.Color

val PrimaryLight = Color(0xFFE45F8D)
val OnPrimaryLight = Color(0xFFFFFFFF)
val PrimaryContainerLight = Color(0xFFFFE1EB)
val OnPrimaryContainerLight = Color(0xFF4A1830)

val SecondaryLight = Color(0xFF347F75)
val OnSecondaryLight = Color(0xFFFFFFFF)
val SecondaryContainerLight = Color(0xFFD9EFE8)
val OnSecondaryContainerLight = Color(0xFF153E38)

val TertiaryLight = Color(0xFFEFA545)
val OnTertiaryLight = Color(0xFFFFFFFF)
val TertiaryContainerLight = Color(0xFFFFE9CA)
val OnTertiaryContainerLight = Color(0xFF55380F)

val SurfaceLight = Color(0xFFFFF8F1)
val OnSurfaceLight = Color(0xFF253330)
val SurfaceVariantLight = Color(0xFFEAE4F4)
val OnSurfaceVariantLight = Color(0xFF544C63)

val OutlineLight = Color(0xFFE6D7E0)
val OutlineVariantLight = Color(0xFFD6C9D2)

// Dark Palette
val PrimaryDark = Color(0xFFB6A7F2)
val OnPrimaryDark = Color(0xFF1C1A32)
val PrimaryContainerDark = Color(0xFF443B68)
val OnPrimaryContainerDark = Color(0xFFF1EAFE)

val SecondaryDark = Color(0xFF8FD0BD)
val OnSecondaryDark = Color(0xFF143C36)
val SecondaryContainerDark = Color(0xFF28564C)
val OnSecondaryContainerDark = Color(0xFFD9EFE8)

val TertiaryDark = Color(0xFFFFA995)
val OnTertiaryDark = Color(0xFF43231D)
val TertiaryContainerDark = Color(0xFF693D39)
val OnTertiaryContainerDark = Color(0xFFFFE9CA)

val SurfaceDark = Color(0xFF1D2427)
val OnSurfaceDark = Color(0xFFFFF8F1)
val SurfaceVariantDark = Color(0xFF2B3136)
val OnSurfaceVariantDark = Color(0xFFEAE2F0)

val OutlineDark = Color(0xFF615565)
val OutlineVariantDark = Color(0xFF655C6D)

// Attendance Status Colors
val StatusPresent = Color(0xFF3F8B70) // Green
val StatusAbsent = Color(0xFFD96D7D)  // Red
val StatusCancelled = Color(0xFFD99043) // Amber/Orange
val StatusUnmarked = Color(0xFF757575)  // Neutral Gray

// Preset Subject Palette Colors
val SubjectPalette = listOf(
    Color(0xFFE76F91), // Rose
    Color(0xFF52A99A), // Teal
    Color(0xFFF2B654), // Amber
    Color(0xFF8C82D8), // Violet
    Color(0xFF6F9CE8), // Sky
    Color(0xFF7DBE83), // Green
    Color(0xFFE88B68), // Tangerine
    Color(0xFF71808B)  // Cyan
)

data class PresetThemeColor(
    val hex: String,
    val name: String,
    val color: Color
)

/** Blend a subject accent into an opaque pastel surface for cards. */
fun pastelTint(accent: Color, surface: Color, strength: Float = 0.16f): Color {
    val amount = strength.coerceIn(0f, 1f)
    return Color(
        red = surface.red * (1f - amount) + accent.red * amount,
        green = surface.green * (1f - amount) + accent.green * amount,
        blue = surface.blue * (1f - amount) + accent.blue * amount,
        alpha = 1f
    )
}
val PresetThemeColors = listOf(
    PresetThemeColor("#E76F91", "Rose (Default)", Color(0xFFE76F91)),
    PresetThemeColor("#00639B", "Ocean Blue", Color(0xFF00639B)),
    PresetThemeColor("#006C51", "Emerald Green", Color(0xFF006C51)),
    PresetThemeColor("#984061", "Crimson Ruby", Color(0xFF984061)),
    PresetThemeColor("#825500", "Sunset Amber", Color(0xFF825500)),
    PresetThemeColor("#3F51B5", "Royal Indigo", Color(0xFF3F51B5)),
    PresetThemeColor("#006972", "Deep Teal", Color(0xFF006972)),
    PresetThemeColor("#B81B6C", "Vivid Rose", Color(0xFFB81B6C)),
    PresetThemeColor("#00838F", "Electric Cyan", Color(0xFF00838F)),
    PresetThemeColor("#D84315", "Flame Orange", Color(0xFFD84315)),
    PresetThemeColor("#2E7D32", "Forest Green", Color(0xFF2E7D32)),
    PresetThemeColor("#455A64", "Midnight Slate", Color(0xFF455A64))
)
