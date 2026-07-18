import SwiftUI

/// How one league room splits at the end of the week: the top third are
/// promoted, the middle third stay, the bottom third are demoted. The split is
/// taken from the room's ACTUAL size, not the 30-player cap — a half-full room
/// still moves only a third of its players. Any remainder from dividing by
/// three is left in the middle (safe) zone, so promotions and demotions are
/// always balanced and never exceed a third.
///
/// A room needs `Seed.leagueMinPlayers` (3) before anyone moves; below that
/// both zones are empty and everyone stays.
struct LeagueZones {
    /// Number of players in the room.
    let size: Int
    /// Ranks 1…`promote` go up a league.
    let promote: Int
    /// The bottom `demote` ranks drop a league.
    let demote: Int

    init(size: Int) {
        let n = Swift.max(0, size)
        self.size = n
        let third = n >= Seed.leagueMinPlayers ? n / 3 : 0
        self.promote = third
        self.demote = third
    }

    /// Ranks `promote+1`…`safeThrough` keep their league.
    var safeThrough: Int { size - demote }
    /// How many players stay put (the middle zone, including any remainder).
    var stay: Int { size - promote - demote }
    /// Whether this room is big enough to promote/demote at all.
    var movesPlayers: Bool { promote > 0 }

    func isPromotion(rank: Int) -> Bool { rank >= 1 && rank <= promote }
    func isDemotion(rank: Int) -> Bool { promote > 0 && rank > safeThrough && rank <= size }
}

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
    /// A room needs at least this many players for anyone to move: below it
    /// everybody stays put for the week.
    static let leagueMinPlayers = 3

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
