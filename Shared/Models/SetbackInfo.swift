import SwiftUI

/// A gentle "setback" prompt shown after something disappointing happens — a
/// lost streak or a league demotion. It mirrors the celebratory reward sheets
/// but with encouraging (never punishing) copy, so the fox commiserates and
/// nudges the player to bounce back. Held transiently on `AppState` and
/// surfaced as a bottom sheet.
struct SetbackInfo: Identifiable {
    enum Kind { case streakLost, demoted }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let badgeIcon: String        // SF Symbol shown over the fox
    let tint: Color

    /// The player just lost a `lost`-day streak.
    static func streakLost(_ lost: Int) -> SetbackInfo {
        SetbackInfo(
            kind: .streakLost,
            title: "Streak Lost",
            message: lost > 1
                ? "Your \(lost)-day streak just slipped away. Don't sweat it — solve a case today and a fresh streak begins."
                : "Your streak just slipped away. Solve a case today and a fresh streak begins.",
            badgeIcon: "flame.fill",
            tint: .orange)
    }

    /// The player finished last week in the drop zone. `dropped` is true when
    /// they actually fell a tier (false when they were already in Bronze).
    static func demoted(to league: League, dropped: Bool) -> SetbackInfo {
        SetbackInfo(
            kind: .demoted,
            title: dropped ? "Demoted" : "In the Drop Zone",
            message: dropped
                ? "You slipped down to the \(league.name) League this week. Shake it off — earn XP from cases and climb straight back up."
                : "You finished in the drop zone but held on in \(league.name). Push harder this week to climb back to safety.",
            badgeIcon: "arrow.down.circle.fill",
            tint: league.color)
    }
}
