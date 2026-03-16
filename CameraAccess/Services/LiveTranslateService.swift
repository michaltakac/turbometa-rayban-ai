/*
 * Live Translate WebSocket Service
 * Real-time translation service
 * Supports Alibaba (qwen3-livetranslate-flash-realtime) and Google Gemini Live
 */

import Foundation
import UIKit
import AVFoundation

// MARK: - Service Class

class LiveTranslateService: NSObject {

    // WebSocket
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Configuration
    private let apiKey: String
    private let provider: LiveAIProvider

    // Alibaba config
    private let alibabaModel = "qwen3-livetranslate-flash-realtime"
    private var alibabaBaseURL: String {
        return APIProviderManager.staticLiveAIWebsocketURL
    }

    // Gemini config
    private let geminiModel = "gemini-2.5-flash-native-audio-preview-12-2025"
    private let geminiBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    private var isGeminiSessionConfigured = false

    // Audio Engine (for recording)
    private var audioEngine: AVAudioEngine?

    // Audio Playback Engine (separate engine for playback)
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)

    // Audio buffer management
    private var audioBuffer = Data()
    private var isCollectingAudio = false
    private var audioChunkCount = 0
    private let minChunksBeforePlay = 2
    private var hasStartedPlaying = false
    private var isPlaybackEngineRunning = false

    // Translation settings
    private var sourceLanguage: TranslateLanguage = .en
    private var targetLanguage: TranslateLanguage = .zh
    private var voice: TranslateVoice = .cherry
    private var audioOutputEnabled = true

    // Audio resampling
    private var audioConverter: AVAudioConverter?
    private var recordConverter: AVAudioConverter?
    private let targetSampleRate: Double = 16000  // API expects 16kHz
    private let recordTargetFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)

    // Callbacks
    var onConnected: (() -> Void)?
    var onTranslationText: ((String) -> Void)?    // Translation result text
    var onTranslationDelta: ((String) -> Void)?   // Incremental translation text
    var onAudioDelta: ((Data) -> Void)?
    var onAudioDone: (() -> Void)?
    var onError: ((String) -> Void)?

    // State
    private var isRecording = false
    private var eventIdCounter = 0
    private var hasAudioBeenSent = false

    // Image sending
    private var lastImageSendTime: Date?
    private let imageInterval: TimeInterval = 0.5

    init(apiKey: String) {
        self.apiKey = apiKey
        self.provider = APIProviderManager.staticLiveAIProvider
        super.init()
        setupAudioEngine()
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        setupPlaybackEngine()
    }

    private func setupPlaybackEngine() {
        playbackEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let playbackEngine = playbackEngine,
              let playerNode = playerNode,
              let playbackFormat = playbackFormat else {
            print("❌ [Translate] Failed to initialize playback engine")
            return
        }

        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: playbackFormat)
        playbackEngine.prepare()

        print("✅ [Translate] Playback engine initialized: Float32 @ 24kHz")
    }

    private func configureAudioSession(usePhoneMic: Bool = false) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if usePhoneMic {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            } else {
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            }
            try audioSession.setActive(true)
        } catch {
            print("⚠️ [Translate] Audio session configuration failed: \(error)")
        }
    }

    private func startPlaybackEngine() {
        guard let playbackEngine = playbackEngine, !isPlaybackEngineRunning else { return }

        do {
            try playbackEngine.start()
            isPlaybackEngineRunning = true
            print("▶️ [Translate] Playback engine started")
        } catch {
            print("❌ [Translate] Failed to start playback engine: \(error)")
        }
    }

    private func stopPlaybackEngine() {
        guard let playbackEngine = playbackEngine, isPlaybackEngineRunning else { return }

        playerNode?.stop()
        playerNode?.reset()
        playbackEngine.stop()
        isPlaybackEngineRunning = false
        print("⏹️ [Translate] Playback engine stopped")
    }

    // MARK: - WebSocket Connection

    func connect() {
        switch provider {
        case .alibaba:
            connectAlibaba()
        case .google:
            connectGemini()
        }
    }

    private func connectAlibaba() {
        let urlString = "\(alibabaBaseURL)?model=\(alibabaModel)"
        print("🔌 [Translate] Connecting to Alibaba WebSocket: \(urlString)")

        guard let url = URL(string: urlString) else {
            onError?("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.configureAlibabaSession()
        }
    }

    private func connectGemini() {
        let urlString = "\(geminiBaseURL)?key=\(apiKey)"
        print("🔌 [Translate] Connecting to Gemini WebSocket")

        guard let url = URL(string: urlString) else {
            onError?("Invalid URL")
            return
        }

        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        receiveMessage()
    }

    func disconnect() {
        print("🔌 [Translate] Disconnecting WebSocket")
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        stopRecording()
        stopPlaybackEngine()
        isGeminiSessionConfigured = false
    }

    // MARK: - Configuration

    func updateSettings(
        sourceLanguage: TranslateLanguage,
        targetLanguage: TranslateLanguage,
        voice: TranslateVoice,
        audioEnabled: Bool
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.voice = voice
        self.audioOutputEnabled = audioEnabled

        if webSocket != nil {
            switch provider {
            case .alibaba:
                configureAlibabaSession()
            case .google:
                break // Gemini reconfigures on connect
            }
        }
    }

    // MARK: - Alibaba Session Config

    private func configureAlibabaSession() {
        var modalities: [String] = ["text"]
        if audioOutputEnabled {
            modalities.append("audio")
        }

        let sessionConfig: [String: Any] = [
            "event_id": generateEventId(),
            "type": TranslateClientEvent.sessionUpdate.rawValue,
            "session": [
                "modalities": modalities,
                "voice": voice.rawValue,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm24",
                "input_audio_transcription": [
                    "language": sourceLanguage.rawValue
                ],
                "translation": [
                    "language": targetLanguage.rawValue
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ]
            ]
        ]

        sendEvent(sessionConfig)
        print("📤 [Translate] Alibaba session configured: \(sourceLanguage.rawValue) -> \(targetLanguage.rawValue)")
    }

    // MARK: - Gemini Session Config

    private func configureGeminiSession() {
        guard !isGeminiSessionConfigured else { return }

        let sourceName = sourceLanguage.displayName
        let targetName = targetLanguage.displayName

        let instructions = """
        You are a real-time translator. Listen to the user's speech and translate it.
        Source language: \(sourceName) (\(sourceLanguage.rawValue))
        Target language: \(targetName) (\(targetLanguage.rawValue))

        Rules:
        1. Translate the user's speech into \(targetName) immediately
        2. Respond ONLY with the translation, no explanations
        3. Keep translations natural and conversational
        4. If the user speaks in \(targetName), translate to \(sourceName) instead
        5. Speak your translations out loud in \(targetName)
        """

        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/\(geminiModel)",
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": "Aoede"
                            ]
                        ]
                    ]
                ],
                "system_instruction": [
                    "parts": [
                        ["text": instructions]
                    ]
                ]
            ]
        ]

        sendJSON(setupMessage)
        print("📤 [Translate] Gemini session configured: \(sourceLanguage.rawValue) -> \(targetLanguage.rawValue)")
    }

    // MARK: - Audio Recording

    func startRecording(usePhoneMic: Bool = false) {
        guard !isRecording else { return }

        do {
            print("🎤 [Translate] Starting recording, using \(usePhoneMic ? "iPhone" : "Bluetooth") microphone")

            if let engine = audioEngine, engine.isRunning {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }

            configureAudioSession(usePhoneMic: usePhoneMic)

            if let inputRoute = AVAudioSession.sharedInstance().currentRoute.inputs.first {
                print("🎙️ [Translate] Current input device: \(inputRoute.portName) (\(inputRoute.portType.rawValue))")
            }

            guard let engine = audioEngine else {
                print("❌ [Translate] Audio engine not initialized")
                return
            }

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Set up converter for Gemini (needs 16kHz PCM16)
            if provider == .google, let recordTargetFormat {
                recordConverter = AVAudioConverter(from: inputFormat, to: recordTargetFormat)
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer)
            }

            engine.prepare()
            try engine.start()

            isRecording = true
            hasAudioBeenSent = false
            print("✅ [Translate] Recording started")

        } catch {
            print("❌ [Translate] Failed to start recording: \(error.localizedDescription)")
            onError?("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        print("🛑 [Translate] Stopping recording")
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false
        hasAudioBeenSent = false
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        switch provider {
        case .alibaba:
            processAudioBufferAlibaba(buffer)
        case .google:
            processAudioBufferGemini(buffer, inputFormat: buffer.format)
        }
    }

    private func processAudioBufferAlibaba(_ buffer: AVAudioPCMBuffer) {
        let inputSampleRate = buffer.format.sampleRate

        if inputSampleRate != targetSampleRate {
            guard let resampledBuffer = resampleBuffer(buffer) else { return }
            sendBufferAsPCM16Alibaba(resampledBuffer)
        } else {
            sendBufferAsPCM16Alibaba(buffer)
        }
    }

    private func processAudioBufferGemini(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let recordConverter, let recordTargetFormat else { return }

        let ratio = recordTargetFormat.sampleRate / inputFormat.sampleRate
        let targetFrameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))

        guard let converted = AVAudioPCMBuffer(pcmFormat: recordTargetFormat, frameCapacity: max(1, targetFrameCapacity)) else {
            return
        }

        var hasProvidedInput = false
        var error: NSError?

        let status = recordConverter.convert(to: converted, error: &error) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, status != .error else { return }
        guard let floatChannelData = converted.floatChannelData else { return }

        let frameLength = Int(converted.frameLength)
        let channel = floatChannelData.pointee

        var int16Data = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = channel[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clampedSample * 32767.0)
        }

        let data = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
        let base64Audio = data.base64EncodedString()

        sendGeminiRealtimeInput(audioData: base64Audio)

        if !hasAudioBeenSent {
            hasAudioBeenSent = true
            print("✅ [Translate] First audio sent to Gemini")
        }
    }

    private func resampleBuffer(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inputFormat = inputBuffer.format
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1) else {
            return nil
        }

        if audioConverter == nil || audioConverter?.inputFormat != inputFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        guard let converter = audioConverter else { return nil }

        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("❌ [Translate] Resampling failed: \(error.localizedDescription)")
            return nil
        }

        return outputBuffer
    }

    private func sendBufferAsPCM16Alibaba(_ buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channel = floatChannelData.pointee

        var int16Data = [Int16](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let sample = channel[i]
            let clampedSample = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clampedSample * 32767.0)
        }

        let data = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
        let base64Audio = data.base64EncodedString()

        sendAlibabaAudioAppend(base64Audio)
    }

    // MARK: - Image Sending

    func sendImageFrame(_ image: UIImage) {
        let now = Date()
        if let lastTime = lastImageSendTime, now.timeIntervalSince(lastTime) < imageInterval {
            return
        }
        lastImageSendTime = now

        guard let imageData = image.jpegData(compressionQuality: 0.6) else { return }
        guard imageData.count <= 500 * 1024 else { return }

        let base64Image = imageData.base64EncodedString()

        switch provider {
        case .alibaba:
            let event: [String: Any] = [
                "event_id": generateEventId(),
                "type": TranslateClientEvent.inputImageBufferAppend.rawValue,
                "image": base64Image
            ]
            sendEvent(event)
        case .google:
            let message: [String: Any] = [
                "realtimeInput": [
                    "video": [
                        "data": base64Image,
                        "mimeType": "image/jpeg"
                    ]
                ]
            ]
            sendJSON(message)
        }
    }

    // MARK: - Send Events (Alibaba)

    private func sendEvent(_ event: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket?.send(message) { error in
            if let error = error {
                print("❌ [Translate] Failed to send event: \(error.localizedDescription)")
                self.onError?("Send error: \(error.localizedDescription)")
            }
        }
    }

    private var audioSendCount = 0

    private func sendAlibabaAudioAppend(_ base64Audio: String) {
        audioSendCount += 1
        if audioSendCount == 1 || audioSendCount % 50 == 0 {
            print("🎵 [Translate] Sending audio chunk #\(audioSendCount)")
        }

        let event: [String: Any] = [
            "event_id": generateEventId(),
            "type": TranslateClientEvent.inputAudioBufferAppend.rawValue,
            "audio": base64Audio
        ]
        sendEvent(event)
    }

    // MARK: - Send Events (Gemini)

    private func sendJSON(_ json: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocket?.send(message) { error in
            if let error = error {
                print("❌ [Translate] Gemini send failed: \(error.localizedDescription)")
                self.onError?("Send error: \(error.localizedDescription)")
            }
        }
    }

    private func sendGeminiRealtimeInput(audioData: String) {
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": audioData,
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
        sendJSON(message)
    }

    // MARK: - Receive Messages

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure(let error):
                print("❌ [Translate] Failed to receive message: \(error.localizedDescription)")
                self?.onError?("Receive error: \(error.localizedDescription)")
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            switch provider {
            case .alibaba:
                handleAlibabaServerEvent(text)
            case .google:
                handleGeminiServerEvent(text)
            }
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                switch provider {
                case .alibaba:
                    handleAlibabaServerEvent(text)
                case .google:
                    handleGeminiServerEvent(text)
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Alibaba Server Events

    private func handleAlibabaServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case TranslateServerEvent.sessionCreated.rawValue,
                 TranslateServerEvent.sessionUpdated.rawValue:
                print("✅ [Translate] Alibaba session established")
                self.onConnected?()

            case TranslateServerEvent.responseAudioTranscriptText.rawValue:
                if let delta = json["delta"] as? String {
                    self.onTranslationDelta?(delta)
                }

            case TranslateServerEvent.responseAudioTranscriptDone.rawValue:
                if let text = json["text"] as? String {
                    self.onTranslationText?(text)
                }

            case TranslateServerEvent.responseTextDone.rawValue:
                if let text = json["text"] as? String {
                    self.onTranslationText?(text)
                }

            case TranslateServerEvent.responseAudioDelta.rawValue:
                if let base64Audio = json["delta"] as? String,
                   let audioData = Data(base64Encoded: base64Audio) {
                    self.onAudioDelta?(audioData)
                    self.handleAudioChunk(audioData)
                }

            case TranslateServerEvent.responseAudioDone.rawValue:
                self.finishAudioPlayback()

            case TranslateServerEvent.error.rawValue:
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ [Translate] Server error: \(message)")
                    self.onError?(message)
                }

            default:
                break
            }
        }
    }

    // MARK: - Gemini Server Events

    private func handleGeminiServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        DispatchQueue.main.async {
            // Setup complete
            if json["setupComplete"] != nil {
                print("✅ [Translate] Gemini session configured")
                self.isGeminiSessionConfigured = true
                self.onConnected?()
                return
            }

            // Server content (audio/text responses)
            if let serverContent = json["serverContent"] as? [String: Any] {
                self.handleGeminiServerContent(serverContent)
                return
            }

            // Errors
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                print("❌ [Translate] Gemini error: \(message)")
                self.onError?(message)
                return
            }
        }
    }

    private func handleGeminiServerContent(_ content: [String: Any]) {
        // Model turn - AI translation response
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                // Text translation
                if let text = part["text"] as? String {
                    onTranslationDelta?(text)
                }

                // Audio translation
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   mimeType.contains("audio"),
                   let base64Audio = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64Audio) {
                    onAudioDelta?(audioData)
                    handleAudioChunk(audioData)
                }
            }
        }

        // Turn complete
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            finishAudioPlayback()
            // Emit the accumulated streaming translation as final
            onTranslationText?("")
        }

        // Interrupted
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            stopPlaybackEngine()
            setupPlaybackEngine()
        }

        // Output transcription (AI spoken text)
        if let outputTranscription = content["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            onTranslationDelta?(text)
        }
    }

    // MARK: - Audio Playback

    private func handleAudioChunk(_ audioData: Data) {
        if !isCollectingAudio {
            isCollectingAudio = true
            audioBuffer = Data()
            audioChunkCount = 0
            hasStartedPlaying = false

            if isPlaybackEngineRunning {
                stopPlaybackEngine()
                setupPlaybackEngine()
                startPlaybackEngine()
                playerNode?.play()
            }
        }

        audioChunkCount += 1

        if !hasStartedPlaying {
            audioBuffer.append(audioData)
            if audioChunkCount >= minChunksBeforePlay {
                hasStartedPlaying = true
                playAudio(audioBuffer)
                audioBuffer = Data()
            }
        } else {
            playAudio(audioData)
        }
    }

    private func finishAudioPlayback() {
        isCollectingAudio = false

        if !audioBuffer.isEmpty {
            playAudio(audioBuffer)
            audioBuffer = Data()
        }

        audioChunkCount = 0
        hasStartedPlaying = false
        onAudioDone?()
    }

    private func playAudio(_ audioData: Data) {
        guard let playerNode = playerNode,
              let playbackFormat = playbackFormat else { return }

        if !isPlaybackEngineRunning {
            startPlaybackEngine()
            playerNode.play()
        } else if !playerNode.isPlaying {
            playerNode.play()
        }

        guard let pcmBuffer = createPCMBuffer(from: audioData, format: playbackFormat) else { return }
        playerNode.scheduleBuffer(pcmBuffer)
    }

    private func createPCMBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = data.count / 2
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channelData = buffer.floatChannelData else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }
            let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
            let floatData = channelData[0]
            for i in 0..<frameCount {
                floatData[i] = Float(int16Pointer[i]) / 32768.0
            }
        }

        return buffer
    }

    // MARK: - Helpers

    private func generateEventId() -> String {
        eventIdCounter += 1
        return "translate_\(eventIdCounter)_\(UUID().uuidString.prefix(8))"
    }
}

// MARK: - URLSessionWebSocketDelegate

extension LiveTranslateService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ [Translate] WebSocket connection established")
        if provider == .google {
            DispatchQueue.main.async {
                self.configureGeminiSession()
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
        print("🔌 [Translate] WebSocket disconnected, closeCode: \(closeCode.rawValue), reason: \(reasonString)")
    }
}
