import SwiftUI
import AVFoundation
import Foundation
import FirebaseAuth

// MARK: - Main Application View (Multi-Language Support)
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var networkManager = NetworkManager()
    @StateObject private var voiceRecorder = VoiceRecorder()
    @StateObject private var speechSynthesizer = SpeechSynthesizer()
    @StateObject private var languageManager = LanguageManager()
    @StateObject private var premiumManager = PremiumManager()
    @EnvironmentObject var authManager: AuthManager
    
    // UI State
    @State private var autoPlayback = true
    @State private var recordingActive = false
    @State private var resultsVisible = false
    @State private var showingCreditsSheet = false
    @State private var showingLanguageSelector = false
    @State private var showConnectionDetails = false
    @State private var lastTranslationMetrics: VoiceRecorder.RecordingMetrics?
    @State private var showingRecordingTips = false
    @State private var recordingGuidance: String = ""
    @State private var showRecordingFeedback = false
    @State private var buttonPressed = false
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 0) {
                appHeader
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Language Selection
                        languageSelectionCard
                        
                        if resultsVisible {
                            enhancedTranslationDisplay
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                        }
                        
                        enhancedSpeechSettings
                        
                        if showingRecordingTips && !recordingActive && !networkManager.processing {
                            recordingTipsCard
                                .transition(.scale.combined(with: .opacity))
                        }
                        
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, 22)
                }
                
                Spacer()
                enhancedMicrophoneInterface
            }
        }
        .onAppear(perform: initializeApp)
        .task {
            if authManager.isAuthenticated {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await networkManager.fetchUserCredits()
            }
        }
        .onReceive(authManager.$isAuthenticated) { isAuth in
            if isAuth {
                Task {
                    await networkManager.fetchUserCredits()
                }
            }
        }
        .onChange(of: networkManager.targetResult) { _, _ in
            handleTranslationUpdate()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: voiceRecorder.isRecording) { _, isRec in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                recordingActive = isRec
            }
        }
        .onChange(of: voiceRecorder.recordingQuality) { _, quality in
            updateRecordingGuidance(quality)
        }
        .onChange(of: languageManager.selectedDirection) { _, direction in
            networkManager.setTranslationDirection(direction)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCreditsSheet) {
            PremiumCreditsView(networkManager: networkManager, premiumManager: premiumManager)
        }
        .sheet(isPresented: $showingLanguageSelector) {
            LanguageSelectorView(languageManager: languageManager)
        }
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
    
    private var creditsColor: Color {
        guard let credits = networkManager.userCredits else { return .gray }
        return credits.statusColor
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
                
                HStack(spacing: 12) {
                    // Connection status indicator
                    connectionStatusIndicator
                    
                    // Credits button
                    Button(action: { showingCreditsSheet.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: networkManager.userCredits?.isUnlimited == true ? "infinity" : "creditcard.fill")
                                .font(.caption)
                            if let credits = networkManager.userCredits {
                                if credits.isUnlimited {
                                    Text("∞")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                } else {
                                    Text("\(Int(credits.remainingMinutes))m")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            } else {
                                Text("--")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(creditsColor.opacity(0.3))
                                .overlay(
                                    Capsule()
                                        .stroke(creditsColor, lineWidth: 1)
                                )
                        )
                    }
                    
                    // Settings menu
                    Menu {
                        Button(action: { showingCreditsSheet.toggle() }) {
                            Label("Premium & Credits", systemImage: "star.circle")
                        }
                        
                        Button(action: { showingLanguageSelector.toggle() }) {
                            Label("Language Settings", systemImage: "globe")
                        }
                        
                        Button(action: {
                            withAnimation {
                                showingRecordingTips.toggle()
                            }
                        }) {
                            Label("Recording Tips", systemImage: "lightbulb")
                        }
                        
                        if !networkManager.targetResult.isEmpty && networkManager.targetResult.hasPrefix("Error:") {
                            Button(action: quickRetry) {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: { authManager.signOut() }) {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            
            Text("Hold to record • Release to translate")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.top, 25)
        .padding(.bottom, 15)
        .padding(.horizontal, 22)
    }
    
    // MARK: - Language Selection Card
    
    private var languageSelectionCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Translation Direction")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Change") {
                    showingLanguageSelector = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            Button(action: { showingLanguageSelector = true }) {
                HStack(spacing: 20) {
                    // Source Language
                    VStack(spacing: 8) {
                        Text(languageManager.selectedDirection.sourceLanguage.flag)
                            .font(.system(size: 40))
                        
                        Text(languageManager.selectedDirection.sourceLanguage.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.blue.opacity(0.5), lineWidth: 2)
                            )
                    )
                    
                    // Swap and Arrow
                    VStack(spacing: 8) {
                        Button(action: quickLanguageSwap) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(
                                    Circle()
                                        .fill(.blue.opacity(0.8))
                                )
                        }
                        .scaleEffect(1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: languageManager.selectedDirection.sourceLanguage.code)
                        
                        Text("TAP TO\nCHANGE")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    
                    // Target Language
                    VStack(spacing: 8) {
                        Text(languageManager.selectedDirection.targetLanguage.flag)
                            .font(.system(size: 40))
                        
                        Text(languageManager.selectedDirection.targetLanguage.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.green.opacity(0.5), lineWidth: 2)
                            )
                    )
                }
            }
            
            // Quick language pairs
            if !languageManager.recentDirections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(languageManager.recentDirections.prefix(3), id: \.id) { direction in
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    languageManager.setTranslationDirection(direction)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(direction.sourceLanguage.flag)
                                        .font(.caption)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(direction.targetLanguage.flag)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .stroke(.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var enhancedTranslationDisplay: some View {
        VStack(spacing: 20) {
            ResultCard(
                flag: languageManager.selectedDirection.sourceLanguage.flag,
                language: languageManager.selectedDirection.sourceLanguage.name,
                content: networkManager.sourceResult,
                accentColor: Color(red: 0.1, green: 0.4, blue: 0.9),
                canSpeak: true,
                languageCode: TTS_LANGUAGE_MAP[languageManager.selectedDirection.sourceLanguage.code] ?? "en-US",
                onSpeak: {
                    let languageCode = TTS_LANGUAGE_MAP[languageManager.selectedDirection.sourceLanguage.code] ?? "en-US"
                    speechSynthesizer.vocalize(networkManager.sourceResult, languageCode: languageCode)
                }
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
                flag: languageManager.selectedDirection.targetLanguage.flag,
                language: languageManager.selectedDirection.targetLanguage.name,
                content: networkManager.targetResult,
                accentColor: Color(red: 0.1, green: 0.7, blue: 0.1),
                canSpeak: true,
                languageCode: TTS_LANGUAGE_MAP[languageManager.selectedDirection.targetLanguage.code] ?? "en-US",
                onSpeak: {
                    let languageCode = TTS_LANGUAGE_MAP[languageManager.selectedDirection.targetLanguage.code] ?? "en-US"
                    speechSynthesizer.vocalize(networkManager.targetResult, languageCode: languageCode)
                }
            )
            
            if let metrics = lastTranslationMetrics {
                MetricsCard(metrics: metrics)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private var enhancedSpeechSettings: some View {
        HStack(spacing: 16) {
            Image(systemName: autoPlayback ? "speaker.wave.3.fill" : "speaker.slash.fill")
                .foregroundColor(autoPlayback ? .white : .gray)
                .font(.title3)
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), value: speechSynthesizer.isSpeaking)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto Voice Playback")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                if speechSynthesizer.isSpeaking {
                    Text("Speaking...")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.9))
                        .transition(.opacity)
                } else {
                    Text("Plays translated text automatically")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
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
    
    private var recordingTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Recording Tips")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Dismiss") {
                    withAnimation {
                        showingRecordingTips = false
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                tipRow("🎯", "Hold button and speak clearly")
                tipRow("🔊", "Speak at normal volume")
                tipRow("⏱️", "Minimum 0.5 seconds, maximum 2 minutes")
                tipRow("🌐", "Requires internet connection")
                tipRow("🔄", "Release to translate automatically")
                tipRow("🌍", "Supports 50+ languages")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Enhanced Microphone Interface (Optimized for Instant Response)
    private var enhancedMicrophoneInterface: some View {
        VStack(spacing: 24) {
            if networkManager.processing {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Processing...")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.9))
                            .fontWeight(.medium)
                        
                        Text("Translating \(languageManager.selectedDirection.sourceLanguage.name) to \(languageManager.selectedDirection.targetLanguage.name)...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
            
            if recordingActive {
                VStack(spacing: 12) {
                    // Enhanced Timer and Progress Bar
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .scaleEffect(1.5)
                                .opacity(0.8)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: recordingActive)
                            
                            Text(voiceRecorder.timeDisplayString)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(voiceRecorder.timerColor)
                                .animation(.easeInOut(duration: 0.3), value: voiceRecorder.timerColor)
                        }
                        
                        // Enhanced Progress Bar with smooth animations
                        ProgressView(value: voiceRecorder.recordingProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: voiceRecorder.progressColor))
                            .frame(height: 4)
                            .scaleEffect(x: 1, y: 2)
                            .animation(.easeInOut(duration: 0.3), value: voiceRecorder.progressColor)
                            .background(
                                Rectangle()
                                    .fill(.white.opacity(0.2))
                                    .frame(height: 4)
                                    .scaleEffect(x: 1, y: 2)
                            )
                    }
                    
                    Text(recordingGuidance)
                        .font(.caption)
                        .foregroundColor(voiceRecorder.recordingQuality.color)
                        .fontWeight(.medium)
                        .animation(.easeInOut, value: recordingGuidance)
                }
                .transition(.opacity.combined(with: .scale))
            }
            
            // Optimized Microphone Button with Instant Feedback
            Button(action: {}) {
                ZStack {
                    // Outer Ring with instant feedback
                    Circle()
                        .stroke(recordingActive ? .red : optimizedButtonColor, lineWidth: 4)
                        .frame(width: 130, height: 130)
                        .scaleEffect(recordingActive ? 1.15 : (buttonPressed ? 1.05 : 1.0))
                        .opacity(recordingActive ? 0.8 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: recordingActive)
                        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: buttonPressed)
                    
                    // Dynamic ripple effects during recording
                    if recordingActive {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(.red.opacity(0.4 - Double(index) * 0.1), lineWidth: 3)
                                .frame(width: 150 + CGFloat(index * 25), height: 150 + CGFloat(index * 25))
                                .scaleEffect(1.0 + Double(voiceRecorder.recordingLevel) * (1.0 + Double(index) * 0.3))
                                .opacity(0.7 - Double(index) * 0.2)
                                .animation(.easeOut(duration: 0.08), value: voiceRecorder.recordingLevel)
                        }
                    }
                    
                    // Audio level visualization
                    if recordingActive && voiceRecorder.recordingLevel > 0.1 {
                        Circle()
                            .fill(.red.opacity(0.15 + Double(voiceRecorder.recordingLevel) * 0.1))
                            .frame(width: 100 + CGFloat(voiceRecorder.recordingLevel * 30), height: 100 + CGFloat(voiceRecorder.recordingLevel * 30))
                            .animation(.easeOut(duration: 0.08), value: voiceRecorder.recordingLevel)
                    }
                    
                    // Main button with enhanced gradient
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    recordingActive ? .red : optimizedButtonColor,
                                    recordingActive ? .red.opacity(0.7) : optimizedButtonColor.opacity(0.7)
                                ]),
                                center: .center,
                                startRadius: 5,
                                endRadius: 55
                            )
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(recordingActive ? 0.95 : (buttonPressed ? 0.97 : 1.0))
                        .shadow(
                            color: recordingActive ? .red.opacity(0.5) : optimizedButtonColor.opacity(0.3),
                            radius: buttonPressed ? 15 : 10,
                            x: 0,
                            y: buttonPressed ? 8 : 5
                        )
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: recordingActive)
                        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: buttonPressed)
                    
                    // Icon with smooth transitions
                    ZStack {
                        if recordingActive {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(.white)
                                .scaleEffect(1.4)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recordingActive)
                }
            }
            .scaleEffect(recordingActive ? 1.03 : (buttonPressed ? 1.01 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: recordingActive)
            .animation(.spring(response: 0.15, dampingFraction: 0.8), value: buttonPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !buttonPressed {
                            animateButtonPress()
                        }
                        
                        if canRecordInstantly && !voiceRecorder.isRecording {
                            Task {
                                await voiceRecorder.beginRecording()
                            }
                        }
                    }
                    .onEnded { _ in
                        animateButtonRelease()
                        
                        if voiceRecorder.isRecording {
                            voiceRecorder.endRecording()
                        }
                    }
            )
            .onTapGesture {
                if voiceRecorder.isRecording {
                    voiceRecorder.endRecording()
                }
            }
            .disabled(!canRecordInstantly && !voiceRecorder.isRecording)
            
            // Enhanced Status Display
            VStack(spacing: 12) {
                Text(optimizedStatusText)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .animation(.easeInOut, value: optimizedStatusText)
                
                if !canRecordInstantly && !voiceRecorder.isRecording {
                    VStack(spacing: 6) {
                        Text(optimizedHelpText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        
                        if !voiceRecorder.microphonePermission {
                            Button("Open Settings") {
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        } else if !networkManager.hasInternet {
                            Button("Check Connection") {
                                Task {
                                    await networkManager.checkConnectionAndServer()
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .transition(.opacity)
                }
                
                if canRecordInstantly && !recordingActive && !networkManager.processing {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text("Ready • Speak clearly in \(languageManager.selectedDirection.sourceLanguage.name)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                // Connection quality indicator
                if canRecordInstantly {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: canRecordInstantly)
                        
                        Text(networkManager.connectionDisplayText)
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.8))
                            .fontWeight(.medium)
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 50)
    }
    
    // MARK: - Helper Views
    
    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
        }
    }
    
    private var connectionStatusIndicator: some View {
        HStack(spacing: 6) {
            if networkManager.hasInternet {
                if networkManager.serverHealth {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                        .scaleEffect(0.7)
                }
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
                    .font(.caption)
                
                Button(action: {
                    Task {
                        await networkManager.checkConnectionAndServer()
                    }
                }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Optimized Computed Properties
    
    private var canRecordInstantly: Bool {
        return voiceRecorder.readyToRecord && networkManager.isReadyForRecording
    }
    
    private var optimizedButtonColor: Color {
        if canRecordInstantly {
            return Color(red: 0.1, green: 0.4, blue: 0.9)
        } else if networkManager.hasInternet && !networkManager.serverHealth {
            return .orange.opacity(0.7)
        } else {
            return .gray.opacity(0.6)
        }
    }
    
    private var optimizedStatusText: String {
        if recordingActive {
            return "Release to Translate"
        } else if !voiceRecorder.microphonePermission {
            return "Microphone Access Required"
        } else if !networkManager.hasInternet {
            return "Internet Connection Required"
        } else if !networkManager.serverHealth {
            return "Connecting to Server..."
        } else if voiceRecorder.readyToRecord && networkManager.isReadyForRecording {
            return "Hold to Record"
        } else {
            return "Preparing Recording..."
        }
    }
    
    private var optimizedHelpText: String {
        if !voiceRecorder.microphonePermission {
            return "Enable microphone access in Settings"
        } else if !networkManager.hasInternet {
            return "Check your internet connection"
        } else if !networkManager.serverHealth {
            return "Checking server availability..."
        } else if !voiceRecorder.readyToRecord {
            return "Preparing audio system..."
        } else {
            return ""
        }
    }
    
    // MARK: - Optimized Helper Functions
    
    private func initializeApp() {
        print("🚀 Initializing Optimized Voice Translator...")
        
        setupOptimizedRecordingCallback()
        voiceRecorder.networkManager = networkManager
        premiumManager.setNetworkManager(networkManager)
        
        // Set initial translation direction
        networkManager.setTranslationDirection(languageManager.selectedDirection)
        
        // Optimized startup sequence - no blocking operations
        Task { @MainActor in
            // Start background connection check (non-blocking)
            Task.detached {
                let connectionOK = await networkManager.backgroundServerCheck()
                print("📶 App startup - Background connection status: \(connectionOK ? "Ready" : "Not Ready")")
            }
            
            // Fetch credits in background if authenticated
            if authManager.isAuthenticated {
                Task.detached {
                    await networkManager.fetchUserCredits()
                }
            }
            
            // Setup background task management
            handleBackgroundTasks()
            
            // Optimize audio session
            optimizeAudioSession()
            
            print("✅ App initialization completed instantly")
        }
    }
    
    private func setupOptimizedRecordingCallback() {
        voiceRecorder.recordingCompleted = { [networkManager] audioData, metrics in
            guard let data = audioData else {
                print("⚠️ No audio data")
                return
            }
            
            Task { @MainActor in
                lastTranslationMetrics = metrics
                
                // Optimized audio transmission with pre-flight check
                let canTransmit = await networkManager.checkInternetBeforeTransmission()
                if canTransmit {
                    networkManager.transmitAudio(data)
                } else {
                    networkManager.targetResult = "Error: Cannot connect to translation server. Please check your connection."
                    networkManager.processing = false
                }
            }
        }
        
        voiceRecorder.serverCheckFailed = { errorMessage in
            print("❌ Recording failed: \(errorMessage)")
            
            // Show user-friendly error with retry option
            Task { @MainActor in
                networkManager.targetResult = "Error: \(errorMessage)"
                
                // Auto-clear error after 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if networkManager.targetResult.hasPrefix("Error:") {
                    networkManager.targetResult = ""
                }
            }
        }
    }
    
    private func showRecordingErrorAlert(_ message: String) {
        // This function is no longer needed since we handle errors directly in the callback
    }
    
    private func handleTranslationUpdate() {
        // Enhanced auto-playback with better timing
        if autoPlayback &&
           !networkManager.targetResult.isEmpty &&
           !networkManager.targetResult.hasPrefix("Error:") &&
           !speechSynthesizer.isSpeaking {
            
            let languageCode = TTS_LANGUAGE_MAP[languageManager.selectedDirection.targetLanguage.code] ?? "en-US"
            
            // Small delay to ensure UI has updated
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                speechSynthesizer.vocalize(networkManager.targetResult, languageCode: languageCode)
            }
        }
        
        if !networkManager.targetResult.isEmpty {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                resultsVisible = true
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            print("📱 App backgrounded")
            if recordingActive {
                voiceRecorder.endRecording()
            }
            // Pause any ongoing speech
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pause()
            }
            
        case .active:
            print("📱 App activated")
            
            // Resume speech if it was paused
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.resume()
            }
            
            // Quick background check on resume
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                await networkManager.backgroundServerCheck()
                
                // Update ready state
                voiceRecorder.objectWillChange.send()
            }
            
        case .inactive:
            // Handle inactive state (like when Control Center is pulled down)
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pause()
            }
            
        @unknown default:
            break
        }
    }
    
    private func updateRecordingGuidance(_ quality: VoiceRecorder.RecordingQuality) {
        let newGuidance: String
        
        switch quality {
        case .silent:
            newGuidance = "Speak louder"
        case .low:
            newGuidance = "Speak closer to microphone"
        case .medium:
            newGuidance = "Good - keep speaking"
        case .good:
            newGuidance = "Excellent quality"
        case .excellent:
            newGuidance = "Perfect - great audio!"
        }
        
        // Only update if guidance actually changed to avoid unnecessary animations
        if recordingGuidance != newGuidance {
            withAnimation(.easeInOut(duration: 0.3)) {
                recordingGuidance = newGuidance
            }
        }
    }
    
    // MARK: - Quick Actions
    
    private func quickLanguageSwap() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            languageManager.swapLanguages()
        }
    }
    
    private func quickRetry() {
        guard !networkManager.processing else { return }
        
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        // Clear previous results
        networkManager.sourceResult = ""
        networkManager.targetResult = ""
        
        withAnimation {
            resultsVisible = false
        }
        
        // Quick connection check
        Task {
            await networkManager.quickServerCheck()
        }
    }
    
    // MARK: - Enhanced Animations
    
    private func animateButtonPress() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        
        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
            buttonPressed = true
        }
        
        feedback.impactOccurred()
    }
    
    private func animateButtonRelease() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        
        withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
            buttonPressed = false
        }
        
        feedback.impactOccurred()
    }
    
    // MARK: - Audio Session Management
    
    private func optimizeAudioSession() {
        // This runs in background to prepare audio system
        Task.detached { @MainActor in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // Optimize for low latency
                try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer
                try audioSession.setPreferredSampleRate(44100)
                
                print("🎵 Audio session optimized for low latency")
            } catch {
                print("⚠️ Audio session optimization failed: \(error)")
            }
        }
    }
    
    // MARK: - Background Task Management
    
    private func handleBackgroundTasks() {
        // Ensure smooth transitions when app goes to background
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Pause any ongoing operations smoothly
            if voiceRecorder.isRecording {
                voiceRecorder.endRecording()
            }
            
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pause()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Resume operations
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.resume()
            }
            
            // Quick health check
            Task {
                await networkManager.quickServerCheck()
            }
        }
    }
}

