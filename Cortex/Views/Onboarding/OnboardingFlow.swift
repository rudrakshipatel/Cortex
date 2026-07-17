import SwiftUI

/// Cortex onboarding — a value-first flow that lets the user solve a real
/// (mini) patient before it ever asks for a commitment.
///
/// Order (new user): welcome → meet Dr. Vix → personalize (profession,
/// experience, specialties, goal) → country → how a case works → interactive
/// mini-case → emergency + notifications → daily commitment → plan → sign-in
/// (save progress) → launch.
///
/// A first-time user never authenticates up front: the whole value-first flow
/// runs as a guest and the sign-in screen only appears at the very end, to save
/// their progress. The sign-in screen is shown early ONLY when the user taps
/// "Already a member? Sign in" on the welcome screen. Either way a successful
/// sign-in (or "continue without an account") finishes onboarding.
struct OnboardingFlow: View {
    @EnvironmentObject var app: AppState
    @State private var step: Step
    @State private var forward = true
    /// True when the auth screen was reached via "Already a member? Sign in"
    /// (a focused sign-in) rather than as the final save-your-progress step.
    @State private var authFromSignIn = false

    enum Step {
        case welcome, meetVix, auth, profession, experience, specialty, goal, country
        case howItWorks, miniCase, emergency, commitment, plan, proPaywall
    }

    init(startAt: Step = .welcome) { _step = State(initialValue: startAt) }

    var body: some View {
        screen
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal:   .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            .animation(.easeOut(duration: 0.38), value: step)
    }

    @ViewBuilder private var screen: some View {
        switch step {
        case .welcome:
            AppBackground { WelcomeScreen(onStart: { go(.meetVix) },
                                          onSignIn: { authFromSignIn = true; go(.auth) }) }
        case .meetVix:
            AppBackground { MeetVixScreen { go(.profession) } }
        case .auth:
            AppBackground {
                AuthScreen(isSignIn: authFromSignIn,
                           onBack: authFromSignIn ? { back(.welcome) } : nil,
                           // End of onboarding + actually signed in → show the Pro
                           // paywall before entering. Guests and returning members
                           // go straight in.
                           onDone: {
                               if !authFromSignIn && SupabaseService.shared.isSignedIn {
                                   go(.proPaywall)
                               } else {
                                   finish()
                               }
                           })
            }
        case .proPaywall:
            AppBackground { ProPaywallScreen(onDone: finish) }
        case .profession:
            AppBackground { ProfessionScreen(progress: 0.14) { go(.experience) } }
        case .experience:
            AppBackground { ExperienceScreen(progress: 0.26, onBack: { back(.profession) }, onNext: { go(.specialty) }) }
        case .specialty:
            AppBackground { SpecialtyScreen(progress: 0.38, onBack: { back(.experience) }, onNext: { go(.goal) }) }
        case .goal:
            AppBackground { GoalScreen(progress: 0.50, onBack: { back(.specialty) }, onNext: { go(.country) }) }
        case .country:
            AppBackground { CountryScreen(progress: 0.62, onBack: { back(.goal) }, onNext: { go(.howItWorks) }) }
        case .howItWorks:
            AppBackground { HowItWorksScreen(progress: 0.72, onBack: { back(.country) }, onNext: { go(.miniCase) }) }
        case .miniCase:
            OnboardingCaseScreen(progress: 0.84) { go(.emergency) }
        case .emergency:
            AppBackground { EmergencyNotifyScreen(progress: 0.90) { go(.commitment) } }
        case .commitment:
            AppBackground { CommitmentScreen(progress: 0.94) { go(.plan) } }
        case .plan:
            AppBackground { PlanScreen { authFromSignIn = false; go(.auth) } }
        }
    }

    private func go(_ s: Step)   { forward = true;  step = s }
    private func back(_ s: Step) { forward = false; step = s }
    private func finish()        { withAnimation { app.finishOnboarding() } }
}

// MARK: - Shared chrome

/// Top bar with an optional back button and an animated progress track.
private struct OnbBar: View {
    var progress: Double
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CX.navySoft)
                        .frame(width: 38, height: 38)
                        .background(CX.card, in: Circle())
                        .overlay(Circle().stroke(CX.hairline, lineWidth: 1))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CX.navy.opacity(0.10))
                    Capsule().fill(CX.tealButton)
                        .frame(width: max(12, geo.size.width * progress))
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.45), value: progress)
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }
}

/// A selectable option row used across the personalization screens.
private struct OptionRow: View {
    var icon: String? = nil
    var title: String
    var subtitle: String? = nil
    var selected: Bool
    var onTap: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        } label: {
            HStack(spacing: 13) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 22))
                        .foregroundStyle(selected ? CX.orange : CX.teal)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CX.heading(17)).foregroundStyle(CX.navy)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(CX.body(13)).foregroundStyle(CX.navySoft)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? CX.orange : CX.hairline)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? CX.orange : CX.hairline, lineWidth: selected ? 2 : 1.5))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct ScreenTitle: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(CX.title(27)).foregroundStyle(CX.navy)
            Text(subtitle).font(CX.body(15)).foregroundStyle(CX.navySoft)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
    }
}

/// A rounded message bubble with a small tail on the leading edge — used to make
/// Dr. Vix look like he's speaking.
struct SpeechBubble<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
            .overlay(alignment: .leading) {
                BubbleTail()
                    .fill(CX.card)
                    .overlay(BubbleTail().stroke(CX.hairline, lineWidth: 1.5))
                    .frame(width: 9, height: 16)
                    .offset(x: -8)
            }
    }
}

private struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A delayed scale + fade "pop in" used by the walkthrough reveals.
private struct PopIn: ViewModifier {
    var delay: Double = 0
    var fromScale: CGFloat = 0.6
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : fromScale)
            .opacity(shown ? 1 : 0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { shown = true }
                }
            }
    }
}

private extension View {
    func popIn(delay: Double = 0, fromScale: CGFloat = 0.6) -> some View {
        modifier(PopIn(delay: delay, fromScale: fromScale))
    }
}

// MARK: - 1. Welcome

private struct WelcomeScreen: View {
    var onStart: () -> Void
    var onSignIn: () -> Void

    @State private var pulse = false
    @State private var bob = false
    @State private var kick: CGFloat = 0
    @State private var shown = false

    var body: some View {
        ZStack {
            // Ambient drifting colour orbs behind everything.
            VStack {
                HStack {
                    orb(CX.tealSoft, 280).offset(x: bob ? -120 : -90, y: bob ? -180 : -140)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    orb(CX.orangeSoft, 260).offset(x: bob ? -110 : -80, y: bob ? -160 : -120)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: bob)

            VStack(spacing: 0) {
                HStack {
                    CortexLogo(layout: .horizontal, size: 34)
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 8)

                Spacer()

                // Mascot on a pulsing halo — tap it for a playful bounce.
                mascot.bounceIn(delay: 0.15)

                Spacer().frame(height: 22)

                VStack(spacing: 10) {
                    Text("Think like a clinician.")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(CX.navy)
                    Text("Not a quiz — a real patient to work up, from the first complaint to the final call.")
                        .font(CX.body(16)).foregroundStyle(CX.navySoft)
                        .padding(.horizontal, 24)
                }
                .multilineTextAlignment(.center)
                .offset(y: shown ? 0 : 14)
                .opacity(shown ? 1 : 0)

                Spacer()

                VStack(spacing: 12) {
                    CXButton(title: "Get started") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onStart()
                    }
                    .scaleEffect(pulse ? 1.015 : 0.985)

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSignIn()
                    }) {
                        Text("Already a member? ").font(CX.body(15)).foregroundStyle(CX.navySoft)
                        + Text("Sign in").font(CX.body(15).bold()).foregroundStyle(CX.teal)
                    }

                    Text("Tap Dr. Vix to say hi — your first patient is already waiting.")
                        .font(CX.label(12)).foregroundStyle(CX.teal)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22).padding(.bottom, 26)
            }
        }
        .onAppear {
            bob = true
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { shown = true }
        }
    }

    private var mascot: some View {
        ZStack {
            Circle().fill(CX.teal.opacity(0.12))
                .frame(width: 220, height: 220)
                .scaleEffect(pulse ? 1.08 : 0.9)
            Circle().stroke(CX.teal.opacity(0.28), lineWidth: 2)
                .frame(width: 196, height: 196)
                .scaleEffect(pulse ? 1.15 : 0.98)
                .opacity(pulse ? 0 : 0.8)
            VixClip(anim: .wave, size: 168, fallback: .cheer)
                .offset(y: bob ? -7 : 7)
                .scaleEffect(1 + 0.07 * kick)
        }
        .frame(width: 240, height: 240)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { kick = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { kick = 0 }
            }
        }
    }

    private func orb(_ color: Color, _ size: CGFloat) -> some View {
        Circle().fill(color.opacity(0.65))
            .frame(width: size, height: size)
            .blur(radius: 42)
    }
}

// MARK: - 2. Meet Dr. Vix

private struct MeetVixScreen: View {
    var onNext: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VixClip(anim: .wave, size: 220, fallback: .cheer).bounceIn(delay: 0.15)
            Spacer().frame(height: 28)
            VStack(spacing: 8) {
                Text("Hi, I'm Dr. Vix")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(CX.navy)
                Text("Your Personal Mentor").font(CX.title(22)).foregroundStyle(CX.teal)
            }
            .multilineTextAlignment(.center)
            .opacity(shown ? 1 : 0)
            Spacer()
            CXButton(title: "Continue") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onNext()
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 26)
        .onAppear { withAnimation(.easeOut(duration: 0.6).delay(0.15)) { shown = true } }
    }
}

// MARK: - 3. Auth

private struct AuthScreen: View {
    var isSignIn = false
    var onBack: (() -> Void)? = nil
    var onDone: () -> Void

