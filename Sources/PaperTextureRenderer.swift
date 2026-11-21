import AppKit

/// Renders a paper-texture preset into a small, seamlessly-tiling `NSImage`
/// entirely on the CPU — no WebKit. The grain is fractal value-noise (fBm),
/// baked as light and dark specks in the tile's alpha channel, so it textures
/// what is behind it without veiling it (the wash is a separate layer). Because the
/// overlay is static, this runs only when the settings change (a few ms), so
/// there's no per-frame cost and no helper processes.
enum PaperTextureRenderer {

    /// Bitmap edge in pixels: a larger texture size means a longer repeat distance.
    static func pixelEdge(for settings: PaperSettings) -> Int {
        Int((320 * settings.textureSize).rounded())
    }

    /// A tileable RGBA tile for `texture`, shaped by `settings` (grain size,
    /// texture size). `scale` maps pixels to points (2 → crisp on Retina).
    static func tile(for texture: PaperTexture,
                     settings: PaperSettings,
                     scale: CGFloat = 2) -> NSImage {
        let n = pixelEdge(for: settings)
        let octaves = max(1, texture.numOctaves)

        // 1/grainSize ≈ cycles/pixel (SVG feTurbulence convention): it sets the
        // FINEST grain. We build `octaves` bands from coarse → fine, each doubling
        // in frequency and halving in amplitude, so a broad mottle dominates and
        // fine grain rides on top — the way real paper fibre reads.
        let finest = max(2.0, Double(n) / max(settings.grainSize, 0.1))
        let coarsest = max(2.0, finest / pow(2.0, Double(octaves - 1)))

        var cellsPer = [Int]()
        var amps = [Double]()
        var ampSum = 0.0
        for o in 0..<octaves {
            cellsPer.append(max(2, Int((coarsest * pow(2.0, Double(o))).rounded())))
            let a = pow(0.5, Double(o))
            amps.append(a)
            ampSum += a
        }

        // Peak speck opacity before the grain-strength setting scales it.
        let grainDepth = 0.85

        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
        let pixels = buffer
        // Rows are independent, so render them across all cores.
        DispatchQueue.concurrentPerform(iterations: n) { y in
            let v = Double(y) / Double(n)
            for x in 0..<n {
                let u = Double(x) / Double(n)
                var val = 0.0
                for o in 0..<octaves {
                    val += amps[o] * valueNoise(u, v, cells: cellsPer[o], seed: texture.seed &+ o)
                }
                val /= ampSum                              // normalise to [0,1]
                let signed = 2.0 * val - 1.0               // <0 dark speck, >0 light speck
                let alpha = channel(grainDepth * abs(signed))
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

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var h = (x &* 73856093) ^ (y &* 19349663) ^ (seed &* 83492791)
        h &= 0x7fffffff
        h = (h &* 1103515245 &+ 12345) & 0x7fffffff
        return Double(h) / Double(0x7fffffff)
    }
}
