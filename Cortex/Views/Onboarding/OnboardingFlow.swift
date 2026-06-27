import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject var app: AppState
    @State private var step: Step

    enum Step { case intro, auth, country, reminder }

    init(startAt: Step = .intro) { _step = State(initialValue: startAt) }

    var body: some View {
        AppBackground {
            switch step {
            case .intro:    IntroCarousel { step = .auth }
            case .auth:     AuthScreen { step = .country }
            case .country:  CountryScreen { step = .reminder }
            case .reminder: ReminderScreen { finish() }
            }
        }
        .animation(.easeInOut, value: step)
    }

    private func finish() {
        withAnimation { app.onboarded = true }
    }
}

// MARK: - 1. Intro carousel
private struct IntroCarousel: View {
    var onDone: () -> Void
    @State private var page = 0

    struct Slide { let title: String; let emoji: String; let bullets: [String] }
    private let slides = [
        Slide(title: "Welcome to Cortex", emoji: "🏥",
              bullets: ["You're the only doctor on duty today.", "Every department is waiting for your lead."]),
        Slide(title: "Your Patients Are Waiting", emoji: "🧑‍⚕️",
              bullets: ["Each specialty has a patient ready.", "Solve a case to unlock the next.", "Cases get harder as you grow."]),
        Slide(title: "Every Decision Counts", emoji: "🩺",
              bullets: ["From history to diagnosis, reason it out.", "Dr. Vix mentors you at every step."]),
        Slide(title: "Ready to Think?", emoji: "🧠",
              bullets: ["Take charge of the Cortex ward.", "Your first patient is waiting for you."])
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CortexLogo(layout: .horizontal, size: 36)
                Spacer()
                Button("SKIP") { onDone() }
                    .font(CX.label(15)).foregroundStyle(CX.navySoft)
            }
            .padding(.horizontal, 20).padding(.top, 8)

            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    slideCard(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: slides.count, index: page).padding(.bottom, 18)

