import SwiftUI

// Drawn in the same 24-point coordinate space as the web composer's icons.
struct ComposerIcon: View {
    enum Kind { case close, drawer, photo, gif, poll, emoji, calendar, location, plus, globe, oak, robot }
    let kind: Kind
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / 24, y: canvas.height / 24)
            let stroke = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
            var p = Path()
            switch kind {
            case .close:
                p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 18, y: 18))
                p.move(to: CGPoint(x: 18, y: 6)); p.addLine(to: CGPoint(x: 6, y: 18))
            case .drawer:
                p.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 2, height: 2))
                p.move(to: CGPoint(x: 14, y: 4)); p.addLine(to: CGPoint(x: 14, y: 20))
                for y in [9.0, 12.0, 15.0] {
                    p.move(to: CGPoint(x: 17, y: y)); p.addLine(to: CGPoint(x: 18, y: y))
                }
            case .photo:
                p.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 2, height: 2))
                p.move(to: CGPoint(x: 3, y: 17)); p.addLines([CGPoint(x: 9, y: 11), CGPoint(x: 13, y: 15), CGPoint(x: 16, y: 12), CGPoint(x: 21, y: 17)])
                p.addEllipse(in: CGRect(x: 14.5, y: 6, width: 2.5, height: 2.5))
            case .gif:
                p.addRoundedRect(in: CGRect(x: 2, y: 4, width: 20, height: 16), cornerSize: CGSize(width: 2, height: 2))
                context.draw(Text("GIF").font(.system(size: 9, weight: .heavy)).foregroundColor(Theme.blue), at: CGPoint(x: 12, y: 12))
            case .poll:
                for (y, w) in [(5.0, 12.0), (12.0, 17.0), (19.0, 8.0)] {
                    p.move(to: CGPoint(x: 6, y: y)); p.addLine(to: CGPoint(x: w + 4, y: y))
                    p.move(to: CGPoint(x: 2, y: y)); p.addLine(to: CGPoint(x: 2.1, y: y))
                }
            case .emoji:
                p.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 19, height: 19))
                p.move(to: CGPoint(x: 7, y: 14)); p.addQuadCurve(to: CGPoint(x: 17, y: 14), control: CGPoint(x: 12, y: 21))
                p.addEllipse(in: CGRect(x: 7.6, y: 8, width: 0.8, height: 0.8))
                p.addEllipse(in: CGRect(x: 15.6, y: 8, width: 0.8, height: 0.8))
            case .calendar:
                p.addRoundedRect(in: CGRect(x: 3, y: 5, width: 18, height: 16), cornerSize: CGSize(width: 2, height: 2))
                p.move(to: CGPoint(x: 3, y: 10)); p.addLine(to: CGPoint(x: 21, y: 10))
                for x in [8.0, 16.0] { p.move(to: CGPoint(x: x, y: 2)); p.addLine(to: CGPoint(x: x, y: 7)) }
                p.move(to: CGPoint(x: 8, y: 15)); p.addLines([CGPoint(x: 11, y: 18), CGPoint(x: 16, y: 13)])
            case .location:
                p.move(to: CGPoint(x: 12, y: 22))
                p.addCurve(to: CGPoint(x: 4, y: 9), control1: CGPoint(x: 10, y: 19), control2: CGPoint(x: 4, y: 14))
                p.addCurve(to: CGPoint(x: 20, y: 9), control1: CGPoint(x: 4, y: -1), control2: CGPoint(x: 20, y: -1))
                p.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 20, y: 14), control2: CGPoint(x: 14, y: 19))
                p.addEllipse(in: CGRect(x: 9, y: 6, width: 6, height: 6))
            case .plus:
                p.move(to: CGPoint(x: 12, y: 5)); p.addLine(to: CGPoint(x: 12, y: 19))
                p.move(to: CGPoint(x: 5, y: 12)); p.addLine(to: CGPoint(x: 19, y: 12))
            case .globe:
                p.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
                p.addEllipse(in: CGRect(x: 7.5, y: 2, width: 9, height: 20))
                for y in [8.0, 16.0] { p.move(to: CGPoint(x: 3, y: y)); p.addLine(to: CGPoint(x: 21, y: y)) }
            case .robot:
                p.addRoundedRect(in: CGRect(x: 5, y: 7, width: 14, height: 13), cornerSize: CGSize(width: 3, height: 3))
                p.move(to: CGPoint(x: 12, y: 7)); p.addLine(to: CGPoint(x: 12, y: 3))
                p.addEllipse(in: CGRect(x: 11, y: 1, width: 2, height: 2))
                for x in [2.0, 19.0] {
                    p.addRoundedRect(in: CGRect(x: x, y: 11, width: 3, height: 6), cornerSize: CGSize(width: 1, height: 1))
                }
                for x in [8.0, 14.0] { p.addEllipse(in: CGRect(x: x, y: 11, width: 2, height: 2)) }
                p.move(to: CGPoint(x: 9, y: 16)); p.addLine(to: CGPoint(x: 15, y: 16))
            case .oak:
                p.move(to: CGPoint(x: 12, y: 19))
                p.addCurve(to: CGPoint(x: 6, y: 16), control1: CGPoint(x: 8, y: 20), control2: CGPoint(x: 4, y: 19))
                p.addCurve(to: CGPoint(x: 4, y: 11), control1: CGPoint(x: 1, y: 17), control2: CGPoint(x: 1, y: 11))
                p.addQuadCurve(to: CGPoint(x: 5, y: 9), control: CGPoint(x: 7, y: 12))
                p.addCurve(to: CGPoint(x: 8, y: 5), control1: CGPoint(x: 1, y: 8), control2: CGPoint(x: 4, y: 3))
                p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 8, y: 1), control2: CGPoint(x: 11, y: 1))
                p.addCurve(to: CGPoint(x: 16, y: 5), control1: CGPoint(x: 13, y: 1), control2: CGPoint(x: 16, y: 1))
                p.addCurve(to: CGPoint(x: 19, y: 9), control1: CGPoint(x: 20, y: 3), control2: CGPoint(x: 23, y: 8))
                p.addQuadCurve(to: CGPoint(x: 20, y: 11), control: CGPoint(x: 17, y: 12))
                p.addCurve(to: CGPoint(x: 18, y: 16), control1: CGPoint(x: 23, y: 11), control2: CGPoint(x: 23, y: 17))
                p.addCurve(to: CGPoint(x: 12, y: 19), control1: CGPoint(x: 20, y: 19), control2: CGPoint(x: 16, y: 20))
                p.closeSubpath()
                p.move(to: CGPoint(x: 12, y: 23)); p.addLine(to: CGPoint(x: 12, y: 7))
            }
            context.stroke(p, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
