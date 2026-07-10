import SwiftUI

/// Past Cases — replay previous daily cases from a calendar. Unlocked once the
/// player has solved today's daily. Each past case costs energy like a random
/// case (25 free / 8.5 Pro); daily-solve state drives the per-day styling.
struct PastCasesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: ContentStore
    @Environment(\.dismiss) private var dismiss

    @State private var monthAnchor = PastCasesView.startOfMonth(Date())
    @State private var specialty: String? = nil        // nil = All
    @State private var active: ClinicalCase?
    @State private var activeDay: Int?
    @State private var showNoLife = false

    // MARK: GMT calendar helpers (daily cases are keyed by GMT day)
    private static var gmtCal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "GMT")!
        c.firstWeekday = 1   // Sunday, matching the reference layout
        return c
    }
    private static func startOfMonth(_ d: Date) -> Date {
        let c = gmtCal
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? d
    }

    // MARK: Data
    /// Daily cases strictly before today — the replayable pool.
    private var pastCases: [DailyCase] { store.dailyCases.filter { $0.dayKey < app.todayKey } }
    private var filteredPast: [DailyCase] {
        guard let sp = specialty else { return pastCases }
        return pastCases.filter { $0.clinicalCase.specialty == sp }
    }
    private var specialties: [String] { Array(Set(pastCases.map { $0.clinicalCase.specialty })).sorted() }
    private var byDay: [Int: DailyCase] {
        Dictionary(filteredPast.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var total: Int { filteredPast.count }
    private var solvedCount: Int { filteredPast.filter { app.solvedDaily(day: $0.dayKey) }.count }
    private var missedCount: Int { total - solvedCount }

    var body: some View {
        AppBackground {
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if !specialties.isEmpty { specialtyChips }
                        statsRow
                        calendarCard
                        legend
                    }
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
                }
            }
        }
        .fullScreenCover(item: $active) { c in
            CaseFlow(clinicalCase: c, consumesLife: true, onFinish: { solved in
                if solved, let day = activeDay { app.markDailySolved(day: day) }
            })
        }
        .alert("Not enough Energy", isPresented: $showNoLife) { Button("OK") {} } message: {
            Text("Each past case costs \(AppState.energyText(app.randomCaseCost)) energy, which refills over time.")
        }
    }

    // MARK: Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(CX.navySoft)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Past Cases").font(CX.title(22)).foregroundStyle(CX.teal)
                Text("Pick a date to revisit a previous mystery!")
                    .font(CX.label(12)).foregroundStyle(CX.navySoft)
            }
            Spacer()
            Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(.clear)  // balances the layout
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)
    }

    // MARK: Specialty filter
    private var specialtyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All (\(pastCases.count))", selected: specialty == nil) { specialty = nil }
                ForEach(specialties, id: \.self) { sp in
                    chip(sp, selected: specialty == sp) { specialty = sp }
                }
            }.padding(.horizontal, 2)
        }
    }
    private func chip(_ text: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text).font(CX.label(13)).foregroundStyle(selected ? .white : CX.navy)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(CX.teal) : AnyShapeStyle(CX.card), in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : CX.hairline, lineWidth: 1.5))
        }.buttonStyle(PressStyle())
    }

    // MARK: Stats
    private var statsRow: some View {
        CXCard {
            HStack {
                stat("\(total)", "TOTAL", CX.teal)
                Divider().frame(height: 34)
                stat("\(solvedCount)", "SOLVED", CX.teal)
                Divider().frame(height: 34)
                stat("\(missedCount)", "MISSED", .red)
            }.frame(maxWidth: .infinity)
        }
    }
    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(CX.title(24)).foregroundStyle(color)
            Text(label).font(CX.label(11)).foregroundStyle(CX.navySoft)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Calendar
    private var calendarCard: some View {
        CXCard {
            VStack(spacing: 12) {
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "arrow.left").foregroundStyle(CX.teal) }
                    Spacer()
                    Text(monthTitle).font(CX.heading(18)).foregroundStyle(CX.teal)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "arrow.right").foregroundStyle(canGoNext ? CX.teal : CX.hairline) }
                        .disabled(!canGoNext)
                }
                HStack(spacing: 0) {
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { d in
                        Text(d).font(CX.label(12)).foregroundStyle(CX.navySoft).frame(maxWidth: .infinity)
                    }
                }
                grid
            }
        }
    }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private var grid: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 52) }
            ForEach(1...daysInMonth, id: \.self) { day in dayCell(day) }
        }
    }

    @ViewBuilder private func dayCell(_ day: Int) -> some View {
        let key = dayKey(for: day)
        let isPastOrToday = key < app.todayKey
        let dc = byDay[key]
        let solved = dc != nil && app.solvedDaily(day: key)
        let available = dc != nil && !solved && isPastOrToday

        Button {
            guard available, let dc else { return }
            guard app.canAfford(life: app.randomCaseCost) else { showNoLife = true; return }
            activeDay = key; active = dc.clinicalCase
        } label: {
            VStack(spacing: 2) {
                Text("\(day)").font(CX.heading(16))
                    .foregroundStyle(dc == nil || !isPastOrToday ? CX.navySoft.opacity(0.5) : (solved ? CX.teal : CX.navy))
                if solved { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CX.teal) }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(solved ? CX.tealSoft : CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(available ? CX.teal : (solved ? CX.teal.opacity(0.5) : CX.hairline),
                        lineWidth: available || solved ? 2 : 1))
        }
        .buttonStyle(PressStyle())
        .disabled(!available)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(CX.tealSoft, CX.teal, "SOLVED")
            legendItem(CX.card, CX.teal, "AVAILABLE")
            legendItem(CX.card, CX.hairline, "LOCKED")
        }.font(CX.label(11)).foregroundStyle(CX.navySoft)
    }
    private func legendItem(_ fill: Color, _ stroke: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(stroke, lineWidth: 1.5))
                .frame(width: 14, height: 14)
            Text(label)
        }
    }

    // MARK: Month math
    private var monthTitle: String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "MMMM yyyy"
        return f.string(from: monthAnchor)
    }
    private var daysInMonth: Int {
        Self.gmtCal.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }
    private var leadingBlanks: Int {
        // weekday of the 1st (1 = Sunday) → 0-based offset.
        (Self.gmtCal.component(.weekday, from: monthAnchor) - 1)
    }
    private func dayKey(for day: Int) -> Int {
        let c = Self.gmtCal
        let date = c.date(byAdding: .day, value: day - 1, to: monthAnchor) ?? monthAnchor
        return AppState.gmtDay(date)
    }
    private var canGoNext: Bool { monthAnchor < Self.startOfMonth(Date()) }
    private func shiftMonth(_ delta: Int) {
        if delta > 0 && !canGoNext { return }
        if let d = Self.gmtCal.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = Self.startOfMonth(d)
        }
    }
}
