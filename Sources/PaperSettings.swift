import Foundation

/// Everything the user can tune, persisted in `UserDefaults`. New knobs go
/// here so callers keep passing one value around.
struct PaperSettings {
    var enabled = true
    var wash: Double          // 0...1 opacity of the flat paper-tint veil
    var grain: Double         // 0...1 strength of the light/dark specks
    var textureSize: Double   // tile edge multiplier (repeat distance)
    var grainSize: Double     // finest speck size in pixels

    static let washRange = 0.0...0.40
    static let grainRange = 0.0...0.50
    static let textureSizeRange = 1.0...12.0
    static let grainSizeRange = 0.9...12.0

    init(texture: PaperTexture) {
        wash = texture.defaultOpacity / 2
        grain = texture.defaultOpacity / 2
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
    }

    static func load(texture: PaperTexture, from defaults: UserDefaults = .standard) -> PaperSettings {
        var settings = PaperSettings(texture: texture)
        if defaults.object(forKey: "enabled") != nil { settings.enabled = defaults.bool(forKey: "enabled") }

        func stored(_ key: String, fallback: Double, in range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        // Pre-split installs stored one "intensity"; it covered both halves.
        let legacy = defaults.object(forKey: "intensity") != nil ? defaults.double(forKey: "intensity") / 2 : nil
        settings.wash = stored("wash", fallback: legacy ?? settings.wash, in: washRange)
        settings.grain = stored("grain", fallback: legacy ?? settings.grain, in: grainRange)
        settings.textureSize = stored("textureSize", fallback: settings.textureSize, in: textureSizeRange)
        settings.grainSize = stored("grainSize", fallback: settings.grainSize, in: grainSizeRange)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(wash, forKey: "wash")
        defaults.set(grain, forKey: "grain")
        defaults.set(textureSize, forKey: "textureSize")
        defaults.set(grainSize, forKey: "grainSize")
    }

    /// Restores the texture-shape knobs to the preset, keeping enabled/wash/grain.
    mutating func resetTexture(to texture: PaperTexture) {
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
    }
}
