import SwiftUI
import UIKit

/// Cortex onboarding — a value-first flow that lets the user solve a real
/// (mini) patient before it ever asks for a commitment, so they finish thinking
/// "I can't wait to solve my first patient."
///
/// Order: welcome → (optional sign-in) → personalize (profession, experience,
/// specialties, goal) → country → how a case works → interactive mini-case →
/// celebration → daily commitment → plan → launch.
///
/// Sign-in stays near the front (before any personalization) on purpose: signing
/// in re-mounts this flow via RootView, and putting auth ahead of the first data
/// entry means a mid-flow sign-in can't discard anything. RootView re-enters a
/// signed-in new account at `.profession`.
struct OnboardingFlow: View {
    @EnvironmentObject var app: AppState
    @State private var step: Step
    @State private var forward = true

    enum Step: Int { case welcome, auth, profession, experience, specialty, goal, country, howItWorks, miniCase, celebrate, commitment, plan }

    init(startAt: Step = .welcome) { _step = State(initialValue: startAt) }

    private let nav = Animation.spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        AppBackground {
            ZStack {
                screen(for: step)
                    .id(step)
                    .transition(pushTransition)
            }
        }
        .animation(nav, value: step)
    }

    private var pushTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func go(_ s: Step) { forward = true; withAnimation(nav) { step = s } }
    private func back(_ s: Step) { forward = false; withAnimation(nav) { step = s } }

    @ViewBuilder private func screen(for step: Step) -> some View {
        switch step {
        case .welcome:    WelcomeScreen(onStart: { go(.auth) })
        case .auth:       AuthScreen(onDone: { go(.profession) })
        case .profession: ProfessionScreen(progress: 0.14, onNext: { go(.experience) })
        case .experience: ExperienceScreen(progress: 0.26, onBack: { back(.profession) }, onNext: { go(.specialty) })
        case .specialty:  SpecialtyScreen(progress: 0.38, onBack: { back(.experience) }, onNext: { go(.goal) })
        case .goal:       GoalScreen(progress: 0.50, onBack: { back(.specialty) }, onNext: { go(.country) })
        case .country:    CountryScreen(progress: 0.62, onBack: { back(.goal) }, onNext: { go(.howItWorks) })
        case .howItWorks: HowItWorksScreen(progress: 0.72, onBack: { back(.country) }, onNext: { go(.miniCase) })
        case .miniCase:   MiniCaseScreen(progress: 0.84, onSolved: { go(.celebrate) })
        case .celebrate:  CelebrateScreen(onNext: { go(.commitment) })
        case .commitment: CommitmentScreen(progress: 0.94, onNext: { go(.plan) })
        case .plan:       PlanScreen(onFinish: finish)
        }
    }

    private func finish() {
        Haptics.medium()
        withAnimation { app.onboarded = true }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap()     { UISelectionFeedbackGenerator().selectionChanged() }
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Shared chrome

/// Top bar with an optional back button and an animated progress track.
private struct OnbBar: View {
    var progress: Double
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button { Haptics.light(); onBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CX.navySoft).frame(width: 38, height: 38)
                        .background(CX.card, in: Circle())
                        .overlay(Circle().stroke(CX.hairline, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CX.navy.opacity(0.10))
                    Capsule().fill(LinearGradient(colors: [CX.teal, CX.tealDark], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, geo.size.width * progress))
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
    }
}

/// A selectable option row used across the personalization screens.
private struct OptionRow: View {
    var icon: String?
    var title: String
    var subtitle: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 13) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? CX.orange : CX.teal)
                        .frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CX.heading(17)).foregroundStyle(CX.navy)
                    if let subtitle {
                        Text(subtitle).font(CX.body(13)).foregroundStyle(CX.navySoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? CX.orange : CX.hairline)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? CX.orange : CX.hairline, lineWidth: selected ? 2 : 1.5))
        }
        .buttonStyle(PressStyle())
    }
}

private struct ScreenTitle: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(CX.title(27)).foregroundStyle(CX.navy)
                .multilineTextAlignment(.center)
            Text(subtitle).font(CX.body(15)).foregroundStyle(CX.navySoft)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - 1. Welcome