    @EnvironmentObject var app: AppState
    @EnvironmentObject var sb: SupabaseService
    @State private var working: String?     // which provider is in-flight
    @State private var error: String?
    @State private var showEmail = false

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CX.navySoft)
                            .frame(width: 38, height: 38)
                            .background(CX.card, in: Circle())
                            .overlay(Circle().stroke(CX.hairline, lineWidth: 1))
                    }
                    Spacer()
                }
            }
            Spacer()
            CortexLogo(layout: .stacked, size: 68, showTagline: true)
            Spacer().frame(height: 12)
            Text(isSignIn ? "Welcome back" : "Save your progress")
                .font(CX.title(26)).foregroundStyle(CX.navy)
            Spacer().frame(height: 4)
            Text(isSignIn
                 ? "Sign in to pick up your streak, XP and roadmap right where you left off."
                 : "Keep your streak, XP and roadmap on every device — or start playing now and sign in later.")
                .font(CX.body(14)).foregroundStyle(CX.navySoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer().frame(height: 12)
            VixClip(anim: .wave, size: 150, fallback: .idle)
            Spacer()

            VStack(spacing: 13) {
                authButton("Continue with Google", system: "g.circle.fill",
                           fg: .white, bg: AnyShapeStyle(CX.navy), provider: "google")
                authButton("Continue with Apple", system: "applelogo",
                           fg: .white, bg: AnyShapeStyle(Color.black), provider: "apple")

                Button { showEmail = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                        Text("Continue with Email")
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

                if !isSignIn {
                    Button("Continue without an account") { onDone() }
                        .font(CX.heading(15)).foregroundStyle(CX.navySoft)
                        .disabled(working != nil)
                }

                Text("By continuing, you agree to our terms & privacy policy.")
                    .font(CX.label(11)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .sheet(isPresented: $showEmail) {
            // The sheet binds the account itself; a signed-in state means success.
            EmailSignInSheet(onSignedIn: onDone)
        }
    }

    private func authButton(_ title: String, system: String, fg: Color, bg: AnyShapeStyle, provider: String) -> some View {
        Button { signIn(provider) } label: {
            HStack(spacing: 8) {
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
                // account), then hand back to the flow — it decides between the Pro
                // paywall and launch.
                await app.bindAccount()
                working = nil
                onDone()
            } catch {
                working = nil
                self.error = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Please try again."
            }
        }
    }
}

// MARK: - 3b. Email sign-in (6-digit code)

struct EmailSignInSheet: View {
    /// Called after a verified code has bound the account. Onboarding uses this
    /// to advance the flow; callers elsewhere can ignore it.
    var onSignedIn: (() -> Void)? = nil

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
            dismiss()
            onSignedIn?()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "That code didn't work."
            code = ""
        }
    }
}

// MARK: - 4. Profession

private struct ProfessionScreen: View {
    var progress: Double
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var choice = ""

