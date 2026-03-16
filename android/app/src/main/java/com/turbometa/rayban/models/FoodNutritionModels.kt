package com.turbometa.rayban.models

import com.turbometa.rayban.ui.theme.HealthExcellent
import com.turbometa.rayban.ui.theme.HealthFair
import com.turbometa.rayban.ui.theme.HealthGood
import com.turbometa.rayban.ui.theme.HealthPoor
import androidx.compose.ui.graphics.Color

data class FoodNutritionResponse(
    val foods: List<FoodItem> = emptyList(),
    val totalCalories: Int = 0,
    val totalProtein: Double = 0.0,
    val totalFat: Double = 0.0,
    val totalCarbs: Double = 0.0,
    val healthScore: Int = 0,
    val suggestions: List<String> = emptyList()
) {
    val healthScoreColor: Color
        get() = when {
            healthScore >= 80 -> HealthExcellent
            healthScore >= 60 -> HealthGood
            healthScore >= 40 -> HealthFair
            else -> HealthPoor
        }

    val healthScoreText: String
        get() = when {
            healthScore >= 80 -> "Excellent"
            healthScore >= 60 -> "Good"
            healthScore >= 40 -> "Fair"
            else -> "Poor"
        }
}

data class FoodItem(
    val name: String,
    val portion: String,
    val calories: Int,
    val protein: Double,
    val fat: Double,
    val carbs: Double,
    val fiber: Double? = null,
    val sugar: Double? = null,
    val healthRating: String = "Good"
) {
    val healthRatingEmoji: String
        get() = when (healthRating) {
            "Excellent" -> "🟢"
            "Good" -> "🟡"
            "Fair" -> "🟠"
            "Poor" -> "🔴"
            else -> "🟡"
        }

    val healthRatingColor: Color
        get() = when (healthRating) {
            "Excellent" -> HealthExcellent
            "Good" -> HealthGood
            "Fair" -> HealthFair
            "Poor" -> HealthPoor
            else -> HealthGood
        }
}
