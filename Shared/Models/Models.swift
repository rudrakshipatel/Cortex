import SwiftUI

// MARK: - App-wide state
@MainActor
final class AppState: ObservableObject {
    /// Whether the user has finished onboarding. Published (not @AppStorage) so
    /// that flipping it actually re-renders RootView and shows the main app.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    /// XP is the lifetime score that drives the Leagues ranking.
    @Published var lifetimeXP: Int  { didSet { defaults.set(lifetimeXP, forKey: K.xp) } }
    /// Coins are the spendable currency — earned by solving cases, spent to
    /// unlock Mentor Insight.
    @Published var coins: Int       { didSet { defaults.set(coins, forKey: K.coins) } }
    /// Life is energy spent to play cases; it refills to `maxLife` at GMT 00:00.
    @Published var life: Int        { didSet { defaults.set(life, forKey: K.life) } }
    @Published var isPro: Bool = false
    /// Username shown on the profile and the global leaderboard.
    @Published var displayName: String { didSet { defaults.set(displayName, forKey: K.name) } }

    /// Stable anonymous identity for the global leaderboard (generated once).
    let playerId: String

    /// Full Life bar — restored every GMT day.
    static let maxLife = 100

    /// Country chosen during onboarding (persisted). Emergency timing uses the
    /// device's own timezone, which is more precise than country.
    @Published var country: String { didSet { defaults.set(country, forKey: K.country) } }

    // MARK: Streak (GMT-day based, persisted)
    @Published private(set) var streak: Int            { didSet { defaults.set(streak, forKey: K.streak) } }
    @Published private(set) var lastActiveEpochDay: Int { didSet { defaults.set(lastActiveEpochDay, forKey: K.lastDay) } }
    /// The best streak ever reached (for the "new record" coin bonus).
    @Published private(set) var highestStreak: Int     { didSet { defaults.set(highestStreak, forKey: K.highStreak) } }
    /// Streak Freezes owned — each covers one missed day (bought in the Shop).
    @Published private(set) var streakFreezes: Int     { didSet { defaults.set(streakFreezes, forKey: K.freezes) } }
    /// GMT days the user was active — drives the streak calendar.
    @Published private(set) var activeDays: Set<Int>   { didSet { defaults.set(Array(activeDays), forKey: K.activeDays) } }
    /// The GMT day Life was last refilled — drives the daily reset.
    @Published private(set) var lastLifeDay: Int { didSet { defaults.set(lastLifeDay, forKey: K.lifeDay) } }
    /// Timestamp from which energy has been regenerating (whole units only; the
    /// sub-unit remainder is preserved by only advancing this clock by the units
    /// actually granted).
    private var lastEnergyDate: Date { didSet { defaults.set(lastEnergyDate.timeIntervalSince1970, forKey: K.energyDate) } }
    /// GMT days on which the user has already solved that day's Daily Case.
    @Published private(set) var solvedDailyDays: Set<Int> {
        didSet { defaults.set(Array(solvedDailyDays), forKey: K.solvedDaily) }
    }
    /// IDs of clinical/practice cases solved correctly — excluded from "random".
    @Published private(set) var solvedCaseIDs: Set<String> {
        didSet { defaults.set(Array(solvedCaseIDs), forKey: K.solvedCases) }
    }
    /// Best trophy tier earned per case (1 = bronze, 2 = silver, 3 = gold),
    /// keyed by case id — shown on that case's Practice card.
    @Published private(set) var caseTrophies: [String: Int] {
        didSet { defaults.set(caseTrophies, forKey: K.caseTrophies) }
    }

