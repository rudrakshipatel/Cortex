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

    struct Slide { let title: String; let image: String; let bullets: [String] }
    private let slides = [
        Slide(title: "Welcome to Cortex", image: "case-img-11",
              bullets: ["You're the only doctor on duty today.", "Every department is waiting for your lead."]),
        Slide(title: "Your Patients Are Waiting", image: "case-img-3",
              bullets: ["Each specialty has a patient ready.", "Solve a case to unlock the next.", "Cases get harder as you grow."]),
        Slide(title: "Every Decision Counts", image: "case-img-9",
              bullets: ["From history to diagnosis, reason it out.", "Dr. Vix mentors you at every step."]),
        Slide(title: "Ready to Think?", image: "case-img-5",
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
                Image(s.image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    @State private var showEmail = false

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
                Button { showEmail = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                        Text("Sign in with Email")
                    }
                    .font(CX.heading(17)).foregroundStyle(CX.navy)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
                }
                .buttonStyle(PressStyle())
                .disabled(working != nil)

                if let error {
                    Text(error).font(CX.label(13)).foregroundStyle(CX.orange)
                        .multilineTextAlignment(.center)
                }

                Button("Continue without an account") { onDone() }
                    .font(CX.heading(15)).foregroundStyle(CX.navySoft)
                    .disabled(working != nil)
                Text("You can play right away and sign in later to save your progress across devices.")
                    .font(CX.label(11)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)

                Text("By continuing, you agree to our terms & privacy policy")
                    .font(CX.label(12)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)
                Text("Cortex • v1.0").font(CX.label(12)).foregroundStyle(CX.teal)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24)
        .sheet(isPresented: $showEmail) { EmailSignInSheet() }
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
                _ = try await sb.signInWithOAuth(provider: provider)
                // Load this account's cloud profile (creates a fresh one for a new
                // account). RootView then routes to onboarding or the main app.
                await app.bindAccount()
                working = nil
            } catch {
                working = nil
                self.error = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Please try again."
            }
        }
    }
}

// MARK: - 2b. Email sign-in (6-digit code)
struct EmailSignInSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sb: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    enum Stage { case email, code }
    @State private var stage: Stage = .email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(CX.navySoft)
                    }
                }
                Spacer()
                Image(systemName: stage == .email ? "envelope.fill" : "lock.shield.fill")
                    .font(.system(size: 52)).foregroundStyle(CX.teal)

                if stage == .email {
                    Text("Sign in with Email").font(CX.title(24)).foregroundStyle(CX.navy)
                    Text("We'll email you a 6-digit code.")
                        .font(CX.body(15)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused)
                        .font(CX.body(17)).padding(16)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))
                    primaryButton("Send Code", enabled: emailValid) { Task { await send() } }
                } else {
                    Text("Enter the code").font(CX.title(24)).foregroundStyle(CX.navy)
                    Text("Sent to \(email)")
                        .font(CX.body(15)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focused)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center).kerning(8)
                        .padding(16)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))
                        .onChange(of: code) { _, v in
                            code = String(v.filter(\.isNumber).prefix(6))
                            if code.count == 6 { Task { await verify() } }
                        }
                    primaryButton("Verify", enabled: code.count == 6) { Task { await verify() } }
                    Button("Use a different email") { stage = .email; code = ""; error = nil }
                        .font(CX.label(14)).foregroundStyle(CX.teal)
                }

                if let error {
                    Text(error).font(CX.label(13)).foregroundStyle(CX.orange).multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .onAppear { focused = true }
    }

    private func primaryButton(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(.white) } else { Text(title) }
            }
            .font(CX.heading(17)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(enabled ? AnyShapeStyle(CX.orangeButton) : AnyShapeStyle(CX.navySoft.opacity(0.4)),
                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!enabled || busy)
    }

    private func send() async {
        error = nil; busy = true; defer { busy = false }
        do {
            try await sb.sendEmailCode(email.trimmingCharacters(in: .whitespaces).lowercased())
            stage = .code; code = ""; focused = true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't send the code."
        }
    }

    private func verify() async {
        guard !busy else { return }
        error = nil; busy = true; defer { busy = false }
        do {
            _ = try await sb.verifyEmailCode(email.trimmingCharacters(in: .whitespaces).lowercased(), code: code)
            await app.bindAccount()
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "That code didn't work."
            code = ""
        }
    }
}

// MARK: - 3. Country
private struct CountryScreen: View {
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var selected: String

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        // Default to the device's region, else United States.
        let code = Locale.current.region?.identifier
        let name = code.flatMap { Locale(identifier: "en_US").localizedString(forRegionCode: $0) }
        _selected = State(initialValue: name ?? "United States")
    }

    /// Every ISO country, with its flag, sorted by name (built once).
    private static let all: [(name: String, flag: String)] = {
        let en = Locale(identifier: "en_US")
        return Locale.Region.isoRegions
            .map(\.identifier).filter { $0.count == 2 }
            .compactMap { code -> (String, String)? in
                guard let name = en.localizedString(forRegionCode: code) else { return nil }
                return (name, flag(code))
            }
            .sorted { $0.0 < $1.0 }
    }()

    /// Turn a 2-letter ISO code into its flag emoji (regional indicators).
    private static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value).map(String.init) }
            .joined()
    }

    private var filtered: [(name: String, flag: String)] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? Self.all : Self.all.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("Your medical journey starts here").font(CX.title(26))
                    .foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text("Choose your country so we can tailor cases just right for you.")
                    .font(CX.body(15)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CX.navySoft)
                TextField("Search countries", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(CX.body(16))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(CX.navySoft)
                    }
                }
            }
            .padding(12)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(filtered, id: \.name) { c in
                        Button { selected = c.name } label: {
                            HStack(spacing: 12) {
                                Text(c.flag).font(.system(size: 26))
                                Text(c.name).font(CX.body(17)).foregroundStyle(CX.navy)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: selected == c.name ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected == c.name ? CX.orange : CX.hairline)
                            }
                            .padding(16)
                            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selected == c.name ? CX.orange : CX.hairline, lineWidth: 1.5))
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
                    // "Remind Me" → daily reminder at 11:00 local time.
                    NotificationManager.shared.scheduleDailyReminder(hour: 11, minute: 0)
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
