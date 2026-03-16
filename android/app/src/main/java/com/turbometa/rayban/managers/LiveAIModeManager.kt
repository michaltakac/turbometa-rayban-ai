package com.turbometa.rayban.managers

import android.content.Context
import android.content.SharedPreferences
import com.turbometa.rayban.R
import com.turbometa.rayban.models.LiveAIMode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Live AI Mode Manager
 * Real-time conversation mode manager - manages current mode, custom prompts, translation target language
 */
class LiveAIModeManager private constructor(private val context: Context) {

    companion object {
        private const val PREFS_NAME = "live_ai_prefs"
        private const val KEY_MODE = "live_ai_mode"
        private const val KEY_CUSTOM_PROMPT = "live_ai_custom_prompt"
        private const val KEY_TRANSLATE_TARGET_LANGUAGE = "live_ai_translate_target_language"

        @Volatile
        private var instance: LiveAIModeManager? = null

        fun getInstance(context: Context): LiveAIModeManager {
            return instance ?: synchronized(this) {
                instance ?: LiveAIModeManager(context.applicationContext).also { instance = it }
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
    val currentMode: StateFlow<LiveAIMode> = _currentMode.asStateFlow()

    // Custom prompt
    private val _customPrompt = MutableStateFlow(loadCustomPrompt())
    val customPrompt: StateFlow<String> = _customPrompt.asStateFlow()

    // Translation target language
    private val _translateTargetLanguage = MutableStateFlow(loadTranslateTargetLanguage())
    val translateTargetLanguage: StateFlow<String> = _translateTargetLanguage.asStateFlow()

    private fun loadMode(): LiveAIMode {
        val modeId = prefs.getString(KEY_MODE, LiveAIMode.STANDARD.id) ?: LiveAIMode.STANDARD.id
        return LiveAIMode.fromId(modeId)
    }

    private fun loadCustomPrompt(): String {
        return prefs.getString(KEY_CUSTOM_PROMPT, context.getString(R.string.liveai_custom_default)) ?: ""
    }

    private fun loadTranslateTargetLanguage(): String {
        return prefs.getString(KEY_TRANSLATE_TARGET_LANGUAGE, "zh-CN") ?: "zh-CN"
    }

    fun setMode(mode: LiveAIMode) {
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
     * Get the full system prompt for the current mode
     */
    fun getSystemPrompt(): String {
        return when (_currentMode.value) {
            LiveAIMode.CUSTOM -> _customPrompt.value
            LiveAIMode.TRANSLATE -> getTranslatePrompt()
            else -> _currentMode.value.getSystemPrompt(context)
        }
    }

    /**
     * Get the system prompt for a specified mode
     */
    fun getSystemPrompt(mode: LiveAIMode): String {
        return when (mode) {
            LiveAIMode.CUSTOM -> _customPrompt.value
            LiveAIMode.TRANSLATE -> getTranslatePrompt()
            else -> mode.getSystemPrompt(context)
        }
    }

    /**
     * Get the prompt for translation mode (includes target language)
     */
    private fun getTranslatePrompt(): String {
        val targetLanguageName = supportedLanguages.find { it.first == _translateTargetLanguage.value }?.second ?: "Chinese"
        val basePrompt = context.getString(R.string.prompt_liveai_translate)
        return basePrompt.replace("{LANGUAGE}", targetLanguageName)
    }

    /**
     * Get target language name
     */
    fun getTranslateTargetLanguageName(): String {
        return supportedLanguages.find { it.first == _translateTargetLanguage.value }?.second ?: "Chinese"
    }

    /**
     * Whether to automatically send images when speech is triggered
     */
    fun autoSendImageOnSpeech(): Boolean {
        return _currentMode.value.autoSendImageOnSpeech()
    }
}
