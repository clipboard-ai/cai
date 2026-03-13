import SwiftUI

/// GitHub Invertocat mark rendered as a SwiftUI Shape.
/// Path data from the official GitHub SVG asset (assets/GitHub_Invertocat_Black.svg).
/// Original viewBox: 98 x 96
struct GitHubIcon: View {
    var color: Color = .caiTextSecondary

    var body: some View {
        GitHubIconShape()
            .fill(color)
            .aspectRatio(98.0 / 96.0, contentMode: .fit)
    }
}

struct GitHubIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 98.0
        let scaleY = rect.height / 96.0
        let t = CGAffineTransform(scaleX: scaleX, y: scaleY)

        var p = Path()
        p.move(to: CGPoint(x: 41.4395, y: 69.3848))
        p.addCurve(to: CGPoint(x: 19.9062, y: 46.9902),
                    control1: CGPoint(x: 28.8066, y: 67.8535),
                    control2: CGPoint(x: 19.9062, y: 58.7617))
        p.addCurve(to: CGPoint(x: 24.5, y: 33.5918),
                    control1: CGPoint(x: 19.9062, y: 42.2051),
                    control2: CGPoint(x: 21.6289, y: 37.0371))
        p.addCurve(to: CGPoint(x: 24.8828, y: 20.959),
                    control1: CGPoint(x: 23.2559, y: 30.4336),
                    control2: CGPoint(x: 23.4473, y: 23.7344))
        p.addCurve(to: CGPoint(x: 36.9414, y: 25.2656),
                    control1: CGPoint(x: 28.7109, y: 20.4805),
                    control2: CGPoint(x: 33.8789, y: 22.4902))
        p.addCurve(to: CGPoint(x: 49.0957, y: 23.543),
                    control1: CGPoint(x: 40.5781, y: 24.1172),
                    control2: CGPoint(x: 44.4062, y: 23.543))
        p.addCurve(to: CGPoint(x: 61.0586, y: 25.1699),
                    control1: CGPoint(x: 53.7852, y: 23.543),
                    control2: CGPoint(x: 57.6133, y: 24.1172))
        p.addCurve(to: CGPoint(x: 73.1172, y: 20.959),
                    control1: CGPoint(x: 64.0254, y: 22.4902),
                    control2: CGPoint(x: 69.2891, y: 20.4805))
        p.addCurve(to: CGPoint(x: 73.4043, y: 33.4961),
                    control1: CGPoint(x: 74.457, y: 23.543),
                    control2: CGPoint(x: 74.6484, y: 30.2422))
        p.addCurve(to: CGPoint(x: 78.0937, y: 46.9902),
                    control1: CGPoint(x: 76.4668, y: 37.1328),
                    control2: CGPoint(x: 78.0937, y: 42.0137))
        p.addCurve(to: CGPoint(x: 56.3691, y: 69.2891),
                    control1: CGPoint(x: 78.0937, y: 58.7617),
                    control2: CGPoint(x: 69.1934, y: 67.6621))
        p.addCurve(to: CGPoint(x: 61.8242, y: 81.252),
                    control1: CGPoint(x: 59.623, y: 71.3945),
                    control2: CGPoint(x: 61.8242, y: 75.9883))
        p.addLine(to: CGPoint(x: 61.8242, y: 91.2051))
        p.addCurve(to: CGPoint(x: 67.0879, y: 94.5547),
                    control1: CGPoint(x: 61.8242, y: 94.0762),
                    control2: CGPoint(x: 64.2168, y: 95.7031))
        p.addCurve(to: CGPoint(x: 98, y: 49.1914),
                    control1: CGPoint(x: 84.4102, y: 87.9512),
                    control2: CGPoint(x: 98, y: 70.6289))
        p.addCurve(to: CGPoint(x: 48.9043, y: 0),
                    control1: CGPoint(x: 98, y: 22.1074),
                    control2: CGPoint(x: 75.9883, y: 0))
        p.addCurve(to: CGPoint(x: 0, y: 49.1914),
                    control1: CGPoint(x: 21.8203, y: 0),
                    control2: CGPoint(x: 0, y: 22.1074))
        p.addCurve(to: CGPoint(x: 31.6777, y: 94.6504),
                    control1: CGPoint(x: 0, y: 70.4375),
                    control2: CGPoint(x: 13.4941, y: 88.0469))
        p.addCurve(to: CGPoint(x: 36.75, y: 91.3008),
                    control1: CGPoint(x: 34.2617, y: 95.6074),
                    control2: CGPoint(x: 36.75, y: 93.8848))
        p.addLine(to: CGPoint(x: 36.75, y: 83.6445))
        p.addCurve(to: CGPoint(x: 32.1562, y: 84.6016),
                    control1: CGPoint(x: 35.4102, y: 84.2188),
                    control2: CGPoint(x: 33.6875, y: 84.6016))
        p.addCurve(to: CGPoint(x: 19.4277, y: 74.7441),
                    control1: CGPoint(x: 25.8398, y: 84.6016),
                    control2: CGPoint(x: 22.1074, y: 81.1563))
        p.addCurve(to: CGPoint(x: 15.0254, y: 70.3418),
                    control1: CGPoint(x: 18.375, y: 72.1602),
                    control2: CGPoint(x: 17.2266, y: 70.6289))
        p.addCurve(to: CGPoint(x: 13.4941, y: 69.1934),
                    control1: CGPoint(x: 13.877, y: 70.2461),
                    control2: CGPoint(x: 13.4941, y: 69.7676))
        p.addCurve(to: CGPoint(x: 17.3223, y: 67.1836),
                    control1: CGPoint(x: 13.4941, y: 68.0449),
                    control2: CGPoint(x: 15.4082, y: 67.1836))
        p.addCurve(to: CGPoint(x: 24.9785, y: 72.4473),
                    control1: CGPoint(x: 20.0977, y: 67.1836),
                    control2: CGPoint(x: 22.4902, y: 68.9063))
        p.addCurve(to: CGPoint(x: 31.2949, y: 76.4668),
                    control1: CGPoint(x: 26.8926, y: 75.2227),
                    control2: CGPoint(x: 28.9023, y: 76.4668))
        p.addCurve(to: CGPoint(x: 37.4199, y: 73.4043),
                    control1: CGPoint(x: 33.6875, y: 76.4668),
                    control2: CGPoint(x: 35.2187, y: 75.6055))
        p.addCurve(to: CGPoint(x: 41.4395, y: 69.3848),
                    control1: CGPoint(x: 39.0469, y: 71.7773),
                    control2: CGPoint(x: 40.291, y: 70.3418))
        p.closeSubpath()

        return p.applying(t)
    }
}
