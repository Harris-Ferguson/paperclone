import Foundation

/// One kind of paper: every value the renderer and overlay need. Paper is a
/// height map of tooth (bumps `grainSize` pixels across), fibres (strands
/// `fibreLength` pixels long) and formation (clumps `formationScale` pixels
/// across), shaded by `relief` and `highlights`, drawn at `grain` opacity over
/// a `wash` of the tint. The tint is the paper's colour: white content is toned
/// down to it, so the screen stops glowing pure white.
struct PaperTexture: Codable, Equatable {
    var name: String
    var tintR: Int
    var tintG: Int
    var tintB: Int
    var wash: Double            // 0...1 opacity of the flat tint veil
    var grain: Double           // 0...1 opacity of the grain
    var grainSize: Double       // pixels
    var relief: Double          // 0 matte specks ... 1 embossed bumps
    var highlights: Double      // 0...1 share of light specks kept
    var formation: Double       // 0...1
    var fibre: Double           // 0...1
    var formationScale: Double  // pixels
    var fibreLength: Double     // pixels
    var seed: Int

    /// What the rendered tile depends on; wash, grain and tint are applied by the overlay.
    var renderKey: PaperTexture {
        var key = self
        key.name = ""
        key.tintR = 0
        key.tintG = 0
        key.tintB = 0
        key.wash = 0
        key.grain = 0
        return key
    }

    static let printer = PaperTexture(
        name: "Printer", tintR: 250, tintG: 250, tintB: 246,
        wash: 0.06, grain: 0.20, grainSize: 2.0, relief: 0.70, highlights: 0.45,
        formation: 0.15, fibre: 0.05, formationScale: 80, fibreLength: 14, seed: 3)

    static let vellum = PaperTexture(
        name: "Vellum", tintR: 248, tintG: 245, tintB: 236,
        wash: 0.04, grain: 0.34, grainSize: 2.5, relief: 0.60, highlights: 0.50,
        formation: 0.55, fibre: 0.20, formationScale: 64, fibreLength: 18, seed: 8)

    static let newsprint = PaperTexture(
        name: "Newsprint", tintR: 233, tintG: 227, tintB: 211,
        wash: 0.16, grain: 0.55, grainSize: 1.8, relief: 0.15, highlights: 0.35,
        formation: 0.55, fibre: 0.55, formationScale: 48, fibreLength: 8, seed: 21)

    static let watercolour = PaperTexture(
        name: "Watercolour", tintR: 249, tintG: 244, tintB: 230,
        wash: 0.08, grain: 0.45, grainSize: 4.0, relief: 0.65, highlights: 0.50,
        formation: 0.75, fibre: 0.20, formationScale: 90, fibreLength: 20, seed: 34)

    static let kraft = PaperTexture(
        name: "Kraft", tintR: 226, tintG: 200, tintB: 165,
        wash: 0.10, grain: 0.48, grainSize: 3.0, relief: 0.50, highlights: 0.50,
        formation: 0.60, fibre: 0.80, formationScale: 56, fibreLength: 30, seed: 55)

    static let builtIn = [printer, vellum, newsprint, watercolour, kraft]
}