    // MARK: Solved progress (persisted)
    /// Cases finished with the correct diagnosis. Broken into trophy tiers by
    /// how well the workup went: gold = perfect, silver = strong, bronze = solved.
    @Published private(set) var casesSolved: Int { didSet { defaults.set(casesSolved, forKey: K.casesSolved) } }
    /// Total cases finished (regardless of outcome) — used to qualify for the league.
    @Published private(set) var casesFinished: Int { didSet { defaults.set(casesFinished, forKey: K.casesFinished) } }
    /// XP earned in the current league week (resets every week). Drives the league rank.
    @Published private(set) var weeklyXP: Int { didSet { defaults.set(weeklyXP, forKey: K.weeklyXP) } }
    /// Cases finished in the current league week — need ≥1 to enter the leaderboard.
    @Published private(set) var leagueCasesThisWeek: Int { didSet { defaults.set(leagueCasesThisWeek, forKey: K.leagueCases) } }
    private var lastLeagueWeek: Int { didSet { defaults.set(lastLeagueWeek, forKey: K.leagueWeek) } }
    @Published private(set) var gold: Int        { didSet { defaults.set(gold, forKey: K.gold) } }
    @Published private(set) var silver: Int      { didSet { defaults.set(silver, forKey: K.silver) } }
    @Published private(set) var bronze: Int      { didSet { defaults.set(bronze, forKey: K.bronze) } }
    /// Top-3 league finishes (shown as a profile stat).
    @Published private(set) var topThreeFinishes: Int { didSet { defaults.set(topThreeFinishes, forKey: K.topThree) } }

    private let defaults = UserDefaults.standard
    private enum K {
        static let xp = "cx.lifetimeXP", coins = "cx.coins", life = "cx.life", lifeDay = "cx.lifeDay"
        static let energyDate = "cx.lastEnergyDate"
        static let streak = "cx.streak", lastDay = "cx.lastActiveDay", country = "cx.country"
        static let casesSolved = "cx.casesSolved", gold = "cx.gold", silver = "cx.silver", bronze = "cx.bronze"
        static let casesFinished = "cx.casesFinished", topThree = "cx.topThreeFinishes"
        static let weeklyXP = "cx.weeklyXP", leagueCases = "cx.leagueCasesThisWeek", leagueWeek = "cx.leagueWeek"
        static let solvedDaily = "cx.solvedDaily", playerId = "cx.playerId", name = "cx.name"
        static let solvedCases = "cx.solvedCases", caseTrophies = "cx.caseTrophies"
        static let freezes = "cx.streakFreezes", activeDays = "cx.activeDays", highStreak = "cx.highStreak"
    }

    init() {
        let d = UserDefaults.standard
        onboarded = d.bool(forKey: "onboarded")
        if let pid = d.string(forKey: K.playerId) {
            playerId = pid
        } else {
            let pid = UUID().uuidString.lowercased()
            d.set(pid, forKey: K.playerId)
            playerId = pid
        }
        lifetimeXP = d.object(forKey: K.xp)    as? Int ?? 0   // new users start at Level 1
        coins      = d.object(forKey: K.coins) as? Int ?? 500   // new users start with 500 free coins
        life       = d.object(forKey: K.life)  as? Int ?? Self.maxLife
        lastLifeDay = d.object(forKey: K.lifeDay) as? Int ?? Self.gmtDay()
        let storedEnergyTS = d.double(forKey: K.energyDate)   // 0 when unset
        lastEnergyDate = storedEnergyTS > 0 ? Date(timeIntervalSince1970: storedEnergyTS) : Date()
        // didSet doesn't fire during init, so persist the seed timestamp now —
        // otherwise every launch would reset the regen clock and energy would
        // never accrue across launches.
        if storedEnergyTS <= 0 { d.set(lastEnergyDate.timeIntervalSince1970, forKey: K.energyDate) }
        streak     = d.object(forKey: K.streak) as? Int ?? 0
        lastActiveEpochDay = d.object(forKey: K.lastDay) as? Int ?? 0
        streakFreezes = d.object(forKey: K.freezes) as? Int ?? 0
        highestStreak = d.object(forKey: K.highStreak) as? Int ?? 0
        activeDays = Set(d.array(forKey: K.activeDays) as? [Int] ?? [])
        solvedDailyDays = Set(d.array(forKey: K.solvedDaily) as? [Int] ?? [])
        solvedCaseIDs = Set(d.stringArray(forKey: K.solvedCases) ?? [])
        caseTrophies = d.dictionary(forKey: K.caseTrophies) as? [String: Int] ?? [:]
        displayName = d.string(forKey: K.name) ?? "Dr. Vix Trainee"
        casesSolved = d.object(forKey: K.casesSolved) as? Int ?? 0
        casesFinished = d.object(forKey: K.casesFinished) as? Int ?? 0
        weeklyXP = d.object(forKey: K.weeklyXP) as? Int ?? 0
        leagueCasesThisWeek = d.object(forKey: K.leagueCases) as? Int ?? 0
        lastLeagueWeek = d.object(forKey: K.leagueWeek) as? Int ?? Self.gmtWeek()
        gold   = d.object(forKey: K.gold)   as? Int ?? 0
        silver = d.object(forKey: K.silver) as? Int ?? 0
        bronze = d.object(forKey: K.bronze) as? Int ?? 0
        topThreeFinishes = d.object(forKey: K.topThree) as? Int ?? 0
        country = d.string(forKey: K.country) ?? ""
        refreshForNewDay()
    }

