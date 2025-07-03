import SwiftUI
import AVFoundation
import Foundation

// MARK: - Voice Recorder (Güncellenmiş Görsel Feedback)
@MainActor
class VoiceRecorder: NSObject, ObservableObject {
    private var recorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var minimumRecordingDuration: TimeInterval = 0.5
    private var maximumRecordingDuration: TimeInterval = 120.0 // 2 dakika
    
    @Published var isRecording = false
    @Published var microphonePermission = false
    @Published var recordingLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var recordingQuality: RecordingQuality = .silent
    @Published var canFinishRecording = false
    @Published var serverCheckPassed = false
    
    // Yeni görsel feedback özellikleri
    @Published var showWarningColor = false      // Son 10 saniye için sarı
    @Published var showDangerColor = false       // Son 5 saniye için kırmızı
    @Published var recordingProgress: Float = 0.0 // Progress bar için
    @Published var formattedTimeRemaining = "2:00" // Kalan süre
    @Published var formattedElapsedTime = "0:00"   // Geçen süre
    
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
    
    // Timer renkleri için computed property
    var timerColor: Color {
        if showDangerColor {
            return .red
        } else if showWarningColor {
            return .orange
        } else {
            return .white
        }
    }
    
    // Progress bar rengi
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
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        meteringTimer?.invalidate()
        durationTimer?.invalidate()
        
        if recorder?.isRecording == true {
            recorder?.stop()
        }
        
        try? audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    }
    
    private func setupAudioSession() {
        audioSession = AVAudioSession.sharedInstance()
        
        Task { @MainActor in
            do {
                try audioSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession?.setActive(true)
                
                let permission = await AVAudioApplication.requestRecordPermission()
                microphonePermission = permission
                
                print(permission ? "🎤 Microphone access granted" : "❌ Microphone access denied")
            } catch {
                print("❌ Audio session setup failed: \(error)")
            }
        }
    }
    
    func beginRecording() {
        print("🎤 Begin recording requested")
        
        guard microphonePermission else {
            print("❌ No microphone permission")
            return
        }
        
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }
        
        guard let networkManager = networkManager else {
            serverCheckFailed?("Network manager not available")
            return
        }
        
        // Buton basıldığında internet ve sunucu kontrolü yap
        Task {
            let connectionOK = await networkManager.checkInternetBeforeRecording()
            
            await MainActor.run {
                guard connectionOK else {
                    print("❌ Connection check failed - cannot start recording")
                    serverCheckFailed?("Cannot connect to translation server. Please check your connection and try again.")
                    return
                }
                
                print("✅ Connection check passed - starting recording")
                startRecordingProcess()
            }
        }
    }
    
    private func startRecordingProcess() {
        resetRecordingState()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFile = documentsPath.appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970)).wav")
        
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
            try audioSession?.setCategory(.record, mode: .measurement, options: [])
            try audioSession?.setActive(true)
            
            recorder = try AVAudioRecorder(url: audioFile, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()
            
            let success = recorder?.record() ?? false
            if success {
                recordingStartTime = Date()
                isRecording = true
                
                startEnhancedMetering()
                startDurationTimer()
                
                print("🎤 ✅ Recording started successfully")
                
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.impactOccurred()
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
                
                try? FileManager.default.removeItem(at: audioFile)
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
        
        // Reset görsel feedback
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
        
        // Reset görsel feedback
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
    
    private func startEnhancedMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateEnhancedMeteringLevels()
            }
        }
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
                    
                    // Görsel feedback güncellemeleri
                    self.updateVisualFeedback()
                    
                    // Maksimum süreye ulaşıldığında otomatik durdur
                    if self.recordingDuration >= self.maximumRecordingDuration {
                        print("⏱️ Maximum recording duration reached - auto stopping")
                        
                        // Hafif titreşim feedback
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
        // Progress bar güncelleme
        recordingProgress = Float(recordingDuration / maximumRecordingDuration)
        
        // Zaman formatları güncelleme
        formattedElapsedTime = formatTime(recordingDuration)
        let remainingTime = max(0, maximumRecordingDuration - recordingDuration)
        formattedTimeRemaining = formatTime(remainingTime)
        
        // Renk uyarıları
        let remainingSeconds = maximumRecordingDuration - recordingDuration
        
        if remainingSeconds <= 5.0 {
            // Son 5 saniye: Kırmızı + Titreşim
            if !showDangerColor {
                showDangerColor = true
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.impactOccurred()
            }
            showWarningColor = false
        } else if remainingSeconds <= 10.0 {
            // Son 10 saniye: Sarı/Turuncu
            showWarningColor = true
            showDangerColor = false
        } else {
            // Normal durum: Beyaz
            showWarningColor = false
            showDangerColor = false
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func updateEnhancedMeteringLevels() {
        guard isRecording, let recorder = recorder else { return }
        
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        
        let normalizedLevel = max(0.0, min(1.0, powf(10.0, averagePower / 20.0)))
        let normalizedPeak = max(0.0, min(1.0, powf(10.0, peakPower / 20.0)))
        
        recordingLevel = normalizedLevel
        peakLevel = max(peakLevel, normalizedPeak)
        levelHistory.append(normalizedLevel)
        
        if levelHistory.count > 100 {
            levelHistory.removeFirst()
        }
        
        updateRecordingQuality(averagePower: averagePower)
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
        }
        return permission
    }
    
    func getRecordingStatus() -> String {
        if !microphonePermission {
            return "Microphone permission required"
        } else if isRecording {
            return "Recording \(formattedElapsedTime) / 2:00 • \(recordingQuality.description)"
        } else {
            return "Ready to record (max 2 min)"
        }
    }
    
    var isMinimumDurationMet: Bool {
        return recordingDuration >= minimumRecordingDuration
    }
    
    var progressPercentage: Float {
        return recordingProgress
    }
    
    // Yeni: Maximum süre display string
    var maxDurationDisplay: String {
        return "Max: 2:00"
    }
    
    // Yeni: Time display with colors
    var timeDisplayString: String {
        return "\(formattedElapsedTime) / 2:00"
    }
}
