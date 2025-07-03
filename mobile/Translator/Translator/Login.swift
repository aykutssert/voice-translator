/*import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUpMode = false
    @State private var showingForgotPassword = false
    @State private var resetEmail = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password, confirmPassword
    }
    
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
                    VStack(spacing: 40) {
                        Spacer(minLength: 60)
                        
                        // App Header
                        VStack(spacing: 20) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                                .symbolEffect(.pulse.byLayer)
                            
                            Text("Voice Translator")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Real-time voice translation")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // Email/Password Form
                        VStack(spacing: 20) {
                            VStack(spacing: 16) {
                                // Email Field
                                textFieldContainer {
                                    HStack {
                                        Image(systemName: "envelope")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        TextField("Email", text: $email)
                                            .focused($focusedField, equals: .email)
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                            .foregroundColor(.white)
                                            .submitLabel(.next)
                                            .onSubmit {
                                                focusedField = .password
                                            }
                                            .placeholder(when: email.isEmpty) {
                                                Text("Email").foregroundColor(.white.opacity(0.6))
                                            }
                                    }
                                }
                                
                                // Password Field
                                textFieldContainer {
                                    HStack {
                                        Image(systemName: "lock")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        SecureField("Password", text: $password)
                                            .focused($focusedField, equals: .password)
                                            .foregroundColor(.white)
                                            .submitLabel(isSignUpMode ? .next : .done)
                                            .onSubmit {
                                                if isSignUpMode {
                                                    focusedField = .confirmPassword
                                                } else {
                                                    focusedField = nil
                                                    handleEmailPasswordAction()
                                                }
                                            }
                                            .placeholder(when: password.isEmpty) {
                                                Text("Password").foregroundColor(.white.opacity(0.6))
                                            }
                                    }
                                }
                                
                                // Confirm Password (Sign Up only)
                                if isSignUpMode {
                                    textFieldContainer {
                                        HStack {
                                            Image(systemName: "lock.fill")
                                                .foregroundColor(.white.opacity(0.7))
                                                .frame(width: 20)
                                            
                                            SecureField("Confirm Password", text: $confirmPassword)
                                                .focused($focusedField, equals: .confirmPassword)
                                                .foregroundColor(.white)
                                                .submitLabel(.done)
                                                .onSubmit {
                                                    focusedField = nil
                                                    handleEmailPasswordAction()
                                                }
                                                .placeholder(when: confirmPassword.isEmpty) {
                                                    Text("Confirm Password").foregroundColor(.white.opacity(0.6))
                                                }
                                        }
                                    }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            
                            // Email/Password Action Button
                            Button(action: handleEmailPasswordAction) {
                                HStack {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(isSignUpMode ? "Create Account" : "Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.1, green: 0.4, blue: 0.9))
                                )
                            }
                            .disabled(authManager.isLoading || !isValidForm)
                            .opacity(isValidForm ? 1.0 : 0.6)
                            
                            // Toggle Sign In/Sign Up
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isSignUpMode.toggle()
                                    clearForm()
                                    focusedField = nil
                                }
                            }) {
                                Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            // Forgot Password (Sign In only)
                            if !isSignUpMode {
                                Button(action: {
                                    focusedField = nil
                                    showingForgotPassword = true
                                }) {
                                    Text("Forgot Password?")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .underline()
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(.white.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("or")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                            
                            Rectangle()
                                .fill(.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 32)
                        
                        // Social Login Buttons
                        VStack(spacing: 16) {
                            // Google Sign In
                            Button(action: {
                                focusedField = nil
                                Task { await authManager.signInWithGoogle() }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.title2)
                                    Text("Continue with Google")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white)
                                )
                            }
                            .disabled(authManager.isLoading)
                            
                            // Apple Sign In
                            Button(action: {
                                focusedField = nil
                                authManager.signInWithApple()
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "applelogo")
                                        .font(.title2)
                                    Text("Continue with Apple")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.black)
                                )
                            }
                            .disabled(authManager.isLoading)
                            
                            // Anonymous Access
                            Button(action: {
                                focusedField = nil
                                Task { await authManager.signInAnonymously() }
                            }) {
                                Text("Try without account")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .underline()
                            }
                            .disabled(authManager.isLoading)
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .keyboardAdaptive()
            }
            .alert("Message", isPresented: $authManager.showError) {
                Button("OK") {
                    authManager.showError = false
                }
            } message: {
                Text(authManager.errorMessage)
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView(authManager: authManager)
            }
            .onTapGesture {
                focusedField = nil
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func textFieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            )
    }
    
    // MARK: - Helper Methods
    
    private var isValidForm: Bool {
        if isSignUpMode {
            return !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword && password.count >= 6
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func handleEmailPasswordAction() {
        focusedField = nil
        Task {
            if isSignUpMode {
                await authManager.signUpWithEmail(email: email, password: password)
            } else {
                await authManager.signInWithEmail(email: email, password: password)
            }
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
    }
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                // Same background gradient
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
                
                VStack(spacing: 30) {
                    VStack(spacing: 16) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Reset Password")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Enter your email address and we'll send you a link to reset your password")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 20) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 20)
                            
                            TextField("Email", text: $email)
                                .focused($isEmailFocused)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .submitLabel(.send)
                                .onSubmit {
                                    if !email.isEmpty {
                                        sendResetEmail()
                                    }
                                }
                                .placeholder(when: email.isEmpty) {
                                    Text("Email").foregroundColor(.white.opacity(0.6))
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                        
                        Button(action: sendResetEmail) {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                
                                Text("Send Reset Link")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.1, green: 0.4, blue: 0.9))
                            )
                        }
                        .disabled(authManager.isLoading || email.isEmpty)
                        .opacity(email.isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .padding(.top, 60)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEmailFocused = false
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onTapGesture {
                isEmailFocused = false
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }
    
    private func sendResetEmail() {
        isEmailFocused = false
        Task {
            await authManager.resetPassword(email: email)
            dismiss()
        }
    }
}

// MARK: - Keyboard Adaptive Extension

extension View {
    func keyboardAdaptive() -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            // Keyboard responsive behavior can be added here if needed
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            // Keyboard hide behavior can be added here if needed
        }
    }
}

// MARK: - View Extension for Placeholder

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
*/

