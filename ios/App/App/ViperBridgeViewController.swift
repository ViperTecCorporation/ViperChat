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
        view.backgroundColor = nativeBrandColor
        webView?.backgroundColor = nativeBrandColor
        webView?.scrollView.backgroundColor = nativeBrandColor
    }

    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SecureStoragePlugin())
        bridge?.registerPluginInstance(NativeSharePlugin())
    }
}