    private let options: [(String, String)] = [
        ("Medical Student", "graduationcap.fill"),
        ("Intern", "cross.case.fill"),
        ("Resident", "stethoscope"),
        ("Consultant", "checkmark.seal.fill"),
        ("Nurse", "heart.fill"),
        ("Dentist", "facemask.fill"),
        ("Physician Assistant", "person.2.fill"),
        ("Nurse Practitioner", "syringe.fill"),
        ("Other", "ellipsis.circle.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress)
            Spacer().frame(height: 16)
            ScreenTitle(title: "What best describes you?", subtitle: "We'll tune every case to your world.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(options, id: \.0) { o in
                        OptionRow(icon: o.1, title: o.0, selected: choice == o.0) { choice = o.0 }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            CXButton(title: "Continue", enabled: !choice.isEmpty) {
                app.position = choice
                onNext()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
        .onAppear { if !app.position.isEmpty { choice = app.position } }
    }
}

// MARK: - 5. Experience

private struct ExperienceScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var choice = ""

    private let levels: [(String, String, String)] = [
        ("Just starting out", "New to clinical reasoning", "leaf.fill"),
        ("Building confidence", "Some ward experience", "flame.fill"),
        ("Experienced", "Comfortable with most cases", "bolt.fill"),
        ("Seasoned", "I want a real challenge", "rosette"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress, onBack: onBack)
            Spacer().frame(height: 16)
            ScreenTitle(title: "Where are you in your journey?", subtitle: "So cases feel challenging — never crushing.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(levels, id: \.0) { l in
                        OptionRow(icon: l.2, title: l.0, subtitle: l.1, selected: choice == l.0) { choice = l.0 }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            CXButton(title: "Continue", enabled: !choice.isEmpty) {
                app.experience = choice
                onNext()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
        .onAppear { if !app.experience.isEmpty { choice = app.experience } }
    }
}

// MARK: - 6. Specialty interests

private struct SpecialtyScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var picked: Set<String> = []

    private let specialties = [
        "Cardiology", "Emergency", "Neurology", "Pediatrics", "Internal Medicine",
        "Surgery", "OB/GYN", "Psychiatry", "Respiratory", "Dermatology", "Nephrology", "Endocrine",
    ]
    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress, onBack: onBack)
            Spacer().frame(height: 16)
            ScreenTitle(title: "Which specialities excite you?", subtitle: "Choose a few — we'll start there.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(specialties, id: \.self) { s in
                        let on = picked.contains(s)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if on { picked.remove(s) } else { picked.insert(s) }
                        } label: {
                            Text(s)
                                .font(CX.body(14)).foregroundStyle(on ? CX.tealDark : CX.navy)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14).padding(.horizontal, 8)
                                .background(on ? CX.tealSoft : CX.card,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(on ? CX.teal : CX.hairline, lineWidth: on ? 2 : 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            Text(picked.isEmpty ? "Pick at least one" : "\(picked.count) selected")
                .font(CX.label(12)).foregroundStyle(picked.isEmpty ? CX.navySoft : CX.teal)
                .padding(.vertical, 6)
            CXButton(title: "Continue", enabled: !picked.isEmpty) {
                app.specialtyInterests = Array(picked)
                onNext()
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
        .onAppear { picked = Set(app.specialtyInterests) }
    }
}

// MARK: - 7. Goal

private struct GoalScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var choice = ""

    private let goals: [(String, String)] = [
        ("Pass my exams", "target"),
        ("Feel confident on the ward", "cross.case.fill"),
        ("Sharpen my reasoning", "brain.head.profile"),
        ("Prep for my specialty", "star.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress, onBack: onBack)
            Spacer().frame(height: 16)
            ScreenTitle(title: "What are you training for?", subtitle: "We'll focus your plan on what matters most.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(goals, id: \.0) { g in
                        OptionRow(icon: g.1, title: g.0, selected: choice == g.0) { choice = g.0 }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            CXButton(title: "Continue", enabled: !choice.isEmpty) {
                app.trainingGoal = choice
                onNext()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
        .onAppear { if !app.trainingGoal.isEmpty { choice = app.trainingGoal } }
    }
}

// MARK: - 8. Country

private struct CountryScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var selected: String

    init(progress: Double, onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.progress = progress
        self.onBack = onBack
        self.onNext = onNext
        _selected = State(initialValue: Self.defaultCountry)
    }

    /// The pre-selected country. The United States by default, per the flow's
    /// design — not the device region.
    private static let defaultCountry = "United States"

    /// Popular practice locations, pinned above the full list in this order.
    private static let popularNames = [
        "United States", "United Kingdom", "Australia", "Canada", "New Zealand",
        "India", "Germany", "Japan", "Spain", "France", "Brazil", "Nigeria",
        "Pakistan", "Bangladesh", "South Africa", "China", "Egypt", "Mexico",
        "Indonesia", "Philippines", "Nepal", "Sri Lanka", "United Arab Emirates",
        "Saudi Arabia", "Italy", "Netherlands", "Singapore", "Kenya", "Ghana", "Ireland",
    ]

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

    /// The popular entries, in their pinned order (dropping any the platform
    /// doesn't name).
    private static let popular: [(name: String, flag: String)] = {
        let byName = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return popularNames.compactMap { byName[$0] }
    }()

    /// Everything else, alphabetical.
    private static let rest: [(name: String, flag: String)] = {
        let pinned = Set(popularNames)
        return all.filter { !pinned.contains($0.name) }
    }()

    /// Turn a 2-letter ISO code into its flag emoji (regional indicators).
    private static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value).map(String.init) }
            .joined()
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    /// While searching, one flat list across every country; otherwise the pinned
    /// popular ones first, then the rest under their own heading.
    private var filtered: [(name: String, flag: String)] {
        Self.all.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 14) {
            OnbBar(progress: progress, onBack: onBack)
            ScreenTitle(title: "Where do you practice?",
                        subtitle: "So your daily and emergency patients arrive at the right local time.")

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
            .padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if query.isEmpty {
                        ForEach(Self.popular, id: \.name) { row($0) }
                        heading("ALL COUNTRIES")
                        ForEach(Self.rest, id: \.name) { row($0) }
                    } else {
                        ForEach(filtered, id: \.name) { row($0) }
                    }
                }
                .padding(.horizontal, 20)
            }
            CXButton(title: "Continue") { app.country = selected; onNext() }
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(CX.label(12)).foregroundStyle(CX.navySoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func row(_ c: (name: String, flag: String)) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selected = c.name
        } label: {
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
        .buttonStyle(.plain)
    }
}

// MARK: - 9. How a case works (walkthrough)

private struct HowItWorksScreen: View {
    var progress: Double
    var onBack: () -> Void
    var onNext: () -> Void
    @State private var walk = 0
    private let lastStep = 5

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress, onBack: onBack)
            Spacer().frame(height: 16)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    // Dr. Vix, standing, with a speech bubble — fixed across steps.
                    HStack(alignment: .center, spacing: 12) {
                        Image("vix-standing")
                            .resizable().scaledToFill()
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        SpeechBubble {
                            Text("Let me explain how each case works.")
                                .font(CX.heading(16)).foregroundStyle(CX.navy)
                        }
                    }
                    // The current step's cards slide in from the right.
                    stepContent(walk)
                        .id(walk)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6)
            }
            CXButton(title: "Continue") {
                if walk < lastStep {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeOut(duration: 0.42)) { walk += 1 }
                } else {
                    onNext()
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder private func stepContent(_ step: Int) -> some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 16) {
                Text("Patient comes with a complaint.").font(CX.title(20)).foregroundStyle(CX.navy)
                WalkCard("chief-complaint-card")
            }
        case 1:
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyse History & Physical Examination").font(CX.title(20)).foregroundStyle(CX.navy)
                WalkCard("history-card")
                WalkCard("physical-exam-card")
            }
        case 2: OrderTestsStep()
        case 3: DiagnosisTreatmentStep()
        case 4: GetFeedbackStep()
        default: GetFullAnalysisStep()
        }
    }
}

/// A walkthrough card — the supplied transparent card image, aspect-fit.
private struct WalkCard: View {
    let asset: String
    init(_ asset: String) { self.asset = asset }
    var body: some View {
        Image(asset).resizable().scaledToFit().frame(maxWidth: .infinity)
    }
}

/// A walkthrough video slot — a bundled looping clip at its native portrait
/// dimensions (aspect-fit), on a rounded card.
private struct WalkVideo: View {
    let resource: String
    var height: CGFloat = 268
    // The clips are full portrait phone recordings (~1320×2700).
    private let aspect: CGFloat = 1320.0 / 2700.0

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: resource, withExtension: "mp4") {
                LoopingVideo(url: url)
            } else {
                CX.card
            }
        }
        .frame(width: height * aspect, height: height)
        .background(CX.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
        .shadow(color: CX.navy.opacity(0.08), radius: 8, y: 4)
    }
}

