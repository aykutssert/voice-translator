import SwiftUI
import AVFoundation
import Foundation
import FirebaseAuth
import Network

// MARK: - Simplified Network Manager
@MainActor
class NetworkManager: NSObject, ObservableObject {
    private var session: URLSession
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var connected = false
    @Published var sourceResult = ""
    @Published var targetResult = ""
    @Published var processing = false
    @Published var connectionStatus = "Disconnected"
    @Published var lastActivity: Date = Date()
    @Published var userCredits: UserCredits?
    @Published var hasInternet = false
    @Published var currentTranslationDirection: TranslationDirection?
    
    // Configuration
    private let requestTimeout: TimeInterval = 30.0
    private let maxRetryAttempts = 3
    private let maxRecordingDurationMinutes = 2.0
    
    override init() {
        // URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 45.0
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.networkServiceType = .responsiveData
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        
        self.session = URLSession(configuration: config)
        
        super.init()
        
        startNetworkMonitoring()
        setupAppLifecycleObservers()
        performInitialServerCheck()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        networkMonitor.cancel()
        session.invalidateAndCancel()
    }
    
    func setTranslationDirection(_ direction: TranslationDirection) {
        currentTranslationDirection = direction
        sourceResult = ""
        targetResult = ""
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasInternet = path.status == .satisfied
                self?.updateConnectionStatus(path.status == .satisfied ? "Internet Available" : "No Internet")
                print("📶 Internet status: \(path.status == .satisfied ? "Available" : "Unavailable")")
            }
        }
        networkMonitor.start(queue: monitorQueue)
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
    }
    
    @objc private func appWillEnterForeground() {
        print("📱 App entered foreground")
        updateLastActivity()
        performServerCheck()
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entered background")
        updateConnectionStatus("Background Mode")
    }
    
    private func performInitialServerCheck() {
        Task {
            await checkConnectionAndServer()
        }
    }
    
    private func performServerCheck() {
        Task {
            await checkConnectionAndServer()
        }
    }
    
    // MARK: - Simple Connection Check (Only for App Start + Background Return)
    
    func checkConnectionAndServer() async -> Bool {
        print("🔍 Checking server connection...")
        
        // hasInternet kontrolü kaldır - direkt server'ı dene
        do {
            let serverURL = URL(string: "http://\(getServerIP())/health")!
            var request = URLRequest(url: serverURL)
            request.timeoutInterval = 5.0
            request.cachePolicy = .reloadIgnoringCacheData
            
            let (_, response) = try await session.data(for: request)
            
            let isHealthy = (response as? HTTPURLResponse)?.statusCode == 200
            
            await MainActor.run {
                connected = isHealthy
                updateConnectionStatus(isHealthy ? "Connected" : "Server Unavailable")
                print("✅ Server check completed - connected: \(connected)")
            }
            
            return isHealthy
            
        } catch {
            await MainActor.run {
                connected = false
                updateConnectionStatus("Server Unreachable")
                print("❌ Server check failed - connected: \(connected)")
            }
            return false
        }
    }
    // MARK: - Audio Transmission (Direct Send - Error on Server Down)
    
    func transmitAudio(_ data: Data) {
        guard let direction = currentTranslationDirection else {
            print("❌ No translation direction set")
            return
        }
        
        processing = true
        
        Task {
            // Quick duration check
            let estimatedDuration = estimateAudioDuration(data)
            if estimatedDuration > maxRecordingDurationMinutes {
                await handleTranslationError("Recording too long. Maximum duration is \(Int(maxRecordingDurationMinutes)) minutes.")
                return
            }
            
            // Direct transmission - no pre-checks
            await performAudioTranslation(data, direction: direction)
        }
    }
    
    private func estimateAudioDuration(_ audioData: Data) -> Double {
        // Estimation: 44.1kHz, 16-bit, mono = 88200 bytes per second
        let estimatedSeconds = Double(audioData.count) / 88200.0
        return estimatedSeconds / 60.0 // Minutes
    }
    
    private func performAudioTranslation(_ audioData: Data, direction: TranslationDirection) async {
        let encodedAudio = audioData.base64EncodedString()
        let userId = Auth.auth().currentUser?.uid ?? "anonymous"
        
        let requestBody = [
            "audio_base64": encodedAudio,
            "user_id": userId,
            "source_language": direction.sourceLanguage.whisperCode,
            "target_language": direction.targetLanguage.whisperCode,
            "source_language_name": direction.sourceLanguage.name,
            "target_language_name": direction.targetLanguage.name
        ]
        
        for attempt in 1...maxRetryAttempts {
            do {
                print("🔄 Translation attempt \(attempt)/\(maxRetryAttempts)")
                print("🌍 Translating: \(direction.sourceLanguage.name) → \(direction.targetLanguage.name)")
                
                let serverURL = URL(string: "http://\(getServerIP())/api/translate")!
                var request = URLRequest(url: serverURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                request.timeoutInterval = requestTimeout
                request.cachePolicy = .reloadIgnoringCacheData
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    
                    await processTranslationResponse(data, direction: direction)
                    return // Success, exit retry loop
                    
                } else if let httpResponse = response as? HTTPURLResponse {
                    let errorMessage = "Server error: \(httpResponse.statusCode)"
                    print("❌ \(errorMessage)")
                    
                    if attempt == maxRetryAttempts {
                        if httpResponse.statusCode == 0 || httpResponse.statusCode >= 500 {
                            await handleTranslationError("Translation server is not available. Please try again later.")
                        } else if httpResponse.statusCode == 402 {
                            await handleTranslationError("Insufficient credits. Please purchase a premium package.")
                        } else {
                            await handleTranslationError(errorMessage)
                        }
                    }
                } else {
                    throw URLError(.badServerResponse)
                }
                
            } catch {
                print("❌ Translation attempt \(attempt) failed: \(error)")
                
                if attempt == maxRetryAttempts {
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .cannotConnectToHost, .cannotFindHost:
                            await handleTranslationError("Cannot connect to translation server. Please check your connection and try again.")
                        case .timedOut:
                            await handleTranslationError("Translation server is not responding. Please try again later.")
                        default:
                            await handleTranslationError(getUserFriendlyError(error))
                        }
                    } else {
                        await handleTranslationError("Network error: \(error.localizedDescription)")
                    }
                } else {
                    // Exponential backoff for retries
                    let delay = min(Double(attempt * 2), 5.0) // Max 5 seconds
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }
    
    private func getUserFriendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection. Please check your network and try again."
            case .timedOut:
                return "Server is not responding. Please try again later."
            case .cannotFindHost, .cannotConnectToHost:
                return "Cannot reach translation server. Please check your connection."
            default:
                return "Connection failed. Please try again."
            }
        }
        return "Translation failed. Please try again."
    }
    
    private func processTranslationResponse(_ data: Data, direction: TranslationDirection) async {
        do {
            let responseData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Handle error responses
            if let error = responseData?["error"] as? String {
                await handleTranslationError("Translation error: \(error)")
                return
            }
            
            // Update user credits
            if let creditsData = responseData?["user_credits"] as? [String: Any] {
                updateUserCredits(from: creditsData)
            }
            
            // Extract translation results
            let sourceText = responseData?["source_text"] as? String ?? ""
            let targetText = responseData?["target_text"] as? String ?? ""
            let duration = responseData?["duration_minutes"] as? Double ?? 0.0
            let creditsUsed = responseData?["credits_used"] as? Double ?? 0.0
            
            if !sourceText.isEmpty || !targetText.isEmpty {
                sourceResult = sourceText
                targetResult = targetText
                updateLastActivity()
                
                print("✅ Translation completed")
                print("📝 \(direction.sourceLanguage.name): \(sourceText)")
                print("📝 \(direction.targetLanguage.name): \(targetText)")
                print("⏱️ Duration: \(String(format: "%.1f", duration * 60))s")
                print("💎 Credits used: \(String(format: "%.3f", creditsUsed))")
            }
            
            processing = false
            
        } catch {
            await handleTranslationError("Failed to parse response: \(error.localizedDescription)")
        }
    }
    
    private func handleTranslationError(_ errorMessage: String) async {
        processing = false
        sourceResult = ""
        targetResult = "Error: \(errorMessage)"
        print("❌ Translation error: \(errorMessage)")
    }
    
    // MARK: - Credits Management
    
    func fetchUserCredits() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user")
            return
        }
        guard hasInternet else {
            print("⚠️ No internet for credits fetch")
            return
        }
        
        do {
            let serverURL = URL(string: "http://\(getServerIP())/api/credits/\(userId)")!
            var request = URLRequest(url: serverURL)
            request.timeoutInterval = 10.0
            request.cachePolicy = .reloadIgnoringCacheData
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                let creditsData = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                if let creditsData = creditsData {
                    updateUserCredits(from: creditsData)
                    print("✅ User credits fetched successfully")
                }
            } else {
                print("❌ Failed to fetch credits: Invalid response")
            }
            
        } catch {
            print("❌ Failed to fetch credits: \(error)")
        }
    }
    
    private func updateUserCredits(from data: [String: Any]) {
        let credits = UserCredits(
            userId: data["user_id"] as? String ?? "",
            isAdmin: data["is_admin"] as? Bool ?? false,
            isPremium: data["is_premium"] as? Bool ?? false,
            isUnlimited: data["is_unlimited"] as? Bool ?? false,
            remainingMinutes: data["remaining_minutes"] as? Double ?? 0.0,
            totalPurchasedMinutes: data["total_purchased_minutes"] as? Double ?? 0.0,
            usedMinutes: data["used_minutes"] as? Double ?? 0.0,
            subscriptionType: data["subscription_type"] as? String,
            subscriptionExpiry: data["subscription_expiry"] as? String
        )
        userCredits = credits
    }
    
    // MARK: - Utilities
    
    private func getServerIP() -> String {
        #if targetEnvironment(simulator)
            return "127.0.0.1:8000"
        #else
            //return "voice-translator-2jaq.onrender.com"
            return "192.168.1.105:8000" // Replace with your actual server IP
        #endif
    }
    
    private func updateConnectionStatus(_ status: String) {
        connectionStatus = status
    }
    
    private func updateLastActivity() {
        lastActivity = Date()
    }
    
    // MARK: - Simple Connection State
    
    var connectionDisplayText: String {
        if !hasInternet {
            return "No Internet"
        } else {
            return "Ready"
        }
    }
}
