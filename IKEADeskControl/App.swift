import SwiftUI
import AppKit
import Combine

//@main
//struct IKEADeskControlApp: App {
//
//    @StateObject private var appModel = AppModel.shared
//
//    var body: some Scene {
//        MenuBarExtra("IKEA Desk Control", systemImage: "arrow.up.and.down") {
//            Button("Quit IKEA Desk Control") {
//                NSApp.terminate(nil)
//            }
//            .keyboardShortcut("Q", modifiers: .command)
//        }
//    }
//}

@main
struct IKEADeskControlApp {
    static func main() {
        let app = NSApplication.shared
        
        let delegate = AppDelegate()
        app.delegate = delegate

        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    // MARK: - Private Vars
    
    private var appModel: AppModel!
    
    private var statusItem: NSStatusItem!
    private var setupResetMenuItem: NSMenuItem!
    
    private var setupWindow: NSWindow?
    private var setupViewModel: SetupViewModel?
    
    // MARK: - NSApplicationDelegate
 
    func applicationDidFinishLaunching(_ notification: Notification) {
        appModel = AppModel.shared
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.up.and.down",
                accessibilityDescription: "IKEA Desk Control"
            )
        }
        
        setupMenu()
        
        updateSetupResetMenuItem()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        setupWindow = nil
        setupViewModel = nil
        return true
    }
    
    // MARK: - Setup
    
    private func setupMenu() {
        setupResetMenuItem = NSMenuItem(
            title: "",
            action: #selector(AppDelegate.toggle),
            keyEquivalent: ""
        )
        
        let statusMenu = NSMenu()
        statusMenu.addItem(setupResetMenuItem)
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(
            title: "Quit IKEA Desk Control",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "Q"
        ))
        statusItem.menu = statusMenu
    }
    
    // MARK: - Utils
    
    private func updateSetupResetMenuItem() {
        if appModel.isActive {
            setupResetMenuItem.title = "Stop"
        } else {
            setupResetMenuItem.title = "Setup..."
        }
    }
    
    @objc private func toggle() {
        if appModel.isActive {
            appModel.stop()
            updateSetupResetMenuItem()
        } else {
            showSetupWindow()
        }
    }
    
    private func showSetupWindow() {
        if let existingWindow = setupWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let setupWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setupWindow.title = "Setup IKEADeskControl"
        setupWindow.isReleasedWhenClosed = false
        
        let setupViewModel = SetupViewModel { [weak self] in
            self?.start(with: $0)
        }
        
        setupWindow.contentView = NSHostingView(
            rootView: SetupView(viewModel: setupViewModel)
        )
        setupWindow.delegate = self
        setupWindow.setFrameAutosaveName("com.roebert.IKEADeskControl.config")
        
        setupWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.setupWindow = setupWindow
        self.setupViewModel = setupViewModel
    }
    
    private func start(with configuration: SetupViewModel.StartConfiguration) {
        setupWindow?.close()
        setupWindow = nil
        setupViewModel = nil
        
        appModel.start(
            mqttURL: configuration.mqttURL,
            mqttUsername: configuration.mqttUsername,
            mqttPassword: configuration.mqttPassword,
            mqttIdentifier: configuration.mqttIdentifier
        )
        updateSetupResetMenuItem()
    }
}
