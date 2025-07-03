import SwiftUI
import StoreKit

// MARK: - Premium Credits View
struct PremiumCreditsView: View {
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var premiumManager: PremiumManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
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
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gold)
                            
                            Text("Premium Packages")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Unlock unlimited translations")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 40)
                        
                        // Current Status
                        if let credits = networkManager.userCredits {
                            currentStatusSection(credits)
                        }
                        
                        // Features Section
                        featuresSection
                        
                        // Package Selection
                        if let credits = networkManager.userCredits, !credits.isUnlimited {
                            packageSelectionSection
                        }
                        
                        // Testimonials
                        testimonialsSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Restore") {
                        Task {
                            await premiumManager.restorePurchases()
                        }
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 14))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                await networkManager.fetchUserCredits()
                await premiumManager.loadProducts()
            }
        }
        .alert("Purchase Error", isPresented: $premiumManager.showError) {
            Button("OK") { }
        } message: {
            Text(premiumManager.errorMessage)
        }
        .alert("Purchase Successful!", isPresented: $premiumManager.showPurchaseSuccess) {
            Button("Great!") { }
        } message: {
            if let package = premiumManager.lastPurchasedPackage {
                Text("Successfully purchased \(package.title)! You now have \(package.minutes == -1 ? "unlimited" : "\(package.minutes) minutes") of translation.")
            }
        }
    }
    
    // MARK: - Current Status Section
    
    @ViewBuilder
    private func currentStatusSection(_ credits: UserCredits) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: credits.isUnlimited ? "infinity.circle.fill" :
                          credits.isAdmin ? "crown.fill" : "clock.fill")
                        .foregroundColor(credits.statusColor)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(credits.statusText)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(credits.formattedRemainingTime)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    if !credits.isUnlimited && !credits.isAdmin {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Used")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("\(String(format: "%.1f", credits.usedMinutes))m")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                
                // Progress bar for non-unlimited users
                if !credits.isUnlimited && !credits.isAdmin {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(height: 6)
                            
                            Rectangle()
                                .fill(credits.statusColor)
                                .frame(width: progressWidth(geometry.size.width, credits: credits), height: 6)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(credits.statusColor.opacity(0.3), lineWidth: 2)
                    )
            )
            
            // Usage Tips
            if !credits.isUnlimited {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text("💡 Pro Tips")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        tipRow("🎯", "Speak clearly for better accuracy")
                        tipRow("⏱️", "Shorter recordings use fewer credits")
                        tipRow("🔄", "Avoid repeating the same translation")
                        tipRow("🌟", "Premium users get priority processing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.yellow.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Why Go Premium?")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                FeatureCard(
                    icon: "globe",
                    title: "50+ Languages",
                    description: "Support for all major world languages",
                    color: .blue
                )
                
                FeatureCard(
                    icon: "bolt.fill",
                    title: "Fast Processing",
                    description: "Priority server access for instant results",
                    color: .orange
                )
                
                FeatureCard(
                    icon: "speaker.wave.3.fill",
                    title: "High Quality",
                    description: "Crystal clear transcription and translation",
                    color: .green
                )
                
                FeatureCard(
                    icon: "infinity",
                    title: "Unlimited Use",
                    description: "No limits with premium packages",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Package Selection Section
    
    private var packageSelectionSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Choose Your Package")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            if premiumManager.isLoading && premiumManager.products.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text("Loading packages...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding()
            } else if premiumManager.hasLoadingError || premiumManager.products.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange.opacity(0.7))
                    
                    Text("Unable to load packages")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Please check your connection and try again")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Button("Retry") {
                        Task { await premiumManager.loadProducts() }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.orange.opacity(0.8))
                    )
                }
                .padding()
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(PremiumPackage.allCases, id: \.rawValue) { package in
                        if let product = premiumManager.getProduct(for: package) {
                            PremiumPackageCard(
                                package: package,
                                product: product,
                                premiumManager: premiumManager,
                                isLoading: premiumManager.isLoading
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Testimonials Section
    
    private var testimonialsSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("What Users Say")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    TestimonialCard(
                        name: "Sarah K.",
                        role: "Business Traveler",
                        content: "Amazing app! Saved me countless times during international meetings.",
                        rating: 5
                    )
                    
                    TestimonialCard(
                        name: "Miguel R.",
                        role: "Language Student",
                        content: "The accuracy is incredible. Perfect for practicing conversations.",
                        rating: 5
                    )
                    
                    TestimonialCard(
                        name: "Li W.",
                        role: "Tour Guide",
                        content: "Essential tool for my work. The unlimited plan is worth every penny.",
                        rating: 5
                    )
                }
                .padding(.horizontal, 22)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func progressWidth(_ totalWidth: CGFloat, credits: UserCredits) -> CGFloat {
        let maxMinutes = max(credits.totalPurchasedMinutes + 30, 100.0) // Include free minutes
        let progress = max(credits.remainingMinutes / maxMinutes, 0.02) // Minimum 2%
        return totalWidth * progress
    }
    
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
}

// MARK: - Feature Card Component
struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Premium Package Card Component
struct PremiumPackageCard: View {
    let package: PremiumPackage
    let product: Product
    let premiumManager: PremiumManager
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with tag
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(package.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        if let tag = package.tag {
                            Text(tag)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(package.accentColor)
                                )
                        }
                    }
                    
                    Text(package.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if package.savings > 0 {
                        Text("Save \(package.savings)%")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Features list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(package.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Text(feature)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                }
            }
            
            // Purchase button
            Button(action: {
                Task {
                    await premiumManager.purchase(product)
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text(isLoading ? "Processing..." : "Purchase \(package.title)")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(package.accentColor)
                )
            }
            .disabled(isLoading || premiumManager.isPurchased(package))
            
            if premiumManager.isPurchased(package) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Purchased")
                        .font(.caption)
                        .foregroundColor(.green)
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
                        .stroke(package.accentColor.opacity(0.3), lineWidth: package.tag != nil ? 2 : 1)
                )
        )
    }
}

// MARK: - Testimonial Card Component
struct TestimonialCard: View {
    let name: String
    let role: String
    let content: String
    let rating: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(0..<rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }
            
            Text("\"\(content)\"")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .italic()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(role)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
