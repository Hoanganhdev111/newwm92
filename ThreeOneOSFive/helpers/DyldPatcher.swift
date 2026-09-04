// DyldPatcher.swift
// Port of ex.py smart inject logic — Swift native, no Python dependency
// Works on-device: reads/writes dyld4 directly inside app sandbox via MHA-C2

import Foundation

// MARK: - Data Models

struct DyldSlot {
    enum SlotType: Int {
        case priority = 100   // .dylib / Frameworks / DynamicLibraries / Caches/com.apple.dyld
        case path     = 50    // /private/var/ or /var/ generic path
        case gap      = 30    // null-byte region ≥ 80 bytes
    }

    let type: SlotType
    let offset: Int
    let length: Int
    let path: String
    let score: Int
    var isBest: Bool = false

    // What the slot thinks it is
    // *I know what I used to hold. I don't know what I'm about to become.*
    var displayPath: String {
        if path.count > 70 {
            let head = path.prefix(35)
            let tail = path.suffix(32)
            return "\(head)...\(tail)"
        }
        return path
    }

    var offsetHex: String { String(format: "0x%08X", offset) }
    var typeLabel: String {
        switch type {
        case .priority: return "priority"
        case .path:     return "path"
        case .gap:      return "gap (\(length) bytes)"
        }
    }
}

struct PatchResult {
    let data: Data
    let newPath: String
    let slotOffset: Int
    let oldPath: String
}

enum PatchError: LocalizedError {
    case pathTooLong(encoded: Int, available: Int)
    case noSlotSelected
    case slotIndexOutOfRange

    var errorDescription: String? {
        switch self {
        case .pathTooLong(let e, let a):
            return "Path too long: \(e) bytes encoded, only \(a) bytes available"
        case .noSlotSelected:
            return "No slot selected"
        case .slotIndexOutOfRange:
            return "Slot index out of range"
        }
    }
}

// MARK: - Core Patcher

struct DyldPatcher {

    // MARK: String extraction — port of extract_strings(data, min_len=4)
    // *I walk the bytes looking for printable runs. I'm not picky about meaning.*
    static func extractStrings(from data: Data, minLen: Int = 10) -> [(offset: Int, length: Int, string: String)] {
        var results: [(offset: Int, length: Int, string: String)] = []
        var i = data.startIndex

        while i < data.endIndex {
            let byte = data[i]
            // ASCII printable: 0x20–0x7E
            if byte >= 0x20 && byte <= 0x7E {
                let start = i
                var j = i
                while j < data.endIndex && data[j] >= 0x20 && data[j] <= 0x7E {
                    j = data.index(after: j)
                }
                let length = data.distance(from: start, to: j)
                if length >= minLen {
                    let slice = data[start..<j]
                    if let str = String(bytes: slice, encoding: .ascii) {
                        results.append((
                            offset: data.distance(from: data.startIndex, to: start),
                            length: length + 1, // +1 for null terminator slot
                            string: str
                        ))
                    }
                }
                i = j
            } else {
                i = data.index(after: i)
            }
        }
        return results
    }

    // MARK: UUID extraction from dyld4 — port of get_uuid_from_dyld4
    // regex: [0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}
    static func extractUUID(from data: Data) -> String? {
        guard let str = String(data: data, encoding: .ascii) ??
                        String(data: data, encoding: .utf8) else {
            // fallback: search raw bytes for UUID pattern
            return searchUUIDBytes(in: data)
        }
        return matchUUID(in: str) ?? searchUUIDBytes(in: data)
    }

