//
//  InjectDylibView.swift
//  ThreeOneOSFive
//
//  Tab Inject dylib
//

import SwiftUI
import UniformTypeIdentifiers

struct InjectDylibView: View {
    @ObservedObject var appManager: AppManager
    @StateObject private var patcher = DyldPatcher()
    @State private var dylibName = "LocketGold.dylib"
    @State private var selectedDylibData: Data?
    @State private var selectedFileName = ""
    @State private var slots: [DyldSlot] = []
    @State private var selectedSlot: DyldSlot?
    @State private var status = "Ready"
    @State private var isProcessing = false
    @State private var showFilePicker = false
    @State private var useManualDyld4 = false
    @State private var manualDyld4Data: Data?
    @State private var showDyld4Picker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Target info
                targetInfoView
                
                Divider()
                
                // Dylib selection
                dylibSelectionView
                
                Divider()
                
                // Dyld4 selection
                dyld4SelectionView
                
                Divider()
                
                // Slot list
                slotListView
                
                Divider()
                
                // Actions
                actionButtonsView
                
                // Status
                statusView
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url) {
                    selectedDylibData = data
                    selectedFileName = url.lastPathComponent
                    dylibName = selectedFileName
                    status = "✅ Dylib loaded: \(selectedFileName)"
                }
            case .failure(let error):
                status = "❌ Error: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showDyld4Picker, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url) {
                    manualDyld4Data = data
                    useManualDyld4 = true
                    status = "✅ Manual dyld4 loaded"
                    scanSlots()
                }
            case .failure(let error):
                status = "❌ Error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Subviews
    
    private var targetInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🎯 Target App")
                .font(.headline)
            
            if let app = appManager.selectedApp {
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.name)
                            .font(.body)
                            .bold()
                        Text(app.bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("UUID: \(appManager.deviceUUID.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            } else {
                Text("Select an app in Apps tab first")
                    .foregroundColor(.orange)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
    }
    
    private var dylibSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("📁 Dylib File")
                .font(.headline)
            
            HStack {
                Text(selectedFileName.isEmpty ? "No file selected" : selectedFileName)
                    .font(.caption)
                    .foregroundColor(selectedFileName.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Browse") {
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appManager.selectedApp == nil)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            TextField("Dylib name on device", text: $dylibName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocapitalization(.none)
        }
    }
    
    private var dyld4SelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔧 Dyld4 Source")
                .font(.headline)
            
            HStack {
                Text(useManualDyld4 ? "Manual mode" : "Auto from container")
                    .font(.caption)
                    .foregroundColor(useManualDyld4 ? .blue : .secondary)
                
                Spacer()
                
                Toggle("Manual", isOn: $useManualDyld4)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
            
            if useManualDyld4 {
                HStack {
                    Text(manualDyld4Data == nil ? "No dyld4 selected" : "✅ dyld4 loaded")
                        .font(.caption)
                        .foregroundColor(manualDyld4Data == nil ? .secondary : .green)
                    
                    Spacer()
                    
                    Button("Pick dyld4") {
                        showDyld4Picker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
    }
    
    private var slotListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🎯 Slots")
                    .font(.headline)
                
                Spacer()
                
                Button("SMART SCAN") {
                    scanSlots()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isContainerReady)
            }
            
            if slots.isEmpty {
                Text(isContainerReady ? "No slots found. Tap SMART SCAN." : "Open container first")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(slots) { slot in
                            SlotCard(slot: slot, isSelected: selectedSlot?.id == slot.id) {
                                selectedSlot = slot
                                status = "✅ Selected slot at offset 0x\(String(format: "%08X", slot.offset))"
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button("🔄 Reset") {
                resetAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isProcessing)
            
            Button("🚀 INJECT & PATCH") {
                injectAndPatch()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isReadyToInject)
        }
    }
    
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundColor(status.contains("✅") ? .green : status.contains("❌") ? .red : .primary)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            
            if isProcessing {
                ProgressView()
                    .padding()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isContainerReady: Bool {
        return appManager.containerPath != nil
    }
    
    private var isReadyToInject: Bool {
        return selectedDylibData != nil &&
               selectedSlot != nil &&
               isContainerReady &&
               !isProcessing
    }
    
    // MARK: - Functions
    
    private func scanSlots() {
        guard let containerPath = appManager.containerPath else {
            status = "❌ No container opened"
            return
        }
        
        let dyldPath = "\(containerPath)/Library/Caches/com.apple.dyld"
        let fileManager = FileManager.default
        
        var dyld4Data: Data?
        
        if useManualDyld4 {
            dyld4Data = manualDyld4Data
        } else {
            guard let files = try? fileManager.contentsOfDirectory(atPath: dyldPath) else {
                status = "❌ No dyld4 found. Launch app once."
                return
            }
            
            if let dyld4File = files.first(where: { $0.hasSuffix(".dyld4") }) {
                let fullPath = "\(dyldPath)/\(dyld4File)"
                dyld4Data = try? Data(contentsOf: URL(fileURLWithPath: fullPath))
            }
        }
        
        guard let data = dyld4Data else {
            status = "❌ Cannot read dyld4"
            return
        }
        
        status = "⏳ Scanning slots..."
        DispatchQueue.global(qos: .userInitiated).async {
            let foundSlots = DyldPatcher().smartScanSlots(dyld4Data: data)
            DispatchQueue.main.async {
                self.slots = foundSlots
                if let best = foundSlots.first {
                    self.selectedSlot = best
                    status = "✅ Found \(foundSlots.count) slots. Best score: \(best.score)"
                } else {
                    status = "❌ No slots found"
                }
            }
        }
    }
    
    private func injectAndPatch() {
        guard let dylibData = selectedDylibData,
              let slot = selectedSlot,
              let containerPath = appManager.containerPath else {
            status = "❌ Missing required data"
            return
        }
        
        isProcessing = true
        status = "⏳ Injecting..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                let dyldPath = "\(containerPath)/Library/Caches/com.apple.dyld"
                try? fileManager.createDirectory(atPath: dyldPath, withIntermediateDirectories: true)
                
                // 1. Copy dylib
                let dylibDest = "\(dyldPath)/\(dylibName)"
                fileManager.createFile(atPath: dylibDest, contents: dylibData)
                
                // 2. Get dyld4
                var dyld4Data: Data?
                var dyld4Path: String?
                
                if useManualDyld4 {
                    dyld4Data = manualDyld4Data
                    if let data = dyld4Data {
                        let tempPath = "\(dyldPath)/manual.dyld4"
                        try data.write(to: URL(fileURLWithPath: tempPath))
                        dyld4Path = tempPath
                    }
                } else {
                    let files = try fileManager.contentsOfDirectory(atPath: dyldPath)
                    if let dyld4File = files.first(where: { $0.hasSuffix(".dyld4") }) {
                        dyld4Path = "\(dyldPath)/\(dyld4File)"
                        dyld4Data = try Data(contentsOf: URL(fileURLWithPath: dyld4Path!))
                    }
                }
                
                guard let data = dyld4Data, let path = dyld4Path else {
                    DispatchQueue.main.async {
                        status = "❌ Cannot find dyld4"
                        isProcessing = false
                    }
                    return
                }
                
                // 3. Patch
                let newPath = "\(dyldPath)/\(dylibName)"
                if let patchedData = DyldPatcher().patchDyld4(data: data, slotOffset: slot.offset, slotLength: slot.length, newPath: newPath) {
                    try patchedData.write(to: URL(fileURLWithPath: path))
                    
                    DispatchQueue.main.async {
                        status = "✅ Inject successful!\n📁 \(dylibName) copied to \(dyldPath)"
                        isProcessing = false
                    }
                } else {
                    DispatchQueue.main.async {
                        status = "❌ Patch failed"
                        isProcessing = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    status = "❌ Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
    
    private func resetAll() {
        slots = []
        selectedSlot = nil
        selectedDylibData = nil
        selectedFileName = ""
        status = "Ready"
    }
}

// MARK: - Slot Card
struct SlotCard: View {
    let slot: DyldSlot
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if slot.isBest {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    Text("0x\(String(format: "%08X", slot.offset))")
                        .font(.caption)
                        .bold()
                }
                Text(slot.path)
                    .font(.caption2)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Score: \(slot.score)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(width: 160, height: 70)
            .background(isSelected ? Color.blue.opacity(0.3) : Color(.secondarySystemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