    /// Whole days since the Unix epoch in **GMT** (all daily resets are at GMT 00:00).
    nonisolated static func gmtDay(_ date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "GMT")!
        let start = cal.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }
    /// Back-compat alias used around the app.
    nonisolated static func epochDay(_ date: Date = Date()) -> Int { gmtDay(date) }

    /// League week index (Mon-anchored, GMT). Leagues reset each week.
    nonisolated static func gmtWeek(_ date: Date = Date()) -> Int {
        // Unix epoch (1970-01-01) was a Thursday; shift by 4 days so weeks start Monday.
        return (gmtDay(date) + 4) / 7
    }
    /// Whole days remaining in the current league week (for "resets in N days").
    var leagueDaysLeft: Int {
        let dayInWeek = (Self.gmtDay() + 4) % 7      // 0 = Monday … 6 = Sunday
        return Swift.max(1, 7 - dayInWeek)
    }

    /// Top up time-based energy regen and roll the league over on a new week.
    /// Safe to call repeatedly (idempotent between accrued whole units).
    func refreshForNewDay() {
        regenerateEnergy()
        lastLifeDay = Self.gmtDay()
        // Roll the league over at the start of each new week.
        let week = Self.gmtWeek()
        if week != lastLeagueWeek {
            weeklyXP = 0
            leagueCasesThisWeek = 0
            lastLeagueWeek = week
        }
    }

    // MARK: Energy regeneration
    /// Energy regenerated per minute — 0.0694444…/min = exactly 100 over 24 hours.
    static let energyRegenPerMinute = 100.0 / (24.0 * 60.0)

    /// Grant whole energy units accrued since `lastEnergyDate`, capped at `maxLife`.
    /// The clock advances only by the units actually granted, so the fractional
    /// remainder carries over to the next call (no regen is lost to rounding).
    func regenerateEnergy() {
        guard life < Self.maxLife else { lastEnergyDate = Date(); return }
        let now = Date()
        let minutes = now.timeIntervalSince(lastEnergyDate) / 60.0
        guard minutes > 0 else { return }
        let gained = Int((minutes * Self.energyRegenPerMinute).rounded(.down))
        guard gained > 0 else { return }
        life = Swift.min(Self.maxLife, life + gained)
        if life >= Self.maxLife {
            lastEnergyDate = now
        } else {
            let secondsPerUnit = 60.0 / Self.energyRegenPerMinute
            lastEnergyDate = lastEnergyDate.addingTimeInterval(Double(gained) * secondsPerUnit)
        }
    }

    // MARK: Daily Case
    /// The GMT day index for "today".
    var todayKey: Int { Self.gmtDay() }
    var solvedTodaysDaily: Bool { solvedDailyDays.contains(todayKey) }
    func solvedDaily(day: Int) -> Bool { solvedDailyDays.contains(day) }
    func markDailySolved(day: Int) { solvedDailyDays.insert(day) }

    // MARK: Solved cases (per-case, by id)
    func isCaseSolved(_ id: UUID) -> Bool { solvedCaseIDs.contains(id.uuidString) }
    func markCaseSolved(_ id: UUID) { solvedCaseIDs.insert(id.uuidString) }

    /// True once the user has already completed a case today.
    var playedToday: Bool { lastActiveEpochDay == Self.gmtDay() }

    /// Record that the user was active today. Advances the streak on a
    /// consecutive day; a Streak Freeze covers each missed day, otherwise the
    /// streak resets. No-op if already counted today.
    func registerDailyActivity() {
        let today = Self.gmtDay()
        guard lastActiveEpochDay != today else { return }   // already counted today
        if lastActiveEpochDay == 0 {
            streak = 1                                      // first ever play
        } else {
            let missed = Swift.max(0, today - lastActiveEpochDay - 1)
            if missed == 0 {
                streak += 1
            } else if missed <= streakFreezes {
                streakFreezes -= missed                     // freezes save the streak
                streak += 1
            } else {
                streak = 1                                  // streak broken
            }
        }
        lastActiveEpochDay = today
        activeDays.insert(today)
        if streak > highestStreak { highestStreak = streak }   // track the record
        // Milestone reward: every 50-day streak pays 10 coins per streak day
        // (50 days → 500, 100 days → 1000, …).
        if streak > 0 && streak % 50 == 0 { coins += 10 * streak }
    }

    // MARK: Shop / Streak Freeze
    static let streakFreezeCost = 1000
    /// Buy one Streak Freeze with coins. Returns false if too few coins.
    @discardableResult
    func buyStreakFreeze() -> Bool {
        guard coins >= Self.streakFreezeCost else { return false }
        coins -= Self.streakFreezeCost
        streakFreezes += 1
        return true
    }

    // MARK: Energy economy
    // Energy is spent *after* a case, scaled to how well it was solved: a perfect
    // 100-XP solve costs the least (5), a 0-XP attempt costs the most (15). The
    // cost falls linearly by 1 for every 10 XP earned.
    static let maxEnergyCost = 15   // earning 0 XP
    static let minEnergyCost = 5    // earning a perfect 100 XP

    /// Energy spent for a case, by the XP earned (0 → 15, 10 → 14, … 90 → 6, 100 → 5).
    static func energyCost(forXP xp: Int) -> Int {
        let cost = maxEnergyCost - Int((Double(xp) / 10.0).rounded())
        return Swift.min(maxEnergyCost, Swift.max(minEnergyCost, cost))
    }
    func canAfford(life cost: Int) -> Bool { life >= cost }
    /// Spend energy after a case, never dropping below zero. Banks any pending
    /// regen first, then starts the regen clock if this drops us below full.
    func spendEnergy(_ cost: Int) {
        regenerateEnergy()
        let wasFull = life >= Self.maxLife
        life = Swift.max(0, life - cost)
        if wasFull && life < Self.maxLife { lastEnergyDate = Date() }
    }

    // MARK: Level & skill (XP-based progression)
    /// Player level, starting at 1. Advancing from level L → L+1 costs L×100 XP.
    var level: Int { Self.level(forXP: lifetimeXP) }
    nonisolated static func level(forXP xp: Int) -> Int {
        var lvl = 1, spent = 0
        while spent + lvl * 100 <= xp { spent += lvl * 100; lvl += 1 }
        return lvl
    }
    /// XP earned within the current level, and the XP needed to reach the next.
    var levelProgress: (into: Int, needed: Int) {
        var lvl = 1, spent = 0
        while spent + lvl * 100 <= lifetimeXP { spent += lvl * 100; lvl += 1 }
        return (lifetimeXP - spent, lvl * 100)
    }
    /// The player's current skill rank/title.
    var skill: SkillRank { Seed.skill(forLevel: level) }

    /// Total XP required to reach a given level.
    nonisolated static func xpForLevel(_ level: Int) -> Int { 50 * (level - 1) * level }
    /// Progress through the current skill band and the next skill (nil at top).
    var skillProgress: (into: Int, needed: Int, next: SkillRank?) {
        let band = (level - 1) / 10 + 1
        let bandStartXP = Self.xpForLevel((band - 1) * 10 + 1)
        guard band < Seed.skillRanks.count else { return (lifetimeXP - bandStartXP, 0, nil) }
        let nextStartXP = Self.xpForLevel(band * 10 + 1)
        return (lifetimeXP - bandStartXP, nextStartXP - bandStartXP, Seed.skill(forLevel: band * 10 + 1))
    }

    /// Award XP — the lifetime score that drives levels, plus the weekly score
    /// that drives the league leaderboard.
    func award(xp: Int) { lifetimeXP += xp; weeklyXP += xp }

    /// Award coins — the spendable currency.
    func award(coins amount: Int) { coins += amount }

    /// Record a case finished with the correct diagnosis. Awards a trophy tier
    /// (an achievement) based on the share of the case's reward that was earned.
    /// Coins are awarded only from the case payout (see `award(coins:)`), so the
    /// wallet always matches the amount shown on the outcome screen.
    func recordCaseSolved(_ id: UUID, earned: Int, outOf maxReward: Int) {
        casesSolved += 1
        let ratio = maxReward > 0 ? Double(earned) / Double(maxReward) : 0
        let tier: Int
        if ratio >= 1.0       { gold += 1;   tier = 3 }
        else if ratio >= 0.8  { silver += 1; tier = 2 }
        else                  { bronze += 1; tier = 1 }
        // Record this case's trophy on its Practice card, keeping the best tier.
        caseTrophies[id.uuidString] = Swift.max(caseTrophies[id.uuidString] ?? 0, tier)
    }

    /// The best trophy tier earned for a case (1 bronze … 3 gold), or nil if unsolved.
    func caseTrophyTier(_ id: UUID) -> Int? { caseTrophies[id.uuidString] }

    /// Record that a case was finished (any outcome). Drives league qualification.
    func recordCaseFinished() {
        casesFinished += 1
        refreshForNewDay()            // make sure the week is current before counting
        leagueCasesThisWeek += 1
    }

    /// Cases a trainee must finish this week to enter the league leaderboard.
    static let casesToQualify = 1
    /// True once the user has finished at least one case this league week.
    var qualifiedForLeague: Bool { leagueCasesThisWeek >= Self.casesToQualify }

    /// Coin cost to reveal a case's mentor insights.
    static let mentorCost = 300

    /// Spend coins (e.g., to unlock mentor insights). Returns false if insufficient.
    func spendCoins(_ amount: Int) -> Bool {
        guard coins >= amount else { return false }
        coins -= amount
        return true
    }
}

