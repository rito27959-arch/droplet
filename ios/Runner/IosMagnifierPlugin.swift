import Flutter
import UIKit

/// Plugin Flutter gérant la loupe native iOS via UITextLoupeSession.
///
/// Canal : `droplet/native_magnifier`
/// Méthodes :
///   - show(x, y)    → Affiche la loupe à la position donnée
///   - move(x, y)    → Déplace la loupe
///   - hide           → Masque la loupe
class IosMagnifierPlugin: NSObject, FlutterPlugin {

    private var loupeSession: UITextLoupeSession?
    private var flutterView: FlutterView?

    // MARK: - FlutterPlugin

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "droplet/native_magnifier",
            binaryMessenger: registrar.messenger()
        )
        let instance = IosMagnifierPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            guard let args = call.arguments as? [String: Any],
                  let x = args["x"] as? CGFloat,
                  let y = args["y"] as? CGFloat else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments x,y requis", details: nil))
                return
            }
            showLoupe(at: CGPoint(x: x, y: y))
            result(nil)

        case "move":
            guard let args = call.arguments as? [String: Any],
                  let x = args["x"] as? CGFloat,
                  let y = args["y"] as? CGFloat else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments x,y requis", details: nil))
                return
            }
            moveLoupe(to: CGPoint(x: x, y: y))
            result(nil)

        case "hide":
            hideLoupe()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Loupe

    private func findFlutterView() -> FlutterView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first else {
            return nil
        }
        return findFlutterView(in: window)
    }

    private func findFlutterView(in view: UIView) -> FlutterView? {
        if let flutterView = view as? FlutterView {
            return flutterView
        }
        for subview in view.subviews {
            if let found = findFlutterView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func showLoupe(at point: CGPoint) {
        guard let flutterView = findFlutterView() else {
            return
        }
        self.flutterView = flutterView

        if let session = loupeSession {
            // Déplacer la session existante
            session.move(to: point, with: .zero, trackingCaret: false)
        } else {
            // Créer une nouvelle session
            // beginLoupeSessionAtPoint:fromSelectionWidgetView:inView:
            // Le 2e argument est la vue "selection widget" (peut être la même)
            let session = UITextLoupeSession.begin(
                at: point,
                fromSelectionWidgetView: flutterView,
                in: flutterView
            )
            self.loupeSession = session
        }
    }

    private func moveLoupe(to point: CGPoint) {
        loupeSession?.move(to: point, with: .zero, trackingCaret: false)
    }

    private func hideLoupe() {
        loupeSession?.invalidate()
        loupeSession = nil
        flutterView = nil
    }
}