/// Walkthrough step 3: order a test (video), an orange arrow, then three result
/// cards that pop in one by one.
private struct OrderTestsStep: View {
    private let results = ["result-ecg", "result-cxr", "result-cbc"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Order Tests").font(CX.title(20)).foregroundStyle(CX.navy)
            HStack(spacing: 8) {
                WalkVideo(resource: "onboarding-tests", height: 268)
                    .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CX.orange)
                    .popIn(delay: 0.35, fromScale: 0.9)
                VStack(spacing: 10) {
                    ForEach(Array(results.enumerated()), id: \.element) { i, r in
                        WalkCard(r).frame(width: 120)
                            .popIn(delay: 0.85 + Double(i) * 0.3)
                    }
                }
            }
        }
    }
}

/// Walkthrough step 4: pick a diagnosis (video); after it has played, an orange
/// arrow emerges toward the treatment (a second video).
private struct DiagnosisTreatmentStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Diagnosis & give Treatment").font(CX.title(20)).foregroundStyle(CX.navy)
            HStack(spacing: 8) {
                WalkVideo(resource: "onboarding-diagnosis", height: 300)
                    .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CX.orange)
                    .popIn(delay: 1.6, fromScale: 0.9)
                WalkVideo(resource: "onboarding-treatment", height: 300)
                    .frame(maxWidth: .infinity)
                    .popIn(delay: 1.7, fromScale: 0.9)
            }
        }
    }
}

/// Walkthrough step 5: three feedback pictures stacked, popping in one by one.
private struct GetFeedbackStep: View {
    private let pics = ["feedback-tests", "feedback-diagnosis", "feedback-treatment"]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Get feedback").font(CX.title(20)).foregroundStyle(CX.navy)
            ForEach(Array(pics.enumerated()), id: \.element) { i, p in
                WalkCard(p).popIn(delay: 0.35 + Double(i) * 0.3, fromScale: 0.94)
            }
        }
    }
}

/// Walkthrough step 6: seven analysis pictures that pop in one by one, arranged
/// as an overlapping scattered pile.
private struct GetFullAnalysisStep: View {
    private let cardSize: CGFloat = 250
    // (asset, x, y, rotation°) offsets from the pile centre.
    private let pics: [(String, CGFloat, CGFloat, Double)] = [
        ("analysis-insights", -125, -210, -4),
        ("analysis-ddx", 125, -185, 4),
        ("analysis-learning", -140, -55, 4),
        ("analysis-tests", 140, -30, -3),
        ("analysis-pearls", 0, 105, -3),
        ("analysis-treatment", -130, 235, 4),
        ("analysis-traps", 135, 210, -4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get full analysis of the case").font(CX.title(20)).foregroundStyle(CX.navy)
            ZStack {
                ForEach(Array(pics.enumerated()), id: \.element.0) { i, p in
                    WalkCard(p.0)
                        .frame(width: cardSize)
                        .rotationEffect(.degrees(p.3))
                        .offset(x: p.1, y: p.2)
                        .popIn(delay: 0.3 + Double(i) * 0.22)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 720)
        }
    }
}

// MARK: - 10. Interactive onboarding case

/// The single case every new user solves during onboarding. A short Dr. Vix
/// intro leads into the app's real CaseFlow, run in onboarding mode.
private struct OnboardingCaseScreen: View {
    var progress: Double
    var onDone: () -> Void
    @State private var started = false

    var body: some View {
        if started {
            CaseFlow(clinicalCase: onboardingCase, consumesLife: false,
                     onboarding: true, onboardingContinue: onDone)
        } else {
            AppBackground {
                VStack(spacing: 0) {
                    OnbBar(progress: progress)
                    Spacer()
                    Image("vix-standing").resizable().scaledToFit()
                        .frame(width: 168, height: 168)
                    Spacer().frame(height: 18)
                    SpeechBubble {
                        Text("Now let's solve a case!").font(CX.heading(18)).foregroundStyle(CX.navy)
                    }
                    .padding(.horizontal, 40)
                    Spacer().frame(height: 18)
                    Text("A real patient is waiting. Read the story, order your tests, commit to a diagnosis and treat — exactly how every case works in Cortex.")
                        .font(CX.body(16)).foregroundStyle(CX.navySoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Spacer()
                    CXButton(title: "Start the case") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        started = true
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - 11. Emergency case + notifications permission

/// After the first case: Dr. Vix warns that emergencies can strike any time, an
/// emergency case drops in from above, then we prime the user for notifications
/// with a stylised Allow / Don't Allow prompt.
private struct EmergencyNotifyScreen: View {
    var progress: Double
    var onNext: () -> Void
    @State private var dropped = false
    @State private var showPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    HStack(alignment: .center, spacing: 12) {
                        Image("vix-standing")
                            .resizable().scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        SpeechBubble {
                            Text("Emergency case can come at any time")
                                .font(CX.heading(16)).foregroundStyle(CX.navy)
                        }
                    }
                    Image("onboarding-emergency")
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .red.opacity(0.18), radius: 14, y: 8)
                        .offset(y: dropped ? 0 : -260)
                        .opacity(dropped ? 1 : 0)

                    VStack(spacing: 14) {
                        Text("Allow Cortex to send you notifications")
                            .font(CX.heading(18)).foregroundStyle(CX.navy)
                            .multilineTextAlignment(.center)
                        VStack(spacing: 0) {
                            Button(action: allow) {
                                Text("Allow").font(CX.heading(18)).foregroundStyle(.red)
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                            }
                            Divider().overlay(CX.hairline)
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onNext()
                            } label: {
                                Text("Don't Allow").font(CX.body(16))
                                    .foregroundStyle(CX.navySoft.opacity(0.55))
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                            }
                        }
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
                    }
                    .opacity(showPrompt ? 1 : 0)
                }
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
            }
            CXButton(title: "Continue") { onNext() }
                .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { dropped = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                withAnimation(.easeOut(duration: 0.4)) { showPrompt = true }
            }
        }
    }

