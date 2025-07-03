/*import Firebase
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices
import UIKit

@MainActor
class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var showError = false
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    override init() {
        super.init()
        checkAuthState()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    
    private func checkAuthState() {
        guard FirebaseApp.app() != nil else {
                print("❌ Firebase not initialized")
                return
            }
        
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                
                if let user = user {
                    await self?.trackUserSession(userId: user.uid)
                }
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signUpWithEmail(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            showErrorMessage("Please fill in all fields")
            return
        }
        
        guard isValidEmail(email) else {
            showErrorMessage("Please enter a valid email address")
            return
        }
        
        guard password.count >= 6 else {
            showErrorMessage("Password must be at least 6 characters")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("✅ Email sign-up successful for: \(result.user.email ?? "Unknown")")
            
            // Send email verification
            try await result.user.sendEmailVerification()
            showErrorMessage("Verification email sent! Please check your inbox.")
            
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    func signInWithEmail(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            showErrorMessage("Please fill in all fields")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("✅ Email sign-in successful for: \(result.user.email ?? "Unknown")")
            
            if !result.user.isEmailVerified {
                showErrorMessage("Please verify your email address before continuing")
            }
            
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    func resetPassword(email: String) async {
        guard !email.isEmpty else {
            showErrorMessage("Please enter your email address")
            return
        }
        
        guard isValidEmail(email) else {
            showErrorMessage("Please enter a valid email address")
            return
        }
        
        isLoading = true
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            showErrorMessage("Password reset email sent! Check your inbox.")
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Google Sign In
    
    func signInWithGoogle() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let presentingViewController = windowScene.windows.first?.rootViewController else {
            showErrorMessage("Unable to present sign-in interface")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                showErrorMessage("Google sign-in failed")
                isLoading = false
                return
            }
            
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            
            try await Auth.auth().signIn(with: credential)
            print("✅ Google sign-in successful")
            
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Apple Sign In
    
    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - Anonymous Sign In
    
    func signInAnonymously() async {
        isLoading = true
        
        do {
            try await Auth.auth().signInAnonymously()
            print("✅ Anonymous sign-in successful")
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            print("✅ Sign out successful")
        } catch let error as NSError {
            handleAuthError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func trackUserSession(userId: String) async {
        print("📊 Session tracked for user: \(userId)")
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func handleAuthError(_ error: NSError) {
        let errorMessage: String
        
        switch error.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            errorMessage = "This email is already registered"
        case AuthErrorCode.invalidEmail.rawValue:
            errorMessage = "Invalid email address"
        case AuthErrorCode.weakPassword.rawValue:
            errorMessage = "Password is too weak"
        case AuthErrorCode.userNotFound.rawValue:
            errorMessage = "No account found with this email"
        case AuthErrorCode.wrongPassword.rawValue:
            errorMessage = "Incorrect password"
        case AuthErrorCode.userDisabled.rawValue:
            errorMessage = "This account has been disabled"
        case AuthErrorCode.tooManyRequests.rawValue:
            errorMessage = "Too many attempts. Please try again later"
        case AuthErrorCode.networkError.rawValue:
            errorMessage = "Network error. Please check your connection"
        default:
            errorMessage = "Authentication failed: \(error.localizedDescription)"
        }
        
        showErrorMessage(errorMessage)
        print("❌ Auth error: \(errorMessage)")
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Apple Sign In Delegates

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let nonce = "random-nonce-\(UUID().uuidString)"
            
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                showErrorMessage("Apple sign-in failed")
                return
            }
            
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce
            )
            
            Task { @MainActor in
                isLoading = true
                do {
                    try await Auth.auth().signIn(with: credential)
                    print("✅ Apple sign-in successful")
                } catch let error as NSError {
                    handleAuthError(error)
                }
                isLoading = false
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let error = error as? ASAuthorizationError {
            switch error.code {
            case .canceled:
                print("ℹ️ Apple sign-in canceled by user")
            case .failed:
                showErrorMessage("Apple sign-in failed")
            case .invalidResponse:
                showErrorMessage("Invalid response from Apple")
            case .notHandled:
                showErrorMessage("Apple sign-in not handled")
            case .unknown:
                showErrorMessage("Unknown Apple sign-in error")
            @unknown default:
                showErrorMessage("Apple sign-in error")
            }
        }
        isLoading = false
    }
}

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
*/

import Firebase
import FirebaseAuth
import FirebaseFirestore
import UIKit

@MainActor
class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var showError = false
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    override init() {
        super.init()
        checkAuthState()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    private func checkAuthState() {
        guard FirebaseApp.app() != nil else {
            print("❌ Firebase not initialized")
            return
        }
        
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                
                if let user = user {
                    await self?.trackUserSession(userId: user.uid)
                }
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signUpWithEmail(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            showErrorMessage("Please fill in all fields")
            return
        }
        
        guard isValidEmail(email) else {
            showErrorMessage("Please enter a valid email address")
            return
        }
        
        guard password.count >= 6 else {
            showErrorMessage("Password must be at least 6 characters")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("✅ Email sign-up successful: \(result.user.email ?? "Unknown")")
            
            // Send email verification
            try await result.user.sendEmailVerification()
            showErrorMessage("Verification email sent! Please check your inbox.")
            
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    func signInWithEmail(email: String, password: String) async {
        guard !email.isEmpty, !password.isEmpty else {
            showErrorMessage("Please fill in all fields")
            return
        }
        
        isLoading = true
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("✅ Email sign-in successful: \(result.user.email ?? "Unknown")")
            
            if !result.user.isEmailVerified {
                showErrorMessage("Please verify your email address before continuing")
            }
            
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    func resetPassword(email: String) async {
        guard !email.isEmpty else {
            showErrorMessage("Please enter your email address")
            return
        }
        
        guard isValidEmail(email) else {
            showErrorMessage("Please enter a valid email address")
            return
        }
        
        isLoading = true
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            showErrorMessage("Password reset email sent! Check your inbox.")
        } catch let error as NSError {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            print("✅ Sign out successful")
        } catch let error as NSError {
            handleAuthError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func trackUserSession(userId: String) async {
        print("📊 Session tracked for user: \(userId)")
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func handleAuthError(_ error: NSError) {
        let errorMessage: String
        
        switch error.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            errorMessage = "This email is already registered"
        case AuthErrorCode.invalidEmail.rawValue:
            errorMessage = "Invalid email address"
        case AuthErrorCode.weakPassword.rawValue:
            errorMessage = "Password is too weak"
        case AuthErrorCode.userNotFound.rawValue:
            errorMessage = "No account found with this email"
        case AuthErrorCode.wrongPassword.rawValue:
            errorMessage = "Incorrect password"
        case AuthErrorCode.userDisabled.rawValue:
            errorMessage = "This account has been disabled"
        case AuthErrorCode.tooManyRequests.rawValue:
            errorMessage = "Too many attempts. Please try again later"
        case AuthErrorCode.networkError.rawValue:
            errorMessage = "Network error. Please check your connection"
        default:
            errorMessage = "Authentication failed: \(error.localizedDescription)"
        }
        
        showErrorMessage(errorMessage)
        print("❌ Auth error: \(errorMessage)")
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}
