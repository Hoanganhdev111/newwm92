//
//  DyldPatcher.swift
//  ThreeOneOSFive
//
//  Patch dyld4 để inject dylib
//

import Foundation

class DyldPatcher {
    
    func smartScanSlots(dyld4Data: Data) -> [DyldSlot] {
        var slots: [DyldSlot] = []
        let data = dyld4Data as NSData
        var offset = 0
        
        while offset < data.length {
            var length = 0
            var isString = false
            var currentOffset = offset
            
            while currentOffset < data.length {
                var byte: UInt8 = 0
                data.getBytes(&byte, range: NSRange(location: currentOffset, length: 1))
                
                if byte >= 32 && byte <= 126 {
                    length += 1
                    isString = true
                    currentOffset += 1
                } else {
                    break
                }
            }
            
            if isString && length > 10 {
                let stringData = data.subdata(with: NSRange(location: offset, length: length))
                if let string = String(data: stringData, encoding: .utf8) {
                    var score = 0
                    if string.contains(".dylib") { score += 30 }
                    if string.contains(".framework") { score += 30 }
                    if string.contains("Frameworks/") { score += 20 }
                    if string.contains("/private/var/") { score += 20 }
                    
                    if score > 0 {
                        slots.append(DyldSlot(
                            offset: offset,
                            length: length + 1,
                            path: string,
                            score: score
                        ))
                    }
                }
            }
            
            offset += length + 1
        }
        
        slots.sort { $0.score > $1.score }
        return slots
    }
    
    func patchDyld4(data: Data, slotOffset: Int, slotLength: Int, newPath: String) -> Data? {
        var patched = Data(data)
        let newPathData = newPath.data(using: .utf8)!
        
        guard slotOffset + slotLength <= data.count else { return nil }
        guard newPathData.count < slotLength else { return nil }
        
        let zeroRange = slotOffset..<slotOffset + slotLength
        patched.replaceSubrange(zeroRange, with: [UInt8](repeating: 0, count: slotLength))
        
        let newRange = slotOffset..<slotOffset + newPathData.count
        patched.replaceSubrange(newRange, with: newPathData)
        
        return patched
    }
}

struct DyldSlot: Identifiable {
    let id = UUID()
    let offset: Int
    let length: Int
    let path: String
    let score: Int
    
    var isBest: Bool { score >= 100 }
}