// MARK: - TTS Language Map
let TTS_LANGUAGE_MAP: [String: String] = [
    "en": "en-US",
    "tr": "tr-TR",
    "es": "es-ES",
    "fr": "fr-FR",
    "de": "de-DE",
    "it": "it-IT",
    "pt": "pt-PT",
    "ru": "ru-RU",
    "zh": "zh-CN",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "ar": "ar-SA",
    "hi": "hi-IN",
    "af": "af-ZA",
    "sq": "sq-AL",
    "hy": "hy-AM",
    "az": "az-AZ",
    "be": "be-BY",
    "bs": "bs-BA",
    "bg": "bg-BG",
    "ca": "ca-ES",
    "hr": "hr-HR",
    "cs": "cs-CZ",
    "da": "da-DK",
    "nl": "nl-NL",
    "et": "et-EE",
    "fi": "fi-FI",
    "gl": "gl-ES",
    "ka": "ka-GE",
    "el": "el-GR",
    "he": "he-IL",
    "hu": "hu-HU",
    "is": "is-IS",
    "id": "id-ID",
    "kn": "kn-IN",
    "kk": "kk-KZ",
    "lv": "lv-LV",
    "lt": "lt-LT",
    "mk": "mk-MK",
    "ms": "ms-MY",
    "mr": "mr-IN",
    "mi": "mi-NZ",
    "ne": "ne-NP",
    "no": "no-NO",
    "fa": "fa-IR",
    "pl": "pl-PL",
    "ro": "ro-RO",
    "sr": "sr-RS",
    "sk": "sk-SK",
    "sl": "sl-SI",
    "sw": "sw-KE",
    "sv": "sv-SE",
    "tl": "tl-PH",
    "ta": "ta-IN",
    "th": "th-TH",
    "uk": "uk-UA",
    "ur": "ur-PK",
    "vi": "vi-VN",
    "cy": "cy-GB"
]

