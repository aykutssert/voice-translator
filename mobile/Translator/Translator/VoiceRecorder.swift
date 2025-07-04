import SwiftUI
import AVFoundation
import Foundation

// MARK: - Voice Recorder (Optimized for Instant Response)
@MainActor
class VoiceRecorder: NSObject, ObservableObject {
    private var recorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var minimumRecordingDuration: TimeInterval = 0.5
    private var maximumRecordingDuration: TimeInterval = 120.0 // 2 dakika
    
    // Pre-configured audio session for instant start
    private var isAudioSessionReady = false
    private var preConfiguredAudioFile: URL?
    private let cancelThreshold: CGFloat = 100.0
    
    @Published var isRecording = false
    @Published var microphonePermission = false
    @Published var recordingLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var recordingQuality: RecordingQuality = .silent
    @Published var canFinishRecording = false
    @Published var recordingCancelled = false
    @Published var serverCheckPassed = false
    
    
    // Optimized visual feedback
    @Published var showWarningColor = false
    @Published var showDangerColor = false
    @Published var recordingProgress: Float = 0.0
    @Published var formattedTimeRemaining = "2:00"
    @Published var formattedElapsedTime = "0:00"
    
    // Pre-connection state for instant feedback
    @Published var readyToRecord = false
    
    weak var networkManager: NetworkManager?
    
    enum RecordingQuality {
        case silent, low, medium, good, excellent
        
        var description: String {
            switch self {
            case .silent: return "Silent"
            case .low: return "Too Quiet"
            case .medium: return "OK"
            case .good: return "Good"
            case .excellent: return "Excellent"
            }
        }
        
        var color: Color {
            switch self {
            case .silent: return .gray
            case .low: return .orange
            case .medium: return .yellow
            case .good: return .green
            case .excellent: return .blue
            }
        }
    }
    
    var timerColor: Color {
        if showDangerColor {
            return .red
        } else if showWarningColor {
            return .orange
        } else {
            return .white
        }
    }
    
    var progressColor: Color {
        if showDangerColor {
            return .red
        } else if showWarningColor {
            return .orange
        } else {
            return .blue
        }
    }
    
    var recordingCompleted: ((Data?, RecordingMetrics?) -> Void)?
    var serverCheckFailed: ((String) -> Void)?
    
    struct RecordingMetrics {
        let duration: TimeInterval
        let averageLevel: Float
        let peakLevel: Float
        let quality: RecordingQuality
        let sampleRate: Double
        let fileSize: Int
    }
    
    private var levelHistory: [Float] = []
    private var peakLevel: Float = 0.0
    
    // Background connection monitoring
    private var connectionCheckTimer: Timer?
    private var lastConnectionCheck: Date = Date()
    private let connectionCheckInterval: TimeInterval = 30.0 // Check every 30 seconds
    
    override init() {
        super.init()
        setupOptimizedAudioSession()
        startBackgroundConnectionMonitoring()
    }
    
    deinit {
        meteringTimer?.invalidate()
        durationTimer?.invalidate()
        connectionCheckTimer?.invalidate()
        
        if recorder?.isRecording == true {
            recorder?.stop()
        }
        
        try? audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    }
    
    // MARK: - Optimized Audio Session Setup
    
    private func setupOptimizedAudioSession() {
        audioSession = AVAudioSession.sharedInstance()
        
        Task { @MainActor in
            do {
                // Pre-configure audio session for instant recording
                try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession?.setActive(true)
                
                let permission = await AVAudioApplication.requestRecordPermission()
                microphonePermission = permission
                
                if permission {
                    prepareAudioRecording()
                }
                
                print(permission ? "🎤 Microphone access granted, session ready" : "❌ Microphone access denied")
            } catch {
                print("❌ Audio session setup failed: \(error)")
            }
        }
    }
    
    func cancelRecording() {
            print("🚫 Recording cancelled by user")
            
            recordingCancelled = true
            let wasRecording = isRecording
            forceStopRecording()
            
            if wasRecording {
                // Haptic feedback for cancellation
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.warning)
                
                // Callback with nil to indicate cancellation
                recordingCompleted?(nil, nil)
            }
            
