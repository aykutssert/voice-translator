import StoreKit
import SwiftUI
import FirebaseAuth

// MARK: - Premium Package Types
enum PremiumPackage: String, CaseIterable {
    case starter = "com.voicetranslator.starter"
    case popular = "com.voicetranslator.popular"
    case professional = "com.voicetranslator.professional"
    case unlimited = "com.voicetranslator.unlimited"
    
    var minutes: Int {
        switch self {
        case .starter: return 300      // 5 saat
        case .popular: return 900      // 15 saat
        case .professional: return 1800 // 30 saat
        case .unlimited: return -1     // Sınırsız
        }
    }
    
    var price: Double {
        switch self {
        case .starter: return 9.99
        case .popular: return 24.99
        case .professional: return 49.99
        case .unlimited: return 99.99
        }
    }
    
    var title: String {
        switch self {
        case .starter: return "Starter Pack"
        case .popular: return "Popular Pack"
        case .professional: return "Professional Pack"
        case .unlimited: return "Unlimited Pack"
        }
    }
    
    var description: String {
        switch self {
        case .starter: return "5 hours of translation\nGreat for occasional use"
        case .popular: return "15 hours of translation\nPerfect for regular users"
        case .professional: return "30 hours of translation\nIdeal for professionals"
        case .unlimited: return "Unlimited translations\n+ Priority support"
        }
    }
    
    var features: [String] {
        switch self {
        case .starter:
            return [
                "5 hours of translation",
                "All language pairs",
                "High-quality transcription",
                "Basic support"
            ]
        case .popular:
            return [
                "15 hours of translation",
                "All language pairs",
                "High-quality transcription",
                "Priority support",
                "Export transcripts"
            ]
        case .professional:
            return [
                "30 hours of translation",
                "All language pairs",
                "High-quality transcription",
                "Priority support",
                "Export transcripts",
                "Batch processing"
            ]
        case .unlimited:
            return [
                "Unlimited translations",
                "All language pairs",
                "Highest quality transcription",
                "Premium support",
                "Export transcripts",
                "Batch processing",
                "Advanced features"
            ]
        }
    }
    
    var tag: String? {
        switch self {
        case .popular: return "MOST POPULAR"
        case .professional: return "BEST VALUE"
        case .unlimited: return "PREMIUM"
        default: return nil
        }
    }
    
    var accentColor: Color {
        switch self {
        case .starter: return .blue
        case .popular: return .orange
        case .professional: return .purple
        case .unlimited: return .gold
        }
    }
    
    var pricePerMinute: Double {
        if minutes == -1 { return 0.0 } // Unlimited
        return price / Double(minutes)
    }
    
    var savings: Int {
        let basePrice = 0.033 // $9.99 for 300 minutes = $0.033 per minute
        if minutes == -1 { return 100 } // Unlimited = 100% value
        let currentPrice = pricePerMinute
        let savingsPercent = ((basePrice - currentPrice) / basePrice) * 100
        return max(0, Int(savingsPercent))
    }
}