import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUpMode = false
    @State private var showingForgotPassword = false
    @State private var resetEmail = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password, confirmPassword
    }
    
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
                    VStack(spacing: 40) {
                        Spacer(minLength: 60)
                        
                        // App Header
                        VStack(spacing: 20) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.white)
                                .symbolEffect(.pulse.byLayer)
                            
                            Text("Voice Translator")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Real-time voice translation")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // Free Trial Banner
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "gift.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("🎉 Free Trial!")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("30 minutes free + Multi-language support")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Spacer()
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.green.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.green.opacity(0.5), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 32)
                        
                        // Email/Password Form
                        VStack(spacing: 20) {
                            VStack(spacing: 16) {
                                // Email Field
                                textFieldContainer {
                                    HStack {
                                        Image(systemName: "envelope")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        TextField("Email", text: $email)
                                            .focused($focusedField, equals: .email)
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                            .foregroundColor(.white)
                                            .submitLabel(.next)
                                            .onSubmit {
                                                focusedField = .password
                                            }
                                    }
                                }
                                
                                // Password Field
                                textFieldContainer {
                                    HStack {
                                        Image(systemName: "lock")
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        SecureField("Password", text: $password)
                                            .focused($focusedField, equals: .password)
                                            .foregroundColor(.white)
                                            .submitLabel(isSignUpMode ? .next : .done)
                                            .onSubmit {
                                                if isSignUpMode {
                                                    focusedField = .confirmPassword
                                                } else {
                                                    focusedField = nil
                                                    handleEmailPasswordAction()
                                                }
                                            }
                                    }
                                }
                                
                                // Confirm Password (Sign Up only)
                                if isSignUpMode {
                                    textFieldContainer {
                                        HStack {
                                            Image(systemName: "lock.fill")
                                                .foregroundColor(.white.opacity(0.7))
                                                .frame(width: 20)
                                            
                                            SecureField("Confirm Password", text: $confirmPassword)
                                                .focused($focusedField, equals: .confirmPassword)
                                                .foregroundColor(.white)
                                                .submitLabel(.done)
                                                .onSubmit {
                                                    focusedField = nil
                                                    handleEmailPasswordAction()
                                                }
                                        }
                                    }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            
                            // Email/Password Action Button
                            Button(action: handleEmailPasswordAction) {
                                HStack {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    
                                    Text(isSignUpMode ? "Create Account" : "Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.1, green: 0.4, blue: 0.9))
                                )
                            }
                            .disabled(authManager.isLoading || !isValidForm)
                            .opacity(isValidForm ? 1.0 : 0.6)
                            
                            // Toggle Sign In/Sign Up
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isSignUpMode.toggle()
                                    clearForm()
                                    focusedField = nil
                                }
                            }) {
                                Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            // Forgot Password (Sign In only)
                            if !isSignUpMode {
                                Button(action: {
                                    focusedField = nil
                                    showingForgotPassword = true
                                }) {
                                    Text("Forgot Password?")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .underline()
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .alert("Message", isPresented: $authManager.showError) {
                Button("OK") {
                    authManager.showError = false
                }
            } message: {
                Text(authManager.errorMessage)
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView(authManager: authManager)
            }
            .onTapGesture {
                focusedField = nil
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func textFieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            )
    }
    
    // MARK: - Helper Methods
    
    private var isValidForm: Bool {
        if isSignUpMode {
            return !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword && password.count >= 6
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    private func handleEmailPasswordAction() {
        focusedField = nil
        Task {
            if isSignUpMode {
                await authManager.signUpWithEmail(email: email, password: password)
            } else {
                await authManager.signInWithEmail(email: email, password: password)
            }
        }
    }
    
    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
    }
}

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
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
                
                VStack(spacing: 30) {
                    VStack(spacing: 16) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Reset Password")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Enter your email address and we'll send you a link to reset your password")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 20) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 20)
                            
                            TextField("Email", text: $email)
                                .focused($isEmailFocused)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .submitLabel(.send)
                                .onSubmit {
                                    if !email.isEmpty {
                                        sendResetEmail()
                                    }
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        )
                        
                        Button(action: sendResetEmail) {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                
                                Text("Send Reset Link")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.1, green: 0.4, blue: 0.9))
                            )
                        }
                        .disabled(authManager.isLoading || email.isEmpty)
                        .opacity(email.isEmpty ? 0.6 : 1.0)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
                .padding(.top, 60)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEmailFocused = false
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onTapGesture {
                isEmailFocused = false
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func sendResetEmail() {
        isEmailFocused = false
        Task {
            await authManager.resetPassword(email: email)
            dismiss()
        }
    }
}
