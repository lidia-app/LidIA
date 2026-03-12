import SwiftUI

struct AvatarView: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo]
        let stableHash = name.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let index = stableHash % colors.count
        let color = colors[index < 0 ? index + colors.count : index]

        Text(initials.isEmpty ? "?" : initials.uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .overlay { Circle().stroke(.background, lineWidth: size < 30 ? 1.5 : 2) }
    }
}
