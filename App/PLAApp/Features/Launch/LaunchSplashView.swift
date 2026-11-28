import SwiftUI

/// Full-screen cold-launch splash displaying the developer emblem (golden crown & crimson cape),
/// matching royal tagline, and minimal gold-to-crimson loading bar on seamless OLED pitch black.
struct LaunchSplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logoVisible = false
    @State private var taglineVisible = false
    @State private var loadingProgress: CGFloat = 0
    @State private var allowTapSkip = false
    @State private var didFinish = false

    private static let crownGold = Color(red: 0.90, green: 0.77, blue: 0.44)
    private static let capeCrimson = Color(red: 0.80, green: 0.17, blue: 0.17)

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    Image("DeveloperLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 216, height: 216)
                        .opacity(logoVisible ? 1 : 0)
                        .scaleEffect(reduceMotion ? 1 : (logoVisible ? 1 : 0.92))
                        .accessibilityLabel("Logo Developer")

                    VStack(spacing: 10) {
                        Text("RULE YOUR DAY")
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .tracking(4.4)
                            .foregroundStyle(Self.crownGold)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Self.crownGold, Self.capeCrimson],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 44, height: 2)

                        Text("Pimpin Harimu. Kendalikan Segalanya.")
                            .font(.caption.weight(.medium))
                            .tracking(0.6)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                    }
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (taglineVisible ? 0 : 8))
                }
                .padding(.horizontal, PLATokens.Spacing.xl)

                Spacer()

                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Self.crownGold, Self.capeCrimson],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * loadingProgress))
                        }
                    }
                    .frame(width: 148, height: 3)

                    Text("LIFE ASSISTANT")
                        .font(.caption2.weight(.semibold))
                        .tracking(2.0)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .opacity(taglineVisible ? 1 : 0)
                .padding(.bottom, 42)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if allowTapSkip {
                completeOnce()
            }
        }
        .task {
            if reduceMotion {
                logoVisible = true
                taglineVisible = true
                loadingProgress = 1.0
            } else {
                withAnimation(.easeOut(duration: 0.50)) {
                    logoVisible = true
                }
                try? await _Concurrency.Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeOut(duration: 0.45)) {
                    taglineVisible = true
                }
                withAnimation(.easeInOut(duration: 1.30)) {
                    loadingProgress = 1.0
                }
            }

            try? await _Concurrency.Task.sleep(nanoseconds: 350_000_000)
            allowTapSkip = true

            try? await _Concurrency.Task.sleep(nanoseconds: 1_150_000_000)
            completeOnce()
        }
    }

    private func completeOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}
