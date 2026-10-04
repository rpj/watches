import Foundation

/// Identifiers shared by the app and widget targets. These must match the
/// entitlements declared in ../project.yml.
public enum WristConstants {
    /// App Group: UserDefaults suite, shared files, and the Keychain access
    /// group (app groups are valid keychain access groups without a team prefix).
    public static let appGroupID = "group.com.ryanswatches.wrist"
    /// kSecAttrService for our Keychain items.
    public static let keychainService = "com.ryanswatches.wrist"
    public static let defaultServerURL = URL(string: "https://ryanswatches.com")!
    /// WidgetKit `kind` for the Top Watches widget.
    public static let widgetKind = "TopWatchesWidget"
    /// Launch argument that swaps live services for in-memory fixtures.
    public static let uiTestingArgument = "-uiTesting"
    /// Deep link opened by the widget's non-interactive areas.
    public static let openURL = URL(string: "wrist://picker")!
}
