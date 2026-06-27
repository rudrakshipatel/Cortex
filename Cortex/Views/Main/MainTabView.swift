import SwiftUI
import StoreKit

struct MainTabView: View {
    @EnvironmentObject var store: ContentStore
    @EnvironmentObject var notif: NotificationManager
    @State private var tab = 0
    @State private var emergencyCase: ClinicalCase?

    var body: some View {
        TabView(selection: $tab) {
            HomeView().tag(0)
                .tabItem { Label("Home", systemImage: "house.fill") }
            PracticeView().tag(1)
                .tabItem { Label("Practice", systemImage: "stethoscope") }
            LeaguesView().tag(2)
                .tabItem { Label("League", systemImage: "rosette") }
            MeView().tag(3)
                .tabItem { Label("Me", systemImage: "pawprint.fill") }
        }
        .tint(CX.orange)
        // Open the emergency case when its notification is tapped. Local-first;
        // falls back to fetching it from Supabase (server-broadcast emergencies).
        .onChange(of: notif.openEmergencyID) { _, id in
            guard let id else { return }
            if let ec = store.emergency(id: id) {
                emergencyCase = ec.clinicalCase
                notif.openEmergencyID = nil
            } else {
                Task {
                    emergencyCase = await SupabaseService.shared.fetchEmergencyCase(id: id)
                    notif.openEmergencyID = nil
                }
            }
        }
        .fullScreenCover(item: $emergencyCase) { c in
            CaseFlow(clinicalCase: c)
        }
    }
}

// MARK: - Shared top bar (Energy / Coins / XP / GO PRO)
struct TopBar: View {
    @EnvironmentObject var app: AppState
    @State private var showPro = false
    @State private var showStreak = false
    /// Ticks energy regeneration while the app is open.
    private let energyTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 8) {
            EnergyBar(value: app.life, max: AppState.maxLife, showsLabel: false)
            resource("dollarsign.circle.fill", "\(app.coins)", CX.gold)
            resource("bolt.circle.fill", "\(app.lifetimeXP)", CX.teal)
            Spacer()
            Button { showStreak = true } label: {
                resource("flame.fill", "\(app.streak)", .orange)
            }
            Button { showPro = true } label: {
                Text("GO PRO").font(CX.label(14)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(CX.tealButton, in: Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .sheet(isPresented: $showPro) { GoProSheet() }
        .sheet(isPresented: $showStreak) { StreakView() }
        .onAppear { app.refreshForNewDay() }
        .onReceive(energyTimer) { _ in app.regenerateEnergy() }
    }

    private func resource(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(CX.label(14)).foregroundStyle(CX.navy)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
    }
}

// MARK: - Energy bar (replaces the old "lives" counter)
struct EnergyBar: View {
    let value: Int
    let max: Int
    /// Optional explicit bar width; nil = compact (top bar).
    var width: CGFloat = 54
    var showsLabel = true

    private var frac: Double { Swift.min(1, Swift.max(0, Double(value) / Double(Swift.max(max, 1)))) }
    private var fill: Color { frac > 0.5 ? .green : (frac > 0.2 ? CX.orange : .red) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(fill)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.08)).frame(width: width, height: 9)
                Capsule().fill(fill).frame(width: width * frac, height: 9)
            }
            if showsLabel {
                Text("\(value)").font(CX.label(13)).foregroundStyle(CX.navy).monospacedDigit()
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
    }
}