private struct WelcomeScreen: View {
    var onStart: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                CortexLogo(layout: .horizontal, size: 34)
                Spacer()
            }
            .padding(.horizontal, 22).padding(.top, 8)

            Spacer()
            VixClip(anim: .wave, size: 168, fallback: .idle)
                .bounceIn()
            VStack(spacing: 10) {
                Text("Think like a clinician.")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(CX.navy).multilineTextAlignment(.center)
                Text("Not a quiz — a real patient to work up, from the first complaint to the final call.")
                    .font(CX.body(16)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)

            Spacer()
            VStack(spacing: 12) {
                CXButton(title: "Get started") { Haptics.medium(); onStart() }
                Text("Your first patient is already waiting.")
                    .font(CX.label(12)).foregroundStyle(CX.teal)
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 26)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15)) { shown = true } }
    }
}

// MARK: - 2. Auth

private struct AuthScreen: View {
    var onDone: () -> Void
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sb: SupabaseService
    @State private var working: String?
    @State private var error: String?
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            CortexLogo(layout: .stacked, size: 68, showTagline: true)
            VStack(spacing: 4) {
                Text("Save your progress").font(CX.title(26)).foregroundStyle(CX.navy)
                Text("Keep your streak, XP and roadmap on every device — or start playing now and sign in later.")
                    .font(CX.body(14)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
            }
            VixClip(anim: .wave, size: 150, fallback: .idle)
            Spacer()
            VStack(spacing: 13) {
                authButton("Continue with Google", system: "g.circle.fill",
                           fg: .white, bg: AnyShapeStyle(CX.navyBar), provider: "google")
                authButton("Continue with Apple", system: "applelogo",
                           fg: .white, bg: AnyShapeStyle(Color.black), provider: "apple")
                Button { Haptics.light(); showEmail = true } label: {
                    HStack(spacing: 10) { Image(systemName: "envelope.fill"); Text("Continue with Email") }
                        .font(CX.heading(17)).foregroundStyle(CX.navy)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
                }
                .buttonStyle(PressStyle()).disabled(working != nil)

                if let error {
                    Text(error).font(CX.label(13)).foregroundStyle(CX.orange).multilineTextAlignment(.center)
                }

                Button("Continue without an account") { Haptics.light(); onDone() }
                    .font(CX.heading(15)).foregroundStyle(CX.navySoft).disabled(working != nil)
                Text("By continuing, you agree to our terms & privacy policy.")
                    .font(CX.label(11)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 22)
        .sheet(isPresented: $showEmail) { EmailSignInSheet() }
    }

    private func authButton(_ title: String, system: String, fg: Color, bg: AnyShapeStyle, provider: String) -> some View {
        Button { signIn(provider) } label: {
            HStack(spacing: 10) {
                if working == provider { ProgressView().tint(fg) } else { Image(systemName: system) }
                Text(title)
            }
            .font(CX.heading(17)).foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle()).disabled(working != nil)
    }

    private func signIn(_ provider: String) {
        error = nil; working = provider
        Task {
            do {
                _ = try await sb.signInWithOAuth(provider: provider)
                await app.bindAccount()
                Haptics.success()
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
                        .font(CX.body(17)).foregroundStyle(CX.navy).tint(CX.navy).padding(16)
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
                        .foregroundStyle(CX.navy).tint(CX.navy)
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
            Haptics.success()
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "That code didn't work."
            code = ""
        }
    }
}

// MARK: - 3. Profession

private struct ProfessionScreen: View {
    var progress: Double
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var choice: String = ""

    private struct P: Identifiable { let id = UUID(); let name: String; let icon: String }
    private let options: [P] = [
        .init(name: "Medical Student", icon: "graduationcap.fill"),
        .init(name: "Intern", icon: "stethoscope"),
        .init(name: "Resident", icon: "cross.case.fill"),
        .init(name: "Consultant", icon: "person.fill.checkmark"),
        .init(name: "Nurse", icon: "heart.text.square.fill"),
        .init(name: "Dentist", icon: "mouth.fill"),
        .init(name: "Physician Assistant", icon: "person.2.fill"),
        .init(name: "Nurse Practitioner", icon: "cross.vial.fill"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: nil)
            ScreenTitle(title: "What best describes you?", subtitle: "We'll tune every case to your world.")
                .padding(.top, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(options) { p in
                        OptionRow(icon: p.icon, title: p.name, subtitle: nil, selected: choice == p.name) {
                            choice = p.name
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 6)
            }
            CXButton(title: "Continue") { app.position = choice; onNext() }
                .padding(.horizontal, 20).disabled(choice.isEmpty).opacity(choice.isEmpty ? 0.5 : 1)
        }
        .padding(.bottom, 20)
        .onAppear { if choice.isEmpty { choice = app.position.isEmpty ? "" : app.position } }
    }
}

// MARK: - 4. Experience

private struct ExperienceScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var choice: String = ""

    private let levels: [(String, String, String)] = [
        ("Just starting out", "New to clinical reasoning", "leaf.fill"),
        ("Building confidence", "Some ward experience", "flame.fill"),
        ("Experienced", "Comfortable with most cases", "bolt.fill"),
        ("Seasoned", "I want a real challenge", "crown.fill"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "Where are you in your journey?", subtitle: "So cases feel challenging — never crushing.")
                .padding(.top, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(levels, id: \.0) { l in
                        OptionRow(icon: l.2, title: l.0, subtitle: l.1, selected: choice == l.0) { choice = l.0 }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 6)
            }
            CXButton(title: "Continue") {
                UserDefaults.standard.set(choice, forKey: "cx.experience"); onNext()
            }
            .padding(.horizontal, 20).disabled(choice.isEmpty).opacity(choice.isEmpty ? 0.5 : 1)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 5. Specialty interests

private struct SpecialtyScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var picked: Set<String> = []

    private let specialties = ["Cardiology","Emergency","Neurology","Pediatrics","Internal Medicine",
                               "Surgery","OB/GYN","Psychiatry","Respiratory","Dermatology","Nephrology","Endocrine"]
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "Which cases excite you?", subtitle: "Choose a few — we'll start there.")
                .padding(.top, 6)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(specialties, id: \.self) { s in
                        let on = picked.contains(s)
                        Button {
                            Haptics.tap()
                            if on { picked.remove(s) } else { picked.insert(s) }
                        } label: {
                            Text(s).font(CX.body(14)).foregroundStyle(on ? CX.tealDark : CX.navy)
                                .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
                                .background(on ? CX.tealSoft : CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(on ? CX.teal : CX.hairline, lineWidth: on ? 2 : 1.5))
                        }
                        .buttonStyle(PressStyle())
                    }
                }.padding(.horizontal, 20).padding(.bottom, 6)
            }
            VStack(spacing: 6) {
                Text(picked.isEmpty ? "Pick at least one" : "\(picked.count) selected")
                    .font(CX.label(12)).foregroundStyle(picked.isEmpty ? CX.navySoft : CX.teal)
                CXButton(title: "Continue") {
                    UserDefaults.standard.set(Array(picked), forKey: "cx.specialties"); onNext()
                }
                .disabled(picked.isEmpty).opacity(picked.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 6. Goal

private struct GoalScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var choice = ""

    private let goals: [(String, String)] = [
        ("Pass my exams", "target"),
        ("Feel confident on the ward", "cross.case.fill"),
        ("Sharpen my reasoning", "brain.head.profile"),
        ("Prep for my specialty", "star.fill"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "What are you training for?", subtitle: "We'll focus your plan on what matters most.")
                .padding(.top, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(goals, id: \.0) { g in
                        OptionRow(icon: g.1, title: g.0, subtitle: nil, selected: choice == g.0) { choice = g.0 }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 6)
            }
            CXButton(title: "Continue") { UserDefaults.standard.set(choice, forKey: "cx.goal"); onNext() }
                .padding(.horizontal, 20).disabled(choice.isEmpty).opacity(choice.isEmpty ? 0.5 : 1)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 7. Country

private struct CountryScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var selected: String

    init(progress: Double, onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.progress = progress; self.onBack = onBack; self.onNext = onNext
        let code = Locale.current.region?.identifier
        let name = code.flatMap { Locale(identifier: "en_US").localizedString(forRegionCode: $0) }
        _selected = State(initialValue: name ?? "United States")
    }

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

    private static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value).map(String.init) }.joined()
    }

    private var filtered: [(name: String, flag: String)] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? Self.all : Self.all.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 14) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "Where do you practice?",
                        subtitle: "So your daily and emergency patients arrive at the right local time.")
                .padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CX.navySoft)
                TextField("Search countries", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(CX.body(16))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(CX.navySoft)
                    }
                }
            }
            .padding(12)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CX.hairline, lineWidth: 1.5))
            .padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(filtered, id: \.name) { c in
                        Button { Haptics.tap(); selected = c.name } label: {
                            HStack(spacing: 12) {
                                Text(c.flag).font(.system(size: 26))
                                Text(c.name).font(CX.body(17)).foregroundStyle(CX.navy).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: selected == c.name ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(selected == c.name ? CX.orange : CX.hairline)
                            }
                            .padding(16)
                            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selected == c.name ? CX.orange : CX.hairline, lineWidth: 1.5))
                        }
                    }
                }.padding(.horizontal, 20)
            }
            CXButton(title: "Continue") { app.country = selected; onNext() }
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 8. How a case works

