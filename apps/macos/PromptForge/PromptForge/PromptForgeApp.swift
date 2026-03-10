import SwiftUI

@main
struct PromptForgeApp: App {
    @StateObject private var appModel: PromptForgeAppModel

    init() {
        let launchContext = LaunchContext(arguments: CommandLine.arguments)
        _appModel = StateObject(
            wrappedValue: PromptForgeAppModel(
                initialProjectPath: launchContext.projectPath,
                initialEngineRoot: launchContext.engineRoot
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
