import SwiftUI
import AVFoundation
import Foundation

// MARK: - Production-Ready Network Manager
@MainActor
class NetworkManager: NSObject, ObservableObject {
    private var socketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectionTimer: Timer?
    private var heartbeatTimer: Timer?
    private var currentApiMode: Bool = true
    private var isConnecting: Bool = false
    private var lastConnectionAttempt: Date = Date.distantPast
    private var connectionHealthCheck: Timer?

    @Published var connected = false
    @Published var turkishResult = ""
    @Published var englishResult = ""
    @Published var processing = false
    @Published var connectionAttempts = 0
    @Published var connectionStatus = "Disconnected"
    @Published var lastActivity: Date = Date()
    
    // Optimized configuration for stability
    private let minReconnectInterval: TimeInterval = 30.0
    private let maxConnectionAttempts = 3
    private let connectionTimeout: TimeInterval = 60.0
    private let heartbeatInterval: TimeInterval = 30.0
    private let modelSwitchDelay: TimeInterval = 4.0
    private let connectionHealthInterval: TimeInterval = 90.0
    
    override init() {
        super.init()
        configureSession()
        setupAppLifecycleObservers()
        startConnectionHealthCheck()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
                reconnectionTimer?.invalidate()
                heartbeatTimer?.invalidate()
                connectionHealthCheck?.invalidate()
                socketTask?.cancel(with: .goingAway, reason: nil)
                socketTask = nil
                session?.invalidateAndCancel()
    }
    
    
    private func configureSession() {
        let config = URLSessionConfiguration.default
        
        // Production-optimized network settings
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = connectionTimeout
        config.timeoutIntervalForResource = connectionTimeout * 3
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        // Stability improvements
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpMaximumConnectionsPerHost = 1
        config.shouldUseExtendedBackgroundIdleMode = true
        config.networkServiceType = .responsiveData
        
        // Connection optimization headers
        config.httpAdditionalHeaders = [
            "Connection": "keep-alive",
            "Cache-Control": "no-cache"
        ]
        
        session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appWillEnterForeground() {
        Task { @MainActor in
            print("📱 App entered foreground")
            updateLastActivity()
            
            // Wait for app to stabilize
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            if !connected && !isConnecting {
                print("🔄 Reconnecting after foreground...")
                connectToServer(apiMode: currentApiMode)
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entered background")
        stopHeartbeat()
        updateConnectionStatus("Background Mode")
    }
    
    @objc private func appWillTerminate() {
        print("📱 App terminating - cleanup")
        Task { @MainActor in
            invalidateAllTimers()
            forceDisconnectSync()
        }
    }
    
    private func startConnectionHealthCheck() {
        connectionHealthCheck = Timer.scheduledTimer(withTimeInterval: connectionHealthInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() async {
        guard connected else { return }
        
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        
        if timeSinceLastActivity > connectionHealthInterval * 2 {
            print("⚠️ Connection stale, reconnecting...")
                        handleConnectionLoss()
        }
    }
    
    func connectToServer(apiMode: Bool = true) {
        guard !isConnecting else {
            print("⚠️ Connection already in progress")
            return
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastConnectionAttempt) >= minReconnectInterval else {
            print("⚠️ Too soon for reconnection, scheduling delayed attempt...")
            scheduleDelayedReconnection(apiMode: apiMode)
            return
        }
        
        guard connectionAttempts < maxConnectionAttempts else {
            print("⚠️ Max connection attempts reached")
            updateConnectionStatus("Max Attempts Reached")
            return
        }
        
        currentApiMode = apiMode
        lastConnectionAttempt = now
        isConnecting = true
        connectionAttempts += 1
        
        updateConnectionStatus("Connecting... (\(connectionAttempts)/\(maxConnectionAttempts))")
                updateLastActivity()
        
        
        // Single endpoint for stability
                let endpoint = "ws://localhost:8000" + (apiMode ? "/ws/translate-api" : "/ws/translate-local")
        
        guard let serverURL = URL(string: endpoint) else {
                    connectionFailed()
                    return
                }
                
                // Clean disconnect before new connection
                forceDisconnect()
                
                socketTask = session?.webSocketTask(with: serverURL)
                socketTask?.resume()
                startListening()
                
                // Longer timeout handling
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
                    
                    if !connected && isConnecting {
                        print("⏰ Connection timeout")
                        connectionFailed()
                        scheduleReconnection()
                    }
                }
    }
    
    private func connectToFirstAvailable(endpoints: [String], path: String) {
        guard !endpoints.isEmpty else {
            print("❌ All endpoints exhausted")
            connectionFailed()
            return
        }
        
        let endpoint = endpoints[0] + path
        print("🔌 Attempting: \(endpoint)")
        
        guard let serverURL = URL(string: endpoint) else {
            let remaining = Array(endpoints.dropFirst())
            connectToFirstAvailable(endpoints: remaining, path: path)
            return
        }
        
        forceDisconnect()
        
        socketTask = session?.webSocketTask(with: serverURL)
        socketTask?.resume()
        startListening()
        
        // Connection timeout with fallback
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
            
            if !connected && isConnecting {
                print("⏰ Timeout for \(endpoint)")
                
                let remaining = Array(endpoints.dropFirst())
                if !remaining.isEmpty {
                    print("🔄 Trying next endpoint...")
                    connectToFirstAvailable(endpoints: remaining, path: path)
                } else {
                    print("❌ All endpoints failed")
                    connectionFailed()
                    scheduleReconnection()
                }
            }
        }
    }
    
    private func scheduleDelayedReconnection(apiMode: Bool) {
        let delay = max(minReconnectInterval - Date().timeIntervalSince(lastConnectionAttempt), 2.0)
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            connectToServer(apiMode: apiMode)
        }
    }
    
    private func connectionFailed() {
        isConnecting = false
        stopHeartbeat()
        connected = false
        updateConnectionStatus("Connection Failed")
    }
    
    private func connectionSucceeded() {
        isConnecting = false
        connectionAttempts = 0
        stopReconnectionTimer()
        startHeartbeat()
        connected = true
        updateConnectionStatus("Connected")
        updateLastActivity()
        
        print("✅ Connection established successfully!")
    }
    
    func disconnectFromServer() {
        print("🔌 Manual disconnect")
        invalidateAllTimers()
        forceDisconnect()
        updateConnectionStatus("Disconnected")
    }
    
    private func forceDisconnect() {
        if let task = socketTask {
                    task.cancel(with: .goingAway, reason: nil)
                    socketTask = nil
                }
                isConnecting = false
                connected = false
                stopHeartbeat()
    }
    
    private func forceDisconnectSync() {
        reconnectionTimer?.invalidate()
        heartbeatTimer?.invalidate()
        connectionHealthCheck?.invalidate()
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
    }
    
    private func scheduleReconnection() {
        guard connectionAttempts < maxConnectionAttempts else {
            print("⚠️ Max reconnection attempts reached")
            updateConnectionStatus("Connection Failed")
            return
        }
        
        stopReconnectionTimer()
        
        // Progressive backoff with jitter
        let baseDelay = min(Double(connectionAttempts * connectionAttempts) * 15.0, 120.0)
        let jitter = Double.random(in: 0...5.0)
        let backoffDelay = baseDelay + jitter
        
        print("⏳ Reconnecting in \(Int(backoffDelay))s...")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
            
            if !connected && !isConnecting {
                print("🔄 Auto-reconnection attempt")
                connectToServer(apiMode: currentApiMode)
            }
        }
    }
    
    private func stopReconnectionTimer() {
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }
    
    private func startHeartbeat() {
        stopHeartbeat()
        
        print("💓 Starting heartbeat (interval: \(heartbeatInterval)s)")
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendHeartbeat()
            }
        }
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func invalidateAllTimers() {
        reconnectionTimer?.invalidate()
                reconnectionTimer = nil
                heartbeatTimer?.invalidate()
                heartbeatTimer = nil
                connectionHealthCheck?.invalidate()
                connectionHealthCheck = nil
    }
    
