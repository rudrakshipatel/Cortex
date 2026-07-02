import SwiftUI

// MARK: - Cortex Shop (tap the coins pill)
//
// Spend coins on Streak Freezes and XP, and see every way to earn more — wired
// to Cortex's real coin economy (daily activity, league finishes, mastery
// trophies). Opened from the coins pill in the top bar.
struct CortexShop: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Purchase?

    /// A coin purchase offered in the shop.
    enum Purchase: Identifiable {
        case freeze1, freeze3, xp
        var id: Int { switch self { case .freeze1: 0; case .freeze3: 1; case .xp: 2 } }
        var cost: Int {
            switch self {
            case .freeze1: AppState.streakFreezeCost
            case .freeze3: AppState.streakFreezeCost * 3
            case .xp:      AppState.xpPackCost
            }
        }
        var name: String {
            switch self {
            case .freeze1: "Streak Freeze × 1"
            case .freeze3: "Streak Freeze × 3"
            case .xp:      "XP × \(AppState.xpPackAmount)"
            }
        }
        var icon: String { self == .xp ? "bolt.fill" : "flame.fill" }
        var tint: Color { self == .xp ? CX.teal : Color(hex: 0x7FC8F0) }
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold)).foregroundStyle(CX.navy)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        Text("Cortex Shop").font(CX.title(34)).foregroundStyle(CX.navy)
                        Text("Use your coins to boost streaks, buy XP, and stay in the game longer.")
                            .font(CX.body(16)).foregroundStyle(CX.navySoft)
                            .multilineTextAlignment(.center).padding(.horizontal, 8)

                        coinsPill

                        // Purchases
                        CXCard {
                            VStack(spacing: 0) {
                                buyRow(.freeze1)
                                Divider().overlay(CX.hairline)
                                buyRow(.freeze3)
                                Divider().overlay(CX.hairline)
                                buyRow(.xp)
                            }
                        }

                        // How to earn
                        Text("How to Earn Coins in Cortex")
                            .font(CX.title(24)).foregroundStyle(CX.navy)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        earnCard("flame.fill", .orange, "Daily Activity", [
                            ("+100", "Every time you complete your daily streak by playing a case."),
                            ("+500", "When you break your highest-ever streak."),
                            ("+500", "For every 10-day streak milestone (e.g., 10, 20, 30 days…)."),
                        ])
                        earnCard("bolt.fill", CX.teal, "Leaderboard", [
                            ("+\(Seed.leagueTopThreeReward)", "Top 3 finish in a league."),
                            ("+\(Seed.leaguePromotionReward)", "Getting promoted in league."),
                            ("+\(Seed.leagueSafeReward)", "Staying in a league."),
                        ])
                        earnCard("trophy.fill", CX.teal, "Trophies", [
                            ("+\(AppState.bronzeTrophyReward)", "For every Bronze Trophy."),
                            ("+\(AppState.silverTrophyReward)", "For every Silver Trophy."),
                            ("+\(AppState.goldTrophyReward)", "For every Gold Trophy."),
                        ])
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
            }
        }
        .confirmationDialog(pending?.name ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { p in
            Button("Buy for \(p.cost) coins") { buy(p) }.disabled(app.coins < p.cost)
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(app.coins >= p.cost
                 ? "Spend \(p.cost) coins — you have \(app.coins)."
                 : "Not enough coins: you have \(app.coins), need \(p.cost).")
        }
    }

    private var coinsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill").foregroundStyle(CX.gold)
            Text("\(app.coins)").font(CX.heading(18)).foregroundStyle(CX.navy).monospacedDigit()
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(.white, in: Capsule())
        .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
    }

    private func buyRow(_ p: Purchase) -> some View {
        Button { pending = p } label: {
            HStack(spacing: 12) {
                Image(systemName: p.icon).font(.system(size: 22)).foregroundStyle(p.tint).frame(width: 30)
                Text(p.name).font(CX.heading(18)).foregroundStyle(CX.navy)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "dollarsign.circle.fill").foregroundStyle(CX.gold)
                    Text("\(p.cost)").font(CX.heading(18)).foregroundStyle(CX.navy).monospacedDigit()
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func earnCard(_ icon: String, _ tint: Color, _ title: String, _ rows: [(String, String)]) -> some View {
        CXCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
                    Text(title).font(CX.heading(20)).foregroundStyle(CX.teal)
                }
                ForEach(rows, id: \.0) { amount, desc in
                    HStack(alignment: .top, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill").font(.system(size: 14)).foregroundStyle(CX.gold)
                            Text("\(amount) coins").font(CX.heading(14)).foregroundStyle(CX.navy)
                        }
                        .fixedSize()
                        Text("- \(desc)").font(CX.body(14)).foregroundStyle(CX.navySoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buy(_ p: Purchase) {
        switch p {
        case .freeze1: _ = app.buyStreakFreeze(count: 1)
        case .freeze3: _ = app.buyStreakFreeze(count: 3)
        case .xp:      _ = app.buyXP()
        }
    }
}