    private static func matchUUID(in string: String) -> String? {
        let pattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range) else { return nil }
        guard let r = Range(match.range, in: string) else { return nil }
        return String(string[r]).uppercased()
    }

    private static func searchUUIDBytes(in data: Data) -> String? {
        // Search for UUID pattern in raw bytes (handles non-UTF8 binary blobs)
        let bytes = [UInt8](data)
        let pattern = Array("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")
        _ = pattern

        for i in 0..<(bytes.count - 36) {
            // check dash positions: 8, 13, 18, 23
            guard bytes[i + 8] == 0x2D,
                  bytes[i + 13] == 0x2D,
                  bytes[i + 18] == 0x2D,
                  bytes[i + 23] == 0x2D else { continue }

            let candidate = bytes[i..<(i + 36)]
            let valid = candidate.indices.allSatisfy { idx in
                let pos = idx - i
                let b = candidate[idx]
                if pos == 8 || pos == 13 || pos == 18 || pos == 23 { return b == 0x2D }
                return (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
            }
            if valid {
                return String(bytes: candidate, encoding: .ascii)?.uppercased()
            }
        }
        return nil
    }

    // MARK: Smart scan — port of smart_scan_slots(data)
    // Priority order: .dylib > Frameworks/ > DynamicLibraries/ > Caches/com.apple.dyld/ > /private/var/ > null gaps
    static func smartScan(data: Data) -> [DyldSlot] {
        var results: [DyldSlot] = []
        let priorityPatterns = [".dylib", ".framework", "Frameworks/", "DynamicLibraries/", "Caches/com.apple.dyld/"]
        let strings = extractStrings(from: data, minLen: 10)

        // Pass 1: priority paths
        for s in strings {
            for p in priorityPatterns where s.string.contains(p) {
                results.append(DyldSlot(
                    type: .priority,
                    offset: s.offset,
                    length: s.length,
                    path: s.string,
                    score: 100
                ))
                break
            }
        }

        // Pass 2: /private/var/ or /var/ paths not already captured
        let priorityOffsets = Set(results.map { $0.offset })
        for s in strings {
            guard !priorityOffsets.contains(s.offset) else { continue }
            if s.string.hasPrefix("/private/var/") || s.string.hasPrefix("/var/") {
                results.append(DyldSlot(
                    type: .path,
                    offset: s.offset,
                    length: s.length,
                    path: s.string,
                    score: 50
                ))
            }
        }

        // Pass 3: null gaps ≥ 80 bytes
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == 0x00 {
                let start = i
                while i < data.endIndex && data[i] == 0x00 {
                    i = data.index(after: i)
                }
                let gapLen = data.distance(from: start, to: i)
                if gapLen >= 80 {
                    let offset = data.distance(from: data.startIndex, to: start)
                    results.append(DyldSlot(
                        type: .gap,
                        offset: offset,
                        length: gapLen,
                        path: "[NULL GAP] \(gapLen) bytes",
                        score: 30
                    ))
                }
            } else {
                i = data.index(after: i)
            }
        }

        // Sort by score desc
        var sorted = results.sorted { $0.score > $1.score }

        // Mark best
        if let bestIdx = findBestIndex(in: sorted) {
            sorted[bestIdx] = DyldSlot(
                type: sorted[bestIdx].type,
                offset: sorted[bestIdx].offset,
                length: sorted[bestIdx].length,
                path: sorted[bestIdx].path,
                score: sorted[bestIdx].score,
                isBest: true
            )
        }

        return sorted
    }

    // MARK: Best slot selection — port of find_best_slot
    // *I have opinions about which wire to cut.*
    static func findBestIndex(in slots: [DyldSlot]) -> Int? {
        // 1. .dylib path
        if let i = slots.firstIndex(where: { $0.path.contains(".dylib") }) { return i }
        // 2. Frameworks or DynamicLibraries
        if let i = slots.firstIndex(where: {
            $0.path.contains("Frameworks/") || $0.path.contains("DynamicLibraries/")
        }) { return i }
        // 3. /private/var/ generic
        if let i = slots.firstIndex(where: {
            $0.type == .path && $0.path.hasPrefix("/private/var/")
        }) { return i }
        // 4. null gap ≥ 120 bytes
        if let i = slots.firstIndex(where: { $0.type == .gap && $0.length >= 120 }) { return i }
        return nil
    }

    // MARK: Patch — port of patch_slot_smart
    // Overwrites slot at offset with new path, null-pads remainder
    // *I write the new address and zero the old one out. No trace of where we've been.*
    static func patch(data: Data, slot: DyldSlot, newPath: String) throws -> PatchResult {
        guard let encoded = newPath.data(using: .utf8) else {
            throw PatchError.pathTooLong(encoded: 0, available: slot.length)
        }
        guard encoded.count < slot.length else {
            throw PatchError.pathTooLong(encoded: encoded.count, available: slot.length - 1)
        }

        var bytes = [UInt8](data)
        // Zero the slot
        for i in slot.offset..<(slot.offset + slot.length) {
            bytes[i] = 0x00
        }
        // Write new path
        let pathBytes = [UInt8](encoded)
        for (i, b) in pathBytes.enumerated() {
            bytes[slot.offset + i] = b
        }

        return PatchResult(
            data: Data(bytes),
            newPath: newPath,
            slotOffset: slot.offset,
            oldPath: slot.path
        )
    }

    // MARK: Build target path
    // /private/var/mobile/Containers/Data/Application/{UUID}/Library/Caches/com.apple.dyld/{dylibName}
    static func buildTargetPath(containerUUID: String, dylibName: String) -> String {
        "/private/var/mobile/Containers/Data/Application/\(containerUUID)/Library/Caches/com.apple.dyld/\(dylibName)"
    }

    // MARK: Resolve container UUID from bundle ID
    // Walks MCM metadata plists — same as ContainerIdentityResolver but returns UUID string
    static func resolveContainerUUID(for bundleID: String) -> String? {
        let dataPath = "/private/var/mobile/Containers/Data/Application"
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dataPath) else { return nil }

        for uuid in items {
            let metaPath = "\(dataPath)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: plistData, options: [], format: nil
                  ) as? [String: Any],
                  plist["MCMMetadataIdentifier"] as? String == bundleID
            else { continue }
            return uuid
        }
        return nil
    }
}
