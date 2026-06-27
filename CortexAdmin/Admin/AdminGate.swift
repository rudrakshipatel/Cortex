import SwiftUI
import CryptoKit

/// Stores and verifies the admin PIN. The PIN itself is never persisted —
/// only its SHA-256 hash is kept in UserDefaults.
enum AdminAccess {
    private static let key = "cx.adminPINHash"

    static var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: key) ?? "").isEmpty
    }

    private static func hash(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func setPIN(_ pin: String) {
        UserDefaults.standard.set(hash(pin), forKey: key)
    }

    static func verify(_ pin: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: key) else { return false }
        return stored == hash(pin)
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
                if let error { Text(error).font(CX.label(13)).foregroundStyle(CX.orange) }

                Spacer()
                PINPad { digit in append(digit) } onDelete: { backspace() }
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
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
        guard entry.count < pinLength else { return }
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
            if AdminAccess.verify(entry) { onUnlock() }
            else { fail("Incorrect PIN") }
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
