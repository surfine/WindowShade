// 设置“外观”卡片里的两行：收起后的样子（跟原来一样 / 统一标题栏 / 缩略图）、透明度滑块。
// 滑块这一行的名字跟着“收起后的样子”走：选缩略图时叫“缩略图半透明”，否则仍叫“卷帘条半透明”。
//
// Preferences.swift 在别处维护：它在“外观”卡片里用 makeCollapseAppearanceRows() 的两行，换掉原来的
// “收起后的样子”分段控件和“卷帘条半透明”开关（“浮在其他窗口上面”那一行不动）。换之前原来那两行照常能用：
// 分段控件走同一个 setAppearanceMode；老开关写的设置照旧生效，拖过滑块以后再拨它也管用（ShadeTranslucency）。
// 最好还是在同一次改动里接上滑块、删掉老开关：同一件事在设置里只留一个控件。

import Cocoa

extension AppDelegate {
    /// 三个选项与分段控件的顺序一致。
    static let collapseAppearanceChoices: [ShadeAppearanceMode] = [.nativeScreenshot, .proxyTitleBar, .thumbnail]

    func makeCollapseAppearanceRows() -> [NSView] {
        let segment = NSSegmentedControl(labels: ["跟原来一样", "统一标题栏", "缩略图"],
                                         trackingMode: .selectOne,
                                         target: self,
                                         action: #selector(prefSelectCollapseAppearance(_:)))
        segment.selectedSegment = Self.collapseAppearanceChoices.firstIndex(of: appearanceMode) ?? 0
        segment.setAccessibilityLabel("收起后的样子")

        let name = appearanceMode == .thumbnail ? "缩略图半透明" : "卷帘条半透明"
        let percent = (ShadeTranslucency.fraction() * 100).rounded()
        let slider = NSSlider(value: percent, minValue: 0, maxValue: ShadeTranslucency.maximum * 100,
                              target: self, action: #selector(prefSlideShadeTranslucency(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.setAccessibilityLabel(name)
        // 读屏念“18%”，不只念“18”（右边的读数不单独读）。
        slider.setAccessibilityValueDescription(Self.translucencyText(percent))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let readout = NSTextField(labelWithString: Self.translucencyText(percent))
        readout.font = .monospacedDigitSystemFont(ofSize: SystemAppearancePolicy.fontSize(relativeToBody: -1),
                                                  weight: .regular)
        readout.textColor = .secondaryLabelColor
        readout.alignment = .right
        readout.setAccessibilityElement(false)
        readout.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let sliderGroup = NSStackView(views: [slider, readout])
        sliderGroup.orientation = .horizontal
        sliderGroup.alignment = .centerY
        sliderGroup.spacing = 8

        return [
            makeCollapseSettingsRow(name: "收起后的样子", subtitle: "卷帘条跟原来一样或用统一标题栏，也可以在原处缩成缩略图",
                                    control: segment),
            makeCollapseSettingsRow(name: name, subtitle: "让它更透一些，能看到后面的内容", control: sliderGroup),
        ]
    }

    @objc func prefSelectCollapseAppearance(_ sender: NSSegmentedControl) {
        let choices = Self.collapseAppearanceChoices
        guard choices.indices.contains(sender.selectedSegment) else { return }
        // 会重建菜单、刷新设置页（滑块那一行的名字跟着换）。
        setAppearanceMode(choices[sender.selectedSegment])
    }

    @objc func prefSlideShadeTranslucency(_ sender: NSSlider) {
        let percent = sender.doubleValue.rounded()
        let stored = ShadeTranslucency.set(percent / 100)
        translucent = stored > 0.001
        sender.setAccessibilityValueDescription(Self.translucencyText(percent))
        if let readout = (sender.superview as? NSStackView)?.arrangedSubviews.last as? NSTextField {
            readout.stringValue = Self.translucencyText(percent)
        }
        applyShadeTranslucencyToOverlays()
    }

    private static func translucencyText(_ percent: Double) -> String {
        "\(Int(percent))%"
    }

    /// 和 Preferences.swift 里的设置行同一个样子：左边名字和一句说明，右边控件。
    private func makeCollapseSettingsRow(name: String, subtitle: String?, control: NSView) -> NSView {
        (control as? NSControl)?.sizeToFit()
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let title = NSTextField(labelWithString: name)
        title.font = SystemAppearancePolicy.font(relativeToBody: 0)
        labels.addArrangedSubview(title)
        if let subtitle {
            let detail = NSTextField(wrappingLabelWithString: subtitle)
            detail.font = SystemAppearancePolicy.font(relativeToBody: -2)
            detail.textColor = .secondaryLabelColor
            detail.maximumNumberOfLines = 2
            labels.addArrangedSubview(detail)
            detail.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
        }
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, control])
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -14),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 40 : 48).isActive = true
        return row
    }
}