    private func sendHeartbeat() async {
        guard connected, let task = socketTask else {
            return
        }
        
        let heartbeatMessage = URLSessionWebSocketTask.Message.string("{\"type\":\"ping\"}")
        
        do {
            try await task.send(heartbeatMessage)
            updateLastActivity()
        } catch {
            print("💔 Heartbeat failed: \(error)")
            handleConnectionLoss()
        }
    }
    
    private func handleConnectionLoss() {
        connected = false
        isConnecting = false
        stopHeartbeat()
        updateConnectionStatus("Connection Lost")
        scheduleReconnection()
    }
    
    private func updateConnectionStatus(_ status: String) {
        connectionStatus = status
    }
    
    private func updateLastActivity() {
        lastActivity = Date()
    }
    
    func transmitAudio(_ data: Data) {
        guard connected && !processing else {
            print("❌ Cannot transmit - not ready")
            return
        }
        
        print("🎤 Transmitting audio: \(data.count) bytes")
        
        let encodedAudio = data.base64EncodedString()
        let payload: [String: Any] = [
            "type": "audio",
            "audio": encodedAudio,
            "timestamp": "\(Date().timeIntervalSince1970)"
        ]
        
        guard let jsonPayload = try? JSONSerialization.data(withJSONObject: payload),
              let jsonText = String(data: jsonPayload, encoding: .utf8) else {
            print("❌ Failed to serialize payload")
            return
        }
        
        let socketMessage = URLSessionWebSocketTask.Message.string(jsonText)
        
        Task { @MainActor in
            processing = true
            updateLastActivity()
            
            do {
                try await socketTask?.send(socketMessage)
                print("✅ Audio transmitted")
            } catch {
                print("❌ Transmission failed: \(error)")
                handleTransmissionError()
            }
        }
    }
    
