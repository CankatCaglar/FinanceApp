import SwiftUI
import UIKit
import PhotosUI
import FirebaseAuth

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Full Name", text: $fullName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .onChange(of: fullName) { newValue in
                            let trimmedValue = newValue.trimmingCharacters(in: .whitespaces)
                            hasChanges = trimmedValue != authViewModel.currentUser?.fullName
                        }
                    
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disabled(true)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile(name: fullName.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
            .onAppear {
                fullName = authViewModel.currentUser?.fullName ?? ""
                email = authViewModel.currentUser?.email ?? ""
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
    }
    
    private func saveProfile(name: String) {
        guard !isSaving else { return }
        isSaving = true
        
        Task {
            do {
                try await authViewModel.updateProfile(fullName: name)
                await MainActor.run {
                    isSaving = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
            }
        }
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Current Password")) {
                    HStack {
                        if showCurrentPassword {
                            TextField("Current Password", text: $currentPassword)
                                .textContentType(.password)
                        } else {
                            SecureField("Current Password", text: $currentPassword)
                                .textContentType(.password)
                        }
                        
                        Button(action: { showCurrentPassword.toggle() }) {
                            Image(systemName: showCurrentPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("New Password")) {
                    HStack {
                        if showNewPassword {
                            TextField("New Password", text: $newPassword)
                                .textContentType(.newPassword)
                        } else {
                            SecureField("New Password", text: $newPassword)
                                .textContentType(.newPassword)
                        }
                        
                        Button(action: { showNewPassword.toggle() }) {
                            Image(systemName: showNewPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    HStack {
                        if showConfirmPassword {
                            TextField("Confirm New Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                        } else {
                            SecureField("Confirm New Password", text: $confirmPassword)
                                .textContentType(.newPassword)
                        }
                        
                        Button(action: { showConfirmPassword.toggle() }) {
                            Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                if !newPassword.isEmpty {
                    Section(header: Text("Password Requirements")) {
                        PasswordRequirementRow(isValid: newPassword.count >= 8,
                                            text: "At least 8 characters")
                        PasswordRequirementRow(isValid: newPassword.contains(where: { $0.isNumber }),
                                            text: "At least 1 number")
                        PasswordRequirementRow(isValid: newPassword.contains(where: { $0.isUppercase }),
                                            text: "At least 1 uppercase letter")
                        PasswordRequirementRow(isValid: newPassword.contains(where: { $0.isLowercase }),
                                            text: "At least 1 lowercase letter")
                        PasswordRequirementRow(isValid: newPassword.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }),
                                            text: "At least 1 special character")
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        changePassword()
                    }
                    .disabled(isLoading || !isFormValid)
                }
            }
            .alert("Change Password", isPresented: $showAlert) {
                Button("OK") {
                    if alertMessage.contains("successfully") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 8 &&
        newPassword.contains(where: { $0.isNumber }) &&
        newPassword.contains(where: { $0.isUppercase }) &&
        newPassword.contains(where: { $0.isLowercase }) &&
        newPassword.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })
    }
    
    private func changePassword() {
        isLoading = true
        
        Task {
            do {
                try await authViewModel.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                await MainActor.run {
                    alertMessage = "Password changed successfully!"
                    showAlert = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                    isLoading = false
                }
            }
        }
    }
}

struct PasswordRequirementRow: View {
    let isValid: Bool
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isValid ? .green : .gray)
            Text(text)
                .foregroundColor(isValid ? .primary : .gray)
        }
    }
} 