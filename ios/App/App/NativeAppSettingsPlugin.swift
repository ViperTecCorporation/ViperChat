import Capacitor
import UIKit

@objc(NativeAppSettingsPlugin)
final class NativeAppSettingsPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "NativeAppSettingsPlugin"
    let jsName = "NativeAppSettings"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openNotificationSettings", returnType: CAPPluginReturnPromise)
    ]

    @objc func openNotificationSettings(_ call: CAPPluginCall) {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            call.reject("Unable to open notification settings")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(settingsURL) { opened in
                if opened {
                    call.resolve()
                } else {
                    call.reject("Unable to open notification settings")
                }
            }
        }
    }
}