private struct HowItWorksScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var lit = 0

    private let steps: [(String, String)] = [
        ("Chief complaint", "person.wave.2.fill"),
        ("History & exam", "list.clipboard.fill"),
        ("Choose investigations", "testtube.2"),
        ("Read the results", "waveform.path.ecg"),
        ("Commit to a diagnosis", "checkmark.seal.fill"),
        ("Treat — now & long-term", "cross.case.fill"),
        ("Clinical insights + XP", "sparkles"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "One patient. Seven decisions.", subtitle: "The path you'll walk on every case.")
                .padding(.top, 6)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        let on = i <= lit
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(on ? CX.teal : CX.hairline).frame(width: 40, height: 40)
                                Image(systemName: steps[i].1).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(on ? .white : CX.navySoft)
                            }
                            .scaleEffect(on ? 1 : 0.9)
                            Text(steps[i].0).font(CX.heading(16))
                                .foregroundStyle(on ? CX.navy : CX.navySoft)
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        if i < steps.count - 1 {
                            Rectangle().fill(i < lit ? CX.teal : CX.hairline)
                                .frame(width: 3, height: 18).padding(.leading, 18)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: lit)
            }
            CXButton(title: "Meet your first patient", style: .teal) { onNext() }
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
        .onAppear { animate() }
    }

    private func animate() {
        lit = 0
        for i in 1..<steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.28) {
                Haptics.tap(); lit = i
            }
        }
    }
}

