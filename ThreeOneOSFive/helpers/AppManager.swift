//
//  AppManager.swift
//  ThreeOneOSFive
//
//  Quản lý danh sách app và container
//

import Foundation
import UIKit

class AppManager: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedApp: AppInfo?
    @Published var containerPath: String?
    @Published var files: [FileItem] = []
    @Published var currentPath = ""
    @Published var pathHistory: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let fileManager = FileManager.default
    private let resolver = ContainerIdentityResolver()
    
    var deviceUUID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
    
    func loadApps() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let allApps = self.getAllApps()
            DispatchQueue.main.async {
                self.apps = allApps
                self.isLoading = false
            }
        }
    }
    
    private func getAllApps() -> [AppInfo] {
        var result: [AppInfo] = []
        let bundlePath = "/private/var/containers/Bundle/Application"
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: bundlePath) else {
            return result
        }
        
        for uuid in items {
            let appPath = "\(bundlePath)/\(uuid)"
            guard let appItems = try? fileManager.contentsOfDirectory(atPath: appPath) else { continue }
            
            for item in appItems where item.hasSuffix(".app") {
                let plistPath = "\(appPath)/\(item)/Info.plist"
                guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else { continue }
                guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else { continue }
                
                let bundleId = plist["CFBundleIdentifier"] as? String ?? "unknown"
                // KHÔNG LỌC HỆ THỐNG - HIỂN THỊ TẤT CẢ
                
                let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? item.replacingOccurrences(of: ".app", with: "")
                let version = plist["CFBundleShortVersionString"] as? String ?? "1.0"
                
                result.append(AppInfo(
                    bundleId: bundleId,
                    name: name,
                    version: version,
                    path: "\(appPath)/\(item)"
                ))
            }
        }
        
        result.sort { $0.name < $1.name }
        return result
    }
    
    func openContainer(for app: AppInfo) {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let path = self.resolver.getContainerPath(for: app.bundleId)
            DispatchQueue.main.async {
                self.containerPath = path
                self.selectedApp = app
                self.currentPath = ""
                self.pathHistory = []
                self.isLoading = false
                
                if let path = path {
                    self.loadDirectory(path: "")
                } else {
                    self.errorMessage = "Cannot open container for \(app.name)"
                }
            }
        }
    }
    
    func loadDirectory(path: String) {
        guard let containerPath = containerPath else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fullPath = path.isEmpty ? containerPath : "\(containerPath)/\(path)"
            let items = self.listDirectory(at: fullPath)
            
            DispatchQueue.main.async {
                self.files = items
                self.currentPath = path
            }
        }
    }
    
    private func listDirectory(at path: String) -> [FileItem] {
        var result: [FileItem] = []
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: path) else {
            return result
        }
        
        for item in items where !item.hasPrefix(".") {
            let fullPath = "\(path)/\(item)"
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
            
            let attributes = try? fileManager.attributesOfItem(atPath: fullPath)
            let size = attributes?[.size] as? Int64 ?? 0
            
            result.append(FileItem(
                name: item,
                path: fullPath,
                isDirectory: isDirectory.boolValue,
                size: size
            ))
        }
        
        result.sort { !$0.isDirectory && $1.isDirectory }
        return result
    }
    
    func navigate(to path: String) {
        pathHistory.append(currentPath)
        loadDirectory(path: path)
    }
    
    func goBack() {
        guard let previous = pathHistory.popLast() else { return }
        loadDirectory(path: previous)
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    
    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
