import Foundation
import SwiftUI

// MARK: - Language Support
struct SupportedLanguage: Identifiable, Hashable {
    let id = UUID()
    let code: String
    let name: String
    let flag: String
    let whisperCode: String // OpenAI Whisper için kod
    
    static let allLanguages: [SupportedLanguage] = [
        // Popüler diller
        SupportedLanguage(code: "en", name: "English", flag: "🇺🇸", whisperCode: "en"),
        SupportedLanguage(code: "tr", name: "Türkçe", flag: "🇹🇷", whisperCode: "tr"),
        SupportedLanguage(code: "es", name: "Español", flag: "🇪🇸", whisperCode: "es"),
        SupportedLanguage(code: "fr", name: "Français", flag: "🇫🇷", whisperCode: "fr"),
        SupportedLanguage(code: "de", name: "Deutsch", flag: "🇩🇪", whisperCode: "de"),
        SupportedLanguage(code: "it", name: "Italiano", flag: "🇮🇹", whisperCode: "it"),
        SupportedLanguage(code: "pt", name: "Português", flag: "🇵🇹", whisperCode: "pt"),
        SupportedLanguage(code: "ru", name: "Русский", flag: "🇷🇺", whisperCode: "ru"),
        SupportedLanguage(code: "zh", name: "中文", flag: "🇨🇳", whisperCode: "zh"),
        SupportedLanguage(code: "ja", name: "日本語", flag: "🇯🇵", whisperCode: "ja"),
        SupportedLanguage(code: "ko", name: "한국어", flag: "🇰🇷", whisperCode: "ko"),
        SupportedLanguage(code: "ar", name: "العربية", flag: "🇸🇦", whisperCode: "ar"),
        SupportedLanguage(code: "hi", name: "हिन्दी", flag: "🇮🇳", whisperCode: "hi"),
        
        // Diğer desteklenen diller
        SupportedLanguage(code: "af", name: "Afrikaans", flag: "🇿🇦", whisperCode: "af"),
        SupportedLanguage(code: "sq", name: "Shqip", flag: "🇦🇱", whisperCode: "sq"),
        SupportedLanguage(code: "hy", name: "Հայերեն", flag: "🇦🇲", whisperCode: "hy"),
        SupportedLanguage(code: "az", name: "Azərbaycan", flag: "🇦🇿", whisperCode: "az"),
        SupportedLanguage(code: "be", name: "Беларуская", flag: "🇧🇾", whisperCode: "be"),
        SupportedLanguage(code: "bs", name: "Bosanski", flag: "🇧🇦", whisperCode: "bs"),
        SupportedLanguage(code: "bg", name: "Български", flag: "🇧🇬", whisperCode: "bg"),
        SupportedLanguage(code: "ca", name: "Català", flag: "🇪🇸", whisperCode: "ca"),
        SupportedLanguage(code: "hr", name: "Hrvatski", flag: "🇭🇷", whisperCode: "hr"),
        SupportedLanguage(code: "cs", name: "Čeština", flag: "🇨🇿", whisperCode: "cs"),
        SupportedLanguage(code: "da", name: "Dansk", flag: "🇩🇰", whisperCode: "da"),
        SupportedLanguage(code: "nl", name: "Nederlands", flag: "🇳🇱", whisperCode: "nl"),
        SupportedLanguage(code: "et", name: "Eesti", flag: "🇪🇪", whisperCode: "et"),
        SupportedLanguage(code: "fi", name: "Suomi", flag: "🇫🇮", whisperCode: "fi"),
        SupportedLanguage(code: "gl", name: "Galego", flag: "🇪🇸", whisperCode: "gl"),
        SupportedLanguage(code: "ka", name: "ქართული", flag: "🇬🇪", whisperCode: "ka"),
        SupportedLanguage(code: "el", name: "Ελληνικά", flag: "🇬🇷", whisperCode: "el"),
        SupportedLanguage(code: "he", name: "עברית", flag: "🇮🇱", whisperCode: "he"),
        SupportedLanguage(code: "hu", name: "Magyar", flag: "🇭🇺", whisperCode: "hu"),
        SupportedLanguage(code: "is", name: "Íslenska", flag: "🇮🇸", whisperCode: "is"),
        SupportedLanguage(code: "id", name: "Bahasa Indonesia", flag: "🇮🇩", whisperCode: "id"),
        SupportedLanguage(code: "kn", name: "ಕನ್ನಡ", flag: "🇮🇳", whisperCode: "kn"),
        SupportedLanguage(code: "kk", name: "Қазақша", flag: "🇰🇿", whisperCode: "kk"),
        SupportedLanguage(code: "lv", name: "Latviešu", flag: "🇱🇻", whisperCode: "lv"),
        SupportedLanguage(code: "lt", name: "Lietuvių", flag: "🇱🇹", whisperCode: "lt"),
        SupportedLanguage(code: "mk", name: "Македонски", flag: "🇲🇰", whisperCode: "mk"),
        SupportedLanguage(code: "ms", name: "Bahasa Melayu", flag: "🇲🇾", whisperCode: "ms"),
        SupportedLanguage(code: "mr", name: "मराठी", flag: "🇮🇳", whisperCode: "mr"),
        SupportedLanguage(code: "mi", name: "Te Reo Māori", flag: "🇳🇿", whisperCode: "mi"),
        SupportedLanguage(code: "ne", name: "नेपाली", flag: "🇳🇵", whisperCode: "ne"),
        SupportedLanguage(code: "no", name: "Norsk", flag: "🇳🇴", whisperCode: "no"),
        SupportedLanguage(code: "fa", name: "فارسی", flag: "🇮🇷", whisperCode: "fa"),
        SupportedLanguage(code: "pl", name: "Polski", flag: "🇵🇱", whisperCode: "pl"),
        SupportedLanguage(code: "ro", name: "Română", flag: "🇷🇴", whisperCode: "ro"),
        SupportedLanguage(code: "sr", name: "Српски", flag: "🇷🇸", whisperCode: "sr"),
        SupportedLanguage(code: "sk", name: "Slovenčina", flag: "🇸🇰", whisperCode: "sk"),
        SupportedLanguage(code: "sl", name: "Slovenščina", flag: "🇸🇮", whisperCode: "sl"),
        SupportedLanguage(code: "sw", name: "Kiswahili", flag: "🇰🇪", whisperCode: "sw"),
        SupportedLanguage(code: "sv", name: "Svenska", flag: "🇸🇪", whisperCode: "sv"),
        SupportedLanguage(code: "tl", name: "Filipino", flag: "🇵🇭", whisperCode: "tl"),
        SupportedLanguage(code: "ta", name: "தமிழ்", flag: "🇮🇳", whisperCode: "ta"),
        SupportedLanguage(code: "th", name: "ไทย", flag: "🇹🇭", whisperCode: "th"),
        SupportedLanguage(code: "uk", name: "Українська", flag: "🇺🇦", whisperCode: "uk"),
        SupportedLanguage(code: "ur", name: "اردو", flag: "🇵🇰", whisperCode: "ur"),
        SupportedLanguage(code: "vi", name: "Tiếng Việt", flag: "🇻🇳", whisperCode: "vi"),
        SupportedLanguage(code: "cy", name: "Cymraeg", flag: "🏴󐁧󐁢󐁷󐁬󐁳󐁿", whisperCode: "cy")
    ]
    
