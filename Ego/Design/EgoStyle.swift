import SwiftUI

enum EgoStyle {
    static let canvas = Color.black
    static let surface = Color(white: 0.065)
    static let line = Color(white: 0.12)
    static let secondary = Color(white: 0.56)
    static let tertiary = Color(white: 0.38)
    static let inset: CGFloat = 20
    static let radius: CGFloat = 26
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

struct EgoCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black, in: RoundedRectangle(cornerRadius: EgoStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: EgoStyle.radius).strokeBorder(EgoStyle.line, lineWidth: 0.6))
    }
}
extension View {
    func egoCard() -> some View { modifier(EgoCard()) }
    func egoScreen() -> some View { frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black).preferredColorScheme(.dark).tint(.white) }
}
struct CircleControl: View {
    var symbol: String
    var label: String
    var filled = false
    var size: CGFloat = 44
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: size > 60 ? 29 : 20, weight: .regular)).frame(width: size, height: size)
            .foregroundStyle(filled ? .black : .white).background(filled ? Color.white : EgoStyle.surface, in: Circle()) }
            .buttonStyle(PressStyle()).accessibilityLabel(label)
    }
}
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).opacity(configuration.isPressed ? 0.75 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct WhiteButton: View {
    var title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) { HStack(spacing: 9) { if let symbol { Image(systemName: symbol) }; Text(title) }.font(.system(size: 18, weight: .medium)).foregroundStyle(.black).padding(.horizontal, 25).frame(height: 56).background(.white, in: Capsule()) }.buttonStyle(PressStyle())
    }
}
struct TagCloud: View {
    var tags: [String]
    var body: some View {
        FlowLayout(spacing: 7) { ForEach(tags, id: \.self) { tag in Text(tag).font(.system(size: 13)).foregroundStyle(EgoStyle.secondary).padding(.horizontal, 10).padding(.vertical, 4).overlay(Capsule().strokeBorder(Color(white: 0.25), lineWidth: 0.7)) } }
    }
}
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { arrange(proposal.width ?? 350, subviews).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(bounds.width, subviews)
        for (i, point) in layout.points.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var row: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews { let s = view.sizeThatFits(.unspecified); if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }; points.append(CGPoint(x: x, y: y)); x += s.width + spacing; row = max(row, s.height) }
        return (CGSize(width: width, height: y + row), points)
    }
}
struct SectionCaption: View {
    var title: String
    var body: some View { Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(EgoStyle.secondary).textCase(.uppercase).tracking(1.3).frame(maxWidth: .infinity, alignment: .leading) }
}
