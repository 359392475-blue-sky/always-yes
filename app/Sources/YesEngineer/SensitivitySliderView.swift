import AppKit

final class SensitivitySliderView: NSView {
    static let minValue = 0.05
    static let maxValue = 0.40

    private let slider = NSSlider()
    var onChange: ((Double) -> Void)?

    init(initial: Double) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        autoresizingMask = [.width]
        buildLabels()
        buildSlider(initial: initial)
        updateValueLabel(initial)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLabels() {
        let titles = [
            L10n.text("Light tap", "轻拍 Mac"),
            L10n.text("Firm tap", "重击"),
            L10n.text("Hard hit", "愤怒砸桌"),
        ]
        let aligns: [NSTextAlignment] = [.left, .center, .right]
        let xs: [CGFloat] = [14, 0, -14]   // -14 means right-aligned with 14 inset
        let widths: [CGFloat] = [80, bounds.width, 80]
        for (i, title) in titles.enumerated() {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.alignment = aligns[i]
            let w: CGFloat = widths[i]
            let x: CGFloat
            switch i {
            case 0: x = xs[i]
            case 1: x = (bounds.width - w) / 2
            default: x = bounds.width - w - 14
            }
            label.frame = NSRect(x: x, y: 32, width: w, height: 16)
            label.autoresizingMask = i == 1 ? [.width] : (i == 2 ? [.minXMargin] : [])
            addSubview(label)
        }
    }

    private func buildSlider(initial: Double) {
        slider.minValue = Self.minValue
        slider.maxValue = Self.maxValue
        slider.doubleValue = initial
        slider.controlSize = .small
        slider.frame = NSRect(x: 14, y: 8, width: bounds.width - 28, height: 20)
        slider.autoresizingMask = [.width]
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        addSubview(slider)
    }

    private func updateValueLabel(_ v: Double) {
        slider.toolTip = L10n.format("Sensitivity threshold %.3f g", "灵敏度阈值 %.3f g", v)
    }

    @objc private func sliderChanged() {
        let v = slider.doubleValue
        updateValueLabel(v)
        onChange?(v)
    }
}
