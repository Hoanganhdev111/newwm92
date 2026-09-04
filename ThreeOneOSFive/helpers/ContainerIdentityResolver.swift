// ContainerIdentityResolver.swift
// Resolve container path and UUID for any installed app via MCM metadata
// Used by both FileBrowserView and InjectDylibView

import Foundation

struct ContainerInfo {
    let bundleID: String
    let containerPath: String   // /private/var/mobile/Containers/Data/Application/{UUID}
    let containerUUID: String   // raw UUID string
}

class ContainerIdentityResolver {
    private let fm = FileManager.default
    private let dataRoot = "/private/var/mobile/Containers/Data/Application"

    // *I read everyone's metadata. I never announce it.*
    func resolve(bundleID: String) -> ContainerInfo? {
        guard let uuids = try? fm.contentsOfDirectory(atPath: dataRoot) else { return nil }

        for uuid in uuids {
            let metaPath = "\(dataRoot)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ) as? [String: Any],
                  plist["MCMMetadataIdentifier"] as? String == bundleID
            else { continue }

            return ContainerInfo(
                bundleID: bundleID,
                containerPath: "\(dataRoot)/\(uuid)",
                containerUUID: uuid
            )
        }
        return nil
    }

    // Convenience: just the path
    func getContainerPath(for bundleID: String) -> String? {
        resolve(bundleID: bundleID)?.containerPath
    }

    // Convenience: just the UUID string
    func getContainerUUID(for bundleID: String) -> String? {
        resolve(bundleID: bundleID)?.containerUUID
    }
}
