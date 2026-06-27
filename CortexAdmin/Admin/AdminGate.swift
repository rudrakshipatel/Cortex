import SwiftUI
import CommonCrypto
import Security

/// Stores and verifies the admin PIN.
///
/// The PIN is never persisted. We store a **PBKDF2-SHA256** hash (150k
/// iterations) with a random per-install salt in the **Keychain**, and we
/// rate-limit verification with an escalating lockout. A short numeric PIN can't
/// be made un-brute-forceable on a device an attacker fully controls, but the
/// salt defeats precomputation and the lockout makes online guessing impractical.
enum AdminAccess {
    private static let saltKey = "cx.adminPINSalt"        // Keychain
    private static let hashKey = "cx.adminPINHash"        // Keychain
    private static let failKey = "cx.adminPINFails"       // UserDefaults (not secret)
    private static let lockKey = "cx.adminPINLockUntil"   // UserDefaults (not secret)
    private static let maxAttempts = 5
    private static let iterations = 150_000

    static var isConfigured: Bool { Keychain.get(hashKey) != nil }

    // MARK: PBKDF2

    private static func derive(_ pin: String, salt: Data) -> String {
        let pinBytes = Array(pin.utf8)
        let saltBytes = [UInt8](salt)
        var out = [UInt8](repeating: 0, count: 32)
        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pin, pinBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &out, out.count)
        return Data(out).base64EncodedString()
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// Constant-time string comparison (avoids leaking match progress via timing).
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    static func setPIN(_ pin: String) {
        let salt = randomSalt()
        Keychain.set(salt.base64EncodedString(), for: saltKey)
        Keychain.set(derive(pin, salt: salt), for: hashKey)
        UserDefaults.standard.removeObject(forKey: "cx.adminPINHash_legacy")
        resetFailures()
    }

    static func verify(_ pin: String) -> Bool {
        guard let saltB64 = Keychain.get(saltKey), let salt = Data(base64Encoded: saltB64),
              let stored = Keychain.get(hashKey) else { return false }
        return constantTimeEqual(derive(pin, salt: salt), stored)
    }

    // MARK: Lockout

    static var isLockedOut: Bool { lockoutRemaining > 0 }

    /// Seconds remaining on the current lockout (0 if not locked).
    static var lockoutRemaining: Int {
        let until = UserDefaults.standard.double(forKey: lockKey)
        return max(0, Int(until.rounded() - Date().timeIntervalSince1970))
    }

    static var attemptsRemaining: Int {
        max(0, maxAttempts - UserDefaults.standard.integer(forKey: failKey))
    }

    /// Record a wrong PIN. Once `maxAttempts` is hit, lock for an escalating
    /// window (30s, then doubling, capped at 1 hour).
    static func registerFailure() {
        let d = UserDefaults.standard
        let fails = d.integer(forKey: failKey) + 1
        d.set(fails, forKey: failKey)
        if fails >= maxAttempts {
            let over = Double(fails - maxAttempts)
            let delay = min(30.0 * pow(2.0, over), 3600)
            d.set(Date().timeIntervalSince1970 + delay, forKey: lockKey)
        }
    }

    static func resetFailures() {
        let d = UserDefaults.standard
        d.removeObject(forKey: failKey)
        d.removeObject(forKey: lockKey)
    }
}

/// Presented when the admin long-presses their profile. Handles first-run PIN
/// creation and subsequent unlock, then reveals the dashboard.
struct AdminContainer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false

    var body: some View {
        Group {
            if unlocked {
                AdminDashboard()
            } else {
                AdminGate(onUnlock: { unlocked = true }, onCancel: { dismiss() })
            }
        }
    }
}

private struct AdminGate: View {
    var onUnlock: () -> Void
    var onCancel: () -> Void