// MARK: - 9. Interactive mini patient case

private struct MiniCaseScreen: View {
    var progress: Double
    var onSolved: () -> Void

    @State private var stage = 0            // 0 complaint, 1 investigation, 2 diagnosis
    @State private var chosen: Int? = nil
    @State private var showWhy = false

    private struct Q { let prompt: String; let sub: String; let options: [(String, String, Bool)]; let mentor: String }
    private let invest = Q(
        prompt: "What do you order first?",
        sub: "One choice — think signal, speed and cost.",
        options: [("D-dimer", "Sensitive but nonspecific here", false),
                  ("12-lead ECG", "Fast, bedside, changes everything", true),
                  ("Chest X-ray", "Useful, but not first for this", false)],
        mentor: "Her story screams cardiac. A bedside ECG is fast and decisive — a D-dimer would only add noise and anchor you to the wrong path.")
    private let diagnose = Q(
        prompt: "ST-elevation in the inferior leads. Your diagnosis?",
        sub: "Commit — this is the moment that matters.",
        options: [("Pulmonary embolism", "Doesn't fit the ECG", false),
                  ("Inferior STEMI", "ST-elevation + classic story", true),
                  ("Anxiety", "Never diagnose by exclusion first", false)],
        mentor: "Inferior ST-elevation with exertional chest pain and diaphoresis is a STEMI until proven otherwise — time is muscle.")