            if page == slides.count - 1 {
                CXButton(title: "Take Charge") { onDone() }
                    .padding(.horizontal, 20)
            } else {
                Text("Swipe to continue")
                    .font(CX.label(14)).foregroundStyle(CX.teal)
                    .frame(height: 56)
            }
        }
        .padding(.bottom, 16)
    }

    private func slideCard(_ s: Slide) -> some View {
        CXCard {
            VStack(spacing: 18) {
                Text(s.title).font(CX.title(26)).foregroundStyle(CX.navy)
                    .multilineTextAlignment(.center)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CX.tealSoft)
                    .frame(height: 180)
                    .overlay(Text(s.emoji).font(.system(size: 90)))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(s.bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(CX.navy).frame(width: 8, height: 8).padding(.top, 7)
                            Text(b).font(CX.body(17)).foregroundStyle(CX.navySoft)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 2. Auth
private struct AuthScreen: View {
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sb: SupabaseService
    @State private var working: String?     // which provider is in-flight
    @State private var error: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            CortexLogo(layout: .stacked, size: 76, showTagline: true)
            VStack(spacing: 4) {
                Text("The game that makes you a").font(CX.heading(22)).foregroundStyle(CX.navy)
                Text("Better Doctor").font(CX.title(34)).foregroundStyle(CX.navy)
            }
            .multilineTextAlignment(.center)
            VixClip(anim: .wave, size: 170, fallback: .idle)
            Spacer()
            VStack(spacing: 14) {
                authButton("Sign in with Google", system: "g.circle.fill",
                           fg: .white, bg: AnyShapeStyle(CX.navyBar), provider: "google")
                authButton("Sign in with Apple", system: "applelogo",
                           fg: .white, bg: AnyShapeStyle(Color.black), provider: "apple")

                if let error {
                    Text(error).font(CX.label(13)).foregroundStyle(CX.orange)
                        .multilineTextAlignment(.center)
                }

                Text("By continuing, you agree to our terms & privacy policy")
                    .font(CX.label(12)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)
                Text("Cortex • v1.0").font(CX.label(12)).foregroundStyle(CX.teal)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func authButton(_ title: String, system: String, fg: Color, bg: AnyShapeStyle, provider: String) -> some View {
        Button { signIn(provider) } label: {
            HStack(spacing: 10) {
                if working == provider { ProgressView().tint(fg) }
                else { Image(systemName: system) }
                Text(title)
            }
            .font(CX.heading(17)).foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(working != nil)
    }

    private func signIn(_ provider: String) {
        error = nil; working = provider
        Task {
            do {
                let email = try await sb.signInWithOAuth(provider: provider)
                // Load this account's cloud profile (creates a fresh one for a new
                // account). RootView then routes to onboarding or the main app.
                await app.bindAccount()
                if let email, !email.isEmpty, app.displayName == "Dr. Vix Trainee" {
                    app.displayName = email.components(separatedBy: "@").first.map { "Dr. " + $0.capitalized } ?? app.displayName
                }
                working = nil
            } catch {
                working = nil
                self.error = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Please try again."
            }
        }
    }
}

// MARK: - 3. Country
private struct CountryScreen: View {
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @State private var selected = "India"
    private let countries = [("India","🇮🇳"),("United States","🇺🇸"),("United Kingdom","🇬🇧"),
                             ("Canada","🇨🇦"),("Australia","🇦🇺"),("Germany","🇩🇪"),("Nigeria","🇳🇬")]
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Your medical journey starts here").font(CX.title(26))
                    .foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text("Choose your country so we can tailor cases just right for you.")
                    .font(CX.body(15)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(countries, id: \.0) { c in
                        Button { selected = c.0 } label: {
                            HStack(spacing: 12) {
                                Text(c.1).font(.system(size: 26))
                                Text(c.0).font(CX.body(17)).foregroundStyle(CX.navy)
                                Spacer()
                                Image(systemName: selected == c.0 ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected == c.0 ? CX.orange : CX.hairline)
                            }
                            .padding(16)
                            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selected == c.0 ? CX.orange : CX.hairline, lineWidth: 1.5))
                        }
                    }
                }
            }
            CXButton(title: "Begin Patient Care") { app.country = selected; onDone() }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }
}

// MARK: - 4. Reminder
private struct ReminderScreen: View {
    var onDone: () -> Void
    @State private var pick = 0
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("⏰").font(.system(size: 70))
            VStack(spacing: 8) {
                Text("Consistency Builds Clinical Confidence")
                    .font(CX.title(26)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text("A daily reminder can help you stay sharp.")
                    .font(CX.body(16)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            }
            VStack(spacing: 14) {
                reminderOption(0, icon: "bell.badge.fill", title: "Remind Me",
                               sub: "Help me build my habit and stay on track.", advised: true)
                reminderOption(1, icon: "bell.slash.fill", title: "I'll Set My Own Pace",
                               sub: "I'll manage reminders on my own (for now!).", advised: false)
            }
            Spacer()
            CXButton(title: "Let's GO") {
                if pick == 0 {
                    // "Remind Me" → daily reminder at 10:00 local time.
                    NotificationManager.shared.scheduleDailyReminder(hour: 10, minute: 0)
                } else {
                    NotificationManager.shared.cancelDailyReminder()
                }
                onDone()
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
    }

    private func reminderOption(_ i: Int, icon: String, title: String, sub: String, advised: Bool) -> some View {
        Button { pick = i } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26))
                    .foregroundStyle(advised ? CX.orange : CX.navySoft)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(CX.heading(18)).foregroundStyle(CX.navy)
                    Text(sub).font(CX.body(14)).foregroundStyle(CX.navySoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: pick == i ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(pick == i ? CX.orange : CX.hairline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(pick == i ? CX.orange : CX.hairline, lineWidth: pick == i ? 2 : 1.5))
        }
    }
}
