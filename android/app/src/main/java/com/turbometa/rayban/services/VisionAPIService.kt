package com.turbometa.rayban.services

import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.turbometa.rayban.managers.AlibabaEndpoint
import com.turbometa.rayban.managers.APIProvider
import com.turbometa.rayban.managers.APIProviderManager
import com.turbometa.rayban.managers.QuickVisionModeManager
import com.turbometa.rayban.utils.APIKeyManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

/**
 * Vision API Service
 * Supports multiple providers: Alibaba Cloud Dashscope (Beijing/Singapore), OpenRouter
 * 1:1 port from iOS VisionAPIConfig + QuickVisionService
 */
class VisionAPIService(
    private val apiKeyManager: APIKeyManager,
    private val providerManager: APIProviderManager,
    private val context: Context? = null
) {
    companion object {
        private const val TAG = "VisionAPIService"

        // Provider-specific URLs
        const val ALIBABA_BEIJING_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        const val ALIBABA_SINGAPORE_URL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        const val OPENROUTER_URL = "https://openrouter.ai/api/v1"

        // Default Models
        const val DEFAULT_ALIBABA_MODEL = "qwen-vl-plus"
        const val DEFAULT_OPENROUTER_MODEL = "qwen/qwen-vl-plus"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()

    // MARK: - Configuration

    private val currentProvider: APIProvider
        get() = providerManager.currentProvider.value

    private val alibabaEndpoint: AlibabaEndpoint
        get() = providerManager.alibabaEndpoint.value

    private val baseURL: String
        get() = when (currentProvider) {
            APIProvider.ALIBABA -> when (alibabaEndpoint) {
                AlibabaEndpoint.BEIJING -> ALIBABA_BEIJING_URL
                AlibabaEndpoint.SINGAPORE -> ALIBABA_SINGAPORE_URL
            }
            APIProvider.OPENROUTER -> OPENROUTER_URL
        }

    private val apiKey: String?
        get() = when (currentProvider) {
            APIProvider.ALIBABA -> apiKeyManager.getAPIKey(APIProvider.ALIBABA, alibabaEndpoint)
            APIProvider.OPENROUTER -> apiKeyManager.getAPIKey(APIProvider.OPENROUTER)
        }

    private val model: String
        get() = providerManager.selectedModel.value

    // MARK: - Analyze Image

    suspend fun analyzeImage(image: Bitmap, prompt: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val key = apiKey
            if (key.isNullOrBlank()) {
                return@withContext Result.failure(VisionAPIError.NoAPIKey)
            }

            Log.d(TAG, "Analyzing image with provider: $currentProvider, model: $model")

            val base64Image = encodeImageToBase64(image)
            val requestBody = buildRequestBody(base64Image, prompt)
            val url = "$baseURL/chat/completions"

            val requestBuilder = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $key")
                .addHeader("Content-Type", "application/json")

            // Add OpenRouter-specific headers
            if (currentProvider == APIProvider.OPENROUTER) {
                requestBuilder.addHeader("HTTP-Referer", "https://turbometa.app")
                requestBuilder.addHeader("X-Title", "TurboMeta")
            }

            val request = requestBuilder
                .post(requestBody.toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            if (!response.isSuccessful) {
                Log.e(TAG, "API Error: ${response.code} - $responseBody")
                return@withContext Result.failure(VisionAPIError.APIError("API Error: ${response.code} - $responseBody"))
            }

            if (responseBody.isNullOrEmpty()) {
                return@withContext Result.failure(VisionAPIError.EmptyResponse)
            }

            val result = parseResponse(responseBody)
            if (result.isNullOrEmpty()) {
                return@withContext Result.failure(VisionAPIError.InvalidResponse)
            }

            Log.d(TAG, "Analysis successful")
            Result.success(result)
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing image: ${e.message}")
            Result.failure(e)
        }
    }

    // MARK: - Quick Vision (for background recognition)
    // Uses QuickVisionModeManager to get the prompt based on selected mode

    suspend fun quickVision(image: Bitmap, language: String = "zh-CN"): Result<String> {
        // Use mode manager if context is available, otherwise fall back to language-based prompt
        val prompt = context?.let {
            val modeManager = QuickVisionModeManager.getInstance(it)
            val currentMode = modeManager.currentMode.value
            val modePrompt = modeManager.getPrompt()
            Log.d(TAG, "QuickVision using mode: ${currentMode.id}, prompt length: ${modePrompt.length}")
            Log.d(TAG, "QuickVision prompt: ${modePrompt.take(100)}...")
            modePrompt
        } ?: getQuickVisionPrompt(language)

        return analyzeImage(image, prompt)
    }

    /**
     * Get localized Quick Vision prompt matching iOS implementation
     */
    private fun getQuickVisionPrompt(language: String): String {
        return when (language) {
            "zh-CN" -> """
                You are a smart glasses AI assistant. Please describe the image content concisely in Chinese, suitable for voice announcement.

                Requirements:
                1. Describe the main content in 1-2 sentences
                2. Use natural, conversational language
                3. Don't use too many punctuation marks
                4. Keep the total under 50 characters
                5. Describe directly, don't say "in the image" or "I see"
            """.trimIndent()
            "en-US" -> """
                You are a smart glasses AI assistant. Please describe the image content concisely, suitable for voice announcement.

                Requirements:
                1. Describe the main content in 1-2 sentences
                2. Use natural, conversational language
                3. Don't use too many punctuation marks
                4. Keep the total under 50 words
                5. Describe directly, don't say "in the image" or "I see"
            """.trimIndent()
            "ja-JP" -> """
                You are a smart glasses AI assistant. Please describe the image content concisely in Japanese, suitable for voice announcement.

                Requirements:
                1. Describe the main content in 1-2 sentences
                2. Use natural, conversational language
                3. Don't use too many punctuation marks
                4. Keep the total under 50 characters
                5. Describe directly, don't say "in the image" or "I see"
            """.trimIndent()
            "ko-KR" -> """
                You are a smart glasses AI assistant. Please describe the image content concisely in Korean, suitable for voice announcement.

                Requirements:
                1. Describe the main content in 1-2 sentences
                2. Use natural, conversational language
                3. Don't use too many punctuation marks
                4. Keep the total under 50 characters
                5. Describe directly, don't say "in the image" or "I see"
            """.trimIndent()
            else -> getQuickVisionPrompt("en-US")
        }
    }

    // MARK: - Private Helpers

    private fun encodeImageToBase64(bitmap: Bitmap): String {
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, outputStream)
        val bytes = outputStream.toByteArray()
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    private fun buildRequestBody(base64Image: String, prompt: String): String {
        val messages = listOf(
            mapOf(
                "role" to "user",
                "content" to listOf(
                    mapOf(
                        "type" to "image_url",
                        "image_url" to mapOf(
                            "url" to "data:image/jpeg;base64,$base64Image"
                        )
                    ),
                    mapOf(
                        "type" to "text",
                        "text" to prompt
                    )
                )
            )
        )

        val request = mapOf(
            "model" to model,
            "messages" to messages,
            "max_tokens" to 2000
        )

        return gson.toJson(request)
    }

    private fun parseResponse(responseBody: String): String? {
        return try {
            val json = gson.fromJson(responseBody, JsonObject::class.java)
            val choices = json.getAsJsonArray("choices")
            if (choices != null && choices.size() > 0) {
                val message = choices[0].asJsonObject.getAsJsonObject("message")
                message?.get("content")?.asString
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing response: ${e.message}")
            null
        }
    }
}

sealed class VisionAPIError : Exception() {
    object InvalidImage : VisionAPIError()
    object EmptyResponse : VisionAPIError()
    object InvalidResponse : VisionAPIError()
    object NoAPIKey : VisionAPIError()
    data class APIError(override val message: String) : VisionAPIError()
}