// MARK: - Departments (home list)
struct Department: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    /// Mystery one-liner shown on the Clinical-mode card.
    let teaser: String
    var bronze: Int = 0
    var silver: Int = 0
    var gold: Int = 0
    /// The curated mystery case opened from this department card.
    let caseRef: ClinicalCase
}

/// A league rank tier shown in the Leagues tab. A player's tier is the highest
/// one whose `unlockXP` their lifetime XP has reached. Medical Student (1) →
/// Chief (6).
struct League: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let color: Color
    let difficulty: Int      // 1 = lowest … 6 = highest
    let unlockXP: Int        // lifetime XP required to reach this tier
}

/// A skill-rank title derived from the player's level (every 10 levels = next
/// rank): Medical Student → Intern → Resident → … → Super Specialist.
struct SkillRank: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let color: Color
}

// MARK: - Clinical case
// Codable so admin-uploaded cases can be persisted to disk (see ContentStore).
struct ClinicalCase: Identifiable, Codable {
    var id = UUID()
    let specialty: String
    let patientName: String
    let gender: String
    let age: String
    let chiefComplaint: String
    let infoCards: [InfoCard]
    let tests: [TestOption]
    let diagnosisQuestion: String
    let diagnoses: [DiagnosisOption]
    let treatments: [TreatmentOption]
    let outcomeTitle: String
    let outcomeBody: String
    let xpReward: Int
    /// Optional structured Mentor Insight, unlocked with coins on the answer screen.
    var mentorInsight: MentorInsightContent? = nil
    // Presentation fields for the rich case card (all optional with fallbacks).
    var title: String? = nil        // dramatic case title, e.g. "Collapse in the Night"
    var teaser: String? = nil       // narrative hook shown on the card
    var imageName: String? = nil    // hero image asset name (added to the app)
    var difficulty: Int? = nil      // 1 (easy) … 5 (hard)
}

