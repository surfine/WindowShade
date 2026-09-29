// 刘海里教手势的那一小段动画：一块小屏幕、一扇小窗、两个手指的圆点，演一遍“手指怎么动、窗口怎么变”，演三遍停下。
// 每条提示一段（见 Core/GestureCoach.swift 的 CoachTip）。“减少动态效果”打开时不动，只摆出结束时的样子。
// 全是 Core Animation 图层，由系统的渲染进程播，不占主线程。
// 卡住时的提示（CoachTip.habit）演什么由那条规则给（HabitDemo，放在 NotchDemoView.habit 里）：按键的几条是两排键帽，
// 上面一排是刚才按的（变暗），下面一排是 Mac 上那一下（亮起）。两排的修饰键都照 Mac 键帽印名字（⌃ 下面写 control）。
// 卡住提示的右上角另有一个小叉：点它只是关掉（点提示别处是替他做成那一下，见 App/Notch+Habit.swift）。

import Cocoa

final class NotchDemoView: NSView {
    static let size = NSSize(width: 100, height: 60)
    private let stage = CALayer()
    private let cycle: CFTimeInterval = 2.2

    /// 下一段卡住提示演什么、点小叉做什么（刘海按 CoachTip.habit 建演示时来这里取）。
    struct HabitShow {
        let demo: HabitDemo
        let onClose: () -> Void
    }
    static var habit: HabitShow?
    /// 小叉在屏幕上的位置（点提示时，岛已经先收了，所以在摆好时就记下来）。
    private static var closeRect: NSRect?
    private var closeButton: HabitCloseButton?
    private let tip: CoachTip

    static var closeRectForProbe: NSRect? { closeRect }

    /// 这一下点在小叉上（周围放宽到 28 点见方，好点）。
    static func closeHit(_ point: NSPoint) -> Bool {
        guard let rect = closeRect else { return false }
        let pad = max(0, (28 - rect.width) / 2)
        return rect.insetBy(dx: -pad, dy: -pad).contains(point)
    }

    init(tip: CoachTip) {
        self.tip = tip
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.frame = bounds
        stage.cornerRadius = 8
        stage.cornerCurve = .continuous
        stage.masksToBounds = true
        stage.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        stage.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        stage.borderWidth = 1
        build(tip)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 卡住提示：放进提示里时，在提示的右上角放一个小叉（和演示同进同出）。
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard tip == .habit else { return }
        guard let host = superview else {
            closeButton?.removeFromSuperview()
            closeButton = nil
            return
        }
        let side: CGFloat = 16
        let button = closeButton ?? HabitCloseButton(frame: .zero)
        button.onPress = Self.habit?.onClose
        button.frame = NSRect(x: host.bounds.width - side - 10, y: host.bounds.height - side - 8, width: side, height: side)
        button.autoresizingMask = [.minXMargin, .minYMargin]
        host.addSubview(button)
        closeButton = button
        // 岛还在长：等这一轮布局走完再记位置。
        DispatchQueue.main.async { [weak button] in
            MainActor.assumeIsolated {
                guard let button, let window = button.window else { return }
                NotchDemoView.closeRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            }
        }
    }

    // MARK: 零件

