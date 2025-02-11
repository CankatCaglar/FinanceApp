import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

enum ActiveSheet: Identifiable {
    case editProfile, changePassword, subscription, about
    
    var id: Int {
        switch self {
        case .editProfile: return 0
        case .changePassword: return 1
        case .subscription: return 2
        case .about: return 3
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var showingSignOutAlert = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettingsAlert = false
    @State private var showingNotificationSettings = false
    
    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        ScrollView {
            if let user = authViewModel.currentUser {
                ProfileContent(
                    user: user,
                    activeSheet: $activeSheet,
                    showingSignOutAlert: $showingSignOutAlert,
                    showingSettingsAlert: $showingSettingsAlert,
                    backgroundColor: backgroundColor
                )
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .background(backgroundColor.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editProfile:
                EditProfileView(isPresented: Binding(
                    get: { self.activeSheet == .editProfile },
                    set: { if !$0 { self.activeSheet = nil } }
                ))
            case .changePassword:
                ChangePasswordView()
            case .subscription:
                PaywallView()
            case .about:
                AboutView()
            }
        }
        .alert(isPresented: $showingSignOutAlert) {
            Alert(
                title: Text("Sign Out"),
                message: Text("Are you sure you want to sign out?"),
                primaryButton: .destructive(Text("Sign Out")) {
                    Task {
                        do {
                            try await authViewModel.signOut()
                        } catch {
                            print("Error signing out: \(error)")
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingNotificationSettings) {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                SafariView(url: settingsUrl)
            }
        }
    }
}

struct ProfileContent: View {
    let user: User
    @Binding var activeSheet: ActiveSheet?
    @Binding var showingSignOutAlert: Bool
    @Binding var showingSettingsAlert: Bool
    let backgroundColor: Color
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Header
            ProfileHeader(user: user)
                .padding(.top, 24)
            
            // Settings Menu
            SettingsMenuContent(
                activeSheet: $activeSheet,
                showingSignOutAlert: $showingSignOutAlert,
                showingSettingsAlert: $showingSettingsAlert,
                backgroundColor: backgroundColor
            )
            .padding(.top, 28)
        }
    }
}

struct ProfileHeader: View {
    let user: User
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showSaveButton = false
    
    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                showImagePicker = true
            }) {
                ProfileImageView(
                    selectedImage: selectedImage ?? authViewModel.profileImage,
                    photoURL: user.photoURL,
                    size: 115
                )
            }
            
            if showSaveButton {
                VStack(spacing: 8) {
                    Button(action: {
                        if let image = selectedImage {
                            Task {
                                await authViewModel.updateProfilePhoto(image)
                                showSaveButton = false
                                selectedImage = nil
                            }
                        }
                    }) {
                        Text("Save Profile Photo")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        selectedImage = nil
                        showSaveButton = false
                    }) {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            
            VStack(spacing: 8) {
                Text(user.fullName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 16)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
                .onChange(of: selectedImage) { _ in
                    showSaveButton = selectedImage != nil
                }
        }
    }
}

struct SettingsMenuContent: View {
    @Binding var activeSheet: ActiveSheet?
    @Binding var showingSignOutAlert: Bool
    @Binding var showingSettingsAlert: Bool
    let backgroundColor: Color
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Group {
                // Edit Profile Button
                MenuButton(
                    icon: "person",
                    title: "Edit Profile",
                    iconColor: .blue,
                    textColor: .primary,
                    backgroundColor: backgroundColor,
                    action: { activeSheet = .editProfile },
                    showChevron: true
                )
                
                // Change Password Button
                MenuButton(
                    icon: "lock",
                    title: "Change Password",
                    iconColor: .green,
                    textColor: .primary,
                    backgroundColor: backgroundColor,
                    action: { activeSheet = .changePassword },
                    showChevron: true
                )
                
                // Subscription Button
                MenuButton(
                    icon: "creditcard",
                    title: "Subscription",
                    iconColor: .purple,
                    textColor: .primary,
                    backgroundColor: backgroundColor,
                    action: { activeSheet = .subscription },
                    showChevron: true
                )
                
                // About Button
                MenuButton(
                    icon: "info.circle",
                    title: "About",
                    iconColor: .primary,
                    textColor: .primary,
                    backgroundColor: backgroundColor,
                    action: { activeSheet = .about },
                    showChevron: true
                )
                
                // Sign Out Button
                MenuButton(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    iconColor: .red,
                    textColor: .red,
                    backgroundColor: backgroundColor,
                    action: { showingSignOutAlert = true },
                    showChevron: true
                )
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
        }
        .padding(.horizontal, 2)
        .padding(.top, 20)
    }
}

struct ProfileImageView: View {
    let selectedImage: UIImage?
    let photoURL: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let photoURL = photoURL,
                      let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 2)
        )
    }
}

