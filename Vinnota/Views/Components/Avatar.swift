import SwiftUI

/// The account avatar: the chosen picture, or initials until there is one.
struct AvatarView: View {
    let image: UIImage?
    let initials: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let initials, !initials.isEmpty {
                Text(initials)
                    .font(Typo.sans(size * 0.375, 600))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.rose(0.10))
            } else {
                // No picture and no name — a neutral mark, never invented initials.
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.44))
                    .foregroundStyle(Palette.rose(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.rose(0.10))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
