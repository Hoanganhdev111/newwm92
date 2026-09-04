// ContentView.swift
// ThreeOneOSFive
//
// MODIFIED: Added Inject tab (tab index 4, after existing tabs)
// Existing tabs unchanged — Dashboard, Files, Patch, Cleaner, WallpaperLab, Settings
// AppManager.selectedApp is the bridge between Apps tab and Inject tab

import SwiftUI

// AppInfo must match whatever model 3105 already defines.
// If it lives elsewhere, remove this stub.
struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    var bundleId: String
    var name: String
    var version: String
    var path: String
}

// AppManager stub — replace with actual class from 3105 codebase.
// Kept here so InjectDylibView compiles standalone.
class AppManager: ObservableObject {
    @Published var selectedApp: AppInfo?
    @Published var containerPath: String?
    @Published var apps: [AppInfo] = []
    @Published var isLoading: Bool = false

    var deviceUUID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
}

// MARK: - Tab identifiers
// Mirror whatever enum 3105 uses for AppSection.
// Add .inject to the existing set — do not renumber existing cases.
enum AppSection: Int, CaseIterable {
    case dashboard  = 0
    case files      = 1
    case patch      = 2
    case cleaner    = 3
    case wallpaper  = 4
    case inject     = 5   // NEW
    case settings   = 6
}

struct ContentView: View {
    @StateObject private var appManager = AppManager()
    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        TabView(selection: $selectedSection) {

            // ─── Dashboard ────────────────────────────────────────────────
            NavigationView {
                // Replace with real DashboardView from 3105
                Text("Dashboard")
                    .navigationTitle("3105")
            }
            .tabItem { Label("Dashboard", systemImage: "house.fill") }
            .tag(AppSection.dashboard)

            // ─── Files / App Data Browser ─────────────────────────────────
            NavigationView {
                // Replace with real AppDataBrowserView(appManager: appManager)
                Text("Files")
                    .navigationTitle("Files")
            }
            .tabItem { Label("Files", systemImage: "folder.fill") }
            .tag(AppSection.files)

            // ─── Patch ────────────────────────────────────────────────────
            NavigationView {
                // Replace with real PatchProjectsView()
                Text("Patch")
                    .navigationTitle("Patch")
            }
            .tabItem { Label("Patch", systemImage: "wrench.and.screwdriver.fill") }
            .tag(AppSection.patch)

            // ─── Cleaner ──────────────────────────────────────────────────
            NavigationView {
                // Replace with real CleanerView()
                Text("Cleaner")
                    .navigationTitle("Cleaner")
            }
            .tabItem { Label("Cleaner", systemImage: "trash.fill") }
            .tag(AppSection.cleaner)

            // ─── WallpaperLab ─────────────────────────────────────────────
            NavigationView {
                // Replace with real WallpaperLabView()
                Text("Wallpaper")
                    .navigationTitle("Wallpaper")
            }
            .tabItem { Label("Wallpaper", systemImage: "photo.fill") }
            .tag(AppSection.wallpaper)

            // ─── Inject (NEW) ─────────────────────────────────────────────
            NavigationView {
                InjectDylibView(appManager: appManager)
                    .navigationTitle("Inject")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Inject", systemImage: "syringe.fill") }
            .tag(AppSection.inject)

            // ─── Settings ─────────────────────────────────────────────────
            NavigationView {
                // Replace with real SettingsView()
                Text("Settings")
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(AppSection.settings)
        }
        .accentColor(Color(hex: "#0a84ff"))
    }
}
