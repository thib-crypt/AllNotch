import Foundation

/// Locates the bundled OpenCode plugin JavaScript shipped as a package
/// resource. `OpenCodePluginInstallationManager.install(pluginSourceData:)`
/// needs the raw bytes; this is the single source of truth for them so the app
/// layer never has to know the resource's on-disk name.
public enum OpenCodePluginSource {
    public enum LoadError: Error, LocalizedError {
        case resourceMissing

        public var errorDescription: String? {
            switch self {
            case .resourceMissing:
                return "Bundled OpenCode plugin source could not be found."
            }
        }
    }

    /// Raw bytes of the bundled `open-island-opencode.js` plugin.
    public static func data() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "open-island-opencode",
            withExtension: "js"
        ) else {
            throw LoadError.resourceMissing
        }
        return try Data(contentsOf: url)
    }
}
