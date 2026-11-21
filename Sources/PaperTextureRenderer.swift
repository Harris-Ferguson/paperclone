import AppKit

/// Renders a paper-texture preset into a small, seamlessly-tiling `NSImage`
/// entirely on the CPU — no WebKit. Paper is modelled as a height map: tooth
/// (band-limited gradient noise) plus fibres (stroked strands), made denser or
/// sparser by formation (warped clumps). The map is embossed — lit from one
/// corner — and baked as highlights and shadows in the tile's alpha channel, so it textures
/// what is behind it without veiling it (the wash is a separate layer). Because the
/// overlay is static, this runs only when the settings change (a few ms), so
/// there's no per-frame cost and no helper processes.
enum PaperTextureRenderer {

    /// A tileable `n`×`n` pixel RGBA tile for `paper`. `zoom` is the factor already
    /// applied to the paper's sizes, so fibre thickness and spacing can follow it.
    /// `scale` maps pixels to points (2 → crisp on Retina).
    static func tile(for paper: PaperTexture, zoom: Double, pixelEdge n: Int, scale: CGFloat = 2) -> NSImage {
        // Tooth is band-limited: bumps one grain size across plus a half-size band,
        // nothing finer, so it reads as a surface rather than per-pixel static.
        let toothCells = max(2, Int((Double(n) / max(paper.grainSize, 1.0)).rounded()))

        let formationCells = max(2, Int((Double(n) / paper.formationScale).rounded()))
        let formation = paper.formation
        // Formation is low-frequency, so a quarter-resolution map is enough.
        let mapEdge = max(2, n / 4)
        let clumps = formation > 0 ? formationMap(edge: mapEdge, cells: formationCells, seed: paper.seed) : []
        let fibre = paper.fibre
        let fibres = fibre > 0 ? fibreLayer(edge: n, length: paper.fibreLength, zoom: zoom, seed: paper.seed) : []

        // Peak speck opacity before the grain-strength setting scales it.
        let grainDepth = 0.85
        let embossGain = 0.6
        let matteGain = 0.5
        let relief = paper.relief
        let highlights = paper.highlights
        let fibreRelief = 3.0        // fibres stand this much taller than tooth
        let formationSwing = 0.4     // density varies ±40% at full formation, never to zero
        let formationShade = 0.1     // faint brightness share of formation

        // Pass 1 — height map: tooth plus raised fibres, made denser or sparser by formation.
        var heights = [Float](repeating: 0, count: n * n)
        heights.withUnsafeMutableBufferPointer { buffer in
        let heights = buffer
        // Rows are independent, so render them across all cores.
        DispatchQueue.concurrentPerform(iterations: n) { y in
            let v = Double(y) / Double(n)
            for x in 0..<n {
                let u = Double(x) / Double(n)
                var height = (gradientNoise(u, v, cells: toothCells, seed: paper.seed)
                              + 0.5 * gradientNoise(u, v, cells: toothCells * 2, seed: paper.seed &+ 1)) / 1.5
                if fibre > 0 {
                    height += fibreRelief * fibre * (Double(fibres[y * n + x]) - 128.0) / 127.0
                }
                if formation > 0 {
                    height *= 1.0 + formationSwing * formation * sample(clumps, edge: mapEdge, u, v)
                }
                heights[y * n + x] = Float(height)
            }
        }
        }
        let heightMap = heights

        // Pass 2 — shade. Embossed: light from one corner, so every bump gets a lit
        // side and a shaded side. Matte: height itself is the tone. `relief` blends them.
        let reach = max(1, Int((paper.grainSize / 2).rounded()))
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
        let pixels = buffer
        DispatchQueue.concurrentPerform(iterations: n) { y in
            let lit = ((y + reach) % n) * n
            for x in 0..<n {
                let height = Double(heightMap[y * n + x])
                let slope = height - Double(heightMap[lit + (x + reach) % n])
                var signed = relief * embossGain * slope + (1.0 - relief) * matteGain * height
                if formation > 0 {
                    signed += formationShade * formation
                        * sample(clumps, edge: mapEdge, Double(x) / Double(n), Double(y) / Double(n))
                }
                signed = max(-1.0, min(1.0, signed))       // <0 shaded, >0 lit
                // Shadows darken every colour by the same share; highlights only
                // show on dark content, so they are scaled back separately.
                let alpha = channel(grainDepth * abs(signed) * (signed > 0 ? highlights : 1.0))
                let white = signed > 0 ? alpha : 0         // premultiplied

                let idx = (y * n + x) * 4
                pixels[idx + 0] = white
                pixels[idx + 1] = white
                pixels[idx + 2] = white
                pixels[idx + 3] = alpha
            }
        }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &pixels,
                            width: n, height: n,
                            bitsPerComponent: 8, bytesPerRow: n * 4,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        let pointEdge = CGFloat(n) / scale
        return NSImage(cgImage: cg, size: NSSize(width: pointEdge, height: pointEdge))
    }

