import SwiftUI
import AVFoundation

/// The bundled Dr. Vix mascot animation clips (mp4, looped, muted).
enum VixAnim: String {
    case happy1   = "vix-happy1"      // great answer (≥ 80 XP)
    case happy2   = "vix-happy2"      // decent answer, room to improve (40–79 XP)
    case sad      = "vix-sad"         // low score (< 40 XP)
    case confetti = "vix-confetti"    // level / skill / leaderboard rank up
    case wave     = "vix-wave"        // greeting
    case tail     = "vix-tail"        // happy reward (coins)
    case writing  = "vix-writing"     // working / performing tests

    /// The reaction clip for a case scored out of 100.
    static func forXP(_ xp: Int) -> VixAnim {
        if xp >= 80 { return .happy1 }
        if xp >= 40 { return .happy2 }
        return .sad
    }
}

/// A looping, muted Dr. Vix animation shown on a rounded "stage". Falls back to
/// the static vector mascot if the clip can't be found in the bundle.
struct VixClip: View {
    let anim: VixAnim
    var size: CGFloat = 150
    var fallback: DrVix.Pose = .cheer

    var body: some View {
        if let url = Bundle.main.url(forResource: anim.rawValue, withExtension: "mp4") {
            LoopingVideo(url: url)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        } else {
            DrVix(pose: fallback, size: size)
        }
    }
}

// MARK: - AVPlayer-backed looping video (muted, aspect-fill)
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> LoopingPlayerView { LoopingPlayerView(url: url) }
    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {}
    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: ()) { uiView.stop() }
}

final class LoopingPlayerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        player.isMuted = true
        player.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill        // fox fills the frame; transparent margins cropped
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.isOpaque = false
        // Composite the clip's alpha channel onto whatever is behind it.
        playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        layer.addSublayer(playerLayer)
        player.play()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
    func stop() { player.pause() }
    deinit { player.pause() }
}