            // Reset cancel state after a short delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                recordingCancelled = false
            }
        }
    
    private func prepareAudioRecording() {
        // Pre-create audio file URL for instant use
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        preConfiguredAudioFile = documentsPath.appendingPathComponent("recording_temp.wav")
        
        // Mark session as ready
        isAudioSessionReady = true
        updateReadyState()
        
        print("🎤 ✅ Audio session pre-configured for instant recording")
    }
    
    // MARK: - Background Connection Monitoring
    
    private func startBackgroundConnectionMonitoring() {
        connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: connectionCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performBackgroundConnectionCheck()
            }
        }
        
        // Initial check
        Task {
            await performBackgroundConnectionCheck()
        }
    }
    
    private func performBackgroundConnectionCheck() async {
        guard let networkManager = networkManager else { return }
        
        // Silent background check without affecting UI
        let connectionOK = await networkManager.backgroundServerCheck()
        
        await MainActor.run {
            serverCheckPassed = connectionOK
            updateReadyState()
            lastConnectionCheck = Date()
        }
    }
    
    private func updateReadyState() {
        readyToRecord = microphonePermission && isAudioSessionReady && serverCheckPassed
    }
    
    // MARK: - Instant Recording Start
    
    func beginRecording() {
        print("🎤 Begin recording requested - instant mode")
        
        guard microphonePermission else {
            print("❌ No microphone permission")
            return
        }
        
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }
        
        // Instant UI feedback - no waiting
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        // Check if we need fresh connection check
        let timeSinceLastCheck = Date().timeIntervalSince(lastConnectionCheck)
        
        if timeSinceLastCheck > 60.0 || !serverCheckPassed {
            // Quick connection check in background
            Task {
                let connectionOK = await networkManager?.quickServerCheck() ?? false
                
                await MainActor.run {
                    if connectionOK {
                        startRecordingInstantly()
                    } else {
                        serverCheckFailed?("Cannot connect to server. Please check your connection.")
                    }
                }
            }
        } else {
            // Start immediately if recent check was OK
            startRecordingInstantly()
        }
    }
    
    private func startRecordingInstantly() {
        guard isAudioSessionReady else {
            setupOptimizedAudioSession()
            return
        }
        
        resetRecordingState()
        
        let audioFile = preConfiguredAudioFile ?? createFallbackAudioFile()
        
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
            // Quick mode switch for recording
            try audioSession?.setCategory(.record, mode: .measurement, options: [])
            
            recorder = try AVAudioRecorder(url: audioFile, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()
            
            let success = recorder?.record() ?? false
            if success {
                recordingStartTime = Date()
                isRecording = true
                
                startOptimizedMetering()
                startDurationTimer()
                
                print("🎤 ✅ Recording started instantly")
                
                // Prepare next audio file for future use
                prepareNextAudioFile()
            } else {
                print("❌ Failed to start recording")
                resetRecordingState()
                serverCheckFailed?("Failed to start recording")
            }
        } catch {
            print("❌ Recording setup failed: \(error)")
            resetRecordingState()
            serverCheckFailed?("Recording setup failed: \(error.localizedDescription)")
        }
    }
    
    private func createFallbackAudioFile() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")
    }
    
    private func prepareNextAudioFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        preConfiguredAudioFile = documentsPath.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970 + 1)).wav")
    }
    
    // MARK: - Optimized Metering
    
    private func startOptimizedMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateOptimizedMeteringLevels()
            }
        }
    }
    
    private func updateOptimizedMeteringLevels() {
        guard isRecording, let recorder = recorder else { return }
        
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        // Optimized normalization
        let normalizedLevel = max(0.0, min(1.0, powf(10.0, averagePower / 20.0)))
        let normalizedPeak = max(0.0, min(1.0, powf(10.0, peakPower / 20.0)))
        
        recordingLevel = normalizedLevel
        peakLevel = max(peakLevel, normalizedPeak)
        
        // Efficient level history management
        levelHistory.append(normalizedLevel)
        if levelHistory.count > 50 { // Reduced from 100 for better performance
            levelHistory.removeFirst()
        }
        
        updateRecordingQuality(averagePower: averagePower)
    }
    
    func endRecording() {
        print("🎤 End recording requested - isRecording: \(isRecording)")
        
        let wasRecording = isRecording
        forceStopRecording()
        
        guard wasRecording else {
            print("⚠️ Was not recording")
            recordingCompleted?(nil, nil)
            return
        }
        
        guard let recorder = recorder,
              let startTime = recordingStartTime else {
            print("❌ No recorder or start time")
            recordingCompleted?(nil, nil)
            return
        }
        
        let audioFile = recorder.url
        let finalDuration = Date().timeIntervalSince(startTime)
        
        if finalDuration < minimumRecordingDuration {
            print("⚠️ Recording too short: \(finalDuration)s")
            
            Task {
                try? FileManager.default.removeItem(at: audioFile)
                await MainActor.run {
                    recordingCompleted?(nil, nil)
                }
            }
            return
        }
        
        // Optimized file reading
        Task {
            do {
                let data = try Data(contentsOf: audioFile)
                
                let averageLevel = levelHistory.isEmpty ? 0.0 : levelHistory.reduce(0, +) / Float(levelHistory.count)
                let metrics = RecordingMetrics(
                    duration: finalDuration,
                    averageLevel: averageLevel,
                    peakLevel: peakLevel,
                    quality: recordingQuality,
                    sampleRate: 44100,
                    fileSize: data.count
                )
                
                print("🎤 ✅ Recording completed: \(data.count) bytes, \(String(format: "%.1f", finalDuration))s, quality: \(recordingQuality.description)")
                
                await MainActor.run {
                    recordingCompleted?(data, metrics)
                }
                
                // Cleanup in background
                try? FileManager.default.removeItem(at: audioFile)
                
                // Prepare for next recording
                await MainActor.run {
                    prepareAudioRecording()
                }
                
            } catch {
                print("❌ Failed to read recording: \(error)")
                await MainActor.run {
                    recordingCompleted?(nil, nil)
                }
            }
        }
        
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }
    
    private func forceStopRecording() {
        print("🛑 Force stopping recording")
        
        isRecording = false
        recordingLevel = 0.0
        canFinishRecording = false
        
        // Reset visual feedback
        showWarningColor = false
        showDangerColor = false
        recordingProgress = 0.0
        formattedElapsedTime = "0:00"
        formattedTimeRemaining = "2:00"
        
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        
        recorder?.stop()
        
        // Quick restoration to playback mode
        do {
            try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        } catch {
            print("⚠️ Failed to reset audio session: \(error)")
        }
        
        print("🛑 ✅ Force stop completed - isRecording: \(isRecording)")
    }
    
    private func resetRecordingState() {
        levelHistory.removeAll()
        peakLevel = 0.0
        recordingDuration = 0.0
        canFinishRecording = false
        recordingQuality = .silent
        recordingLevel = 0.0
        recordingStartTime = nil
        
        // Reset visual feedback
        showWarningColor = false
        showDangerColor = false
        recordingProgress = 0.0
        formattedElapsedTime = "0:00"
        formattedTimeRemaining = "2:00"
        
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                guard self.isRecording else {
                    timer.invalidate()
                    return
                }
                
                if let startTime = self.recordingStartTime {
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                    
                    self.canFinishRecording = self.recordingDuration >= self.minimumRecordingDuration
                    
                    // Visual feedback updates
                    self.updateVisualFeedback()
                    
                    // Auto-stop at maximum duration
                    if self.recordingDuration >= self.maximumRecordingDuration {
                        print("⏱️ Maximum recording duration reached - auto stopping")
                        
                        let feedback = UIImpactFeedbackGenerator(style: .heavy)
                        feedback.impactOccurred()
                        
                        self.endRecording()
                        timer.invalidate()
                    }
                }
            }
        }
    }
    
    private func updateVisualFeedback() {
        // Progress bar update
        recordingProgress = Float(recordingDuration / maximumRecordingDuration)
        
        // Time formats update
        formattedElapsedTime = formatTime(recordingDuration)
        let remainingTime = max(0, maximumRecordingDuration - recordingDuration)
        formattedTimeRemaining = formatTime(remainingTime)
        
        // Color warnings
        let remainingSeconds = maximumRecordingDuration - recordingDuration
        
        if remainingSeconds <= 5.0 {
            // Last 5 seconds: Red + Vibration
            if !showDangerColor {
                showDangerColor = true
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.impactOccurred()
            }
            showWarningColor = false
        } else if remainingSeconds <= 10.0 {
            // Last 10 seconds: Orange
            showWarningColor = true
            showDangerColor = false
        } else {
            // Normal: White
            showWarningColor = false
            showDangerColor = false
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func updateRecordingQuality(averagePower: Float) {
        if averagePower > -20 {
            recordingQuality = .excellent
        } else if averagePower > -30 {
            recordingQuality = .good
        } else if averagePower > -40 {
            recordingQuality = .medium
        } else if averagePower > -50 {
            recordingQuality = .low
        } else {
            recordingQuality = .silent
        }
    }
    
    func requestPermission() async -> Bool {
        let permission = await AVAudioApplication.requestRecordPermission()
        await MainActor.run {
            microphonePermission = permission
            if permission {
                prepareAudioRecording()
            }
        }
        return permission
    }
    
    func getRecordingStatus() -> String {
        if !microphonePermission {
            return "Microphone permission required"
        } else if isRecording {
            return "Recording \(formattedElapsedTime) / 2:00 • \(recordingQuality.description)"
        } else if readyToRecord {
            return "Ready to record instantly"
        } else {
            return "Preparing..."
        }
    }
    
    var isMinimumDurationMet: Bool {
        return recordingDuration >= minimumRecordingDuration
    }
    
    var progressPercentage: Float {
        return recordingProgress
    }
    
    var maxDurationDisplay: String {
        return "Max: 2:00"
    }
    
    var timeDisplayString: String {
        return "\(formattedElapsedTime) / 2:00"
    }
}