    // MARK: Fibres

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    /// An `n`×`n` grey map (128 = flat) of short, randomly oriented, slightly bent
    /// strands: mostly raised (light), a few grooves (dark). Strands crossing an edge are redrawn on the
    /// opposite side, so the map tiles seamlessly.
    private static func fibreLayer(edge n: Int, length: Double, zoom: Double, seed: Int) -> [UInt8] {
        if let cached = fibreCache, cached.edge == n, cached.length == length, cached.zoom == zoom, cached.seed == seed {
            return cached.bytes
        }
        var bytes = [UInt8](repeating: 128, count: n * n)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setLineCap(.round)

            var rng = SplitMix64(state: UInt64(truncatingIfNeeded: seed) &+ 0xF1B3E5)
            let edge = Double(n)
            let reach = min(length, edge / 2)
            // Zoomed-out fibres are also thinner and closer together; the count is
            // capped so a very small zoom cannot stroke millions of strands.
            let count = Int(Double(n * n / 250) * min(4.0, 1.0 / (zoom * zoom)))
            for _ in 0..<count {
                let x0 = rng.next() * edge
                let y0 = rng.next() * edge
                let angle = rng.next() * 2 * Double.pi
                let len = reach * (0.5 + rng.next())
                let bend = (rng.next() - 0.5) * len * 0.4
                let x1 = x0 + len * cos(angle)
                let y1 = y0 + len * sin(angle)
                let cx = (x0 + x1) / 2 - bend * sin(angle)
                let cy = (y0 + y1) / 2 + bend * cos(angle)

                ctx.setStrokeColor(gray: rng.next() < 0.2 ? 0 : 1, alpha: 0.25 + 0.3 * rng.next())
                ctx.setLineWidth(max(0.5, (1.5 + 1.5 * rng.next()) * zoom))

                let minX = min(x0, x1, cx), maxX = max(x0, x1, cx)
                let minY = min(y0, y1, cy), maxY = max(y0, y1, cy)
                for dx in [-edge, 0, edge] where maxX + dx >= 0 && minX + dx <= edge {
                    for dy in [-edge, 0, edge] where maxY + dy >= 0 && minY + dy <= edge {
                        ctx.move(to: CGPoint(x: x0 + dx, y: y0 + dy))
                        ctx.addQuadCurve(to: CGPoint(x: x1 + dx, y: y1 + dy),
                                         control: CGPoint(x: cx + dx, y: cy + dy))
                        ctx.strokePath()
                    }
                }
            }
        }
        fibreCache = (n, length, zoom, seed, bytes)
        return bytes
    }

    // Stroking is the slow part and only depends on these; main-thread only.
    private static var fibreCache: (edge: Int, length: Double, zoom: Double, seed: Int, bytes: [UInt8])?

    // MARK: Noise

    private static func channel(_ x: Double) -> UInt8 {
        UInt8(max(0.0, min(1.0, x)) * 255.0 + 0.5)
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Tileable value noise in [0,1]: a `cells`×`cells` lattice of hashed values,
    /// smoothstep-interpolated. Lattice indices wrap modulo `cells`, so opposite
    /// edges match and the tile repeats seamlessly.
    private static func valueNoise(_ u: Double, _ v: Double, cells: Int, seed: Int) -> Double {
        let fx = u * Double(cells)
        let fy = v * Double(cells)
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let tx = smooth(fx - Double(x0))
        let ty = smooth(fy - Double(y0))

        let x0m = x0 % cells, y0m = y0 % cells
        let x1m = (x0 + 1) % cells, y1m = (y0 + 1) % cells

        let v00 = hash(x0m, y0m, seed)
        let v10 = hash(x1m, y0m, seed)
        let v01 = hash(x0m, y1m, seed)
        let v11 = hash(x1m, y1m, seed)

        let a = v00 + (v10 - v00) * tx
        let b = v01 + (v11 - v01) * tx
        return a + (b - a) * ty
    }

    private static let gradients: [(Double, Double)] = (0..<16).map {
        let angle = Double($0) / 16 * 2 * Double.pi
        return (cos(angle), sin(angle))
    }

    /// Tileable gradient (Perlin) noise in roughly [-1,1]: round, evenly sized
    /// bumps about one lattice cell across, with no blocky lattice artefacts.
    private static func gradientNoise(_ u: Double, _ v: Double, cells: Int, seed: Int) -> Double {
        let fx = u * Double(cells)
        let fy = v * Double(cells)
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let dx = fx - Double(x0), dy = fy - Double(y0)
        let tx = dx * dx * dx * (dx * (dx * 6 - 15) + 10)
        let ty = dy * dy * dy * (dy * (dy * 6 - 15) + 10)

        let x0m = x0 % cells, y0m = y0 % cells
        let x1m = (x0 + 1) % cells, y1m = (y0 + 1) % cells

        func corner(_ cx: Int, _ cy: Int, _ ox: Double, _ oy: Double) -> Double {
            let g = gradients[Int(hash(cx, cy, seed) * 16) & 15]
            return g.0 * ox + g.1 * oy
        }
        let a = corner(x0m, y0m, dx, dy) + (corner(x1m, y0m, dx - 1, dy) - corner(x0m, y0m, dx, dy)) * tx
        let b = corner(x0m, y1m, dx, dy - 1) + (corner(x1m, y1m, dx - 1, dy - 1) - corner(x0m, y1m, dx, dy - 1)) * tx
        return (a + (b - a) * ty) * 1.5
    }

    /// Flocculent clumps in [-1,1]: four octaves looked up at a warped position,
    /// so clumps are ragged and mixed in size instead of round lattice blobs.
    private static func formationNoise(_ u: Double, _ v: Double, cells: Int, seed: Int) -> Double {
        let warpCells = max(2, cells / 2)
        let reach = 3.0 / Double(cells)
        var wu = u + reach * (valueNoise(u, v, cells: warpCells, seed: seed &+ 201) - 0.5)
        var wv = v + reach * (valueNoise(u, v, cells: warpCells, seed: seed &+ 202) - 0.5)
        wu -= wu.rounded(.down)                            // wrap so the tile stays seamless
        wv -= wv.rounded(.down)

        var sum = 0.0, total = 0.0, amp = 1.0, octaveCells = cells
        for octave in 0..<4 {
            sum += amp * valueNoise(wu, wv, cells: octaveCells, seed: seed &+ 101 &+ octave)
            total += amp
            amp *= 0.5
            octaveCells *= 2
        }
        return max(-1.0, min(1.0, (2.0 * sum / total - 1.0) * 1.6))
    }

    private static func formationMap(edge m: Int, cells: Int, seed: Int) -> [Double] {
        var map = [Double](repeating: 0, count: m * m)
        map.withUnsafeMutableBufferPointer { buffer in
            let map = buffer
            DispatchQueue.concurrentPerform(iterations: m) { y in
                let v = Double(y) / Double(m)
                for x in 0..<m {
                    map[y * m + x] = formationNoise(Double(x) / Double(m), v, cells: cells, seed: seed)
                }
            }
        }
        return map
    }

    /// Bilinear lookup into an `m`×`m` map that wraps at the edges.
    private static func sample(_ map: [Double], edge m: Int, _ u: Double, _ v: Double) -> Double {
        let fx = u * Double(m), fy = v * Double(m)
        let x0 = Int(fx) % m, y0 = Int(fy) % m
        let x1 = (x0 + 1) % m, y1 = (y0 + 1) % m
        let tx = fx - fx.rounded(.down), ty = fy - fy.rounded(.down)
        let a = map[y0 * m + x0] + (map[y0 * m + x1] - map[y0 * m + x0]) * tx
        let b = map[y1 * m + x0] + (map[y1 * m + x1] - map[y1 * m + x0]) * tx
        return a + (b - a) * ty
    }

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var h = (x &* 73856093) ^ (y &* 19349663) ^ (seed &* 83492791)
        h &= 0x7fffffff
        h = (h &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(h) / Double(0x7fffffff)
    }
}
