import Foundation

/// Everything the user can tune, persisted in `UserDefaults`. New knobs go
/// here so callers keep passing one value around.
struct PaperSettings {
    var enabled = true
    var intensity: Double     // 0...1 overlay opacity
    var textureSize: Double   // tile edge multiplier (repeat distance)
    var grainSize: Double     // finest speck size in pixels

    static let intensityRange = 0.03...0.40
    static let textureSizeRange = 1.0...12.0
    static let grainSizeRange = 0.9...12.0

    init(texture: PaperTexture) {
        intensity = texture.defaultOpacity
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
        settings.intensity = stored("intensity", fallback: settings.intensity, in: intensityRange)
        settings.textureSize = stored("textureSize", fallback: settings.textureSize, in: textureSizeRange)
        settings.grainSize = stored("grainSize", fallback: settings.grainSize, in: grainSizeRange)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(intensity, forKey: "intensity")
        defaults.set(textureSize, forKey: "textureSize")
        defaults.set(grainSize, forKey: "grainSize")
    }

    /// Restores the texture-shape knobs to the preset, keeping enabled/intensity.
    mutating func resetTexture(to texture: PaperTexture) {
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
    }
}