    private func window(_ frame: CGRect, alpha: CGFloat = 0.92) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        layer.cornerRadius = 3
        layer.masksToBounds = true
        let bar = CALayer()
        bar.backgroundColor = NSColor(white: 0.62, alpha: 1).cgColor
        bar.frame = CGRect(x: 0, y: frame.height - 6, width: frame.width, height: 6)
        bar.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        layer.addSublayer(bar)
        stage.addSublayer(layer)
        return layer
    }

    private func finger(at point: CGPoint) -> CALayer {
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        dot.position = point
        dot.cornerRadius = 4
        dot.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.borderColor = NSColor.white.cgColor
        dot.borderWidth = 1.5
        stage.addSublayer(dot)
        return dot
    }

    private func label(_ text: String, at point: CGPoint) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.fontSize = 9
        layer.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        layer.foregroundColor = NSColor.white.cgColor
        layer.alignmentMode = .center
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.frame = CGRect(x: point.x - 30, y: point.y - 6, width: 60, height: 12)
        stage.addSublayer(layer)
        return layer
    }

    /// 关键帧：values 对应 times（0…1，一轮 cycle 秒），重复三遍，停在最后一帧。
    private func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any], _ times: [NSNumber]) {
        guard !still else {
            layer.setValue(values.last, forKeyPath: keyPath)
            return
        }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = cycle
        animation.repeatCount = 3
        animation.calculationMode = .linear
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1), count: max(1, values.count - 1))
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: keyPath)
    }

    private func point(_ p: CGPoint) -> NSValue { NSValue(point: p) }
    private func size(_ s: CGSize) -> NSValue { NSValue(size: s) }

    // MARK: 各段

    private func build(_ tip: CoachTip) {
        let w = Self.size.width, h = Self.size.height
        let fade: [Any] = [0, 1, 1, 1, 0]
        let fadeTimes: [NSNumber] = [0, 0.08, 0.6, 0.85, 1]
        switch tip {
        case .halves:
            let win = window(CGRect(x: 26, y: 12, width: 48, height: 34))
            let dots = [finger(at: CGPoint(x: 46, y: 43)), finger(at: CGPoint(x: 56, y: 43))]
            for (i, dot) in dots.enumerated() {
                let x = CGFloat(46 + i * 10)
                animate(dot, "position", [point(CGPoint(x: x, y: 43)), point(CGPoint(x: x, y: 43)), point(CGPoint(x: x - 22, y: 43)),
                                          point(CGPoint(x: x - 22, y: 43)), point(CGPoint(x: x - 22, y: 43))], [0, 0.1, 0.4, 0.85, 1])
                animate(dot, "opacity", fade, fadeTimes)
            }
            animate(win, "position", [point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 50, y: 29)),
                                      point(CGPoint(x: 26, y: 30)), point(CGPoint(x: 26, y: 30))], [0, 0.1, 0.42, 0.62, 1])
            animate(win, "bounds.size", [size(CGSize(width: 48, height: 34)), size(CGSize(width: 48, height: 34)),
                                         size(CGSize(width: 48, height: 34)), size(CGSize(width: 46, height: 54)),
                                         size(CGSize(width: 46, height: 54))], [0, 0.1, 0.42, 0.62, 1])
        case .magic:
            let main = window(CGRect(x: 26, y: 12, width: 48, height: 34))
            let side = window(CGRect(x: 60, y: 3, width: 37, height: 54), alpha: 0.7)
            side.opacity = 0
            let left = finger(at: CGPoint(x: 46, y: 43)), right = finger(at: CGPoint(x: 54, y: 43))
            animate(left, "position", [point(CGPoint(x: 46, y: 43)), point(CGPoint(x: 46, y: 43)), point(CGPoint(x: 34, y: 43)),
                                       point(CGPoint(x: 34, y: 43))], [0, 0.1, 0.4, 1])
            animate(right, "position", [point(CGPoint(x: 54, y: 43)), point(CGPoint(x: 54, y: 43)), point(CGPoint(x: 66, y: 43)),
                                        point(CGPoint(x: 66, y: 43))], [0, 0.1, 0.4, 1])
            animate(left, "opacity", fade, fadeTimes); animate(right, "opacity", fade, fadeTimes)
            animate(main, "position", [point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 30, y: 30)),
                                       point(CGPoint(x: 30, y: 30))], [0, 0.42, 0.62, 1])
            animate(main, "bounds.size", [size(CGSize(width: 48, height: 34)), size(CGSize(width: 48, height: 34)),
                                          size(CGSize(width: 54, height: 54)), size(CGSize(width: 54, height: 54))], [0, 0.42, 0.62, 1])
            animate(side, "opacity", [0, 0, 1, 1, 0], [0, 0.45, 0.62, 0.85, 1])
        case .shake:
            let others = [window(CGRect(x: 6, y: 8, width: 30, height: 22), alpha: 0.6),
                          window(CGRect(x: 64, y: 30, width: 30, height: 22), alpha: 0.6)]
            let main = window(CGRect(x: 30, y: 14, width: 40, height: 30))
            let dot = finger(at: CGPoint(x: 50, y: 41))
            let wiggle: [Any] = [50, 50, 44, 56, 44, 56, 50, 50].map { point(CGPoint(x: $0 as CGFloat, y: 29)) }
            let times: [NSNumber] = [0, 0.1, 0.18, 0.26, 0.34, 0.42, 0.5, 1]
            animate(main, "position", wiggle, times)
            animate(dot, "position", [50, 50, 44, 56, 44, 56, 50, 50].map { point(CGPoint(x: $0 as CGFloat, y: 41)) }, times)
            animate(dot, "opacity", fade, fadeTimes)
            for other in others {
                animate(other, "position", [point(CGPoint(x: other.position.x, y: other.position.y)),
                                            point(CGPoint(x: other.position.x, y: other.position.y)),
                                            point(CGPoint(x: w / 2, y: h + 6)), point(CGPoint(x: w / 2, y: h + 6))], [0, 0.52, 0.72, 1])
                animate(other, "opacity", [1, 1, 0, 0, 1], [0, 0.52, 0.72, 0.95, 1])
            }
        case .switcher:
            let cards = (0..<3).map { window(CGRect(x: 8 + CGFloat($0) * 30, y: 22, width: 24, height: 20), alpha: 0.75) }
            let ring = CALayer()
            ring.bounds = CGRect(x: 0, y: 0, width: 28, height: 24)
            ring.cornerRadius = 4
            ring.borderWidth = 2
            ring.borderColor = NSColor.controlAccentColor.cgColor
            ring.position = cards[0].position
            stage.addSublayer(ring)
            _ = label("⌥ + Tab", at: CGPoint(x: w / 2, y: 10))
            animate(ring, "position", [point(cards[0].position), point(cards[1].position), point(cards[1].position),
                                       point(cards[2].position), point(cards[2].position)], [0, 0.2, 0.45, 0.6, 1])
        case .notchHome:
            notchHome()
        case .stripScroll:
            let columns = [window(CGRect(x: 4, y: 4, width: 44, height: 52)), window(CGRect(x: 48, y: 4, width: 34, height: 52), alpha: 0.8),
                           window(CGRect(x: 82, y: 4, width: 34, height: 52), alpha: 0.7)]
            let dots = [finger(at: CGPoint(x: 70, y: 53)), finger(at: CGPoint(x: 78, y: 53))]
            for column in columns {
                let x = column.position.x
                animate(column, "position", [point(CGPoint(x: x, y: 30)), point(CGPoint(x: x, y: 30)), point(CGPoint(x: x - 30, y: 30)),
                                             point(CGPoint(x: x - 30, y: 30)), point(CGPoint(x: x, y: 30))], [0, 0.12, 0.5, 0.88, 1])
            }
            for dot in dots {
                let x = dot.position.x
                animate(dot, "position", [point(CGPoint(x: x, y: 53)), point(CGPoint(x: x, y: 53)), point(CGPoint(x: x - 30, y: 53)),
                                          point(CGPoint(x: x - 30, y: 53))], [0, 0.12, 0.5, 1])
                animate(dot, "opacity", fade, fadeTimes)
            }
        case .dockHide:
            let dock = CALayer()
            dock.frame = CGRect(x: 20, y: 3, width: 60, height: 10)
            dock.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            dock.cornerRadius = 3
            stage.addSublayer(dock)
            let icons = (0..<4).map { index -> CALayer in
                let icon = CALayer()
                icon.frame = CGRect(x: 24 + CGFloat(index) * 14, y: 5, width: 8, height: 6)
                icon.cornerRadius = 1.5
                icon.backgroundColor = NSColor(hue: CGFloat(index) / 4, saturation: 0.5, brightness: 0.95, alpha: 1).cgColor
                stage.addSublayer(icon)
                return icon
            }
            let win = window(CGRect(x: 28, y: 20, width: 44, height: 32))
            let dot = finger(at: CGPoint(x: 42, y: 30))
            animate(dot, "position", [point(CGPoint(x: 42, y: 30)), point(icons[1].position), point(icons[1].position),
                                      point(icons[1].position)], [0, 0.25, 0.4, 1])
            animate(dot, "opacity", fade, fadeTimes)
            animate(icons[1], "transform.scale", [1, 1, 0.7, 1, 1], [0, 0.26, 0.31, 0.38, 1])
            animate(win, "opacity", [1, 1, 0, 0, 1], [0, 0.4, 0.55, 0.9, 1])
            animate(win, "transform.scale", [1, 1, 0.6, 0.6, 1], [0, 0.4, 0.55, 0.9, 1])
        case .splitBar:
            let left = window(CGRect(x: 4, y: 4, width: 44, height: 52))
            let right = window(CGRect(x: 52, y: 4, width: 44, height: 52), alpha: 0.8)
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: 14)
            bar.position = CGPoint(x: 50, y: 30)
            bar.cornerRadius = 1.5
            bar.backgroundColor = NSColor.white.cgColor
            stage.addSublayer(bar)
            let dot = finger(at: CGPoint(x: 50, y: 30))
            let xs: [CGFloat] = [50, 50, 34, 34, 50]
            let times: [NSNumber] = [0, 0.12, 0.45, 0.85, 1]
            animate(dot, "position", xs.map { point(CGPoint(x: $0, y: 30)) }, times)
            animate(dot, "opacity", fade, fadeTimes)
            animate(bar, "position", xs.map { point(CGPoint(x: $0, y: 30)) }, times)
            animate(left, "bounds.size", xs.map { size(CGSize(width: $0 - 6, height: 52)) }, times)
            animate(left, "position", xs.map { point(CGPoint(x: 4 + ($0 - 6) / 2, y: 30)) }, times)
            animate(right, "bounds.size", xs.map { size(CGSize(width: 96 - $0 - 2, height: 52)) }, times)
            animate(right, "position", xs.map { point(CGPoint(x: $0 + 2 + (96 - $0 - 2) / 2, y: 30)) }, times)
        case .slideOverHandle:
            let ring = CALayer()
            ring.frame = CGRect(x: 50, y: 4, width: 46, height: 52)
            ring.cornerRadius = 6
            ring.backgroundColor = NSColor(white: 0.78, alpha: 0.9).cgColor
            stage.addSublayer(ring)
            let win = window(CGRect(x: 53, y: 7, width: 40, height: 46))
            let dot = finger(at: CGPoint(x: 56, y: 10))
            let times: [NSNumber] = [0, 0.12, 0.5, 0.85, 1]
            let grow: [CGFloat] = [0, 0, 14, 14, 0]
            animate(dot, "position", grow.map { point(CGPoint(x: 56 - $0, y: 10)) }, times)
            animate(dot, "opacity", fade, fadeTimes)
            animate(win, "bounds.size", grow.map { size(CGSize(width: 40 + $0, height: 46)) }, times)
            animate(win, "position", grow.map { point(CGPoint(x: 73 - $0 / 2, y: 30)) }, times)
            animate(ring, "bounds.size", grow.map { size(CGSize(width: 46 + $0, height: 52)) }, times)
            animate(ring, "position", grow.map { point(CGPoint(x: 73 - $0 / 2, y: 30)) }, times)
        case .rectangle:
            let keys = label("⌃⌥ ←", at: CGPoint(x: 50, y: 50))
            let win = window(CGRect(x: 30, y: 8, width: 40, height: 30))
            animate(keys, "opacity", [0, 1, 1, 0.4, 0], [0, 0.1, 0.4, 0.85, 1])
            animate(win, "position", [point(CGPoint(x: 50, y: 23)), point(CGPoint(x: 50, y: 23)), point(CGPoint(x: 26, y: 23)),
                                      point(CGPoint(x: 26, y: 23))], [0, 0.4, 0.6, 1])
            animate(win, "bounds.size", [size(CGSize(width: 40, height: 30)), size(CGSize(width: 40, height: 30)),
                                         size(CGSize(width: 46, height: 38)), size(CGSize(width: 46, height: 38))], [0, 0.4, 0.6, 1])
        case .pip:
            let win = window(CGRect(x: 26, y: 12, width: 48, height: 34))
            let dot = finger(at: CGPoint(x: 50, y: 43))
            let times: [NSNumber] = [0, 0.12, 0.45, 0.62, 1]
            animate(dot, "position", [point(CGPoint(x: 50, y: 43)), point(CGPoint(x: 50, y: 43)), point(CGPoint(x: 84, y: 50)),
                                      point(CGPoint(x: 84, y: 50)), point(CGPoint(x: 84, y: 50))], times)
            animate(dot, "opacity", fade, fadeTimes)
            animate(win, "position", [point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 50, y: 29)), point(CGPoint(x: 80, y: 44)),
                                      point(CGPoint(x: 84, y: 48)), point(CGPoint(x: 84, y: 48))], times)
            animate(win, "bounds.size", [size(CGSize(width: 48, height: 34)), size(CGSize(width: 48, height: 34)),
                                         size(CGSize(width: 44, height: 31)), size(CGSize(width: 24, height: 17)),
                                         size(CGSize(width: 24, height: 17))], times)
        case .habit:
            switch Self.habit?.demo {
            case let .keys(from, to)?: keys(from: from, to: to)
            case .notchHome?: notchHome()
            case .flickDown?: flickDown()
            case .menuBar?: menuBar()
            case nil: break
            }
        case .shade:
            let win = window(CGRect(x: 26, y: 10, width: 48, height: 38))
            let dots = [finger(at: CGPoint(x: 46, y: 45)), finger(at: CGPoint(x: 56, y: 45))]
            for dot in dots {
                let x = dot.position.x
                animate(dot, "position", [point(CGPoint(x: x, y: 38)), point(CGPoint(x: x, y: 38)), point(CGPoint(x: x, y: 50)),
                                          point(CGPoint(x: x, y: 50))], [0, 0.1, 0.4, 1])
                animate(dot, "opacity", fade, fadeTimes)
            }
            win.anchorPoint = CGPoint(x: 0.5, y: 1)
            win.position = CGPoint(x: 50, y: 48)
            animate(win, "bounds.size", [size(CGSize(width: 48, height: 38)), size(CGSize(width: 48, height: 38)),
                                         size(CGSize(width: 48, height: 6)), size(CGSize(width: 48, height: 6)),
                                         size(CGSize(width: 48, height: 38))], [0, 0.12, 0.45, 0.88, 1])
        }
    }

    // MARK: 卡住时的提示

    /// Mac 键帽上印的字：修饰键写名字（和键盘上一样），别的照写。
    private static let keyWords: [String: String] = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command", "🌐": "fn"]

    /// 一排键帽，横着居中摆在 y 处。两排都照 Mac 键帽印：修饰键上面是符号、下面一行小字写名字（⌃ 下面写 control），
    /// 第一次看到 ⌃ 也知道是哪个键。lit：Mac 上那一排（强调色）。只有自己设的快捷键（聚焦搜索、启动台）太长放不下时，
    /// 才退回只写符号。
    private func keycapRow(_ labels: [String], y: CGFloat, height: CGFloat, lit: Bool) -> [CALayer] {
        let symbolFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let keyFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let nameFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
        let wordFont = NSFont.systemFont(ofSize: 6, weight: .medium)
        struct Cap { let top: String; let topFont: NSFont; let word: String?; let width: CGFloat }
        func textWidth(_ text: String, _ font: NSFont) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        }
        func caps(words: Bool) -> [Cap] {
            labels.map { label in
                if words, let word = Self.keyWords[label] {
                    let width = max(textWidth(label, symbolFont), textWidth(word, wordFont)) + 5
                    return Cap(top: label, topFont: symbolFont, word: word, width: max(height, width))
                }
                let font = label.count > 1 ? nameFont : keyFont
                return Cap(top: label, topFont: font, word: nil, width: max(height, textWidth(label, font) + 8))
            }
        }
        let gap: CGFloat = 3
        func total(_ row: [Cap]) -> CGFloat { row.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, row.count - 1)) }
        var row = caps(words: true)
        if total(row) > Self.size.width - 6 { row = caps(words: false) }
        var x = (Self.size.width - total(row)) / 2
        var layers: [CALayer] = []
        for item in row {
            let cap = CALayer()
            cap.frame = CGRect(x: x, y: y, width: item.width, height: height)
            cap.cornerRadius = 4
            cap.cornerCurve = .continuous
            cap.backgroundColor = (lit ? NSColor.controlAccentColor.withAlphaComponent(0.28)
                                       : NSColor.white.withAlphaComponent(0.1)).cgColor
            cap.borderColor = (lit ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.35)).cgColor
            cap.borderWidth = 1
            func text(_ string: String, _ font: NSFont, alpha: CGFloat, centerY: CGFloat) {
                let layer = CATextLayer()
                layer.string = string
                layer.font = font
                layer.fontSize = font.pointSize
                layer.foregroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
                layer.alignmentMode = .center
                layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                let line = ceil(font.ascender - font.descender)
                layer.frame = CGRect(x: 0, y: round(centerY - line / 2), width: item.width, height: line)
                cap.addSublayer(layer)
            }
            if let word = item.word {
                // 上面符号、下面名字（图层坐标 y 朝上）。
                text(item.top, item.topFont, alpha: 1, centerY: height * 0.66)
                text(word, wordFont, alpha: 0.85, centerY: height * 0.26)
            } else {
                text(item.top, item.topFont, alpha: 1, centerY: height / 2)
            }
            stage.addSublayer(cap)
            layers.append(cap)
            x += item.width + gap
        }
        return layers
    }

    /// 两排键帽：上面刚才按的那一下按下去、变暗，下面 Mac 上那一下亮起来、按一下。
    /// 没有上面一排时只按下面一排；没有下面一排时（没有可教的组合）只按下去、变暗。
    private func keys(from: [String], to: [String]) {
        let height: CGFloat = 22
        let middle = (Self.size.height - height) / 2
        if from.isEmpty || to.isEmpty {
            let lit = from.isEmpty
            for cap in keycapRow(lit ? to : from, y: middle, height: height, lit: lit) {
                animate(cap, "transform.scale", [1, 1, 0.86, 1, 1], [0, 0.3, 0.36, 0.44, 1])
                if !lit { animate(cap, "opacity", [1, 1, 0.35, 0.35], [0, 0.44, 0.56, 1]) }
            }
            return
        }
        for cap in keycapRow(from, y: 33, height: height, lit: false) {
            animate(cap, "transform.scale", [1, 1, 0.86, 1, 1], [0, 0.1, 0.16, 0.24, 1])
            animate(cap, "opacity", [1, 1, 0.35, 0.35], [0, 0.3, 0.42, 1])
        }
        for cap in keycapRow(to, y: 5, height: height, lit: true) {
            animate(cap, "opacity", [0, 0, 1, 1], [0, 0.38, 0.5, 1])
            animate(cap, "transform.scale", [1, 1, 0.86, 1, 1], [0, 0.62, 0.68, 0.76, 1])
        }
    }

    /// 往下甩一下标题栏：窗口铺满。
    private func flickDown() {
        let win = window(CGRect(x: 30, y: 22, width: 40, height: 28))
        let dot = finger(at: CGPoint(x: 50, y: 47))
        let times: [NSNumber] = [0, 0.12, 0.3, 0.5, 1]
        animate(dot, "position", [point(CGPoint(x: 50, y: 47)), point(CGPoint(x: 50, y: 47)), point(CGPoint(x: 50, y: 32)),
                                  point(CGPoint(x: 50, y: 32)), point(CGPoint(x: 50, y: 32))], times)
        animate(dot, "opacity", [0, 1, 1, 0, 0], [0, 0.08, 0.32, 0.42, 1])
        animate(win, "position", [point(CGPoint(x: 50, y: 36)), point(CGPoint(x: 50, y: 36)), point(CGPoint(x: 50, y: 30)),
                                  point(CGPoint(x: 50, y: 30)), point(CGPoint(x: 50, y: 30))], times)
        animate(win, "bounds.size", [size(CGSize(width: 40, height: 28)), size(CGSize(width: 40, height: 28)),
                                     size(CGSize(width: 40, height: 28)), size(CGSize(width: 92, height: 52)),
                                     size(CGSize(width: 92, height: 52))], times)
    }

    /// 菜单栏一直在屏幕最上面：指到 App 名上，菜单掉下来。
    private func menuBar() {
        let h = Self.size.height
        let bar = CALayer()
        bar.frame = CGRect(x: 0, y: h - 9, width: Self.size.width, height: 9)
        bar.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        stage.addSublayer(bar)
        let highlight = CALayer()
        highlight.frame = CGRect(x: 5, y: h - 8.5, width: 18, height: 8)
        highlight.cornerRadius = 2
        highlight.backgroundColor = NSColor.controlAccentColor.cgColor
        highlight.opacity = 0
        stage.addSublayer(highlight)
        for index in 0..<4 {
            let title = CALayer()
            title.frame = CGRect(x: 8 + CGFloat(index) * 16, y: h - 6.5, width: index == 0 ? 12 : 10, height: 4)
            title.cornerRadius = 1
            title.backgroundColor = NSColor.white.withAlphaComponent(index == 0 ? 0.9 : 0.6).cgColor
            stage.addSublayer(title)
        }
        let menu = CALayer()
        menu.frame = CGRect(x: 6, y: h - 39, width: 34, height: 30)
        menu.cornerRadius = 3
        menu.backgroundColor = NSColor(white: 0.85, alpha: 0.95).cgColor
        menu.opacity = 0
        stage.addSublayer(menu)
        let start = CGPoint(x: 62, y: 22), target = CGPoint(x: 14, y: h - 4.5)
        let dot = finger(at: start)
        animate(dot, "position", [point(start), point(target), point(target), point(target)], [0, 0.3, 0.45, 1])
        animate(dot, "opacity", [0, 1, 1, 0, 0], [0, 0.08, 0.45, 0.55, 1])
        animate(highlight, "opacity", [0, 0, 1, 1], [0, 0.33, 0.38, 1])
        animate(menu, "opacity", [0, 0, 1, 1], [0, 0.36, 0.45, 1])
    }

    /// 点一下刘海：一排图标出来（回到主屏幕）。
    private func notchHome() {
        let w = Self.size.width, h = Self.size.height
        let notch = CALayer()
        notch.frame = CGRect(x: w / 2 - 14, y: h - 7, width: 28, height: 7)
        notch.backgroundColor = NSColor.black.cgColor
        notch.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        notch.borderWidth = 1
        notch.cornerRadius = 3
        stage.addSublayer(notch)
        let icons = (0..<6).map { index -> CALayer in
            let icon = CALayer()
            icon.frame = CGRect(x: 22 + CGFloat(index % 3) * 20, y: 8 + CGFloat(index / 3) * 18, width: 14, height: 14)
            icon.cornerRadius = 3.5
            icon.backgroundColor = NSColor(hue: CGFloat(index) / 6, saturation: 0.5, brightness: 0.95, alpha: 1).cgColor
            icon.opacity = 0
            stage.addSublayer(icon)
            return icon
        }
        let dot = finger(at: CGPoint(x: w / 2, y: 30))
        animate(dot, "position", [point(CGPoint(x: w / 2, y: 30)), point(CGPoint(x: w / 2, y: h - 4)), point(CGPoint(x: w / 2, y: h - 4)),
                                  point(CGPoint(x: w / 2, y: h - 4))], [0, 0.25, 0.4, 1])
        animate(dot, "opacity", [0, 1, 1, 0, 0], [0, 0.08, 0.4, 0.5, 1])
        animate(notch, "transform.scale", [1, 1, 0.8, 1, 1], [0, 0.28, 0.33, 0.4, 1])
        for icon in icons { animate(icon, "opacity", [0, 0, 1, 1, 0], [0, 0.4, 0.55, 0.9, 1]) }
    }

}

/// 卡住提示右上角的小叉：点它只是关掉，这条不再出。提示本身不接指针（刘海统一接点击，看落点是不是这里），
/// 这个视图只负责画出来，并给辅助功能一个“关闭”按钮。
final class HabitCloseButton: NSView {
    var onPress: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        guard let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.75)]))) else { return }
        let size = image.size
        image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "关闭" }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return onPress != nil
    }
}