struct MenuButton: View {
    let icon: String
    let title: String
    let iconColor: Color
    let textColor: Color
    var backgroundColor: Color
    let action: () -> Void
    let showChevron: Bool
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Modern icon without background circle
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                // Title
                Text(title)
                    .foregroundColor(textColor)
                    .font(.system(size: 16, weight: .medium))
                
                Spacer()
                
                // Chevron
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SubscriptionPlansView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedPlan: SubscriptionPlan = .monthly
    
    enum SubscriptionPlan {
        case monthly, yearly
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Upgrade to Pro")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Unlock all premium features")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top)
            
            // Plan Selection
            HStack(spacing: 0) {
                PlanSelectionButton(
                    title: "Monthly",
                    isSelected: selectedPlan == .monthly,
                    action: { selectedPlan = .monthly }
                )
                
                PlanSelectionButton(
                    title: "Yearly",
                    isSelected: selectedPlan == .yearly,
                    action: { selectedPlan = .yearly }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
            
            // Features
            VStack(alignment: .leading, spacing: 16) {
                Text("Premium Features")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                FeatureRowView(icon: "chart.bar.fill", title: "Advanced Analytics", description: "Detailed insights and reports")
                FeatureRowView(icon: "bell.badge.fill", title: "Real-time Alerts", description: "Never miss important updates")
                FeatureRowView(icon: "arrow.left.arrow.right", title: "Portfolio Tracking", description: "Track all your investments")
                FeatureRowView(icon: "person.fill.checkmark", title: "Priority Support", description: "Get help when you need it")
                if selectedPlan == .yearly {
                    FeatureRowView(icon: "gift.fill", title: "2 Months Free", description: "Save with yearly plan")
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

struct PlanSelectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.blue : Color.clear)
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRowView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                SubscriptionPlansView()
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileHeaderView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showSaveButton = false
    
    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                showImagePicker = true
            }) {
                if let image = selectedImage ?? authViewModel.profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray, lineWidth: 2))
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                }
            }
            
            if showSaveButton {
                Button(action: {
                    if let image = selectedImage {
                        Task {
                            await authViewModel.updateProfilePhoto(image)
                            showSaveButton = false
                            selectedImage = nil
                        }
                    }
                }) {
                    Text("Save Profile Photo")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    selectedImage = nil
                    showSaveButton = false
                }) {
                    Text("Cancel")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            if let user = authViewModel.currentUser {
                Text(user.fullName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
                .onChange(of: selectedImage) { _ in
                    showSaveButton = selectedImage != nil
                }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Button(action: {
                        if let url = URL(string: "https://cankatcaglar.github.io/FinanceApp/privacy-policy.html") {
                            openURL(url)
                        }
                    }) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: "https://cankatcaglar.github.io/FinanceApp/terms-of-use.html") {
                            openURL(url)
                        }
                    }) {
                        HStack {
                            Text("Terms of Use")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: "https://cankatcaglar.github.io/FinanceApp/support.html") {
                            openURL(url)
                        }
                    }) {
                        HStack {
                            Text("Support")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
} 
