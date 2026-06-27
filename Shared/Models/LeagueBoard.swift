import SwiftUI

/// One row in the weekly league leaderboard.
struct LeagueEntry: Identifiable {
    let id = UUID()
    let name: String
    let weeklyXP: Int        // XP earned this league week (drives the rank)
    let totalXP: Int         // lifetime XP (shown small, under the weekly number)
    let trophies: Int        // gold-trophy badge count
    let isYou: Bool
    var rank: Int = 0
    var avatarTint: Color = CX.orange
}

/// Deterministic RNG (SplitMix64) so each league week produces a stable roster.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Seed {
    /// Total players in a weekly league.
    static let leagueSize = 30
    /// Top players promoted to the next league each Monday.
    static let leaguePromotionCount = 10
    /// Bottom players demoted from the league each Monday (middle 10 stay).
    static let leagueDemotionCount = 10

    /// Weekly coin rewards, by finishing zone.
    static let leagueTopThreeReward = 5000
    static let leaguePromotionReward = 2000
    static let leagueSafeReward = 500

    private static let leagueNames = [
        "Saad Sahil", "Sumanth Mutluri", "Harshit Ashtaputre", "Rare Npc",
        "Fathima Sahla", "Revati Khurape", "Scrub Phantom", "Mehak Lohana",
        "Tanmay Tiwari", "Mihika Korde", "Dr. Mei Lin", "Dr. Omar Farouk",
        "Dr. Aisha Khan", "Night Owl", "Code Blue", "Priya Nair",
        "Lucas Meyer", "Chen Wei", "Nadia Haddad", "Scalpel Sam",
        "Ishaan Rao", "Maya Fernandes", "Diego Alvarez", "Hana Suzuki",
        "Ghost Resident", "Ava Bennett", "Yusuf Demir", "Lena Novak",
        "Triage Titan", "Kofi Mensah", "Sara Lindqvist", "Vital Sign",
    ]
    private static let leagueTints: [Color] = [
        CX.orange, CX.teal, Color(hex: 0x5AA9E6), Color(hex: 0xF08AB0),
        Color(hex: 0x9B7BE0), Color(hex: 0xE0A23C), Color(hex: 0x59B36B),
    ]

    /// Build the weekly league: deterministic bots for `week`, plus the player,
    /// ranked by weekly XP (ties broken by lifetime XP).
    static func leagueBoard(week: Int, you: LeagueEntry) -> [LeagueEntry] {
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(week)) &* 0x100000001B3 &+ 0x9E3779B9)
        var bots: [LeagueEntry] = []
        for name in leagueNames.shuffled(using: &rng).prefix(leagueSize - 1) {
            bots.append(LeagueEntry(
                name: name,
                weeklyXP: Int.random(in: 5...175, using: &rng),
                totalXP: Int.random(in: 40...6000, using: &rng),
                trophies: Bool.random(using: &rng) ? Int.random(in: 1...5, using: &rng) : 0,
                isYou: false,
                avatarTint: leagueTints.randomElement(using: &rng) ?? CX.orange))
        }
        var all = bots + [you]
        all.sort { $0.weeklyXP != $1.weeklyXP ? $0.weeklyXP > $1.weeklyXP : $0.totalXP > $1.totalXP }
        for i in all.indices { all[i].rank = i + 1 }
        return all
    }
}
