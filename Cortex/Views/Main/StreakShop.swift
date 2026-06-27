import SwiftUI

// MARK: - Streak detail page (tap the streak pill)
struct StreakView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showShop = false

    private var headline: String {
        switch app.streak {
        case 0:      return "Start your streak!"
        case 1:      return "Great Start!"
        case 2...6:  return "Keep it going!"
        case 7...29: return "You're on fire!"
        default:     return "Unstoppable!"
        }
    }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold)).foregroundStyle(CX.navy)
                    }
                    Spacer()
                    pill("flame.fill", "\(app.streakFreezes)", Color(hex: 0x7FC8F0))   // freezes owned
                }
                .padding(.horizontal, 18).padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(app.streak)").font(.system(size: 72, weight: .heavy, design: .rounded))
                                    .foregroundStyle(CX.navySoft)
                                Text("Day Streak!").font(CX.title(26)).foregroundStyle(CX.navySoft)
                            }
                            Spacer()
                            Image(systemName: "flame.fill").font(.system(size: 92)).foregroundStyle(.orange)
                        }
                        Text(headline).font(CX.title(30)).foregroundStyle(CX.orange)
                        Text("Solve a case every day to keep the flame alive. Don't stop now!")
                            .font(CX.body(16)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)

                        StreakCalendar(activeDays: app.activeDays)

                        buyFreezeCard
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showShop) { StreakFreezeShop() }
    }

    private var buyFreezeCard: some View {
        CXCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Got Coins? Buy a Freeze!").font(CX.heading(20)).foregroundStyle(CX.teal)
                    bullet("Don't let one missed day break your momentum.")
                    bullet("Buy a Streak Freeze with your coins — stay consistent.")
                    Button { showShop = true } label: {
                        Text("Buy with Coins").font(CX.heading(17)).foregroundStyle(.white)
                    }
                    .buttonStyle(PushButtonStyle(face: CX.teal, lip: CX.tealDark))
                    .padding(.top, 4)
                }
                VixClip(anim: .tail, size: 80, fallback: .hero)
            }
        }
    }

    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(CX.teal)
            Text(t).font(CX.body(14)).foregroundStyle(CX.navySoft).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func pill(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(CX.label(15)).foregroundStyle(CX.navy)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.white, in: Capsule())
        .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
    }
}

// MARK: - Month calendar of streak days
private struct StreakCalendar: View {
    let activeDays: Set<Int>

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "GMT")!; return c
    }
    private let cols = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let first = cal.date(from: comps)!
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let monthName = first.formatted(.dateTime.month(.wide).year())
        let today = AppState.gmtDay()

        return CXCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(monthName).font(CX.title(22)).foregroundStyle(CX.navy)
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(["M","T","W","Th","F","Sa","Su"], id: \.self) { d in
                        Text(d).font(CX.label(12)).foregroundStyle(CX.navySoft)
                    }
                    ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(1...days, id: \.self) { d in
                        let date = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: d, hour: 12))!
                        let key = AppState.gmtDay(date)
                        dayCell(d: d, key: key, today: today)
                    }
                }
            }
        }
    }

    @ViewBuilder private func dayCell(d: Int, key: Int, today: Int) -> some View {
        if key > today {
            Text("\(d)").font(CX.body(15)).foregroundStyle(CX.navySoft).frame(height: 30)
        } else {
            Image(systemName: "flame.fill").font(.system(size: 20))
                .foregroundStyle(activeDays.contains(key) ? .orange : CX.hairline)
                .frame(height: 30)
        }
    }
}

// MARK: - Cortex Shop — Streak Freeze
struct StreakFreezeShop: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold)).foregroundStyle(CX.navy)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(CX.gold)
                        Text("\(app.coins)").font(CX.label(15)).foregroundStyle(CX.navy)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8).background(.white, in: Capsule())
                    .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        freezeIcon.frame(width: 150, height: 150).padding(.top, 8)
                        Text("Streak Freeze").font(CX.title(34)).foregroundStyle(CX.navySoft)
                        Text("Streak Freeze keeps your streak safe when life gets in the way")
                            .font(CX.body(17)).foregroundStyle(CX.navySoft)
                            .multilineTextAlignment(.center).padding(.horizontal, 16)

                        CXCard {
                            VStack(spacing: 12) {
                                HStack(spacing: 14) {
                                    ForEach(0..<5, id: \.self) { i in
                                        Image(systemName: "flame.fill").font(.system(size: 28))
                                            .foregroundStyle(i < app.streakFreezes ? Color(hex: 0x7FC8F0) : CX.hairline)
                                    }
                                }
                                Text("Pro tip: Always keep at least one Streak Freeze ready — you never know when you'll need it.")
                                    .font(CX.body(13)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
                            }
                        }

                        Spacer(minLength: 24)

                        VStack(spacing: 8) {
                            Button { confirm = true } label: {
                                Text("Buy Streak Freeze").font(CX.heading(18)).foregroundStyle(.white)
                            }.buttonStyle(PushButtonStyle(face: CX.orange, lip: CX.orangeDark))
                            Text("1 Streak Freeze = \(AppState.streakFreezeCost) coins")
                                .font(CX.label(13)).foregroundStyle(CX.teal)
                            Text("Peace of mind for your streak")
                                .font(CX.label(12)).foregroundStyle(CX.navySoft)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
            }
        }
        .confirmationDialog("Buy a Streak Freeze?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Buy for \(AppState.streakFreezeCost) coins") { _ = app.buyStreakFreeze() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.coins >= AppState.streakFreezeCost
                 ? "Spend \(AppState.streakFreezeCost) coins — you have \(app.coins)."
                 : "Not enough coins: you have \(app.coins), need \(AppState.streakFreezeCost).")
        }
    }

    private var freezeIcon: some View {
        ZStack {
            Image(systemName: "flame.fill").resizable().scaledToFit()
                .foregroundStyle(Color(hex: 0x7FC8F0))
            Image(systemName: "drop.fill").resizable().scaledToFit()
                .frame(width: 46).foregroundStyle(.white.opacity(0.55)).offset(y: 14)
        }
    }
}
