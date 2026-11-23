import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct InstaBoxManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ViewState private var store = AppStore()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTestSuite.runAndExit()
        }
        if CommandLine.arguments.contains("--mcp") {
            MCPStdioRunner.runAndExit()
        }
    }

    var body: some Scene {
        WindowGroup("InstaBox 管理面板", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1260, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建沙盒…") {
                    if store.isConnected {
                        store.showCreateMachineSheet = true
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!store.isConnected)

                Button("刷新全部数据") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!store.isConnected)
            }
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cube.transparent.fill")
                if store.isConnected && store.runningMachineCount > 0 {
                    Text("\(store.runningMachineCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .frame(width: 560, height: 460)
        }
    }
}
