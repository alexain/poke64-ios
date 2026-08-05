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

final class MouseCaptureUIView: UIView {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onButton: ((Int, Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGestures()
    }

    private func configureGestures() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(pan)

        let primaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryTap(_:))
        )
        primaryTap.numberOfTouchesRequired = 1
        primaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(primaryTap)

        let secondaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSecondaryTap(_:))
        )
        secondaryTap.numberOfTouchesRequired = 2
        secondaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(secondaryTap)

        primaryTap.require(toFail: secondaryTap)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        onMove?(translation.x, translation.y)
    }

    @objc private func handlePrimaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        pulse(button: 0)
    }

    @objc private func handleSecondaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        pulse(button: 1)
    }

    private func pulse(button: Int) {
        onButton?(button, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.onButton?(button, false)
        }
    }
}
