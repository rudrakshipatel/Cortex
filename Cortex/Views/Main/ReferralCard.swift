import SwiftUI

/// "Invite friends → 1 free month" card. Shows the signed-in user's invite
/// link + progress toward the reward, and lets them claim the free month once
/// they've referred `SupabaseService.referralGoal` friends who signed up. The
/// grant itself is server-verified (grant-referral-reward Edge Function).
struct ReferralCard: View {
    @EnvironmentObject var sb: SupabaseService
    @EnvironmentObject var store: StoreManager

    @State private var stats: SupabaseService.ReferralStats?
    @State private var loading = false
    @State private var claiming = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private var goal: Int { SupabaseService.referralGoal }

    var body: some View {
        CXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invite friends, get Pro free").font(CX.title(20)).foregroundStyle(CX.navy)
                        Text("Invite \(goal) friends who sign up and earn 1 free month of Cortex Pro.")
                            .font(CX.body(14)).foregroundStyle(CX.navySoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "gift.fill").font(.system(size: 36)).foregroundStyle(CX.orange)
                }

                if !sb.isSignedIn {
                    Text("Sign in to get your personal invite link and start earning.")
                        .font(CX.label(13)).foregroundStyle(CX.teal)
                    shareButton(url: CXDeepLink.appDownloadURL,
                                message: "Join me on Cortex — real clinical cases, real ranks. 🦊🩺")
                } else if let s = stats {
                    progressBar(count: s.count)
                    Text("\(s.count) / \(goal) friends joined")
                        .font(CX.label(13)).foregroundStyle(CX.navySoft)

                    if let url = CXDeepLink.inviteURL(code: s.code) {
                        shareButton(url: url,
                                    message: "Join me on Cortex — real clinical cases, real ranks. Use my invite code \(s.code)! 🦊🩺")
                    }

                    if s.rewardGranted {
                        Label("Free month unlocked 🎉", systemImage: "checkmark.seal.fill")
                            .font(CX.heading(15)).foregroundStyle(CX.teal)
                    } else if s.count >= goal {
                        claimButton
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { Task { await reload() } }
        .alert("Referrals", isPresented: $showAlert) {
            Button("OK") {}
        } message: { Text(alertMessage ?? "") }
    }

    private func progressBar(count: Int) -> some View {
        let frac = min(1.0, Double(count) / Double(goal))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CX.hairline).frame(height: 10)
                Capsule().fill(CX.orange).frame(width: geo.size.width * frac, height: 10)
            }
        }
        .frame(height: 10)
    }

    private func shareButton(url: URL, message: String) -> some View {
        ShareLink(item: url, subject: Text("Join me on Cortex"), message: Text(message)) {
            Label("Share invite link", systemImage: "square.and.arrow.up")
                .font(CX.heading(16)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(CX.orangeButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(PressStyle())
    }

    private var claimButton: some View {
        Button { Task { await claim() } } label: {
            HStack {
                if claiming { ProgressView().tint(.white) }
                Text("Claim your free month").font(CX.heading(16)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(CX.tealButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(claiming)
    }

    private func reload() async {
        guard sb.isSignedIn else { stats = nil; return }
        loading = stats == nil
        stats = await sb.referralStats()
        loading = false
    }

    private func claim() async {
        claiming = true
        defer { claiming = false }
        if let error = await sb.claimReferralReward() {
            alertMessage = error
        } else {
            await store.refreshEntitlement()      // reflect the new Pro entitlement
            await reload()
            alertMessage = "🎉 You've unlocked 1 free month of Cortex Pro!"
        }
        showAlert = true
    }
}