    private func handleTransmissionError() {
        connected = false
        processing = false
        stopHeartbeat()
        updateConnectionStatus("Transmission Error")
        scheduleReconnection()
    }
    
    private func startListening() {
        guard let task = socketTask else { return }
        
        Task {
            do {
                let message = try await task.receive()
                
                await MainActor.run {
                    if case .string(let response) = message {
                        handleReceivedMessage(response)
                    }
                    
                    if connected {
                        startListening()
                    }
                }
            } catch {
                await MainActor.run {
                    handleReceptionError(error)
                }
            }
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        updateLastActivity()
        
        // Handle heartbeat responses
        if message.contains("\"type\":\"pong\"") || message.contains("\"type\":\"ping\"") {
            return
        }
        
        processResponse(message)
    }
    
    private func handleReceptionError(_ error: Error) {
        let nsError = error as NSError
        
        if nsError.code == NSURLErrorCancelled {
            return
        }
        
        print("❌ Reception error: \(error)")
        connected = false
        isConnecting = false
        stopHeartbeat()
        updateConnectionStatus("Reception Error")
        
        if nsError.code != NSURLErrorCancelled {
            scheduleReconnection()
        }
    }
    
    
    
    
    private func processResponse(_ response: String) {
        guard let responseData = response.data(using: .utf8),
                  let parsedResponse = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                processing = false
                return
            }
        
        // Handle errors
            if let error = parsedResponse["error"] as? String {
                print("❌ Server error: \(error)")
                processing = false
                turkishResult = ""
                englishResult = "Error: \(error)"
                updateLastActivity()
                return
            }
        
        let newTurkish = parsedResponse["turkish"] as? String ?? ""
        let newEnglish = parsedResponse["english"] as? String ?? ""
        
        if !newTurkish.isEmpty || !newEnglish.isEmpty {
            turkishResult = newTurkish
            englishResult = newEnglish
            updateLastActivity()
            
            print("✅ Translation received")
        }
        processing = false
    }
    
    func reconnect() {
        print("🔄 Manual reconnection")
        invalidateAllTimers()
        connectionAttempts = max(0, connectionAttempts - 2)
        lastConnectionAttempt = Date.distantPast
        connectToServer(apiMode: currentApiMode)
    }
    
    func resetConnection() {
        print("🔄 Connection reset")
        connectionAttempts = 0
        lastConnectionAttempt = Date.distantPast
        invalidateAllTimers()
        forceDisconnect()
        updateConnectionStatus("Reset")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            connectToServer(apiMode: currentApiMode)
        }
    }
    
    func switchModel(to newMode: Bool) {
        guard newMode != currentApiMode else { return }
        
        print("🔄 Switching to \(newMode ? "Cloud API" : "Local Engine")")
        
        if connected {
            disconnectFromServer()
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(modelSwitchDelay * 1_000_000_000))
                connectToServer(apiMode: newMode)
            }
        } else {
            currentApiMode = newMode
        }
    }
}

extension NetworkManager: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            print("✅ WebSocket opened")
            connectionSucceeded()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            print("❌ WebSocket closed - Code: \(closeCode.rawValue)")
            
            connected = false
            isConnecting = false
            stopHeartbeat()
            
            // Special handling for different close codes
            switch closeCode.rawValue {
            case 1001: // Going Away
                updateConnectionStatus("Server Going Away")
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 second delay
                if !connected {
                    scheduleReconnection()
                }
            case 1000: // Normal Closure
                updateConnectionStatus("Disconnected")
            default: // Unexpected closure
                updateConnectionStatus("Unexpected Disconnect")
                scheduleReconnection()
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            
            Task { @MainActor in
                if nsError.code != NSURLErrorCancelled {
                    print("❌ URLSession error: \(error)")
                    connected = false
                    isConnecting = false
                    stopHeartbeat()
                    updateConnectionStatus("Network Error")
                    scheduleReconnection()
                }
            }
        }
    }
}

