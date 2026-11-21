import Foundation

/// Everything the user can tune, persisted in `UserDefaults`. New knobs go
/// here so callers keep passing one value around.
struct PaperSettings {
    var enabled = true
    var excludeMenuBar = true // overlay sits under the menu bar and its menus
    var wash: Double          // 0...1 opacity of the flat paper-tint veil
    var grain: Double         // 0...1 strength of the light/dark specks
    var textureSize: Double   // tile edge multiplier (repeat distance)
    var grainSize: Double     // finest speck size in pixels
    var formation: Double     // 0...1 strength of the cloudy blotches
    var fibre: Double         // 0...1 strength of the fibre strands
    var relief: Double        // 0 matte specks ... 1 embossed bumps
    var highlights: Double    // 0...1 share of light specks kept (shadows are always full)

    static let washRange = 0.0...0.40
    static let grainRange = 0.0...1.0
    static let textureSizeRange = 1.0...12.0
    static let grainSizeRange = 1.5...12.0
    static let formationRange = 0.0...1.0
    static let fibreRange = 0.0...1.0
    static let reliefRange = 0.0...1.0
    static let highlightsRange = 0.0...1.0

    init(texture: PaperTexture) {
        wash = texture.defaultOpacity / 2
        grain = texture.defaultOpacity
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
        formation = texture.defaultFormation
        fibre = texture.defaultFibre
        relief = texture.defaultRelief
        highlights = texture.defaultHighlights
    }

    static func load(texture: PaperTexture, from defaults: UserDefaults = .standard) -> PaperSettings {
        var settings = PaperSettings(texture: texture)
        if defaults.object(forKey: "enabled") != nil { settings.enabled = defaults.bool(forKey: "enabled") }
        if defaults.object(forKey: "excludeMenuBar") != nil { settings.excludeMenuBar = defaults.bool(forKey: "excludeMenuBar") }

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
        settings.formation = stored("formation", fallback: settings.formation, in: formationRange)
        settings.fibre = stored("fibre", fallback: settings.fibre, in: fibreRange)
        settings.relief = stored("relief", fallback: settings.relief, in: reliefRange)
        settings.highlights = stored("highlights", fallback: settings.highlights, in: highlightsRange)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(excludeMenuBar, forKey: "excludeMenuBar")
        defaults.set(wash, forKey: "wash")
        defaults.set(grain, forKey: "grain")
        defaults.set(textureSize, forKey: "textureSize")
        defaults.set(grainSize, forKey: "grainSize")
        defaults.set(formation, forKey: "formation")
        defaults.set(fibre, forKey: "fibre")
        defaults.set(relief, forKey: "relief")
        defaults.set(highlights, forKey: "highlights")
    }

    /// Restores the texture-shape knobs to the preset, keeping enabled/wash/grain.
    mutating func resetTexture(to texture: PaperTexture) {
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
        formation = texture.defaultFormation
        fibre = texture.defaultFibre
        relief = texture.defaultRelief
        highlights = texture.defaultHighlights
    }
}
