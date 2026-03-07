import SwiftUI

/// Small green "PRO" badge displayed next to user's name / in Profile header
struct ProBadge: View {
    var small: Bool = false

    var body: some View {
        Text("PRO")
            .font(small ? .caption2 : .caption)
            .fontWeight(.black)
            .foregroundColor(.white)
            .padding(.horizontal, small ? 5 : 7)
            .padding(.vertical, small ? 2 : 3)
            .background(Theme.success)
            .clipShape(RoundedRectangle(cornerRadius: small ? 3 : 4))
    }
}

#Preview {
    HStack(spacing: 12) {
        ProBadge()
        ProBadge(small: true)
    }
    .padding()
    .background(Theme.background)
}
