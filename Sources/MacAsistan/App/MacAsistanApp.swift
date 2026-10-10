import AppKit
import SwiftUI

@main
struct MacAsistanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("Mac Asistan", id: "chat") {
            ChatView()
                .environmentObject(app)
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 820, height: 600)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
                .environmentObject(app)
        }
        .menuBarExtraStyle(.window)

        Window("Mac Asistan – Ayarlar", id: "settings") {
            SettingsView()
                .environmentObject(app)
        }
        .windowResizability(.contentSize)
    }
}

/// Menü çubuğundaki simge. Uygulama açılır açılmaz çizildiği için başlangıç işlerini de burada tetikliyoruz.
struct MenuBarLabel: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .onAppear {
                app.openWindowAction = openWindow
                app.start()
            }
    }

    private var symbol: String {
        if app.speechOut.isSpeaking { return "speaker.wave.2.fill" }
        switch app.speechIn.mode {
        case .command: return "waveform.circle.fill"
        case .wake, .bargeIn: return "ear"
        case .off: return app.isSending ? "ellipsis.bubble" : "sparkles"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// İkinci kez açılan kopya, çalışan kopyaya "pencereni göster" der.
    static let showNotification = Notification.Name("com.keremtuna.macasistan.show")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dock simgesi: uygulamanın çalıştığı her zaman görünsün (menü çubuğu simgesi çentiğin arkasında kalabilir).
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Başka bir kopya (ör. eski sürüm) çalışıyorsa onu kapat: her zaman en son açılan kopya kazanır.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            for other in others {
                other.terminate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !other.isTerminated { other.forceTerminate() }
                }
            }
        }

        DistributedNotificationCenter.default().addObserver(forName: Self.showNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.showMainWindow() }
        }

        // Menü çubuğu simgesi başlatmayı tetiklemezse diye yedek.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { AppState.shared.start() }
        }
    }

    /// Dock simgesine tıklanınca veya uygulama Finder'dan yeniden açılınca.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated { AppState.shared.showMainWindow() }
        }
        return true
    }

    /// Pencere kapansa da uygulama menü çubuğunda çalışmaya devam etsin.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