    static let popularLanguages: [SupportedLanguage] = Array(allLanguages.prefix(13))
    
    static func getLanguage(by code: String) -> SupportedLanguage? {
       return allLanguages.first { $0.code == code }
    }

    static func getLanguageByWhisperCode(_ whisperCode: String) -> SupportedLanguage? {
       return allLanguages.first { $0.whisperCode == whisperCode }
    }
}

// MARK: - Translation Direction
struct TranslationDirection: Identifiable, Hashable {
    let id = UUID()
    let sourceLanguage: SupportedLanguage
    let targetLanguage: SupportedLanguage
    
    var displayName: String {
        "\(sourceLanguage.flag) \(sourceLanguage.name) → \(targetLanguage.flag) \(targetLanguage.name)"
    }
    
    var shortDisplayName: String {
        "\(sourceLanguage.flag)→\(targetLanguage.flag)"
    }
}

// MARK: - Language Manager
@MainActor
class LanguageManager: ObservableObject {
    @Published var selectedDirection: TranslationDirection
    @Published var recentDirections: [TranslationDirection] = []
    @Published var favoriteDirections: [TranslationDirection] = []
    
    private let userDefaults = UserDefaults.standard
    private let recentDirectionsKey = "RecentTranslationDirections"
    private let favoriteDirectionsKey = "FavoriteTranslationDirections"
    private let selectedDirectionKey = "SelectedTranslationDirection"
    
