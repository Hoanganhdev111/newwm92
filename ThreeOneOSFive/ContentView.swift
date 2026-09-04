// ContentView.swift
// ThreeOneOSFive
//
// SỬA: Gắn đúng view vào các tab

import SwiftUI

// MARK: - Tab identifiers
enum AppSection: Int, CaseIterable {
    case dashboard  = 0
    case files      = 1
    case patch      = 2
    case cleaner    = 3
    case wallpaper  = 4
    case inject     = 5
    case settings   = 6
}

struct ContentView: View {
    @StateObject private var appManager = AppManager()
    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        TabView(selection: $selectedSection) {

            // ─── Dashboard ────────────────────────────────────────────────
            NavigationView {
                // Thay bằng view thật của 3105
                Text("Dashboard")
                    .navigationTitle("3105")
            }
            .tabItem { Label("Dashboard", systemImage: "house.fill") }
            .tag(AppSection.dashboard)

            // ─── Files / App Data Browser ─────────────────────────────────
            NavigationView {
                AppDataBrowserView(appManager: appManager)
                    .navigationTitle("Apps")
            }
            .tabItem { Label("Apps", systemImage: "folder.fill") }
            .tag(AppSection.files)

            // ─── Patch ────────────────────────────────────────────────────
            NavigationView {
                PatchProjectsView()
                    .navigationTitle("Patch")
            }
            .tabItem { Label("Patch", systemImage: "wrench.and.screwdriver.fill") }
            .tag(AppSection.patch)

            // ─── Cleaner ──────────────────────────────────────────────────
            NavigationView {
                CleanerView()
                    .navigationTitle("Cleaner")
            }
            .tabItem { Label("Cleaner", systemImage: "trash.fill") }
            .tag(AppSection.cleaner)

            // ─── WallpaperLab ─────────────────────────────────────────────
            NavigationView {
                WallpaperLabView()
                    .navigationTitle("Wallpaper")
            }
            .tabItem { Label("Wallpaper", systemImage: "photo.fill") }
            .tag(AppSection.wallpaper)

            // ─── Inject (MỚI) ─────────────────────────────────────────────
            NavigationView {
                InjectDylibView(appManager: appManager)
                    .navigationTitle("Inject")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Inject", systemImage: "syringe.fill") }
            .tag(AppSection.inject)

            // ─── Settings ─────────────────────────────────────────────────
            NavigationView {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemimage: "gear") }
            .tag(AppSection.settings)
        }
        .accentColor(Color(hex: "#0a84ff"))
        .onAppear {
            // Tải danh sách app khi mở
            appManager.loadApps()
        }
    }
}

// MARK: - Color Extension (cho hex)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