    private var q: Q { stage == 1 ? invest : diagnose }

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: nil)

            // Patient header
            HStack(spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(CX.tealSoft).frame(width: 46, height: 46)
                    Text("🧑🏽").font(.system(size: 24)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Maria, 58").font(CX.heading(17)).foregroundStyle(CX.navy)
                    Text("Chief complaint").font(CX.label(12)).foregroundStyle(CX.navySoft)
                }
                Spacer()
            }.padding(.horizontal, 22).padding(.top, 4)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    CXCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\"My chest feels tight and my left arm aches.\"")
                                .font(CX.heading(17)).foregroundStyle(CX.navy)
                            Text("Started 40 minutes ago, worse on exertion. She's pale and sweaty.")
                                .font(CX.body(14)).foregroundStyle(CX.navySoft)
                            HStack(spacing: 6) {
                                ForEach(["BP 148/92","HR 98","SpO₂ 96%"], id: \.self) { v in
                                    Text(v).font(CX.label(11)).foregroundStyle(CX.tealDark)
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(CX.tealSoft, in: Capsule())
                                }
                            }.padding(.top, 2)
                        }
                    }

                    if stage >= 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stage == 1 ? "Investigation" : "Diagnosis")
                                .font(CX.label(12)).foregroundStyle(CX.orange)
                            Text(q.prompt).font(CX.heading(18)).foregroundStyle(CX.navy)
                            Text(q.sub).font(CX.body(13)).foregroundStyle(CX.navySoft)
                        }

                        VStack(spacing: 9) {
                            ForEach(q.options.indices, id: \.self) { i in
                                optionButton(i)
                            }
                        }

                        if chosen != nil {
                            Button { Haptics.light(); withAnimation { showWhy.toggle() } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text(showWhy ? "Hide Dr. Vix's reasoning" : "Ask Dr. Vix why")
                                }.font(CX.label(13)).foregroundStyle(CX.teal)
                            }
                            if showWhy {
                                Text(q.mentor).font(CX.body(13)).foregroundStyle(CX.navySoft)
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CX.tealSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: stage)
            }

            primaryButton
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private func optionButton(_ i: Int) -> some View {
        let correct = q.options[i].2
        let picked = chosen == i
        let reveal = chosen != nil
        let bg: Color = reveal && correct ? CX.tealSoft : (picked && !correct ? CX.orangeSoft : CX.card)
        let stroke: Color = reveal && correct ? CX.teal : (picked && !correct ? CX.orange : CX.hairline)
        let fg: Color = reveal && correct ? CX.tealDark : (picked && !correct ? CX.orangeDark : CX.navy)
        return Button {
            guard chosen == nil else { return }
            chosen = i
            if correct { Haptics.success() } else { Haptics.warning() }
            withAnimation { showWhy = false }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(q.options[i].0).font(CX.heading(16)).foregroundStyle(fg)
                    if reveal { Text(q.options[i].1).font(CX.body(12)).foregroundStyle(fg.opacity(0.85)) }
                }
                Spacer()
                if reveal && correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(CX.teal) }
                else if picked { Image(systemName: "xmark.circle.fill").foregroundStyle(CX.orange) }
            }
            .padding(14)
            .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stroke, lineWidth: picked || (reveal && correct) ? 2 : 1.5))
        }
        .buttonStyle(PressStyle()).disabled(chosen != nil)
    }

    @ViewBuilder private var primaryButton: some View {
        if stage == 0 {
            CXButton(title: "Choose your first investigation", style: .teal) { advance() }
        } else {
            CXButton(title: stage == 1 ? "See the result" : "Confirm diagnosis", style: .teal) { advance() }
                .disabled(chosen == nil).opacity(chosen == nil ? 0.5 : 1)
        }
    }

    private func advance() {
        Haptics.medium()
        if stage == 2 { onSolved(); return }
        withAnimation { stage += 1; chosen = nil; showWhy = false }
    }
}

// MARK: - 10. Celebration

private struct CelebrateScreen: View {
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var xp = 0
    @State private var awarded = false

    var body: some View {
        ZStack {
            ConfettiBurst()
            VStack(spacing: 18) {
                Spacer()
                VixClip(anim: .happy1, size: 168, fallback: .cheer).bounceIn()
                Text("+\(xp) XP")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(CX.gold).bounceIn(delay: 0.1)
                VStack(spacing: 8) {
                    Text("You just made your first clinical decision.")
                        .font(CX.title(24)).foregroundStyle(CX.navy).multilineTextAlignment(.center)
                    Text("That's the exact reasoning experts run on autopilot. You're on your way.")
                        .font(CX.body(15)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
                CXButton(title: "Keep going") { onNext() }
                    .padding(.horizontal, 22)
            }
            .padding(.bottom, 26)
        }
        .onAppear {
            if !awarded {
                awarded = true
                app.award(xp: 40)                      // a real head-start for solving the case
                Haptics.success()
                countUp()
            }
        }
    }

    private func countUp() {
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            if xp >= 40 { xp = 40; t.invalidate() } else { xp += 2 }
        }
    }
}

// MARK: - 11. Daily commitment (goal + reminder time)

private struct CommitmentScreen: View {
    var progress: Double
    var onNext: () -> Void
    @State private var goal = 3
    @State private var hour: Int? = 8

