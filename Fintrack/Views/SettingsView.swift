import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showImagePicker = false
    @State private var isShowingEditProfile = false
    @State private var isShowingChangePassword = false
    @Environment(\.colorScheme) var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Section
                    VStack(spacing: 16) {
                        // Profile Photo and Name Section
                        GeometryReader { geometry in
                            HStack(spacing: 15) {
                                Button(action: {
                                    showImagePicker = true
                                }) {
                                    Group {
                                        if let image = authViewModel.profileImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else if let photoURL = authViewModel.currentUser?.photoURL,
                                                  let url = URL(string: photoURL) {
                                            AsyncImage(url: url) { image in
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            } placeholder: {
                                                ProgressView()
                                            }
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(width: min(geometry.size.width * 0.2, 80), 
                                           height: min(geometry.size.width * 0.2, 80))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                    .overlay(
                                        Circle()
                                            .fill(Color.black.opacity(0.1))
                                            .overlay(
                                                Image(systemName: "camera.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 20))
                                            )
                                            .frame(width: 30, height: 30)
                                            .offset(x: 25, y: 25)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(authViewModel.currentUser?.fullName ?? "User")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    Text(authViewModel.currentUser?.email ?? "")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        }
                        .frame(height: 120)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Account Settings Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ACCOUNT SETTINGS")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            Button(action: { isShowingEditProfile = true }) {
                                SettingRow(
                                    icon: "person.fill",
                                    title: "Edit Profile",
                                    iconColor: .primary
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Divider()
                                .padding(.horizontal)
                            
                            Button(action: { isShowingChangePassword = true }) {
                                SettingRow(
                                    icon: "lock.fill",
                                    title: "Change Password",
                                    iconColor: .primary
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Preferences Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PREFERENCES")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        
                        // Add other preference options here if needed
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Sign Out Section
                    Button(action: { 
                        Task {
                            do {
                                try await authViewModel.signOut()
                            } catch {
                                print("Error signing out: \(error)")
                            }
                        }
                    }) {
                        SettingRow(
                            icon: "arrow.right.square.fill",
                            title: "Sign Out",
                            iconColor: .red,
                            showChevron: false,
                            textColor: .red
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical)
            }
            .navigationTitle("Settings")
            .background(backgroundColor.ignoresSafeArea())
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: .constant(nil))
                    .onChange(of: showImagePicker) { isPresented in
                        if !isPresented {
                            if let imageData = UserDefaults.standard.data(forKey: "tempImageData"),
                               let image = UIImage(data: imageData) {
                                Task {
                                    await authViewModel.updateProfilePhoto(image)
                                }
                                UserDefaults.standard.removeObject(forKey: "tempImageData")
                            }
                        }
                    }
            }
            .sheet(isPresented: $isShowingEditProfile) {
                EditProfileView(isPresented: $isShowingEditProfile)
            }
            .sheet(isPresented: $isShowingChangePassword) {
                ChangePasswordView()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if authViewModel.profileImage == nil,
               let cachedData = UserDefaults.standard.data(forKey: "profileImageData"),
               let cachedImage = UIImage(data: cachedData) {
                authViewModel.profileImage = cachedImage
            }
        }
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let iconColor: Color
    var showChevron: Bool = true
    var textColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
            
            Text(title)
                .foregroundColor(textColor)
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.8))
            }
        }
        .padding()
    }
} 
