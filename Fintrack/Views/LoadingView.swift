import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(gradient: Gradient(colors: [
                Color(red: 39/255, green: 45/255, blue: 59/255),
                Color(red: 39/255, green: 45/255, blue: 59/255)
            ]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // FinTrack Logo
            Text("FinTrack")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 126/255, green: 232/255, blue: 250/255),  // Metalik mavi
                            Color(red: 149/255, green: 102/255, blue: 255/255),  // Mor
                            Color(red: 82/255, green: 206/255, blue: 182/255),   // Metalik yeşil
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 149/255, green: 102/255, blue: 255/255).opacity(0.3),
                        radius: 10, x: 0, y: 5)
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 20)
                .animation(.easeOut(duration: 0.8), value: isAnimating)
                .onAppear {
                    isAnimating = true
                }
        }
    }
}

#Preview {
    LoadingView()
} 