// MARK: - Optimized Voice Recorder
@MainActor
class VoiceRecorder: NSObject, ObservableObject {
    private var recorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    private var meteringTimer: Timer?
    
    @Published var isRecording = false
    @Published var microphonePermission = false
    @Published var recordingLevel: Float = 0.0
    
    var recordingCompleted: ((Data?) -> Void)?
    
    override init() {
        super.init()
        initializeAudio()
    }
    
    private func initializeAudio() {
        audioSession = AVAudioSession.sharedInstance()
        
        Task { @MainActor in
            do {
                try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession?.setActive(true)
                
                let permission = await AVAudioApplication.requestRecordPermission()
                microphonePermission = permission
                
                print(permission ? "🎤 Microphone access granted" : "❌ Microphone access denied")
            } catch {
                print("❌ Audio setup failed: \(error)")
            }
        }
    }
    
    func beginRecording() {
        guard microphonePermission else {
            print("❌ No microphone permission")
            return
        }
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFile = documentPath.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            recorder = try AVAudioRecorder(url: audioFile, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            startMetering()
            
            print("🎤 Recording started")
        } catch {
            print("❌ Recording failed: \(error)")
        }
    }
    
    func endRecording() {
        recorder?.stop()
        isRecording = false
        recordingLevel = 0.0
        stopMetering()
        
        guard let recorder = recorder else {
            recordingCompleted?(nil)
            return
        }
        
        let audioFile = recorder.url
        
        Task {
            do {
                let data = try Data(contentsOf: audioFile)
                print("🎤 Recording completed: \(data.count) bytes")
                
                await MainActor.run {
                    recordingCompleted?(data)
                }
                
                try? FileManager.default.removeItem(at: audioFile)
            } catch {
                print("❌ Failed to read recording: \(error)")
                await MainActor.run {
                    recordingCompleted?(nil)
                }
            }
        }
    }
    
    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeteringLevels()
            }
        }
    }
    
    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }
    
    private func updateMeteringLevels() {
        guard isRecording, let recorder = recorder else { return }
        
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let normalizedLevel = powf(10.0, averagePower / 20.0)
        
        recordingLevel = min(max(normalizedLevel, 0.0), 1.0)
    }
}

