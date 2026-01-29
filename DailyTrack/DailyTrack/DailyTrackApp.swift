import SwiftUI

@main
struct DailyTrackApp: App {
    init() {
        // Seed initial tasks on first launch
        SeedData.seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            DailyView()
                .tabItem {
                    Label(String(localized: "Today"), systemImage: "checkmark.circle")
                }

            HistoryView()
                .tabItem {
                    Label(String(localized: "History"), systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
