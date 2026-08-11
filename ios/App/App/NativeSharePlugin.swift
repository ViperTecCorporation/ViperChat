import Capacitor
import Foundation

@objc(NativeSharePlugin)
final class NativeSharePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "NativeSharePlugin"
    let jsName = "NativeShare"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getPendingShare", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearFiles", returnType: CAPPluginReturnPromise)
    ]

    @objc func getPendingShare(_ call: CAPPluginCall) {
        call.resolve(["available": false])
    }

    @objc func clearFiles(_ call: CAPPluginCall) {
        call.resolve()
    }
}
