import SwiftUI
import FocusCore

private func forestColor(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
}

struct ForestScene: View {
    let items: [ForestItem]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let positions = ForestLayout.positions(count: items.count)
            let unit = geometry.size.width / 860
            ZStack(alignment: .topLeading) {
                ForestGround()
                ForEach(items.indices.sorted { positions[$0].y < positions[$1].y }, id: \.self) { index in
                    let item = items[index]
                    let slot = positions[index]
                    let factor = unit * slot.scale
                    let pit = item.kind == .pit
                    let width = (pit ? 80.0 : 170.0) * factor
                    let height = (pit ? 40.0 : 190.0) * factor
                    Button { onSelect(item.id) } label: {
                        ForestPlant(kind: item.kind, selected: selectedID == item.id)
                            .frame(width: width, height: height)
                            .contentShape(ForestPlantHitShape(kind: item.kind))
                    }
                    .buttonStyle(.plain)
                    .position(x: geometry.size.width * slot.x,
                              y: geometry.size.height * slot.y - (pit ? 0 : height / 2 - 12 * factor))
                    .accessibilityLabel("\(item.kind.title)，\(item.record.title)，专注 \(Int(item.record.focusSeconds / 60)) 分钟")
                    .help("\(item.record.title) · \(item.kind.title)")
                }
                if items.isEmpty {
                    Text("这一片土地，等你下一次专注。")
                        .font(.system(size: 12)).foregroundStyle(forestColor(0x82916f))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当天的小森林，\(items.filter { $0.kind != .pit }.count) 棵树，\(items.filter { $0.kind == .pit }.count) 个树坑")
    }
}

struct ForestPlant: View {
    let kind: ForestPlantKind
    var selected = false

