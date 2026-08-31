import Capacitor
import UIKit

/// Capacitor discovers plugins from the generated `capacitor.config.json`,
/// which `cap sync` rewrites from `node_modules` on every build — an entry for
/// a plugin that lives in this target would be dropped each time. Registering
/// the instance by hand keeps LiveActivity out of that file entirely.
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(LiveActivityPlugin())
    }
}
