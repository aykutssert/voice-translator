import SwiftUI
import AVFoundation

// MARK: - Speech Synthesizer (Güncellenmiş)
@MainActor
class SpeechSynthesizer: NSObject, ObservableObject {
    private let voiceEngine = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        voiceEngine.delegate = self
    }
    
    func vocalize(_ content: String, languageCode: String = "en-US") {
        guard !content.isEmpty else { return }
        
        if voiceEngine.isSpeaking {
            voiceEngine.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: content)
        
        // Dil koduna göre ses seçimi
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        
        // Konuşma hızı ve ton ayarları
        utterance.rate = getOptimalRate(for: languageCode)
        utterance.pitchMultiplier = getOptimalPitch(for: languageCode)
        utterance.volume = 1.0
        
        voiceEngine.speak(utterance)
        print("🔊 Speaking (\(languageCode)): \(content.prefix(50))...")
    }
    
    func silence() {
        voiceEngine.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    func pause() {
        if voiceEngine.isSpeaking {
            voiceEngine.pauseSpeaking(at: .immediate)
        }
    }
    
    func resume() {
        if voiceEngine.isPaused {
            voiceEngine.continueSpeaking()
        }
    }
    
    // MARK: - Language-specific optimizations
    
    private func getOptimalRate(for languageCode: String) -> Float {
        /*switch languageCode.prefix(2) {
        case "tr": return 0.45 // Türkçe biraz daha yavaş
        case "ja", "ko": return 0.4 // Asya dilleri daha yavaş
        case "es", "it": return 0.55 // Latin dilleri biraz hızlı
        case "de", "ru": return 0.4 // Karmaşık diller yavaş
        case "zh": return 0.35 // Çince çok yavaş
        case "ar", "he": return 0.4 // Sağdan sola diller
        default: return 0.5 // İngilizce ve diğerleri
        }*/
        return 0.45
    }
    
    private func getOptimalPitch(for languageCode: String) -> Float {
        switch languageCode.prefix(2) {
        case "zh", "vi", "th": return 1.1 // Tonal diller yüksek pitch
        case "de", "ru": return 0.9 // Derin sesler
        case "ja": return 1.05 // Japonca hafif yüksek
        case "ar": return 0.95 // Arapça hafif düşük
        default: return 1.0 // Normal pitch
        }
    }
    
    // MARK: - Voice availability check
    
    func isLanguageSupported(_ languageCode: String) -> Bool {
        return AVSpeechSynthesisVoice.speechVoices().contains { voice in
            voice.language == languageCode
        }
    }
    
    func getAvailableVoices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix(String(languageCode.prefix(2)))
        }
    }
    
    func getBestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let voices = getAvailableVoices(for: languageCode)
        
        // Enhanced voice seçimi tercihi
        return voices.first { $0.quality == .enhanced } ??
               voices.first { $0.quality == .default } ??
               AVSpeechSynthesisVoice(language: "en-US")
    }
    
    // MARK: - Advanced speaking methods
    
    func speakWithCustomVoice(_ content: String, languageCode: String, voiceIdentifier: String? = nil) {
        guard !content.isEmpty else { return }
        
        if voiceEngine.isSpeaking {
            voiceEngine.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: content)
        
        // Özel ses seçimi
        if let identifier = voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
        } else {
            utterance.voice = getBestVoice(for: languageCode)
        }
        
        utterance.rate = getOptimalRate(for: languageCode)
        utterance.pitchMultiplier = getOptimalPitch(for: languageCode)
        utterance.volume = 1.0
        
        voiceEngine.speak(utterance)
        print("🔊 Speaking with custom voice (\(languageCode)): \(content.prefix(50))...")
    }
    
    func speakSlowly(_ content: String, languageCode: String = "en-US") {
        guard !content.isEmpty else { return }
        
        if voiceEngine.isSpeaking {
            voiceEngine.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = getBestVoice(for: languageCode)
        utterance.rate = 0.3 // Çok yavaş
        utterance.pitchMultiplier = getOptimalPitch(for: languageCode)
        utterance.volume = 1.0
        
        voiceEngine.speak(utterance)
        print("🐌 Speaking slowly (\(languageCode)): \(content.prefix(50))...")
    }
    
    func speakWithEmphasis(_ content: String, languageCode: String = "en-US", emphasis: EmphasisLevel = .normal) {
        guard !content.isEmpty else { return }
        
        if voiceEngine.isSpeaking {
            voiceEngine.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: content)
        utterance.voice = getBestVoice(for: languageCode)
        
        // Vurgu seviyesine göre ayarlama
        switch emphasis {
        case .soft:
            utterance.rate = getOptimalRate(for: languageCode) * 0.8
            utterance.pitchMultiplier = getOptimalPitch(for: languageCode) * 0.9
            utterance.volume = 0.8
        case .normal:
            utterance.rate = getOptimalRate(for: languageCode)
            utterance.pitchMultiplier = getOptimalPitch(for: languageCode)
            utterance.volume = 1.0
        case .strong:
            utterance.rate = getOptimalRate(for: languageCode) * 1.1
            utterance.pitchMultiplier = getOptimalPitch(for: languageCode) * 1.2
            utterance.volume = 1.0
        }
        
        voiceEngine.speak(utterance)
        print("🎭 Speaking with \(emphasis) emphasis (\(languageCode)): \(content.prefix(50))...")
    }
    
    enum EmphasisLevel {
        case soft, normal, strong
    }
    
    // MARK: - Text preprocessing for better pronunciation
    
    private func preprocessText(_ text: String, for languageCode: String) -> String {
        var processedText = text
        
        switch languageCode.prefix(2) {
        case "tr":
            // Türkçe özel karakterler ve kısaltmalar
            processedText = processedText.replacingOccurrences(of: "Dr.", with: "Doktor")
            processedText = processedText.replacingOccurrences(of: "Prof.", with: "Profesör")
            processedText = processedText.replacingOccurrences(of: "vs.", with: "ve benzer")
            
        case "en":
            // İngilizce kısaltmalar
            processedText = processedText.replacingOccurrences(of: "Dr.", with: "Doctor")
            processedText = processedText.replacingOccurrences(of: "Prof.", with: "Professor")
            processedText = processedText.replacingOccurrences(of: "vs.", with: "versus")
            processedText = processedText.replacingOccurrences(of: "etc.", with: "etcetera")
            
        case "es":
            // İspanyolca kısaltmalar
            processedText = processedText.replacingOccurrences(of: "Dr.", with: "Doctor")
            processedText = processedText.replacingOccurrences(of: "Sra.", with: "Señora")
            processedText = processedText.replacingOccurrences(of: "Sr.", with: "Señor")
            
        case "fr":
            // Fransızca kısaltmalar
            processedText = processedText.replacingOccurrences(of: "Dr.", with: "Docteur")
            processedText = processedText.replacingOccurrences(of: "M.", with: "Monsieur")
            processedText = processedText.replacingOccurrences(of: "Mme.", with: "Madame")
            
        case "de":
            // Almanca kısaltmalar
            processedText = processedText.replacingOccurrences(of: "Dr.", with: "Doktor")
            processedText = processedText.replacingOccurrences(of: "Hr.", with: "Herr")
            processedText = processedText.replacingOccurrences(of: "Fr.", with: "Frau")
            
        default:
            break
        }
        
        return processedText
    }
    
    func vocalizeWithPreprocessing(_ content: String, languageCode: String = "en-US") {
        let processedContent = preprocessText(content, for: languageCode)
        vocalize(processedContent, languageCode: languageCode)
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
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // Pause event handling if needed
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