    var body: some View {
        Canvas { context, size in
            if kind == .pit {
                context.translateBy(x: size.width / 2, y: size.height / 2)
                context.scaleBy(x: size.width / 80, y: size.height / 40)
                if selected { selection(&context, radius: 33) }
                ellipse(&context, -31, -13, 62, 26, 0x879a65, opacity: 0.18)
                ellipse(&context, -24, -14, 48, 24, 0xd7bf95)
                ellipse(&context, -18, -11, 36, 16, 0x92724e)
                var inner = Path(); inner.move(to: CGPoint(x: -17, y: -4))
                inner.addQuadCurve(to: CGPoint(x: 17, y: -4), control: CGPoint(x: 0, y: -15))
                inner.addQuadCurve(to: CGPoint(x: -17, y: -1), control: CGPoint(x: 0, y: -7)); inner.closeSubpath()
                context.fill(inner, with: .color(forestColor(0x6f583e)))
                var grass = Path(); grass.move(to: CGPoint(x: 27, y: 1)); grass.addLine(to: CGPoint(x: 29, y: -7))
                grass.move(to: CGPoint(x: 27, y: 1)); grass.addLine(to: CGPoint(x: 34, y: -4))
                context.stroke(grass, with: .color(forestColor(0x8da268)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                let unit = min(size.width / 170, size.height / 190)
                context.translateBy(x: size.width / 2, y: size.height - 12 * unit)
                context.scaleBy(x: unit * kind.scale, y: unit * kind.scale)
                if selected { selection(&context, radius: 38) }
                ellipse(&context, -30, -10, 60, 20, 0x779257, opacity: 0.22)
                var trunk = Path(); trunk.move(to: CGPoint(x: -5, y: -56)); trunk.addLine(to: CGPoint(x: 6, y: -56))
                trunk.addLine(to: CGPoint(x: 8, y: 0)); trunk.addQuadCurve(to: CGPoint(x: -8, y: 0), control: CGPoint(x: 0, y: 6)); trunk.closeSubpath()
                context.fill(trunk, with: .color(forestColor(0xa17d51)))
                context.fill(Path(CGRect(x: -4, y: -54, width: 4, height: 54)), with: .color(forestColor(0xbd9461)))
                var branches = Path(); branches.move(to: CGPoint(x: 1, y: -30)); branches.addLine(to: CGPoint(x: 21, y: -52))
                branches.move(to: CGPoint(x: -1, y: -36)); branches.addLine(to: CGPoint(x: -19, y: -52))
                context.stroke(branches, with: .color(forestColor(0xa17d51)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                context.fill(Self.canopy, with: .linearGradient(Gradient(colors: [forestColor(0x74a85a), forestColor(0x437a43)]), startPoint: CGPoint(x: -35, y: -130), endPoint: CGPoint(x: 40, y: -35)))
                ellipse(&context, -26, -132, 47, 25, 0x92bc70, opacity: 0.6)
                ellipse(&context, -49, -104, 31, 25, 0x81b363, opacity: 0.6)
                ellipse(&context, -14, -76, 35, 25, 0x73a657, opacity: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    static var canopy: Path {
        var path = Path(); path.move(to: CGPoint(x: 0, y: -140))
        let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (.init(x:38,y:-116), .init(x:19,y:-145), .init(x:35,y:-132)),
            (.init(x:59,y:-73), .init(x:61,y:-113), .init(x:69,y:-91)),
            (.init(x:23,y:-39), .init(x:66,y:-52), .init(x:42,y:-35)),
            (.init(x:-24,y:-40), .init(x:9,y:-26), .init(x:-12,y:-30)),
            (.init(x:-58,y:-68), .init(x:-44,y:-32), .init(x:-62,y:-49)),
            (.init(x:-37,y:-115), .init(x:-73,y:-89), .init(x:-57,y:-113)),
            (.init(x:0,y:-140), .init(x:-37,y:-132), .init(x:-18,y:-143))]
        for (end, first, second) in curves { path.addCurve(to: end, control1: first, control2: second) }
        path.closeSubpath(); return path
    }
    private func ellipse(_ context: inout GraphicsContext, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ hex: UInt32, opacity: Double = 1) {
        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)), with: .color(forestColor(hex).opacity(opacity)))
    }
    private func selection(_ context: inout GraphicsContext, radius: Double) {
        let shape = Path(ellipseIn: CGRect(x: -radius, y: -14, width: radius * 2, height: 28))
        context.fill(shape, with: .color(forestColor(0xd9edb8)))
        context.stroke(shape, with: .color(forestColor(0x8eaa67)), lineWidth: 1.5)
    }
}

struct ForestPlantHitShape: Shape {
    let kind: ForestPlantKind

    func path(in rect: CGRect) -> Path {
        if kind == .pit {
            let pit = Path(ellipseIn: CGRect(x: -34, y: -16, width: 68, height: 32))
            return pit.applying(CGAffineTransform(a: rect.width / 80, b: 0, c: 0, d: rect.height / 40, tx: rect.midX, ty: rect.midY))
        }
        let unit = min(rect.width / 170, rect.height / 190)
        let scale = unit * kind.scale
        var hit = ForestPlant.canopy
        hit.addRect(CGRect(x: -9, y: -56, width: 18, height: 60))
        hit.addEllipse(in: CGRect(x: -30, y: -10, width: 60, height: 20))
        return hit.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.midX, ty: rect.maxY - 12 * unit))
    }
}

private struct ForestGround: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 860, y: size.height / 430)
            var shadow = context; shadow.addFilter(.blur(radius: 10))
            let shade = Path(ellipseIn: CGRect(x: 119, y: 197, width: 622, height: 210))
            shadow.fill(shade, with: .color(forestColor(0x8eaa70).opacity(0.14)))
            var soil = Path(); soil.move(to: CGPoint(x: 111, y: 234))
            soil.addQuadCurve(to: CGPoint(x:115,y:249), control:.init(x:102,y:241))
            soil.addLine(to: .init(x:412,y:394)); soil.addQuadCurve(to:.init(x:449,y:393),control:.init(x:430,y:402))
            soil.addLine(to:.init(x:744,y:249)); soil.addQuadCurve(to:.init(x:749,y:235),control:.init(x:755,y:243))
            soil.addLine(to:.init(x:430,y:91)); soil.closeSubpath()
            context.fill(soil, with:.linearGradient(Gradient(colors:[forestColor(0xd4bc91),forestColor(0xbd9c6b)]),startPoint:.init(x:430,y:210),endPoint:.init(x:430,y:402)))
            var land = Path(); land.move(to:.init(x:411,y:79))
            land.addQuadCurve(to:.init(x:449,y:79),control:.init(x:430,y:69)); land.addLine(to:.init(x:745,y:222))
            land.addQuadCurve(to:.init(x:745,y:242),control:.init(x:764,y:232)); land.addLine(to:.init(x:449,y:385))
            land.addQuadCurve(to:.init(x:411,y:385),control:.init(x:430,y:394)); land.addLine(to:.init(x:115,y:242))
            land.addQuadCurve(to:.init(x:115,y:222),control:.init(x:96,y:232)); land.closeSubpath()
            context.fill(land,with:.linearGradient(Gradient(colors:[forestColor(0xe3ebc9),forestColor(0xb5ce94)]),startPoint:.init(x:190,y:100),endPoint:.init(x:650,y:380)))
            context.stroke(land,with:.color(forestColor(0xc0d1a4)),lineWidth:1.5)
            for (x,y) in [(175.0,236.0),(606,220),(390,355),(493,149),(659,248)] {
                var grass = Path(); grass.move(to:.init(x:x,y:y)); grass.addLine(to:.init(x:x+1,y:y-7)); grass.move(to:.init(x:x,y:y)); grass.addLine(to:.init(x:x-5,y:y-4))
                context.stroke(grass,with:.color(forestColor(0x99b479).opacity(0.7)),style:StrokeStyle(lineWidth:1.5,lineCap:.round))
            }
            for (x,y) in [(274.0,232.0),(620,278),(392,159),(404,334)] {
                context.fill(Path(ellipseIn:.init(x:x,y:y,width:5,height:5)),with:.color(forestColor(0xfbf4d5)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
