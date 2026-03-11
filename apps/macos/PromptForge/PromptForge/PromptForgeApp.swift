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
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("PromptForge") {
                Button("Command Bar") {
                    appModel.openCommandBar()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("Quick Check") {
                    appModel.runQuickBenchmark()
                }
                .disabled(appModel.selectedPrompt == nil)

                Button("Run Suite") {
                    appModel.runScenarioReview()
                }
                .disabled(appModel.selectedPrompt == nil || appModel.selectedSuite == nil)

                Button("Save Workspace") {
                    appModel.savePromptWorkspace()
                }
                .disabled(appModel.selectedPrompt == nil)
            }
        }
    }
}
