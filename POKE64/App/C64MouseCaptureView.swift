import SwiftUI
import UIKit

struct C64MouseCaptureView: UIViewRepresentable {
    let onMove: (CGFloat, CGFloat) -> Void
    let onButton: (Int, Bool) -> Void

    func makeUIView(context: Context) -> MouseCaptureUIView {
        let view = MouseCaptureUIView()
        view.onMove = onMove
        view.onButton = onButton
        return view
    }

    func updateUIView(_ view: MouseCaptureUIView, context: Context) {
        view.onMove = onMove
        view.onButton = onButton
    }
}

/// Captures direct screen touches as a relative Commodore mouse.
///
/// One finger holds the primary button from touch-down until touch-up, so the
/// user can drag while keeping the button pressed. Two fingers select and hold
/// the secondary button. Pointer devices are handled separately through
/// GameController/GCMouse.
final class MouseCaptureUIView: UIView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onButton: ((Int, Bool) -> Void)?

    private var directTouches: [ObjectIdentifier: UITouch] = [:]
    private var previousCentroid: CGPoint?
    private var activeButton: Int?
    private var suppressPrimaryUntilAllTouchesEnd = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let previousCount = directTouches.count
        for touch in touches where touch.type == .direct {
            directTouches[ObjectIdentifier(touch)] = touch
        }

        guard directTouches.count != previousCount else { return }
        if directTouches.count >= 2 {
            suppressPrimaryUntilAllTouchesEnd = true
        }

        previousCentroid = touchCentroid()
        updateButtonState()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.contains(where: { $0.type == .direct }),
              let centroid = touchCentroid() else {
            return
        }

        if let previousCentroid {
            let deltaX = centroid.x - previousCentroid.x
            let deltaY = centroid.y - previousCentroid.y
            if deltaX != 0 || deltaY != 0 {
                onMove?(deltaX, deltaY)
            }
        }

        previousCentroid = centroid
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelAllTouches()
        }
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            directTouches[ObjectIdentifier(touch)] = nil
        }

        updateButtonState()
        previousCentroid = touchCentroid()

        if directTouches.isEmpty {
            suppressPrimaryUntilAllTouchesEnd = false
        }
    }

    private func updateButtonState() {
        let requestedButton: Int?
        if directTouches.count >= 2 {
            requestedButton = 1
        } else if directTouches.count == 1, !suppressPrimaryUntilAllTouchesEnd {
            requestedButton = 0
        } else {
            requestedButton = nil
        }

        guard requestedButton != activeButton else { return }

        if let activeButton {
            onButton?(activeButton, false)
        }
        activeButton = requestedButton
        if let requestedButton {
            onButton?(requestedButton, true)
        }
    }

    private func touchCentroid() -> CGPoint? {
        guard !directTouches.isEmpty else { return nil }

        var x: CGFloat = 0
        var y: CGFloat = 0
        for touch in directTouches.values {
            let location = touch.location(in: self)
            x += location.x
            y += location.y
        }

        let count = CGFloat(directTouches.count)
        return CGPoint(x: x / count, y: y / count)
    }

    private func cancelAllTouches() {
        if let activeButton {
            onButton?(activeButton, false)
        }
        activeButton = nil
        directTouches.removeAll()
        previousCentroid = nil
        suppressPrimaryUntilAllTouchesEnd = false
    }
}

/// Hides the iPadOS pointer and consumes indirect pointer clicks while a
/// physical mouse controls the emulated 1351. Direct screen touches pass
/// through, so the toolbar remains usable by touch.
struct ExternalMouseCaptureShield: UIViewRepresentable {
    func makeUIView(context: Context) -> ExternalMouseCaptureShieldUIView {
        ExternalMouseCaptureShieldUIView()
    }

    func updateUIView(_ view: ExternalMouseCaptureShieldUIView, context: Context) {}
}

final class ExternalMouseCaptureShieldUIView: UIView, UIPointerInteractionDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        addInteraction(UIPointerInteraction(delegate: self))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), let event else { return nil }

        switch event.type {
        case .hover, .scroll, .transform:
            return self
        case .touches:
            let isPointerClick = event.allTouches?.contains {
                $0.type == .indirectPointer
            } == true
            return isPointerClick ? self : nil
        case .motion, .presses, .remoteControl:
            return nil
        @unknown default:
            return nil
        }
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        regionFor request: UIPointerRegionRequest,
        defaultRegion: UIPointerRegion
    ) -> UIPointerRegion? {
        UIPointerRegion(rect: bounds, identifier: "POKE64ExternalMouseCapture" as NSString)
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {
        .hidden()
    }
}
