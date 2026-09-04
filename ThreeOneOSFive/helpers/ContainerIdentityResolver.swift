//
//  ContainerIdentityResolver.swift
//  ThreeOneOSFive
//
//  Lấy container path cho bất kỳ app nào
//

import Foundation
import UIKit

class ContainerIdentityResolver {
    private let fileManager = FileManager.default
    
    func getContainerPath(for bundleId: String) -> String? {
        let dataPath = "/private/var/mobile/Containers/Data/Application"
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: dataPath) else {
            return nil
        }
        
        for uuid in items {
            let metadataPath = "\(dataPath)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)) else { continue }
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else { continue }
            
            if plist["MCMMetadataIdentifier"] as? String == bundleId {
                return "\(dataPath)/\(uuid)"
            }
        }
        
        return nil
    }
    
    func getDeviceUUID() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
    }
}