    private func allow() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationManager.shared.requestAuthorization { _ in
            DispatchQueue.main.async { onNext() }
        }
    }
}

// MARK: - 12. Daily commitment

private struct CommitmentScreen: View {
    var progress: Double
    var onNext: () -> Void
    @EnvironmentObject var app: AppState
    @State private var goal = 5
    @State private var hour: Int? = 9

    private let goals: [(Int, String)] = [(3, "Casual"), (5, "Regular"), (10, "Serious")]
    private let times: [(Int, String, String)] = [
        (9, "Morning", "sun.max.fill"), (12, "Lunch", "cloud.sun.fill"), (18, "Evening", "moon.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: progress)
            Spacer().frame(height: 16)
            ScreenTitle(title: "Set your daily commitment",
                        subtitle: "A small, steady habit beats cramming — pick a pace you'll keep.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Patients a day").font(CX.heading(15)).foregroundStyle(CX.navySoft)
                    Spacer().frame(height: 10)
                    HStack(spacing: 10) {
                        ForEach(goals, id: \.0) { g in goalCard(g.0, g.1) }
                    }
                    Spacer().frame(height: 20)
                    Text("When should we bring your patient?").font(CX.heading(15)).foregroundStyle(CX.navySoft)
                    Spacer().frame(height: 10)
                    HStack(spacing: 10) {
                        ForEach(times, id: \.0) { t in timeCard(t.0, t.1, t.2) }
                    }
                    Spacer().frame(height: 10)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        hour = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hour == nil ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(hour == nil ? CX.orange : CX.hairline)
                            Text("No reminders for now").font(CX.body(14)).foregroundStyle(CX.navySoft)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            CXButton(title: "Continue") {
                app.dailyGoalCases = goal
                if let hour {
                    NotificationManager.shared.scheduleDailyReminder(hour: hour, minute: 0)
                } else {
                    NotificationManager.shared.cancelDailyReminder()
                }
                onNext()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
    }

    private func goalCard(_ value: Int, _ label: String) -> some View {
        let on = goal == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            goal = value
        } label: {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(on ? .white : CX.navy)
                Text(label).font(CX.label(12))
                    .foregroundStyle(on ? .white.opacity(0.9) : CX.navySoft)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background {
                if on { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CX.tealButton) }
                else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CX.card) }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(on ? .clear : CX.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func timeCard(_ h: Int, _ label: String, _ icon: String) -> some View {
        let on = hour == h
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            hour = h
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22))
                    .foregroundStyle(on ? CX.orange : CX.navySoft)
                Text(label).font(CX.label(12)).foregroundStyle(CX.navy)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(on ? CX.orange : CX.hairline, lineWidth: on ? 2 : 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 13. Plan summary + launch

private struct PlanScreen: View {
    var onFinish: () -> Void
    @EnvironmentObject var app: AppState
    @State private var inviteExpanded = false
    @State private var invite = ""
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            OnbBar(progress: 1.0)
            Spacer().frame(height: 16)
            ScreenTitle(title: "Your plan is ready",
                        subtitle: "Built around your goal, level and the cases you love.")
            Spacer().frame(height: 12)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    CXCard {
                        VStack(spacing: 0) {
                            row("person.fill", "You", app.position.isEmpty ? "Clinician" : app.position)
                            divider
                            row("cross.case.fill", "Focus", app.specialtyInterests.isEmpty
                                ? "A little of everything" : app.specialtyInterests.prefix(3).joined(separator: ", "))
                            divider
                            row("target", "Goal", app.trainingGoal.isEmpty ? "Sharpen my reasoning" : app.trainingGoal)
                            divider
                            row("flame.fill", "Daily", "\(app.dailyGoalCases) patient\(app.dailyGoalCases == 1 ? "" : "s") a day")
                            divider
                            row("globe", "Local delivery", app.country.isEmpty ? "Set" : app.country)
                        }
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation { inviteExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill").font(.system(size: 14))
                            Text(inviteExpanded ? "Hide invite code" : "Have a friend's invite code?")
                                .font(CX.label(13))
                        }
                        .foregroundStyle(CX.teal)
                    }

                    if inviteExpanded {
                        TextField("Enter code", text: $invite)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .multilineTextAlignment(.center)
                            .font(CX.body(16)).foregroundStyle(CX.navy).padding(14)
                            .background(CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CX.hairline, lineWidth: 1.5))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
                .offset(y: shown ? 0 : 12)
                .opacity(shown ? 1 : 0)
            }
            CXButton(title: "Begin today's patient") {
                let code = invite.trimmingCharacters(in: .whitespaces).uppercased()
                if !code.isEmpty { app.pendingInviteCode = code }
                onFinish()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .padding(.bottom, 20)
        .onAppear {
            if let pending = app.pendingInviteCode, !pending.isEmpty {
                invite = pending; inviteExpanded = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) { shown = true }
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(CX.teal)
                .frame(width: 24)
            Text(label).font(CX.body(14)).foregroundStyle(CX.navySoft)
            Spacer()
            Text(value).font(CX.heading(15)).foregroundStyle(CX.navy)
                .multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.vertical, 11)
    }

    private var divider: some View { Rectangle().fill(CX.hairline).frame(height: 1) }
}

// MARK: - 14. Pro paywall (after sign-in, before launch)

/// The final onboarding step for a just-signed-in user: a Free-vs-Pro comparison
/// (tick / cross), what Pro unlocks, then the two Pro plans. "Maybe later" enters
/// the app on the free plan.
private struct ProPaywallScreen: View {
    var onDone: () -> Void
    @EnvironmentObject var store: StoreManager
    @State private var selectedId: String?
    @State private var working = false
    @State private var message: String?

    /// Free-vs-Pro feature matrix.
    private let rows: [(String, Bool, Bool)] = [
        ("Daily clinical case", true, true),
        ("Half the energy per case", false, true),
        ("Emergency cases", false, true),
        ("AI tutor on any case", false, true),
        ("Advanced & senior-level cases", false, true),
        ("Full mentor reasoning on every case", false, true),
    ]

    private var selected: ProPlan? { store.plans.first { $0.id == selectedId } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VixClip(anim: .wave, size: 110, fallback: .hero).padding(.top, 14)
                    Text("Unlock Cortex Pro").font(CX.title(30)).foregroundStyle(CX.navy)
                    Text("See exactly what Pro adds — then pick a plan.")
                        .font(CX.heading(16)).foregroundStyle(CX.navySoft)
                        .multilineTextAlignment(.center)
                    comparison
                    planPicker
                    if let message {
                        Text(message).font(CX.label(13)).foregroundStyle(CX.orange)
                            .multilineTextAlignment(.center)
                    }
                    Text("Auto-renewable subscription. Cancel anytime in Settings ▸ Apple ID ▸ Subscriptions.")
                        .font(CX.label(11)).foregroundStyle(CX.navySoft)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.bottom, 10)
            }
            VStack(spacing: 8) {
                CXButton(title: working ? "Processing…" : cta, icon: nil, style: .teal,
                         enabled: !working && !store.plans.isEmpty) {
                    Task { await subscribe() }
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDone()
                } label: {
                    Text("Maybe later").font(CX.label(15)).foregroundStyle(CX.navySoft)
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 14)
        }
        .onAppear { selectedId = selectedId ?? defaultPlanId }
        .onChange(of: store.plans.count) { _, _ in selectedId = selectedId ?? defaultPlanId }
    }

