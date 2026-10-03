import Foundation

/// 滚动改写只消费分类器已经允许改写的事件。不创建事件，不读设备。
struct ScrollSession: Sendable {
    struct Request: Equatable, Sendable {
        var smooth: SmoothScroll.Preset?
        var invertMouse: Bool
        var fine: Bool
        var sideButtons: Bool
        var foregroundExcluded: Bool
    }

    enum Sample: Sendable {
        case scroll(InputDeviceClassifier.ScrollEvidence, notchesX: Double, notchesY: Double, option: Bool)
        case sideButton(InputDeviceClassifier.ScrollEvidence, number: Int)
    }

    enum Disposition: Equatable, Sendable {
        case pass
        case invert
        case smooth(x: Double, y: Double, finished: Bool)
        case line(x: Int, y: Int)
        case side(back: Bool)
    }

    private var vertical = SmoothScroll(preset: .medium)
    private var horizontal = SmoothScroll(preset: .medium)

    mutating func handle(_ sample: Sample, request: Request, at now: WS2.Instant) -> Disposition {
        if request.foregroundExcluded { return .pass }
        switch sample {
        case .scroll(let evidence, let notchesX, let notchesY, let option):
            return scroll(evidence, notchesX: notchesX, notchesY: notchesY, option: option, request: request, at: now)
        case .sideButton(let evidence, let number):
            guard request.sideButtons else { return .pass }
            guard InputDeviceClassifier.classify(evidence).mayRewrite else { return .pass }
            // 规格写的是侧键 4 / 5。不改成别的编号。
            if number == 4 { return .side(back: true) }
            if number == 5 { return .side(back: false) }
            return .pass
        }
    }

    mutating func step(at now: WS2.Instant) -> Disposition {
        guard let y = vertical.step(at: now), let x = horizontal.step(at: now) else { return .pass }
        let finished = y.finished && x.finished
        return .smooth(x: x.delta, y: y.delta, finished: finished)
    }

    mutating func cancel() {
        vertical.cancel()
        horizontal.cancel()
    }

    var pending: Double { vertical.pending + horizontal.pending }

    private mutating func scroll(_ evidence: InputDeviceClassifier.ScrollEvidence, notchesX: Double, notchesY: Double,
                                 option: Bool, request: Request, at now: WS2.Instant) -> Disposition {
        guard notchesX.isFinite, notchesY.isFinite else { return .pass }
        let classified = InputDeviceClassifier.classify(evidence)
        guard classified.mayRewrite else { return .pass }
        if request.fine, option {
            return .line(x: lineUnit(notchesX), y: lineUnit(notchesY))
        }
        var x = notchesX
        var y = notchesY
        if request.invertMouse, classified.kind == .wheelMouse || classified.kind == .magicMouse {
            x = -x
            y = -y
        }
        if let preset = request.smooth {
            use(preset)
            guard vertical.add(notches: y, at: now) != nil, horizontal.add(notches: x, at: now) != nil else { return .pass }
            let finished = vertical.isFinished && horizontal.isFinished
            return .smooth(x: 0, y: 0, finished: finished)
        }
        if request.invertMouse, classified.kind == .wheelMouse || classified.kind == .magicMouse {
            return .invert
        }
        return .pass
    }

    private mutating func use(_ preset: SmoothScroll.Preset) {
        guard vertical.preset != preset else { return }
        vertical.cancel()
        horizontal.cancel()
        vertical = SmoothScroll(preset: preset)
        horizontal = SmoothScroll(preset: preset)
    }

    /// 一条事件最多一行。事件里没有单独的「第几格」字段。
    private func lineUnit(_ notches: Double) -> Int {
        if notches > 0 { return 1 }
        if notches < 0 { return -1 }
        return 0
    }
}