    @State private var stage: Stage = AdminAccess.isConfigured ? .enter : .create
    @State private var entry = ""
    @State private var firstEntry = ""        // for create-confirm
    @State private var error: String?
    @State private var shake = 0
    @State private var lockRemaining = AdminAccess.lockoutRemaining

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Stage { case create, confirm, enter }
    private let pinLength = 4

    var body: some View {
        AppBackground {
            VStack(spacing: 22) {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CX.navy).frame(width: 40, height: 40)
                        .background(CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(CX.teal)
                Text(title).font(CX.title(26)).foregroundStyle(CX.navy)
                    .multilineTextAlignment(.center)
                Text(subtitle).font(CX.body(15)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)

                dots.modifier(Shake(animatableData: CGFloat(shake)))
                if lockRemaining > 0 {
                    Text("Too many attempts. Try again in \(lockRemaining)s.")
                        .font(CX.label(13)).foregroundStyle(CX.orange)
                } else if let error {
                    Text(error).font(CX.label(13)).foregroundStyle(CX.orange)
                }

                Spacer()
                PINPad { digit in append(digit) } onDelete: { backspace() }
                    .padding(.bottom, 12)
                    .disabled(lockRemaining > 0)
                    .opacity(lockRemaining > 0 ? 0.4 : 1)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
        .onReceive(tick) { _ in lockRemaining = AdminAccess.lockoutRemaining }
    }

    private var title: String {
        switch stage {
        case .create:  return "Create Admin PIN"
        case .confirm: return "Confirm Admin PIN"
        case .enter:   return "Admin Access"
        }
    }
    private var subtitle: String {
        switch stage {
        case .create:  return "Set a \(pinLength)-digit PIN. Only you will use this to upload content."
        case .confirm: return "Re-enter your PIN to confirm."
        case .enter:   return "Enter your PIN to manage questions."
        }
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<pinLength, id: \.self) { i in
                Circle()
                    .fill(i < entry.count ? CX.teal : Color.clear)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(CX.teal, lineWidth: 2))
            }
        }
    }

    private func append(_ d: String) {
        guard lockRemaining == 0, entry.count < pinLength else { return }
        error = nil
        entry += d
        if entry.count == pinLength { submit() }
    }
    private func backspace() { if !entry.isEmpty { entry.removeLast() } }

    private func submit() {
        switch stage {
        case .create:
            firstEntry = entry
            entry = ""
            stage = .confirm
        case .confirm:
            if entry == firstEntry {
                AdminAccess.setPIN(entry)
                onUnlock()
            } else {
                fail("PINs didn't match. Start again.")
                stage = .create; firstEntry = ""
            }
        case .enter:
            if AdminAccess.verify(entry) {
                AdminAccess.resetFailures()
                lockRemaining = 0
                onUnlock()
            } else {
                AdminAccess.registerFailure()
                lockRemaining = AdminAccess.lockoutRemaining
                if lockRemaining > 0 {
                    fail("Too many attempts. Locked for \(lockRemaining)s.")
                } else {
                    fail("Incorrect PIN · \(AdminAccess.attemptsRemaining) tries left")
                }
            }
        }
    }

    private func fail(_ msg: String) {
        error = msg
        entry = ""
        withAnimation(.default) { shake += 1 }
    }
}

// MARK: - Number pad
private struct PINPad: View {
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    private let rows = [["1","2","3"],["4","5","6"],["7","8","9"],["","0","⌫"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 72, height: 72)
        } else {
            Button {
                if key == "⌫" { onDelete() } else { onDigit(key) }
            } label: {
                Text(key)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(CX.navy)
                    .frame(width: 72, height: 72)
                    .background(CX.card, in: Circle())
                    .overlay(Circle().stroke(CX.hairline, lineWidth: 1.5))
            }
            .buttonStyle(PressStyle())
        }
    }
}

// MARK: - Shake animation for wrong PIN
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = sin(animatableData * .pi * 4) * 8
        return ProjectionTransform(CGAffineTransform(translationX: t, y: 0))
    }
}
