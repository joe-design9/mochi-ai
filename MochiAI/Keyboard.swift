import SwiftUI
import UIKit

// MARK: - Tap-outside keyboard dismissal
//
// The user requirement: the keyboard must go away by TAPPING anywhere
// outside a text field ("wegdrücken") — not via a toolbar button. Two
// layers make this robust:
//
// 1. A window-level UITapGestureRecognizer (`KeyboardTapGuard`) that
//    observes every tap WITHOUT cancelling touches (buttons, scrolling
//    and lists keep working). Taps landing on a text input are excluded
//    in `shouldReceive` — those taps are meant to focus the field — and
//    every other tap resigns the first responder.
// 2. A SwiftUI `simultaneousGesture(TapGesture)` on each screen root
//    (this file's `dismissKeyboardOnTap()`), as the brief requires. Its
//    handler consults the guard's "last input touch" timestamp so a tap
//    that just focused a field never instantly unfocuses it again.
//
// The "Fertig" toolbar remains in the forms as a secondary backup, and
// `.scrollDismissesKeyboard(.interactively)` stays on the scroll views.

enum KeyboardDismisser {
    /// Resigns whatever is currently first responder (field/search bar).
    static func hide() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

/// Window-level tap observer: dismisses the keyboard on any tap that
/// does not land on a text input.
final class KeyboardTapGuard: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardTapGuard()

    private weak var installedWindow: UIWindow?

    /// When the most recent tap landed on a text input. The SwiftUI
    /// tap-to-dismiss gesture reads this to avoid unfocusing a field
    /// the user has just tapped into. (The UIKit delegate is consulted
    /// during touch delivery — strictly before SwiftUI reports the
    /// completed tap — so this is always up to date when read.)
    private(set) var lastInputTouchAt: Date = .distantPast

    /// When the most recent tap landed on a control (button etc.).
    /// Control taps are ACTIONS — most importantly the chat's send
    /// button — never dismiss taps. Bug found 2026-10-31: the guard
    /// used to resign the first responder on EVERY non-input tap,
    /// so each tap on "send" killed the keyboard and the user had
    /// to reopen it for every single message.
    private(set) var lastControlTouchAt: Date = .distantPast

    /// Installs the recognizer on the current key window (idempotent —
    /// a new window, e.g. after scene changes, gets its own recognizer).
    func installIfNeeded() {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        guard let keyWindow, installedWindow !== keyWindow else { return }
        installedWindow = keyWindow

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false // never steal touches from controls
        tap.delegate = self
        keyWindow.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        // Belt and braces: even if a tap reaches this handler, never
        // resign right after an input or control touch (the delegate
        // normally filters those out before recognition).
        let now = Date()
        if now.timeIntervalSince(lastInputTouchAt) < 0.4
            || now.timeIntervalSince(lastControlTouchAt) < 0.4 {
            return
        }
        KeyboardDismisser.hide()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Taps on (or inside) a text input focus that input — never
        // treat them as dismiss taps. Remember the moment so the
        // SwiftUI gesture layer can apply the same guard.
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                lastInputTouchAt = Date()
                return false
            }
            if current is UIControl {
                // Buttons and other controls perform an action with
                // the tap (send, call, tab …) — the keyboard must
                // survive it. Dismissal is only for taps on dead
                // surface: message background, empty areas.
                lastControlTouchAt = Date()
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true // observe alongside scroll/button recognizers, never block them
    }
}

/// Zero-size, non-interactive marker view whose appearance (re)installs
/// the window tap guard. Used as the background of every screen root.
private struct KeyboardInstallView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { KeyboardTapGuard.shared.installIfNeeded() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { KeyboardTapGuard.shared.installIfNeeded() }
    }
}

/// Tap-outside-to-dismiss, applied to a screen's root container.
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KeyboardInstallView())
            .simultaneousGesture(
                TapGesture().onEnded {
                    // A tap within the last blink of an eye that landed
                    // on a text input was meant to focus it — the guard
                    // recorded it; don't resign the fresh first responder.
                    let guardState = KeyboardTapGuard.shared
                    if Date().timeIntervalSince(guardState.lastInputTouchAt) > 0.4
                        && Date().timeIntervalSince(guardState.lastControlTouchAt) > 0.4 {
                        KeyboardDismisser.hide()
                    }
                }
            )
    }
}

extension View {
    /// Dismisses the keyboard when the user taps anywhere outside a
    /// text field. Apply once on each screen/sheet root.
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}