// MARK: - Go Pro upsell
struct GoProSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: StoreManager
    @State private var selectedID: String?
    @State private var working = false
    @State private var message: String?

    var body: some View {
        AppBackground {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VixClip(anim: .wave, size: 150, fallback: .hero).padding(.top, 16)
                    Text("GO PRO").font(CX.title(34)).foregroundStyle(CX.navy)
                    Text("Serious Training for Serious Clinicians.")
                        .font(CX.heading(18)).foregroundStyle(CX.navy).multilineTextAlignment(.center)

                    CXCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cortex Pro unlocks:").font(CX.heading(17)).foregroundStyle(CX.teal)
                            proRow("Advanced & senior-level cases")
                            proRow("High-complexity, multi-morbidity patients")
                            proRow("Full mentor reasoning on every case")
                            proRow("Unlimited practice")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if store.isPro {
                        proActiveCard
                    } else {
                        planPicker
                        subscribeButton
                        HStack(spacing: 16) {
                            Button("Restore Purchases") { Task { await restore() } }
                            Text("·").foregroundStyle(CX.hairline)
                            Button("Redeem a Code") { store.redeemCode() }
                        }
                        .font(CX.label(14)).foregroundStyle(CX.teal).disabled(working)
                        Text("Auto-renewable subscription. Cancel anytime in Settings. Payment is charged to your Apple ID.")
                            .font(CX.label(11)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                    }

                    if let message {
                        Text(message).font(CX.label(13)).foregroundStyle(CX.orange).multilineTextAlignment(.center)
                    }
                    Button("No thanks") { dismiss() }
                        .font(CX.label(15)).foregroundStyle(CX.navySoft).padding(.top, 2)
                }
                .padding(.horizontal, 22).padding(.bottom, 24)
            }
        }
        .onAppear { selectedID = selectedID ?? store.plans.last?.id }
        .onChange(of: store.plans.count) { _, _ in
            if selectedID == nil { selectedID = store.plans.last?.id }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var planPicker: some View {
        if store.plans.isEmpty {
            CXCard {
                VStack(spacing: 8) {
                    if store.loadFailed {
                        Text("Plans are unavailable right now.").font(CX.body(15)).foregroundStyle(CX.navy)
                        Text("Check your connection and try again later.").font(CX.label(12)).foregroundStyle(CX.navySoft)
                    } else {
                        ProgressView().tint(CX.teal)
                        Text("Loading plans…").font(CX.label(13)).foregroundStyle(CX.navySoft)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(store.plans) { plan in
                    planRow(plan)
                }
            }
        }
    }

    private func planRow(_ plan: ProPlan) -> some View {
        let isSelected = selectedID == plan.id
        return Button { selectedID = plan.id } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22)).foregroundStyle(isSelected ? CX.orange : CX.hairline)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(CX.heading(17)).foregroundStyle(CX.navy)
                        if plan.isAnnual {
                            Text("BEST VALUE").font(CX.label(10)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(CX.teal, in: Capsule())
                        }
                    }
                    Text(plan.periodLabel).font(CX.body(14)).foregroundStyle(CX.navySoft)
                    if let trial = plan.trialLabel {
                        Text("✨ \(trial), then renews").font(CX.label(12)).foregroundStyle(CX.teal)
                    }
                }
                Spacer()
                Text(plan.priceString).font(CX.heading(18)).foregroundStyle(CX.navy)
            }
            .padding(16)
            .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? CX.orange : CX.hairline, lineWidth: isSelected ? 2 : 1.5))
        }.buttonStyle(.plain)
    }

    private var selectedPlan: ProPlan? { store.plans.first { $0.id == selectedID } }

    private var subscribeButton: some View {
        let cta = selectedPlan?.trialLabel != nil ? "Start Free Trial" : "Subscribe"
        return Button { Task { await subscribe() } } label: {
            HStack(spacing: 8) {
                if working { ProgressView().tint(.white) }
                Text(working ? "Processing…" : cta)
            }
            .font(CX.heading(18)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(CX.tealButton, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(working || store.plans.isEmpty)
        .opacity(store.plans.isEmpty ? 0.5 : 1)
    }

    private var proActiveCard: some View {
        VStack(spacing: 14) {
            CXCard(borderColor: CX.teal) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 34)).foregroundStyle(CX.teal)
                    Text("You're Pro! 🎉").font(CX.heading(20)).foregroundStyle(CX.navy)
                    Text("All advanced cases and mentor reasoning are unlocked.")
                        .font(CX.body(14)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            Button { manageSubscriptions() } label: {
                Text("Manage or Cancel Subscription")
                    .font(CX.heading(16)).foregroundStyle(CX.navy)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(CX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1.5))
            }.buttonStyle(PressStyle())
            Text("Cancelling stops the next renewal — you keep Pro until the current period ends.")
                .font(CX.label(11)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
        }
    }

    /// Open Apple's native Manage Subscriptions sheet (the only sanctioned way to
    /// cancel an auto-renewing subscription — it can't be cancelled in-app).
    private func manageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            // Fall back to the App Store subscriptions page.
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                UIApplication.shared.open(url)
            }
            return
        }
        Task { try? await AppStore.showManageSubscriptions(in: scene) }
    }

    private func proRow(_ t: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(CX.teal)
            Text(t).font(CX.body(15)).foregroundStyle(CX.navySoft)
        }
    }

    // MARK: Actions

    private func subscribe() async {
        guard let id = selectedID, let plan = store.plans.first(where: { $0.id == id }) else { return }
        working = true; message = nil
        defer { working = false }
        do {
            switch try await store.purchase(plan) {
            case .success: dismiss()
            case .pending:  message = "Your purchase is pending approval."
            case .cancelled: break
            }
        } catch {
            message = "Purchase couldn't be completed. Please try again."
        }
    }

    private func restore() async {
        working = true; message = nil
        await store.restore()
        working = false
        if store.isPro { dismiss() } else { message = "No active subscription found to restore." }
    }
}
