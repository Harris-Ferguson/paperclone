import Foundation

/// Everything the user can tune, persisted in `UserDefaults`: which paper, two
/// everyday modifiers on top of it, and the papers they have saved.
struct PaperSettings {
    var enabled = true
    var paper = PaperTexture.vellum   // working copy; Advanced edits change it in place
    var strength = 1.0                // multiplies the paper's wash and grain
    var zoom = 1.0                    // enlarges or shrinks the whole pattern
    var ambientLight = 0.3            // 0...1 unevenness of the light falling on the sheet
    var savedPapers: [PaperTexture] = []

    static let strengthRange = 0.0...2.0
    static let zoomRange = 0.25...4.0
    static let ambientLightRange = 0.0...1.0
    static let minGrainSize = 1.5

    var allPapers: [PaperTexture] { PaperTexture.builtIn + savedPapers }

    /// The stored paper the working copy started from.
    var original: PaperTexture? { allPapers.first { $0.name == paper.name } }

    var isEdited: Bool { original != paper }

    /// The paper as drawn: the working copy with strength and zoom applied.
    var effectivePaper: PaperTexture {
        var drawn = paper
        // Strength also sets how far white is toned toward the paper colour.
        func toned(_ channel: Int) -> Int { max(0, 255 - Int((Double(255 - channel) * strength).rounded())) }
        drawn.tintR = toned(paper.tintR)
        drawn.tintG = toned(paper.tintG)
        drawn.tintB = toned(paper.tintB)
        drawn.wash = min(1, paper.wash * strength)
        drawn.grain = min(1, paper.grain * strength)
        drawn.grainSize = max(Self.minGrainSize, paper.grainSize * zoom)
        drawn.fibreLength = paper.fibreLength * zoom
        drawn.formationScale = paper.formationScale * zoom
        return drawn
    }

    /// Stores the working copy under `name`, replacing a saved paper of that name.
    mutating func savePaper(as name: String) {
        let taken = PaperTexture.builtIn.contains { $0.name == name }
        paper.name = taken ? name + " (custom)" : name
        savedPapers.removeAll { $0.name == paper.name }
        savedPapers.append(paper)
    }

    var isSavedPaper: Bool { savedPapers.contains { $0.name == paper.name } }

    /// Removes the current paper from the saved list and falls back to a built-in.
    mutating func deleteSavedPaper() {
        savedPapers.removeAll { $0.name == paper.name }
        paper = .vellum
    }

    static func load(from defaults: UserDefaults = .standard) -> PaperSettings {
        var settings = PaperSettings()
        if defaults.object(forKey: "enabled") != nil { settings.enabled = defaults.bool(forKey: "enabled") }

        func stored(_ key: String, fallback: Double, in range: ClosedRange<Double>) -> Double {
            let value = defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
            return min(max(value, range.lowerBound), range.upperBound)
        }
        settings.strength = stored("strength", fallback: settings.strength, in: strengthRange)
        settings.zoom = stored("zoom", fallback: settings.zoom, in: zoomRange)
        settings.ambientLight = stored("ambientLight", fallback: settings.ambientLight, in: ambientLightRange)

        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "paper"), let paper = try? decoder.decode(PaperTexture.self, from: data) {
            settings.paper = paper
        }
        if let data = defaults.data(forKey: "savedPapers"), let papers = try? decoder.decode([PaperTexture].self, from: data) {
            settings.savedPapers = papers
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        defaults.set(enabled, forKey: "enabled")
        defaults.set(strength, forKey: "strength")
        defaults.set(zoom, forKey: "zoom")
        defaults.set(ambientLight, forKey: "ambientLight")
        defaults.set(try? encoder.encode(paper), forKey: "paper")
        defaults.set(try? encoder.encode(savedPapers), forKey: "savedPapers")
    }
}
