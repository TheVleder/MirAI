import SwiftUI

/// First-launch onboarding: 3-screen tutorial.
struct OnboardingView: View {

    @Binding var isOnboarded: Bool
    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("brain.head.profile", "Welcome to MirAI", "Your private AI assistant that runs entirely on your device. No cloud, no data leaves your phone.", .cyan),
        ("theatermasks", "Pick a Personality", "Choose from 8 built-in personas or create your own. Switch anytime to change how MirAI responds.", .purple),
        ("mic.fill", "Start Talking", "Hold the mic button to speak, or switch to Hands-Free mode. You can also type your messages.", .green)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        onboardingPage(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 400)

                Spacer()

                // Button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        withAnimation { isOnboarded = true }
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [pages[currentPage].color, pages[currentPage].color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)

                // Skip
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        withAnimation { isOnboarded = true }
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 20)
                }
            }
        }
        .animation(.easeInOut, value: currentPage)
    }

    private func onboardingPage(_ page: (icon: String, title: String, subtitle: String, color: Color)) -> some View {
        VStack(spacing: 24) {
            Image(systemName: page.icon)
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [page.color, page.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 8)

            Text(page.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