    private var cta: String { selected?.trialLabel != nil ? "Start Free Trial" : "Go Pro" }

    private var defaultPlanId: String? {
        store.plans.first(where: \.isAnnual)?.id ?? store.plans.first?.id
    }

    private var comparison: some View {
        CXCard {
            VStack(spacing: 0) {
                HStack {
                    Text("What you get").font(CX.heading(14)).foregroundStyle(CX.navySoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Free").font(CX.label(13)).foregroundStyle(CX.navySoft).frame(width: 52)
                    Text("Pro").font(CX.label(13)).foregroundStyle(CX.orange).frame(width: 52)
                }
                .padding(.bottom, 10)
                ForEach(rows, id: \.0) { r in
                    Rectangle().fill(CX.hairline).frame(height: 1)
                    HStack {
                        Text(r.0).font(CX.body(14)).foregroundStyle(CX.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        mark(r.1).frame(width: 52)
                        mark(r.2).frame(width: 52)
                    }
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private func mark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(on ? CX.teal : .red.opacity(0.5))
    }

    @ViewBuilder private var planPicker: some View {
        if store.plans.isEmpty {
            CXCard {
                VStack(spacing: 8) {
                    if store.loadFailed {
                        Text("Plans are unavailable right now.")
                            .font(CX.body(15)).foregroundStyle(CX.navy)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView().tint(CX.teal)
                        Text("Loading plans…").font(CX.label(13)).foregroundStyle(CX.navySoft)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(store.plans) { p in planRow(p, p.id == selectedId) }
            }
        }
    }

    private func planRow(_ plan: ProPlan, _ isSelected: Bool) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedId = plan.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? CX.orange : CX.hairline)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(CX.heading(17)).foregroundStyle(CX.navy).lineLimit(1)
                        if plan.isAnnual {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(CX.teal, in: Capsule())
                        }
                    }
                    Text(plan.periodLabel).font(CX.body(14)).foregroundStyle(CX.navySoft)
                    if let trial = plan.trialLabel {
                        Text("✨ \(trial), then renews").font(CX.label(12)).foregroundStyle(CX.teal)
                    }
                }
                Spacer(minLength: 8)
                Text(plan.priceString).font(CX.heading(18)).foregroundStyle(CX.navy)
            }
            .padding(16)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? CX.orange : CX.hairline, lineWidth: isSelected ? 2 : 1.5))
        }
        .buttonStyle(.plain)
    }

    private func subscribe() async {
        guard let plan = selected else { return }
        working = true; message = nil
        defer { working = false }
        do {
            let outcome = try await store.purchase(plan)
            switch outcome {
            case .success: onDone()
            case .pending: message = "Your purchase is pending approval."
            default: break
            }
        } catch {
            message = "Purchase couldn't be completed. Please try again."
        }
    }
}

// MARK: - Onboarding case data (STEMI) — the single case every new user solves.

