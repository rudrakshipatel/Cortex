# Cortex 🦊🧠

A SwiftUI iOS clinical-reasoning game — a re-skin of **Atrium**, themed to **DocRiddles.com**
(teal + orange on a mint→peach gradient, navy stat bars) with the **Dr. Vix** fox mascot.

## Run it

```bash
open Cortex.xcodeproj      # then press ⌘R in Xcode (iPhone simulator)
```

Or from the command line:

```bash
xcodebuild -project Cortex.xcodeproj -scheme Cortex \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- Bundle id: `com.docriddles.cortex` · Deployment target: iOS 17 · Devices: iPhone/iPad

## What's inside

| Area | Files |
|------|-------|
| Theme / palette | `Cortex/Theme/Theme.swift` |
| Reusable UI | `Cortex/Components/Components.swift` |
| Dr. Vix mascot | `Cortex/Components/DrVix.swift` |
| Data + state | `Cortex/Models/Models.swift`, `Models/SampleData.swift` |
| Onboarding | `Cortex/Views/Onboarding/OnboardingFlow.swift` |
| Tabs (Home/Learning/Leagues/Me) | `Cortex/Views/Main/` |
| Case gameplay | `Cortex/Views/Case/CaseFlow.swift` |

### Flow
Onboarding (4 slides → auth → country → reminders) → **Home** (department cards)
→ **Case**: patient info → order tests → results → diagnosis (MCQ) → treatments
→ outcome (XP) → streak. Plus Learning, Leagues, Me, and a Go-Pro upsell.

## Dr. Vix poses
`DrVix.swift` draws the fox in SwiftUI as a fallback. If you drop a PNG named
`DrVix-<pose>` (e.g. `DrVix-hero`, `DrVix-cheer`, `DrVix-idea`, `DrVix-avatar`)
into `Assets.xcassets`, it is used automatically instead of the vector.

## Notes
- `CX_SCREEN` launch env var routes directly to any single screen (used for
  screenshot verification; inert in normal use).
- The project uses an Xcode 16+ file-system-synchronized group, so new `.swift`
  files added under `Cortex/` are picked up automatically — no project edits needed.
