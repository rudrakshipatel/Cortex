import SwiftUI

/// A bottom sheet that commiserates after a setback (a lost streak or a league
/// demotion) and points the player back into the game — the downbeat counterpart
/// to the post-case reward screens. Presented from the root via `app.pendingSetback`.
struct SetbackSheet: View {
    let info: SetbackInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppBackground {
            VStack(spacing: 16) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28)).foregroundStyle(CX.navySoft)
                    }
                    Spacer()
                }

                Spacer(minLength: 4)

                ZStack(alignment: .bottomTrailing) {
                    VixClip(anim: .writing, size: 150, fallback: .meditate)
                    ZStack {
                        Circle().fill(.white).frame(width: 50, height: 50)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        Circle().fill(info.tint.opacity(0.16)).frame(width: 50, height: 50)
                        Image(systemName: info.badgeIcon)
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(info.tint)
                    }
                    .offset(x: 6, y: 2)
                }
                .bounceIn()

                Text(info.title)
                    .font(CX.title(28)).foregroundStyle(CX.navy)
                    .multilineTextAlignment(.center)

                Text(info.message)
                    .font(CX.body(16)).foregroundStyle(CX.navySoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                Spacer(minLength: 8)

                CXButton(title: "Resume Progress", icon: "arrow.right") { dismiss() }
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