// MARK: - Premium Manager
@MainActor
class PremiumManager: NSObject, ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedProductIDs = Set<String>()
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var showError = false
    @Published var hasLoadingError = false
    @Published var showPurchaseSuccess = false
    @Published var lastPurchasedPackage: PremiumPackage?
    
    private var networkManager: NetworkManager?
    private var updateListenerTask: Task<Void, Error>?
    
    override init() {
        super.init()
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func setNetworkManager(_ manager: NetworkManager) {
        self.networkManager = manager
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        isLoading = true
        hasLoadingError = false
        
        do {
            let products = try await Product.products(for: PremiumPackage.allCases.map { $0.rawValue })
            
            await MainActor.run {
                self.products = products.sorted { product1, product2 in
                    let package1 = PremiumPackage(rawValue: product1.id)
                    let package2 = PremiumPackage(rawValue: product2.id)
                    
                    guard let pkg1 = package1, let pkg2 = package2 else { return false }
                    return pkg1.price < pkg2.price
                }
                self.isLoading = false
                self.hasLoadingError = products.isEmpty
            }
            
            print("✅ Loaded \(products.count) premium products")
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.hasLoadingError = true
                self.showErrorMessage("Failed to load products: \(error.localizedDescription)")
            }
            print("❌ Failed to load products: \(error)")
        }
    }
    
    func updatePurchasedProducts() async {
        var purchasedIDs = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedIDs.insert(transaction.productID)
            }
        }
        
        await MainActor.run {
            self.purchasedProductIDs = purchasedIDs
        }
    }
    
    // MARK: - Purchase Logic
    
    func purchase(_ product: Product) async {
        print("💳 Purchase started: \(product.id)")
        
        isLoading = true
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await handleSuccessfulPurchase(transaction)
                case .unverified:
                    showErrorMessage("Purchase could not be verified")
                }
            case .userCancelled:
                print("ℹ️ Purchase cancelled by user")
            case .pending:
                showErrorMessage("Purchase is pending approval")
            @unknown default:
                showErrorMessage("Unknown purchase result")
            }
            
        } catch {
            print("❌ Purchase failed: \(error)")
            showErrorMessage("Purchase failed: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    private func handleSuccessfulPurchase(_ transaction: StoreKit.Transaction) async {
        print("✅ Purchase successful: \(transaction.productID)")
        
        guard let package = PremiumPackage(rawValue: transaction.productID) else {
            print("⚠️ Unknown product purchased: \(transaction.productID)")
            return
        }
        
        await MainActor.run {
            self.lastPurchasedPackage = package
            self.showPurchaseSuccess = true
        }
        
        // Finish transaction
        await transaction.finish()
        
        // Update purchased products
        await updatePurchasedProducts()
        
        // Add credits to server
        await addCreditsToServer(for: package, transactionID: UInt64(transaction.id))
        
        // Refresh user credits
        await networkManager?.fetchUserCredits()
    }
    
    private func addCreditsToServer(for package: PremiumPackage, transactionID: UInt64) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No authenticated user for credit addition")
            return
        }
        
        let minutes = package.minutes
        
        print("💳 Adding credits: \(minutes == -1 ? "unlimited" : "\(minutes)") minutes for user \(userId)")
        
        do {
            let serverIP = getServerIP()
            let url = URL(string: "http://\(serverIP)/api/add-credits")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15.0
            
            let payload = [
                "user_id": userId,
                "product_id": package.rawValue,
                "transaction_id": String(transactionID),
                "minutes": minutes,
                "package_type": package.title
            ] as [String : Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = responseData["success"] as? Bool,
                   success {
                    print("✅ Credits added to server: \(minutes == -1 ? "unlimited" : "\(minutes)") minutes")
                } else {
                    print("❌ Server reported failure adding credits")
                }
            } else {
                print("❌ Failed to add credits to server - HTTP error")
            }
            
        } catch {
            print("❌ Server credit addition failed: \(error)")
        }
    }
    
    private func getServerIP() -> String {
        #if targetEnvironment(simulator)
        return "127.0.0.1"
        #else
        return "YOUR_AWS_SERVER_IP" // AWS sunucu IP'nizi buraya yazın
        #endif
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await self.handleSuccessfulPurchase(transaction)
                case .unverified:
                    print("⚠️ Unverified transaction received")
                }
            }
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async {
        isLoading = true
        
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            print("✅ Purchases restored")
        } catch {
            print("❌ Restore failed: \(error)")
            showErrorMessage("Failed to restore purchases: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    func getPackage(for productId: String) -> PremiumPackage? {
        return PremiumPackage(rawValue: productId)
    }
    
    func isPurchased(_ package: PremiumPackage) -> Bool {
        return purchasedProductIDs.contains(package.rawValue)
    }
    
    func hasActiveUnlimitedPlan() -> Bool {
        return isPurchased(.unlimited)
    }
    
    func getProduct(for package: PremiumPackage) -> Product? {
        return products.first { $0.id == package.rawValue }
    }
}

// MARK: - Free Credits Configuration
struct FreeCreditsConfig {
    static let initialMinutes = 30 // 30 dakika ücretsiz
    static let dailyBonus = 5      // Günlük 5 dakika bonus (reklam izleyerek)
    static let referralBonus = 60  // Arkadaş davet bonusu 1 saat
    static let socialShareBonus = 10 // Sosyal medya paylaşım bonusu
}

// MARK: - Usage Analytics
struct UsageMetrics {
    let averageSessionDuration: Double
    let totalTranslations: Int
    let favoriteLanguagePairs: [String]
    let peakUsageHours: [Int]
    let monthlyMinutesUsed: Double
    
    static let empty = UsageMetrics(
        averageSessionDuration: 0,
        totalTranslations: 0,
        favoriteLanguagePairs: [],
        peakUsageHours: [],
        monthlyMinutesUsed: 0
    )
}
