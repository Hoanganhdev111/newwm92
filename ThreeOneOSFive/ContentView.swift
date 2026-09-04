//
//  ContentView.swift
//  ThreeOneOSFive
//
//  SỬA: Dùng AppSection từ AppTabNavigationState.swift
//

import SwiftUI

class AppManager: ObservableObject {
    @Published var selectedApp: AppInfo?
    @Published var containerPath: String?
    @Published var apps: [AppInfo] = []
    @Published var isLoading: Bool = false

    var deviceUUID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
}

struct ContentView: View {
    @StateObject private var appManager = AppManager()
    @State private var selectedSection: AppSection = .dashboard

    var body: some View {
        TabView(selection: $selectedSection) {

            // ─── Dashboard ────────────────────────────────────────────────
            NavigationView {
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
            .tabItem { Label("Apps", systemimage: "folder.fill") }
            .tag(AppSection.files)

            // ─── Patch ────────────────────────────────────────────────────
            NavigationView {
                PatchProjectsView()
                    .navigationTitle("Patch")
            }
            .tabItem { Label("Patch", systemimage: "wrench.and.screwdriver.fill") }
            .tag(AppSection.patch)

            // ─── Cleaner ──────────────────────────────────────────────────
            NavigationView {
                CleanerView()
                    .navigationTitle("Cleaner")
            }
            .tabItem { Label("Cleaner", systemimage: "trash.fill") }
            .tag(AppSection.cleaner)

            // ─── WallpaperLab ─────────────────────────────────────────────
            NavigationView {
                WallpaperLabView()
                    .navigationTitle("Wallpaper")
            }
            .tabItem { Label("Wallpaper", systemimage: "photo.fill") }
            .tag(AppSection.wallpaper)

            // ─── Inject (MỚI) ─────────────────────────────────────────────
            NavigationView {
                InjectDylibView(appManager: appManager)
                    .navigationTitle("Inject")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Inject", systemimage: "syringe.fill") }
            .tag(AppSection.inject)

            // ─── Settings ─────────────────────────────────────────────────
            NavigationView {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemimage: "gear") }
            .tag(AppSection.settings)
        }
        .accentColor(Color.blue)
    }
}
