import SwiftUI

@main
struct PromptForgeApp: App {
    @StateObject private var appModel: PromptForgeAppModel

    init() {
        let launchContext = LaunchContext(arguments: CommandLine.arguments)
        let bundledEngineRoot = (Bundle.main.object(forInfoDictionaryKey: "PromptForgeEngineRoot") as? String).map {
            NSString(string: $0).expandingTildeInPath
        }.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        _appModel = StateObject(
            wrappedValue: PromptForgeAppModel(
                initialProjectPath: launchContext.projectPath,
                initialEngineRoot: launchContext.engineRoot ?? bundledEngineRoot
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
