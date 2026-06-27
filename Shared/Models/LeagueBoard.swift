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

extension Seed {
    /// Max players in one weekly league room. When a room fills, new players
    /// start a fresh room of the same tier (handled server-side).
    static let leagueSize = 30
    /// Top players promoted to the next league each Monday.
    static let leaguePromotionCount = 10
    /// Bottom players demoted from the league each Monday (middle 10 stay).
    static let leagueDemotionCount = 10

    /// Weekly coin rewards, by finishing zone.
    static let leagueTopThreeReward = 5000
    static let leaguePromotionReward = 2000
    static let leagueSafeReward = 500

    private static let leagueTints: [Color] = [
        CX.orange, CX.teal, Color(hex: 0x5AA9E6), Color(hex: 0xF08AB0),
        Color(hex: 0x9B7BE0), Color(hex: 0xE0A23C), Color(hex: 0x59B36B),
    ]

    /// A stable avatar colour derived from a player's id (FNV-1a hash).
    static func tint(forId id: String) -> Color {
        var h: UInt64 = 1469598103934665603
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return leagueTints[Int(h % UInt64(leagueTints.count))]
    }

    /// Map the real league room pulled from the server into display rows.
    static func leagueEntries(from members: [SupabaseService.LeagueMember], youId: String?) -> [LeagueEntry] {
        members.map { m in
            var e = LeagueEntry(name: m.username, weeklyXP: m.weekly_xp, totalXP: m.total_xp,
                                trophies: m.trophies, isYou: m.player_id == youId)
            e.rank = m.rank
            e.avatarTint = m.player_id == youId ? CX.orange : tint(forId: m.player_id)
            return e
        }
    }
}