    // Popüler çeviri yönleri
    static let popularDirections: [TranslationDirection] = [
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "en")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "tr")!
        ),
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "tr")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "en")!
        ),
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "es")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "en")!
        ),
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "fr")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "en")!
        ),
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "de")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "en")!
        ),
        TranslationDirection(
            sourceLanguage: SupportedLanguage.getLanguage(by: "zh")!,
            targetLanguage: SupportedLanguage.getLanguage(by: "en")!
        )
    ]
    
    init() {
        // Varsayılan olarak Türkçe'den İngilizce'ye
        let defaultSource = SupportedLanguage.getLanguage(by: "tr")!
        let defaultTarget = SupportedLanguage.getLanguage(by: "en")!
        self.selectedDirection = TranslationDirection(
            sourceLanguage: defaultSource,
            targetLanguage: defaultTarget
        )
        
        loadSavedDirections()
    }
    
    func setTranslationDirection(_ direction: TranslationDirection) {
        selectedDirection = direction
        addToRecentDirections(direction)
        saveSelectedDirection()
    }
    
    func swapLanguages() {
        let newDirection = TranslationDirection(
            sourceLanguage: selectedDirection.targetLanguage,
            targetLanguage: selectedDirection.sourceLanguage
        )
        setTranslationDirection(newDirection)
    }
    
    func addToFavorites(_ direction: TranslationDirection) {
        if !favoriteDirections.contains(where: { $0.sourceLanguage.code == direction.sourceLanguage.code && $0.targetLanguage.code == direction.targetLanguage.code }) {
            favoriteDirections.append(direction)
            saveFavoriteDirections()
        }
    }
    
    func removeFromFavorites(_ direction: TranslationDirection) {
        favoriteDirections.removeAll { $0.sourceLanguage.code == direction.sourceLanguage.code && $0.targetLanguage.code == direction.targetLanguage.code }
        saveFavoriteDirections()
    }
    
    func isFavorite(_ direction: TranslationDirection) -> Bool {
        return favoriteDirections.contains { $0.sourceLanguage.code == direction.sourceLanguage.code && $0.targetLanguage.code == direction.targetLanguage.code }
    }
    
    private func addToRecentDirections(_ direction: TranslationDirection) {
        // Aynı yön varsa kaldır
        recentDirections.removeAll { $0.sourceLanguage.code == direction.sourceLanguage.code && $0.targetLanguage.code == direction.targetLanguage.code }
        
        // En başa ekle
        recentDirections.insert(direction, at: 0)
        
        // Maksimum 10 tane tut
        if recentDirections.count > 10 {
            recentDirections = Array(recentDirections.prefix(10))
        }
        
        saveRecentDirections()
    }
    
    // MARK: - Persistence
    
    private func saveSelectedDirection() {
        let data = [
            "sourceCode": selectedDirection.sourceLanguage.code,
            "targetCode": selectedDirection.targetLanguage.code
        ]
        userDefaults.set(data, forKey: selectedDirectionKey)
    }
    
    private func saveRecentDirections() {
        let data = recentDirections.map { direction in
            [
                "sourceCode": direction.sourceLanguage.code,
                "targetCode": direction.targetLanguage.code
            ]
        }
        userDefaults.set(data, forKey: recentDirectionsKey)
    }
    
    private func saveFavoriteDirections() {
        let data = favoriteDirections.map { direction in
            [
                "sourceCode": direction.sourceLanguage.code,
                "targetCode": direction.targetLanguage.code
            ]
        }
        userDefaults.set(data, forKey: favoriteDirectionsKey)
    }
    
    private func loadSavedDirections() {
        // Load selected direction
        if let selectedData = userDefaults.object(forKey: selectedDirectionKey) as? [String: String],
           let sourceCode = selectedData["sourceCode"],
           let targetCode = selectedData["targetCode"],
           let sourceLanguage = SupportedLanguage.getLanguage(by: sourceCode),
           let targetLanguage = SupportedLanguage.getLanguage(by: targetCode) {
            selectedDirection = TranslationDirection(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
        
        // Load recent directions
        if let recentData = userDefaults.object(forKey: recentDirectionsKey) as? [[String: String]] {
            recentDirections = recentData.compactMap { data in
                guard let sourceCode = data["sourceCode"],
                      let targetCode = data["targetCode"],
                      let sourceLanguage = SupportedLanguage.getLanguage(by: sourceCode),
                      let targetLanguage = SupportedLanguage.getLanguage(by: targetCode) else {
                    return nil
                }
                return TranslationDirection(
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            }
        }
        
        // Load favorite directions
        if let favoriteData = userDefaults.object(forKey: favoriteDirectionsKey) as? [[String: String]] {
            favoriteDirections = favoriteData.compactMap { data in
                guard let sourceCode = data["sourceCode"],
                      let targetCode = data["targetCode"],
                      let sourceLanguage = SupportedLanguage.getLanguage(by: sourceCode),
                      let targetLanguage = SupportedLanguage.getLanguage(by: targetCode) else {
                    return nil
                }
                return TranslationDirection(
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            }
        }
    }
}
