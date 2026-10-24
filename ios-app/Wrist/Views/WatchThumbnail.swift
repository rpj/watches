import SwiftUI
import WristCore

/// Square watch photo with a brand-initial monogram fallback.
struct WatchThumbnail: View {
    let watch: WearWatch?
    let size: CGFloat

    init(_ watch: WearWatch?, size: CGFloat) {
        self.watch = watch
        self.size = size
    }

    private var initial: String {
        watch?.brand.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Group {
            if watch?.isNothing == true {
                bareWrist
            } else {
                AsyncImage(url: watch?.thumbnailUrl.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        monogram
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    /// The reserved "nothing on" entry: a dashed ring instead of a photo.
    private var bareWrist: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color.secondary.opacity(0.08))
            Image(systemName: "circle.dashed")
                .font(.system(size: size * 0.42, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var monogram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color.accentColor.opacity(0.15))
            Text(initial)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
    }
}
