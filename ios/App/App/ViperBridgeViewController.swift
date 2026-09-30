import Capacitor
import UIKit

final class ViperBridgeViewController: CAPBridgeViewController {
    private let nativeBrandColor = UIColor(
        red: 111 / 255,
        green: 57 / 255,
        blue: 53 / 255,
        alpha: 1
    )

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The entire WebView, including fixed/teleported drawers, must be inside
        // the safe area. Painting over an edge does not reserve layout space.
        if let webView = webView {
            let container = UIView(frame: view.bounds)
            view = container
            container.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor)
            ])
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }
        applyThemeColor(nativeBrandColor)
    }

    func applyThemeColor(_ color: UIColor) {
        view.backgroundColor = color
        webView?.isOpaque = false
        webView?.backgroundColor = color
        webView?.scrollView.backgroundColor = color
        webView?.underPageBackgroundColor = color
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SecureStoragePlugin())
        bridge?.registerPluginInstance(NativeSharePlugin())
        bridge?.registerPluginInstance(NativeAppSettingsPlugin())
        bridge?.registerPluginInstance(NativeVideoPlugin())
        bridge?.registerPluginInstance(NativeSystemBarsPlugin())
    }
}

@objc(NativeSystemBarsPlugin)
final class NativeSystemBarsPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "NativeSystemBarsPlugin"
    let jsName = "NativeSystemBars"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setThemeColor", returnType: CAPPluginReturnPromise)
    ]

    @objc func setThemeColor(_ call: CAPPluginCall) {
        guard let hex = call.getString("color"),
              hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              let rgb = UInt32(hex.dropFirst(), radix: 16) else {
            call.reject("Expected an RGB hex color")
            return
        }
        let color = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                            green: CGFloat((rgb >> 8) & 255) / 255,
                            blue: CGFloat(rgb & 255) / 255, alpha: 1)
        DispatchQueue.main.async {
            guard let controller = self.bridge?.viewController as? ViperBridgeViewController else {
                call.reject("Native view unavailable")
                return
            }
            controller.applyThemeColor(color)
            call.resolve()
        }
    }
}
