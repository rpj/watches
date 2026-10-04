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
        AsyncImage(url: watch?.thumbnailUrl.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
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
