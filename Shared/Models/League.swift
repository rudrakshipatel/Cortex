import SwiftUI

/// The 10 promotable league tiers. A player's tier is the `kind` used to shard
/// weekly rooms, and it rises one step each week they finish in the promotion
/// zone — Bronze → Silver → … → Diamond (the top).
enum League: Int, CaseIterable, Codable {
    case bronze, silver, gold, sapphire, ruby, emerald, amethyst, pearl, obsidian, diamond

    var name: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .sapphire: return "Sapphire"
        case .ruby:     return "Ruby"
        case .emerald:  return "Emerald"
        case .amethyst: return "Amethyst"
        case .pearl:    return "Pearl"
        case .obsidian: return "Obsidian"
        case .diamond:  return "Diamond"
        }
    }

    /// 1…10, used for reward scaling.
    var tierLevel: Int { rawValue + 1 }

    /// The league a player is promoted into, or `nil` at the top (Diamond).
    var next: League? { League(rawValue: rawValue + 1) }

    var color: Color {
        switch self {
        case .bronze:   return Color(hex: 0xCD7F32)
        case .silver:   return Color(hex: 0x9AA6B2)
        case .gold:     return Color(hex: 0xF5B72E)
        case .sapphire: return Color(hex: 0x2E6FF5)
        case .ruby:     return Color(hex: 0xE0115F)
        case .emerald:  return Color(hex: 0x2CB67D)
        case .amethyst: return Color(hex: 0x9B59B6)
        case .pearl:    return Color(hex: 0xB8AEE0)
        case .obsidian: return Color(hex: 0x3A3A44)
        case .diamond:  return Color(hex: 0x39C5E0)
        }
    }

    var icon: String { self == .diamond ? "diamond.fill" : "shield.fill" }

    var subtitle: String {
        if let next { return "Finish in the top 10 this week to reach \(next.name)." }
        return "The pinnacle. Hold your ground at the top."
    }
}

/// Reward granted for a promotion-zone finish, scaled by finishing rank and the
/// league reached. Higher rank and higher league → bigger reward.
struct LeagueReward {
    let rank: Int
    let league: League   // the league the player is in after this result

    /// Rank weight: 1st earns most, tapering through the promotion zone.
    private var rankBase: Int {
        switch rank {
        case 1:  return 100
        case 2:  return 80
        case 3:  return 60
        default: return 40       // ranks 4–10 (rest of the promotion zone)
        }
    }

    var coins: Int { rankBase * league.tierLevel * 10 }
    var xp: Int    { rankBase * league.tierLevel }
}