// MARK: - Enhanced Result Card Component
struct ResultCard: View {
    let flag: String
    let language: String
    let content: String
    let accentColor: Color
    let canSpeak: Bool
    let languageCode: String
    let onSpeak: (() -> Void)?
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
                
                HStack(spacing: 8) {
                    if canSpeak && !content.isEmpty && content != "Ready for translation..." && !content.hasPrefix("Error:") {
                        Button(action: {
                            onSpeak?()
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .transition(.scale)
                    }
                    
                    // Copy button
                    if !content.isEmpty && content != "Ready for translation..." && !content.hasPrefix("Error:") {
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
            }
            
            Text(content.isEmpty ? "Ready for translation..." : content)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(content.isEmpty ? .white.opacity(0.6) :
                               content.hasPrefix("Error:") ? .red.opacity(0.9) : .white)
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
                        .stroke(content.hasPrefix("Error:") ? .red.opacity(0.5) : accentColor.opacity(0.5), lineWidth: 2)
                )
                .shadow(color: (content.hasPrefix("Error:") ? .red : accentColor).opacity(0.3), radius: 10, x: 0, y: 5)
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
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingCopyConfirmation = false
            }
        }
    }
}

// MARK: - Metrics Card
struct MetricsCard: View {
    let metrics: VoiceRecorder.RecordingMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Recording Metrics")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack {
                metricItem("Duration", String(format: "%.1fs", metrics.duration))
                Spacer()
                metricItem("Quality", metrics.quality.description)
                Spacer()
                metricItem("Size", formatFileSize(metrics.fileSize))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func metricItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        return String(format: "%.1fKB", kb)
    }
}
