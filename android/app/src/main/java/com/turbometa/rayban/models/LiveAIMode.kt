package com.turbometa.rayban.models

import android.content.Context
import com.turbometa.rayban.R

/**
 * Live AI Modes
 * Real-time conversation modes - conversation assistants for different scenarios
 */
enum class LiveAIMode(val id: String) {
    STANDARD("standard"),   // Default mode - free conversation
    MUSEUM("museum"),       // Museum mode
    BLIND("blind"),         // Blind assistance mode
    READING("reading"),     // Reading mode
    TRANSLATE("translate"), // Translation mode
    CUSTOM("custom");       // Custom prompt

    fun getDisplayName(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.liveai_mode_standard)
            MUSEUM -> context.getString(R.string.liveai_mode_museum)
            BLIND -> context.getString(R.string.liveai_mode_blind)
            READING -> context.getString(R.string.liveai_mode_reading)
            TRANSLATE -> context.getString(R.string.liveai_mode_translate)
            CUSTOM -> context.getString(R.string.liveai_mode_custom)
        }
    }

    fun getDescription(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.liveai_mode_standard_desc)
            MUSEUM -> context.getString(R.string.liveai_mode_museum_desc)
            BLIND -> context.getString(R.string.liveai_mode_blind_desc)
            READING -> context.getString(R.string.liveai_mode_reading_desc)
            TRANSLATE -> context.getString(R.string.liveai_mode_translate_desc)
            CUSTOM -> context.getString(R.string.liveai_mode_custom_desc)
        }
    }


    /**
     * Get the system prompt for this mode (excluding translate and custom, which need dynamic generation)
     */
    fun getSystemPrompt(context: Context): String {
        return when (this) {
            STANDARD -> context.getString(R.string.prompt_liveai_standard)
            MUSEUM -> context.getString(R.string.prompt_liveai_museum)
            BLIND -> context.getString(R.string.prompt_liveai_blind)
            READING -> context.getString(R.string.prompt_liveai_reading)
            TRANSLATE -> "" // Needs to be obtained through Manager (includes target language)
            CUSTOM -> "" // Needs to be obtained through Manager for custom content
        }
    }

    /**
     * Whether to automatically send images when user speaks
     */
    fun autoSendImageOnSpeech(): Boolean {
        return when (this) {
            STANDARD -> true  // Default mode: send image on voice trigger
            MUSEUM, BLIND, READING, TRANSLATE -> true  // These modes all need image viewing
            CUSTOM -> true  // Custom mode also supports images
        }
    }

    companion object {
        fun fromId(id: String): LiveAIMode {
            return entries.find { it.id == id } ?: STANDARD
        }
    }
}