/// Coin-locked expert teaching attached to a case (shown on the answer screen).
struct MentorInsightContent: Codable, Equatable {
    var reasoning: String = ""        // expert reasoning
    var differentials: String = ""    // differential diagnoses
    var pearls: String = ""           // clinical pearls
    var pitfalls: String = ""         // common pitfalls
    var learningPoints: String = ""   // learning points

    var isEmpty: Bool {
        [reasoning, differentials, pearls, pitfalls, learningPoints]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    /// Non-empty (title, body) sections in display order.
    var sections: [(String, String)] {
        [("Expert reasoning", reasoning), ("Differential diagnoses", differentials),
         ("Clinical pearls", pearls), ("Common pitfalls", pitfalls),
         ("Learning points", learningPoints)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension ClinicalCase {
    /// Card title — the authored title, else the chief complaint.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return chiefComplaint
    }
    /// Card narrative — the authored teaser, else a one-line patient summary.
    var displayTeaser: String {
        if let t = teaser?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return "\(patientName), \(age) — \(chiefComplaint)"
    }
    /// Difficulty 1…5 (defaults to a middle 3).
    var difficultyLevel: Int { Swift.min(5, Swift.max(1, difficulty ?? 3)) }

    /// Info arranged into the standard clinical reading order regardless
    /// of how they were authored: chief complaint → history → physical
    /// examination → anything else (kept in its original relative order).
    var orderedInfoCards: [InfoCard] {
        func rank(_ c: InfoCard) -> Int {
            let t = c.title.lowercased()
            if t.contains("complaint") || t.contains("basic info")
                || t.contains("presenting") || t.contains("presentation") { return 0 }
            if t.contains("history") || t.contains("hx") { return 1 }
            if t.contains("exam") { return 2 }
            return 3
        }
        return infoCards.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
    }
}

struct InfoCard: Identifiable, Codable {
    var id = UUID()
    let title: String
    let bullets: [String]
    let mentor: String
}

struct TestOption: Identifiable, Equatable, Codable {
    var id = UUID()
    let category: String
    let name: String
    let result: String
    let helpful: Bool          // drives mentor feedback
    let mentor: String
    static func == (l: TestOption, r: TestOption) -> Bool { l.id == r.id }
}

struct DiagnosisOption: Identifiable, Codable {
    var id = UUID()
    let name: String
    let correct: Bool
}

struct TreatmentOption: Identifiable, Equatable, Codable {
    var id = UUID()
    let category: String
    let name: String
    let appropriate: Bool
    static func == (l: TreatmentOption, r: TreatmentOption) -> Bool { l.id == r.id }
}

// MARK: - Per-case progress while playing
@MainActor
final class CaseSession: ObservableObject {
    let clinicalCase: ClinicalCase
    @Published var tray: [TestOption] = []
    @Published var pickedDiagnosis: DiagnosisOption?
    @Published var treatmentTray: [TreatmentOption] = []
    @Published var mentorUnlocked = false

    init(_ c: ClinicalCase) { self.clinicalCase = c }

    var diagnosisCorrect: Bool { pickedDiagnosis?.correct ?? false }

    /// Workup quality for this attempt, 0...1. A perfect solve (1.0) needs the
    /// correct diagnosis (60%), every helpful test ordered (20%) and every
    /// appropriate treatment chosen (20%), with no wasteful picks. Ordering
    /// unhelpful tests or inappropriate treatments reduces the score — so
    /// skipping the trays or guessing earns little or nothing.
    var performance: Double {
        // Diagnosis — 60%.
        let dx = diagnosisCorrect ? 0.60 : 0.0

        // Tests — up to 20%: credit for helpful tests ordered, debit for noise.
        let helpfulCount = clinicalCase.tests.filter(\.helpful).count
        var tests = 0.0
        if helpfulCount > 0 {
            let good = Double(tray.filter(\.helpful).count) / Double(helpfulCount)
            let bad  = Double(tray.filter { !$0.helpful }.count)
            tests = Swift.max(0, good - 0.25 * bad) * 0.20
        }

        // Treatments — up to 20%: credit for appropriate, debit for inappropriate.
        let appropriateCount = clinicalCase.treatments.filter(\.appropriate).count
        var tx = 0.0
        if appropriateCount > 0 {
            let good = Double(treatmentTray.filter(\.appropriate).count) / Double(appropriateCount)
            let bad  = Double(treatmentTray.filter { !$0.appropriate }.count)
            tx = Swift.max(0, good - 0.25 * bad) * 0.20
        }

        return Swift.min(1.0, dx + tests + tx)
    }

    /// XP for this attempt — out of a fixed 100. The full 100 is awarded only
    /// for a completely correct solve (perfect workup quality).
    static let maxXP = 100
    var earnedXP: Int { Int((performance * Double(Self.maxXP)).rounded()) }

    /// Coins for this attempt — scale with the case's own reward value.
    var earnedCoins: Int { Int((performance * Double(clinicalCase.xpReward)).rounded()) }
}
