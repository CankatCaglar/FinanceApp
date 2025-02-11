import SwiftUI

struct AuthButtonStyle: ViewModifier {
    let backgroundColor: Color
    let foregroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 55) // Fixed height for all buttons
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct AuthFieldStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .frame(height: 55)
            .padding(.horizontal)
            .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
            .cornerRadius(14)
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .accentColor(colorScheme == .dark ? .white : .black)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct PasswordField: View {
    @Environment(\.colorScheme) var colorScheme
    let placeholder: String
    @Binding var text: String
    @Binding var isSecure: Bool
    
    var body: some View {
        HStack {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
            
            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(.trailing, 8)
        }
        .padding(.horizontal)
        .frame(height: 55)
        .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
        .cornerRadius(14)
        .foregroundColor(colorScheme == .dark ? .white : .black)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var isSignUp = false
    @State private var isPasswordSecure = true
    @State private var isConfirmPasswordSecure = true
    
    var body: some View {
        ZStack {
            // Background gradient matching the app icon colors
            LinearGradient(gradient: Gradient(colors: [
                Color(red: 39/255, green: 45/255, blue: 59/255),
                Color(red: 39/255, green: 45/255, blue: 59/255)
            ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 25) {
                    // App Logo
                    ZStack {
                        // Background circle with darker shade
                        Circle()
                            .fill(Color(red: 18/255, green: 20/255, blue: 28/255))
                            .frame(width: 120, height: 120)
                        
                        // Subtle border with glow
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 76/255, green: 201/255, blue: 140/255).opacity(0.3),
                                        Color(red: 128/255, green: 90/255, blue: 245/255).opacity(0.3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 120, height: 120)
                        
                        // App Logo
                        Image("app_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    }
                    .padding(.top, 50)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    
                    // Welcome Text
                    VStack(spacing: 8) {
                        Text(isSignUp ? "Create Account" : "Welcome to Fintrack")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if !isSignUp {
                            Text("Your Personal Finance Assistant")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 10)
                    
                    // Social Sign In Buttons
                    VStack(spacing: 12) {
                        // Google Sign In Button
                        Button(action: { authViewModel.signInWithGoogle() }) {
                            HStack {
                                Image("google_logo")
                                    .resizable()
                                    .renderingMode(.original)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                
                                Text("Continue with Google")
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                            .modifier(AuthButtonStyle(backgroundColor: .white, foregroundColor: .black.opacity(0.8)))
                        }
                        
                        // Apple Sign In Button
                        Button(action: { authViewModel.signInWithApple() }) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                
                                Text("Continue with Apple")
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                            .modifier(AuthButtonStyle(backgroundColor: .black, foregroundColor: .white))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.white.opacity(0.3))
                        Text("or")
                            .foregroundColor(.white)
                            .font(.subheadline)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal)
                    
                    // Sign Up/Sign In Form
                    VStack(spacing: 15) {
                        if isSignUp {
                            TextField("Full Name", text: $fullName)
                                .modifier(AuthFieldStyle())
                                .textContentType(.name)
                        }
                        
                        TextField("Email", text: $email)
                            .modifier(AuthFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        
                        PasswordField(
                            placeholder: "Password",
                            text: $password,
                            isSecure: $isPasswordSecure
                        )
                        .textContentType(isSignUp ? .newPassword : .password)
                        
                        if isSignUp {
                            PasswordField(
                                placeholder: "Confirm Password",
                                text: $confirmPassword,
                                isSecure: $isConfirmPasswordSecure
                            )
                            .textContentType(.newPassword)
                        }
                        
                        Button(action: {
                            Task {
                                do {
                                    if isSignUp {
                                        // Sign Up validation
                                        if email.isEmpty || password.isEmpty || confirmPassword.isEmpty || fullName.isEmpty {
                                            authViewModel.errorMessage = "Please fill in all fields"
                                            authViewModel.showError = true
                                        } else if password != confirmPassword {
                                            authViewModel.errorMessage = "Passwords don't match"
                                            authViewModel.showError = true
                                        } else if password.count < 6 {
                                            authViewModel.errorMessage = "Password must be at least 6 characters"
                                            authViewModel.showError = true
                                        } else {
                                            try await authViewModel.signUp(email: email, password: password)
                                            try await authViewModel.updateProfile(fullName: fullName)
                                        }
                                    } else {
                                        // Sign In validation
                                        if email.isEmpty || password.isEmpty {
                                            authViewModel.errorMessage = "Please fill in all fields"
                                            authViewModel.showError = true
                                        } else {
                                            try await authViewModel.signIn(email: email, password: password)
                                        }
                                    }
                                } catch {
                                    authViewModel.errorMessage = error.localizedDescription
                                    authViewModel.showError = true
                                }
                            }
                        }) {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 55)
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Toggle Sign In/Up
                    Button(action: {
                        withAnimation {
                            isSignUp.toggle()
                            if isSignUp {
                                password = ""
                            } else {
                                fullName = ""
                                password = ""
                                confirmPassword = ""
                            }
                        }
                    }) {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
        }
        .alert(isPresented: $authViewModel.showError) {
            Alert(
                title: Text("Error"),
                message: Text(authViewModel.errorMessage ?? "An error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// Replace the existing ModernTextFieldStyle with AuthFieldStyle
extension TextField {
    func textFieldStyle() -> some View {
        self.modifier(AuthFieldStyle())
    }
} 
