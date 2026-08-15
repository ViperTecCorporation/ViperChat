import Capacitor
import Foundation

@objc(NativeSharePlugin)
final class NativeSharePlugin: CAPPlugin, CAPBridgedPlugin {
    private let appGroup = "group.net.vipertec.viperchat"
    private let pendingShareKey = "viper.pending-share"
    let identifier = "NativeSharePlugin"
    let jsName = "NativeShare"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getPendingShare", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearFiles", returnType: CAPPluginReturnPromise)
    ]

    @objc func getPendingShare(_ call: CAPPluginCall) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: pendingShareKey),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            call.resolve(["available": false])
            return
        }

        call.resolve(payload.merging(["available": true]) { current, _ in current })
    }

    @objc func clearFiles(_ call: CAPPluginCall) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            call.resolve()
            return
        }

        let shareDirectory = container.appendingPathComponent("shared", isDirectory: true)
            .standardizedFileURL.path + "/"
        for path in call.getArray("paths")?.compactMap({ $0 as? String }) ?? [] {
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            if fileURL.path.hasPrefix(shareDirectory) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: pendingShareKey)
        call.resolve()
    }
}
