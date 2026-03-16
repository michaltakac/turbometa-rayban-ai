package com.turbometa.rayban.managers

import android.content.Context
import android.content.SharedPreferences
import com.turbometa.rayban.R
import com.turbometa.rayban.models.QuickVisionMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Quick Vision Mode Manager
 * Quick vision mode manager - manages current mode, custom prompts, translation target language
 */
class QuickVisionModeManager private constructor(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "quick_vision_prefs"
        private const val KEY_MODE = "quick_vision_mode"
        private const val KEY_CUSTOM_PROMPT = "quick_vision_custom_prompt"
        private const val KEY_TRANSLATE_TARGET_LANGUAGE = "quick_vision_translate_target_language"

        @Volatile
        private var instance: QuickVisionModeManager? = null

        fun getInstance(context: Context): QuickVisionModeManager {
            return instance ?: synchronized(this) {
                instance ?: QuickVisionModeManager(context.applicationContext).also { instance = it }
            }
        }

        // Supported translation target languages
        val supportedLanguages: List<Pair<String, String>> = listOf(
            "zh-CN" to "Chinese",
            "en-US" to "English",
            "ja-JP" to "日本語",
            "ko-KR" to "한국어",
            "fr-FR" to "Français",
            "de-DE" to "Deutsch",
            "es-ES" to "Español",
            "it-IT" to "Italiano",
            "pt-BR" to "Português",
            "ru-RU" to "Русский"
        )
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Current mode
    private val _currentMode = MutableStateFlow(loadMode())
    val currentMode: StateFlow<QuickVisionMode> = _currentMode.asStateFlow()

    // Custom prompt
    private val _customPrompt = MutableStateFlow(loadCustomPrompt())
    val customPrompt: StateFlow<String> = _customPrompt.asStateFlow()

    // Translation target language
    private val _translateTargetLanguage = MutableStateFlow(loadTranslateTargetLanguage())
    val translateTargetLanguage: StateFlow<String> = _translateTargetLanguage.asStateFlow()

    private fun loadMode(): QuickVisionMode {
        val modeId = prefs.getString(KEY_MODE, QuickVisionMode.STANDARD.id) ?: QuickVisionMode.STANDARD.id
        return QuickVisionMode.fromId(modeId)
    }

    private fun loadCustomPrompt(): String {
        return prefs.getString(KEY_CUSTOM_PROMPT, context.getString(R.string.quickvision_custom_default)) ?: ""
    }

    private fun loadTranslateTargetLanguage(): String {
        return prefs.getString(KEY_TRANSLATE_TARGET_LANGUAGE, "zh-CN") ?: "zh-CN"
    }

    fun setMode(mode: QuickVisionMode) {
        _currentMode.value = mode
        prefs.edit().putString(KEY_MODE, mode.id).apply()
    }

    fun setCustomPrompt(prompt: String) {
        _customPrompt.value = prompt
        prefs.edit().putString(KEY_CUSTOM_PROMPT, prompt).apply()
    }

    fun setTranslateTargetLanguage(languageCode: String) {
        _translateTargetLanguage.value = languageCode
        prefs.edit().putString(KEY_TRANSLATE_TARGET_LANGUAGE, languageCode).apply()
    }

    /**
     * Get the full prompt for the current mode
     */
    fun getPrompt(): String {
        return when (_currentMode.value) {
            QuickVisionMode.CUSTOM -> _customPrompt.value
            QuickVisionMode.TRANSLATE -> getTranslatePrompt()
            else -> _currentMode.value.getPrompt(context)
        }
    }

    /**
     * Get the prompt for a specified mode
     */
    fun getPrompt(mode: QuickVisionMode): String {
        return when (mode) {
            QuickVisionMode.CUSTOM -> _customPrompt.value
            QuickVisionMode.TRANSLATE -> getTranslatePrompt()
            else -> mode.getPrompt(context)
        }
    }

    /**
     * Get the prompt for translation mode (includes target language)
     */
    private fun getTranslatePrompt(): String {
        val targetLanguageName = supportedLanguages.find { it.first == _translateTargetLanguage.value }?.second ?: "Chinese"
        val basePrompt = context.getString(R.string.prompt_quickvision_translate)
        return basePrompt.replace("{LANGUAGE}", targetLanguageName)
    }

    /**
     * Get target language name
     */
    fun getTranslateTargetLanguageName(): String {
        return supportedLanguages.find { it.first == _translateTargetLanguage.value }?.second ?: "Chinese"
    }
}
