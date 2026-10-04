import SwiftUI
import UIKit

struct WidgetThumbnail: View {
    let data: Data?
    let brand: String
    let size: CGFloat

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: size, height: size)
                .overlay {
                    Text(String(brand.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
        }
    }
}
