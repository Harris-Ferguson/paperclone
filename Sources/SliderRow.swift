import AppKit

/// A titled slider with a live value read-out, used in the menu and the
/// Advanced window. `onChange` reports the value and whether the drag is still
/// in progress, so expensive work can wait for release.
final class SliderRow: NSView {
    static let height: CGFloat = 56

    var onChange: ((Double, Bool) -> Void)?

    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private let range: ClosedRange<Double>
    private let logarithmic: Bool
    private let format: (Double) -> String

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    static func times(_ value: Double) -> String { String(format: "%.1f×", value) }
    static func pixels(_ value: Double) -> String { String(format: "%.1f px", value) }

    /// `logarithmic`: equal slider travel multiplies the value instead of adding.
    init(title: String,
         value: Double,
         range: ClosedRange<Double>,
         logarithmic: Bool = false,
         width: CGFloat,
         format: @escaping (Double) -> String) {
        self.range = range
        self.logarithmic = logarithmic
        self.format = format
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 14, y: 33, width: 140, height: 16)
        addSubview(titleLabel)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 74, y: 33, width: 60, height: 16)
        addSubview(valueLabel)

        slider.minValue = 0
        slider.maxValue = 1
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.frame = NSRect(x: 14, y: 9, width: width - 28, height: 20)
        addSubview(slider)

        self.value = value
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var value: Double {
        get {
            logarithmic
                ? range.lowerBound * pow(range.upperBound / range.lowerBound, slider.doubleValue)
                : range.lowerBound + slider.doubleValue * (range.upperBound - range.lowerBound)
        }
        set {
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            slider.doubleValue = logarithmic
                ? log(clamped / range.lowerBound) / log(range.upperBound / range.lowerBound)
                : (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
            valueLabel.stringValue = format(clamped)
        }
    }

    @objc private func changed() {
        let current = value
        valueLabel.stringValue = format(current)
        onChange?(current, NSApp.currentEvent?.type == .leftMouseDragged)
    }
}
