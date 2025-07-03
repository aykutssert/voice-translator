import Foundation
import SwiftUI

// MARK: - User Credits Model
struct UserCredits {
    let userId: String
    let isAdmin: Bool
    let isPremium: Bool
    let isUnlimited: Bool
    let remainingMinutes: Double
    let totalPurchasedMinutes: Double
    let usedMinutes: Double
    let subscriptionType: String?
    let subscriptionExpiry: String?
    
    var remainingHours: Double {
        remainingMinutes / 60.0
    }
    
    var formattedRemainingTime: String {
        if isUnlimited {
            return "Unlimited"
        } else if remainingMinutes >= 60 {
            return String(format: "%.1f hours", remainingHours)
        } else {
            return String(format: "%.1f minutes", remainingMinutes)
        }
    }
    
    var isLowOnCredits: Bool {
        !isUnlimited && !isAdmin && remainingMinutes < 10.0
    }
    
    var needsCredits: Bool {
        !isUnlimited && !isAdmin && remainingMinutes <= 0.0
    }
    
    var statusColor: Color {
        if isAdmin || isUnlimited {
            return .gold
        } else if needsCredits {
            return .red
        } else if isLowOnCredits {
            return .orange
        } else {
            return .green
        }
    }
    
    var statusText: String {
        if isAdmin {
            return "Admin Account"
        } else if isUnlimited {
            return "Unlimited Plan"
        } else if isPremium {
            return "Premium User"
        } else {
            return "Free User"
        }
    }
}

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}