let onboardingCase = ClinicalCase(
    specialty: "Cardiology",
    patientName: "John Miller",
    gender: "Male",
    age: "62 Y",
    chiefComplaint: "Chest pain for 2 hours",
    infoCards: [
        InfoCard(
            title: "Basic Info & Chief Complaint",
            bullets: ["62-year-old male", "Chief complaint: central chest pain for 2 hours"],
            mentor: "Sudden, exertional, pressure-like chest pain in an older smoker is acute coronary syndrome until proven otherwise.",
            groups: [
                InfoGroup(system: "Vitals", findings: ["BP 150/90 mmHg", "HR 102 bpm", "RR 18/min", "Temp 37°C (98.6°F)", "SpO₂ 98% on room air"]),
            ]),
        InfoCard(
            title: "History (Hx)",
            bullets: [
                "Sudden central chest pain that began while walking",
                "Pressure-like in character",
                "Radiates to the left arm",
                "Associated sweating and mild nausea",
                "Known hypertension",
                "30-year smoking history",
            ],
            mentor: "Radiation to the arm, diaphoresis and cardiac risk factors (hypertension, smoking) strongly raise the pre-test probability of a myocardial infarction."),
        InfoCard(
            title: "Physical Examination",
            bullets: [],
            mentor: "The exam is unremarkable apart from distress and tachycardia — in ACS the diagnosis rests on the history and ECG, not the exam.",
            groups: [
                InfoGroup(system: "General", findings: ["Appears uncomfortable and diaphoretic"]),
                InfoGroup(system: "Cardiovascular", findings: ["Tachycardia", "Normal heart sounds", "No murmurs"]),
                InfoGroup(system: "Respiratory", findings: ["Clear lungs bilaterally"]),
                InfoGroup(system: "Abdomen", findings: ["Soft, non-tender"]),
                InfoGroup(system: "Extremities", findings: ["No edema"]),
            ]),
    ],
    tests: [
        TestOption(category: "Cardiology", name: "ECG", result: "ST-segment elevation in leads II, III and aVF — inferior STEMI", helpful: true,
                   mentor: "The decisive test — inferior ST-elevation mandates immediate reperfusion."),
        TestOption(category: "Cardiac biomarkers", name: "Troponin I", result: "Elevated", helpful: true,
                   mentor: "Confirms myocardial injury — but a clear STEMI on the ECG should not wait for it."),
        TestOption(category: "Radiology", name: "Chest X-ray", result: "No acute cardiopulmonary abnormality", helpful: false,
                   mentor: "Reasonable to exclude other causes, but not required before reperfusion in a clear STEMI."),
        TestOption(category: "Hematology", name: "D-Dimer", result: "Mildly raised (non-specific)", helpful: false,
                   mentor: "Low-yield here and risks anchoring you toward pulmonary embolism."),
        TestOption(category: "Radiology", name: "Abdominal Ultrasound", result: "Normal", helpful: false,
                   mentor: "No abdominal signs — not indicated."),
        TestOption(category: "Radiology", name: "CT Brain", result: "Normal", helpful: false,
                   mentor: "No neurological features — not indicated."),
    ],
    diagnosisQuestion: "Which diagnosis best fits this presentation?",
    diagnoses: [
        DiagnosisOption(name: "Stable Angina", correct: false),
        DiagnosisOption(name: "Gastroesophageal Reflux Disease", correct: false),
        DiagnosisOption(name: "ST-Elevation Myocardial Infarction (STEMI)", correct: true),
        DiagnosisOption(name: "Panic Attack", correct: false),
        DiagnosisOption(name: "Pneumonia", correct: false),
    ],
    treatments: [
        TreatmentOption(category: "Reperfusion", name: "Activate the cardiac catheterization (PCI) team", appropriate: true),
        TreatmentOption(category: "Disposition", name: "Discharge home", appropriate: false),
        TreatmentOption(category: "Medications", name: "Start antibiotics", appropriate: false),
        TreatmentOption(category: "Imaging", name: "Order an abdominal CT scan", appropriate: false),
    ],
    outcomeTitle: "Well Done",
    outcomeBody: "You recognised an acute inferior STEMI from the history and ECG and activated primary PCI without delay — exactly the call that saves myocardium. Time is muscle.",
    xpReward: 25,
    mentorInsight: MentorInsightContent(
        reasoning: "Exertional, pressure-like central chest pain radiating to the left arm with diaphoresis in a hypertensive smoker is classic acute coronary syndrome. Inferior ST-elevation (II, III, aVF) with a raised troponin confirms an acute inferior STEMI.",
        differentials: "Stable angina resolves with rest and lacks ST-elevation. GERD and panic attack don't raise troponin or the ST segment. Pneumonia would give fever, cough and abnormal lungs/chest X-ray — all absent here.",
        testRationale: "A 12-lead ECG is the single decisive test and should be done within 10 minutes of arrival — it triggers reperfusion. Troponin confirms myocardial injury. Chest X-ray, D-dimer, abdominal ultrasound and CT brain are low-yield and must not delay treatment.",
        treatmentSequencing: "Time is muscle: immediately activate the cardiac catheterization (PCI) team for primary PCI. Aspirin, a second antiplatelet, anticoagulation and analgesia are given alongside — but nothing should delay reperfusion.",
        pearls: [
            ClinicalPearl(
                title: "Inferior STEMI: always get a right-sided ECG",
                body: "Inferior STEMI (II, III, aVF) — always get a right-sided ECG to catch right-ventricular involvement, and use nitrates cautiously if the RV is involved or the blood pressure is low."),
        ]),
    vitals: Vitals(bp: "150/90", pr: "102", rr: "18", spo2: "98%", temperature: "37°C")
)
