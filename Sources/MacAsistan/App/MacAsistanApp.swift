import AppKit
import SwiftUI

@main
struct MacAsistanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
                .environmentObject(app)
        }
        .menuBarExtraStyle(.window)

        Window("Mac Asistan", id: "chat") {
            ChatView()
                .environmentObject(app)
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 820, height: 600)

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uygulama zaten çalışıyorsa (ör. hem DMG'den hem Uygulamalar'dan açıldıysa) o kopyayı öne getir ve bu kopyayı kapat.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate()
                NSApp.terminate(nil)
                return
            }
        }
        // Menü çubuğu simgesi başlatmayı tetiklemezse diye yedek.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { AppState.shared.start() }
        }
    }
}