// MARK: - Speech Synthesizer
@MainActor
class SpeechSynthesizer: NSObject, ObservableObject {
    private let voiceEngine = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        voiceEngine.delegate = self
    }
    
    func vocalize(_ content: String, locale: String = "en-US") {
        guard !content.isEmpty else { return }
        
        if voiceEngine.isSpeaking {
            voiceEngine.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        voiceEngine.speak(utterance)
        print("🔊 Speaking: \(content.prefix(50))...")
    }
    
    func silence() {
        voiceEngine.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}

// MARK: - Main Application View
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var voiceRecorder = VoiceRecorder()
    @StateObject private var speechSynthesizer = SpeechSynthesizer()
    
    @State private var useCloudModel = true
    @State private var autoPlayback = true
    @State private var recordingActive = false
    @State private var resultsVisible = false
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 0) {
                appHeader
                
                ScrollView {
                    VStack(spacing: 28) {
                        serverStatusIndicator
                        modelSelector
                        
                        if resultsVisible {
                            translationDisplay
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                        }
                        
                        speechSettings
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, 22)
                }
                
                Spacer()
                microphoneInterface
            }
        }
        .onAppear(perform: initializeApp)
        .onDisappear {
            networkManager.disconnectFromServer()
        }
        .onChange(of: networkManager.englishResult) { _, _ in
            handleTranslationUpdate()
        }
        .onChange(of: useCloudModel) { _, newValue in
            networkManager.switchModel(to: newValue)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - UI Components
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.08, green: 0.12, blue: 0.32).opacity(0.9),
                Color(red: 0.18, green: 0.08, blue: 0.28).opacity(0.7),
                Color(red: 0.03, green: 0.18, blue: 0.38).opacity(0.95)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var appHeader: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .symbolEffect(.pulse.byLayer)
                
                Text("Voice Translator")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Text("Hold to capture • Release to translate")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.top, 25)
        .padding(.bottom, 15)
        .padding(.horizontal, 22)
    }
    
    private var serverStatusIndicator: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    if !networkManager.connected {
                        Circle()
                            .fill(statusColor.opacity(0.3))
                            .frame(width: 18, height: 18)
                            .scaleEffect(1.8)
                            .opacity(0.6)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: networkManager.connected)
                    }
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                }
                .frame(width: 18, height: 18)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryStatusText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(statusColor)
                    
                    if !networkManager.connectionStatus.isEmpty {
                        Text(networkManager.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                if networkManager.connectionAttempts > 0 && !networkManager.connected {
                    Text("\(networkManager.connectionAttempts)/\(6)")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(.orange.opacity(0.2))
                        )
                }
            }
            
            if !networkManager.connected {
                HStack(spacing: 10) {
                    Button(action: {
                        networkManager.reconnect()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text("Retry")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.orange.opacity(0.8))
                        )
                    }
                    
                    if networkManager.connectionAttempts > 2 {
                        Button(action: {
                            networkManager.resetConnection()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption)
                                Text("Reset")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.red.opacity(0.8))
                            )
                        }
                    }
                    
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var modelSelector: some View {
        VStack(spacing: 14) {
            Text("Processing Engine")
                .font(.headline)
                .foregroundColor(.white)
            
            Picker("Engine", selection: $useCloudModel) {
                Label("Cloud API", systemImage: "cloud.fill").tag(true)
                Label("Local Engine", systemImage: "desktopcomputer").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .colorScheme(.dark)
            .disabled(!networkManager.connected)
        }
        .opacity(networkManager.connected ? 1.0 : 0.6)
        .animation(.easeInOut, value: networkManager.connected)
    }
    
    private var translationDisplay: some View {
        VStack(spacing: 20) {
            ResultCard(
                flag: "🇹🇷",
                language: "Turkish",
                content: networkManager.turkishResult,
                accentColor: Color(red: 0.9, green: 0.1, blue: 0.1)
            )
            
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                )
                .symbolEffect(.bounce.down, value: resultsVisible)
            
            ResultCard(
                flag: "🇺🇸",
                language: "English",
                content: networkManager.englishResult,
                accentColor: Color(red: 0.1, green: 0.4, blue: 0.9)
            )
        }
    }
    
    private var speechSettings: some View {
        HStack(spacing: 16) {
            Image(systemName: autoPlayback ? "speaker.wave.3.fill" : "speaker.slash.fill")
                .foregroundColor(autoPlayback ? .white : .gray)
                .font(.title3)
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), value: speechSynthesizer.isSpeaking)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Playback")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                if speechSynthesizer.isSpeaking {
                    Text("Speaking...")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.9))
                        .transition(.opacity)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $autoPlayback)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.1, green: 0.4, blue: 0.9)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    private var microphoneInterface: some View {
        VStack(spacing: 20) {
            if networkManager.processing {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.1)
                    
                    Text("Processing...")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .fontWeight(.medium)
                }
                .transition(.opacity.combined(with: .scale))
            }
            
            Button(action: {}) {
                ZStack {
                    // Outer recording ring
                    Circle()
                        .stroke(recordingActive ? .red : .white, lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .scaleEffect(recordingActive ? 1.2 : 1.0)
                        .opacity(recordingActive ? 0.8 : 1.0)
                    
                    // Dynamic audio level rings
                    if recordingActive {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(.red.opacity(0.4 - Double(index) * 0.1), lineWidth: 3)
                                .frame(width: 140 + CGFloat(index * 20), height: 140 + CGFloat(index * 20))
                                .scaleEffect(1.0 + Double(voiceRecorder.recordingLevel) * (1.0 + Double(index) * 0.3))
                                .opacity(0.7 - Double(index) * 0.2)
                                .animation(.easeInOut(duration: 0.1), value: voiceRecorder.recordingLevel)
                        }
                    }
                    
                    // Main button
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    recordingActive ? .red : Color(red: 0.1, green: 0.4, blue: 0.9),
                                    recordingActive ? .red.opacity(0.7) : Color(red: 0.05, green: 0.3, blue: 0.7)
                                ]),
                                center: .center,
                                startRadius: 5,
                                endRadius: 55
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(recordingActive ? 0.9 : 1.0)
                    
                    // Microphone icon
                    Image(systemName: recordingActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(recordingActive ? 1.4 : 1.0)
                        .symbolEffect(.bounce, value: recordingActive)
                }
            }
            .scaleEffect(recordingActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: recordingActive)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if canRecord && !recordingActive {
                            initiateRecording()
                        }
                    }
                    .onEnded { _ in
                        if recordingActive {
                            finalizeRecording()
                        }
                    }
            )
            .disabled(!canRecord)
            
            VStack(spacing: 8) {
                Text(statusText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .animation(.easeInOut, value: recordingActive)
                
                if !canRecord {
                    Text(helpText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 50)
    }
    
    // MARK: - Computed Properties
    
    private var canRecord: Bool {
        return networkManager.connected && !networkManager.processing && voiceRecorder.microphonePermission
    }
    
    private var statusColor: Color {
        switch networkManager.connectionStatus {
        case "Connected":
            return .green
        case "Connection Failed", "Max Attempts Reached", "Network Error", "Transmission Error":
            return .red
        case "Connecting...", "Background Mode", "Server Going Away":
            return .orange
        default:
            return .gray
        }
    }
    
    private var primaryStatusText: String {
        if networkManager.connected {
            return "Server Ready"
        } else {
            switch networkManager.connectionStatus {
            case "Connecting...":
                return "Connecting..."
            case "Connection Failed":
                return "Connection Failed"
            case "Max Attempts Reached":
                return "Unable to Connect"
            case "Network Error":
                return "Network Issue"
            case "Background Mode":
                return "Background Mode"
            case "Transmission Error":
                return "Transmission Failed"
            case "Server Going Away":
                return "Server Restarting"
            default:
                return "Disconnected"
            }
        }
    }
    
    private var statusText: String {
        if recordingActive {
            return "Release to Translate"
        } else if networkManager.processing {
            return "Processing Audio..."
        } else if !voiceRecorder.microphonePermission {
            return "Microphone Access Required"
        } else if !networkManager.connected {
            return "Waiting for Server..."
        } else {
            return "Hold to Record"
        }
    }
    
    private var helpText: String {
        if !voiceRecorder.microphonePermission {
            return "Go to Settings → Privacy & Security → Microphone"
        } else if !networkManager.connected {
            return "Check server connection and try again"
        } else {
            return ""
        }
    }
    
    // MARK: - Helper Functions
    
    private func initializeApp() {
        print("🚀 Initializing Voice Translator...")
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            networkManager.connectToServer(apiMode: useCloudModel)
        }
        
        voiceRecorder.recordingCompleted = { audioData in
            guard let data = audioData else {
                print("❌ No audio data received")
                return
            }
            networkManager.transmitAudio(data)
        }
    }
    
    private func handleTranslationUpdate() {
        if autoPlayback && !networkManager.englishResult.isEmpty {
            speechSynthesizer.vocalize(networkManager.englishResult)
        }
        
        if !networkManager.englishResult.isEmpty {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                resultsVisible = true
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            print("📱 App backgrounded")
            if recordingActive {
                finalizeRecording()
            }
        case .active:
            print("📱 App activated")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if !networkManager.connected && !networkManager.processing {
                    networkManager.reconnect()
                }
            }
        default:
            break
        }
    }
    
    private func initiateRecording() {
        guard canRecord else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            recordingActive = true
        }
        
        voiceRecorder.beginRecording()
        
        // Enhanced haptic feedback
        let feedback = UIImpactFeedbackGenerator(style: .heavy)
        feedback.impactOccurred()
        
        print("🎤 Recording started")
    }
    
    private func finalizeRecording() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            recordingActive = false
        }
        
        voiceRecorder.endRecording()
        
        // Success haptic feedback
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        
        print("🎤 Recording completed")
    }
}

// MARK: - Result Card Component
struct ResultCard: View {
    let flag: String
    let language: String
    let content: String
    let accentColor: Color
    
    @State private var showingCopyConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(flag)
                    .font(.title2)
                
                Text(language)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if !content.isEmpty && content != "Awaiting input..." {
                    Button(action: copyToClipboard) {
                        Image(systemName: showingCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(showingCopyConfirmation ? .green : .white.opacity(0.7))
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.1))
                            )
                    }
                    .transition(.scale)
                    .symbolEffect(.bounce, value: showingCopyConfirmation)
                }
            }
            
            Text(content.isEmpty ? "Awaiting input..." : content)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(content.isEmpty ? .white.opacity(0.6) : .white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 60)
                .lineLimit(nil)
                .animation(.easeInOut(duration: 0.3), value: content)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accentColor.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
        )
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = content
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingCopyConfirmation = true
        }
        
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingCopyConfirmation = false
            }
        }
    }
}