    private let goals: [(Int, String)] = [(1, "Casual"), (3, "Regular"), (5, "Serious")]
    private let times: [(Int, String, String)] = [(8, "Morning", "sun.max.fill"), (13, "Lunch", "cloud.sun.fill"), (20, "Evening", "moon.stars.fill")]

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: progress, onBack: nil)
            ScreenTitle(title: "Set your daily commitment", subtitle: "A small, steady habit beats cramming — pick a pace you'll keep.")
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Patients a day").font(CX.heading(15)).foregroundStyle(CX.navySoft)
                        HStack(spacing: 10) {
                            ForEach(goals, id: \.0) { g in
                                let on = goal == g.0
                                Button { Haptics.tap(); goal = g.0 } label: {
                                    VStack(spacing: 4) {
                                        Text("\(g.0)").font(.system(size: 26, weight: .heavy, design: .rounded))
                                            .foregroundStyle(on ? .white : CX.navy)
                                        Text(g.1).font(CX.label(12)).foregroundStyle(on ? .white.opacity(0.9) : CX.navySoft)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .background(on ? AnyShapeStyle(CX.tealButton) : AnyShapeStyle(CX.card),
                                               in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(on ? Color.clear : CX.hairline, lineWidth: 1.5))
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("When should we bring your patient?").font(CX.heading(15)).foregroundStyle(CX.navySoft)
                        HStack(spacing: 10) {
                            ForEach(times, id: \.0) { t in
                                let on = hour == t.0
                                Button { Haptics.tap(); hour = t.0 } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: t.2).font(.system(size: 22))
                                            .foregroundStyle(on ? CX.orange : CX.navySoft)
                                        Text(t.1).font(CX.label(12)).foregroundStyle(CX.navy)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                                    .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(on ? CX.orange : CX.hairline, lineWidth: on ? 2 : 1.5))
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        Button { Haptics.tap(); hour = nil } label: {
                            HStack {
                                Image(systemName: hour == nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(hour == nil ? CX.orange : CX.hairline)
                                Text("No reminders for now").font(CX.body(14)).foregroundStyle(CX.navySoft)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 6)
            }

            CXButton(title: "Continue") {
                UserDefaults.standard.set(goal, forKey: "cx.dailyGoalCases")
                if let hour {
                    NotificationManager.shared.scheduleDailyReminder(hour: hour, minute: 0)
                } else {
                    NotificationManager.shared.cancelDailyReminder()
                }
                onNext()
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 12. Plan summary + launch

private struct PlanScreen: View {
    var onFinish: () -> Void
    @EnvironmentObject var app: AppState
    @State private var inviteExpanded = false
    @State private var invite = ""
    @State private var shown = false

    private var specialties: [String] { UserDefaults.standard.stringArray(forKey: "cx.specialties") ?? [] }
    private var goal: String { UserDefaults.standard.string(forKey: "cx.goal") ?? "" }
    private var dailyGoal: Int { max(1, UserDefaults.standard.integer(forKey: "cx.dailyGoalCases")) }

    var body: some View {
        VStack(spacing: 16) {
            OnbBar(progress: 1.0, onBack: nil)
            ScreenTitle(title: "Your plan is ready", subtitle: "Built around your goal, level and the cases you love.")
                .padding(.top, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    CXCard {
                        VStack(spacing: 0) {
                            row("person.fill", "You", app.position.isEmpty ? "Clinician" : app.position)
                            divider
                            row("stethoscope", "Focus", specialties.isEmpty ? "A little of everything" : specialties.prefix(3).joined(separator: ", "))
                            divider
                            row("target", "Goal", goal.isEmpty ? "Sharpen my reasoning" : goal)
                            divider
                            row("flame.fill", "Daily", "\(dailyGoal) patient\(dailyGoal == 1 ? "" : "s") a day")
                            divider
                            row("globe", "Local delivery", app.country.isEmpty ? "Set" : app.country)
                        }
                    }
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 16)

                    // Optional invite code (preserves the referral entry point).
                    VStack(spacing: 8) {
                        Button { Haptics.light(); withAnimation { inviteExpanded.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gift.fill")
                                Text(inviteExpanded ? "Hide invite code" : "Have a friend's invite code?")
                            }.font(CX.label(13)).foregroundStyle(CX.teal)
                        }
                        if inviteExpanded {
                            TextField("Enter code", text: $invite)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                .font(CX.body(16)).foregroundStyle(CX.navy).tint(CX.navy)
                                .multilineTextAlignment(.center).padding(13)
                                .background(CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CX.hairline, lineWidth: 1.5))
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 6)
            }

            CXButton(title: "Begin today's patient", style: .orange) {
                let code = invite.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !code.isEmpty { app.pendingInviteCode = code }
                onFinish()
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1)) { shown = true }
            if invite.isEmpty, let pending = app.pendingInviteCode { invite = pending; inviteExpanded = true }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(CX.teal).frame(width: 24)
            Text(label).font(CX.body(14)).foregroundStyle(CX.navySoft)
            Spacer()
            Text(value).font(CX.heading(15)).foregroundStyle(CX.navy)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.vertical, 11)
    }

    private var divider: some View { Rectangle().fill(CX.hairline).frame(height: 1) }
}
