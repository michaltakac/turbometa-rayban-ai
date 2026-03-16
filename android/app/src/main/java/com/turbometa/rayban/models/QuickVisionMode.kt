package com.turbometa.rayban.models

import android.content.Context
import com.turbometa.rayban.R

/**
 * Quick Vision Modes
 * Quick vision modes - image recognition assistants for different scenarios
 */
enum class QuickVisionMode(val id: String) {
    STANDARD("standard"),       // Default mode
    HEALTH("health"),           // Health recognition
    BLIND("blind"),             // Blind assistance mode
    READING("reading"),         // Reading mode
    TRANSLATE("translate"),     // Translation mode
    ENCYCLOPEDIA("encyclopedia"), // Encyclopedia (museum) mode
    CUSTOM("custom");           // Custom prompt

    fun getDisplayName(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.quickvision_mode_standard)
            HEALTH -> context.getString(R.string.quickvision_mode_health)
            BLIND -> context.getString(R.string.quickvision_mode_blind)
            READING -> context.getString(R.string.quickvision_mode_reading)
            TRANSLATE -> context.getString(R.string.quickvision_mode_translate)
            ENCYCLOPEDIA -> context.getString(R.string.quickvision_mode_encyclopedia)
            CUSTOM -> context.getString(R.string.quickvision_mode_custom)
        }
    }

    fun getDescription(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.quickvision_mode_standard_desc)
            HEALTH -> context.getString(R.string.quickvision_mode_health_desc)
            BLIND -> context.getString(R.string.quickvision_mode_blind_desc)
            READING -> context.getString(R.string.quickvision_mode_reading_desc)
            TRANSLATE -> context.getString(R.string.quickvision_mode_translate_desc)
            ENCYCLOPEDIA -> context.getString(R.string.quickvision_mode_encyclopedia_desc)
            CUSTOM -> context.getString(R.string.quickvision_mode_custom_desc)
        }
    }


    /**
     * Get the prompt for this mode (excluding translate and custom, which need dynamic generation)
     */
    fun getPrompt(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.prompt_quickvision_standard)
            HEALTH -> context.getString(R.string.prompt_quickvision_health)
            BLIND -> context.getString(R.string.prompt_quickvision_blind)
            READING -> context.getString(R.string.prompt_quickvision_reading)
            TRANSLATE -> "" // Needs to be obtained through Manager (includes target language)
            ENCYCLOPEDIA -> context.getString(R.string.prompt_quickvision_encyclopedia)
            CUSTOM -> "" // Needs to be obtained through Manager for custom content
        }
    }

    companion object {
        fun fromId(id: String): QuickVisionMode {
            return entries.find { it.id == id } ?: STANDARD
        }
    }
}
