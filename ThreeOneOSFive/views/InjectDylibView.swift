// InjectDylibView.swift
// ThreeOneOSFive — Tab: Inject
//
// Full port of SMART INJECTOR v10.0 (ex.py) into SwiftUI.
// Runs on-device: no Python, no desktop required.
//
// Flow:
//   1. Select app → auto-resolve container UUID via MCM
//   2. Select .dylib file via document picker
//   3. Load .dyld4 from container (auto-discovered or manually picked)
//   4. SMART SCAN — find best slot (priority: .dylib path > /private/var/ > null gap)
//   5. INJECT — patch dyld4, copy dylib, write both back via MHA-C2 sandbox access

import SwiftUI
import UniformTypeIdentifiers

// MARK: - View Model

@MainActor
class InjectViewModel: ObservableObject {

    // Inputs
    @Published var selectedApp: AppInfo?          // set by AppManager / app picker
    @Published var dylibData: Data?
    @Published var dylibFileName: String = ""
    @Published var dylibName: String = "LocketGold.dylib"
    @Published var outputDyld4Name: String = "Locket.dyld4"

    // Resolved
    @Published var containerUUID: String = ""
    @Published var containerPath: String = ""
    @Published var dyld4Data: Data?
    @Published var dyld4FileName: String = ""
    @Published var dyld4Path: String = ""         // full on-device path

    // Scan results
    @Published var slots: [DyldSlot] = []
    @Published var selectedSlotIndex: Int = -1
    @Published var bestSlotIndex: Int = -1

    // State
    @Published var isScanning: Bool = false
    @Published var isInjecting: Bool = false
    @Published var showDylibPicker: Bool = false
    @Published var showDyld4Picker: Bool = false
    @Published var logLines: [String] = []
    @Published var statusMsg: String = "Ready"
    @Published var statusIsError: Bool = false
    @Published var statusIsSuccess: Bool = false

    private let resolver = ContainerIdentityResolver()

    // MARK: - Logging

    func log(_ msg: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(stamp)] \(msg)")
        if logLines.count > 200 { logLines.removeFirst(50) }
    }

    func setStatus(_ msg: String, error: Bool = false, success: Bool = false) {
        statusMsg = msg
        statusIsError = error
        statusIsSuccess = success
    }

    // MARK: - App selection handler

    func onAppSelected(_ app: AppInfo) {
        selectedApp = app
        containerUUID = ""
        containerPath = ""
        dyld4Data = nil
        dyld4FileName = ""
        dyld4Path = ""
        slots = []
        selectedSlotIndex = -1
        bestSlotIndex = -1
        logLines = []
        setStatus("App selected: \(app.name)")

        log("[*] Resolving container for \(app.bundleId)...")
        if let info = resolver.resolve(bundleID: app.bundleId) {
            containerUUID = info.containerUUID
            containerPath = info.containerPath
            log("[+] Container: \(info.containerPath)")
            log("[+] UUID: \(info.containerUUID)")
            setStatus("Container resolved")

            // Auto-discover dyld4 in container
            autoDiscoverDyld4(in: info.containerPath)
        } else {
            log("[!] Could not resolve container for \(app.bundleId)")
            setStatus("Container not found", error: true)
        }
    }

    // MARK: - Auto-discover dyld4

    func autoDiscoverDyld4(in containerPath: String) {
        let dyldCachePath = "\(containerPath)/Library/Caches/com.apple.dyld"
        log("[*] Scanning for .dyld4 in \(dyldCachePath)...")

        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dyldCachePath) else {
            log("[!] com.apple.dyld directory not found or empty")
            log("[*] You can select dyld4 manually or it will be auto-created on inject")
            return
        }

        let dyld4Files = items.filter { $0.hasSuffix(".dyld4") }
        if let first = dyld4Files.first {
            let fullPath = "\(dyldCachePath)/\(first)"
            log("[+] Found dyld4: \(first)")
            loadDyld4(from: fullPath, fileName: first)
        } else {
            log("[!] No .dyld4 file found in Caches/com.apple.dyld/")
            log("[*] Run the app once to generate it, or pick manually")
        }
    }

    // MARK: - Load dyld4

    func loadDyld4(from path: String, fileName: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            log("[!] Could not read dyld4 at: \(path)")
            setStatus("Failed to load dyld4", error: true)
            return
        }
        dyld4Data = data
        dyld4FileName = fileName
        dyld4Path = path
        log("[+] Loaded dyld4: \(fileName) (\(data.count) bytes)")

        // Auto-extract UUID if container UUID not already resolved
        if containerUUID.isEmpty {
            if let uuid = DyldPatcher.extractUUID(from: data) {
                containerUUID = uuid
                log("[+] UUID from dyld4: \(uuid)")
            } else {
                log("[!] Could not extract UUID from dyld4")
            }
        }

        setStatus("dyld4 loaded — run SMART SCAN")
    }

    // MARK: - Load dylib from document picker result

    func loadDylib(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            log("[!] Could not read dylib: \(url.lastPathComponent)")
            setStatus("Failed to load dylib", error: true)
            return
        }
        dylibData = data
        dylibFileName = url.lastPathComponent
        // Set name to filename by default, keep extension
        if dylibName.isEmpty || dylibName == "LocketGold.dylib" {
            dylibName = url.lastPathComponent
        }
        log("[+] Loaded dylib: \(url.lastPathComponent) (\(data.count) bytes)")
        setStatus("Dylib loaded: \(url.lastPathComponent)")
    }

    // MARK: - Load dyld4 from document picker result

    func loadDyld4FromPicker(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tmpPath = NSTemporaryDirectory() + url.lastPathComponent
        try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: tmpPath))
        loadDyld4(from: tmpPath, fileName: url.lastPathComponent)
    }

    // MARK: - SMART SCAN (port of smart_scan_slots + find_best_slot)

    func smartScan() {
        guard let data = dyld4Data else {
            setStatus("No dyld4 loaded", error: true)
            return
        }

        isScanning = true
        setStatus("Scanning...")
        log("[*] Starting SMART SCAN (\(data.count) bytes)...")

        Task.detached(priority: .userInitiated) {
            let scanned = DyldPatcher.smartScan(data: data)
            let bestIdx = scanned.firstIndex(where: { $0.isBest })

            await MainActor.run {
                self.slots = scanned
                self.bestSlotIndex = bestIdx ?? -1
                self.selectedSlotIndex = bestIdx ?? (scanned.isEmpty ? -1 : 0)
                self.isScanning = false

                self.log("[+] SMART SCAN complete: \(scanned.count) slots found")

                if let bi = bestIdx {
                    let best = scanned[bi]
                    self.log("[+] BEST slot: \(best.offsetHex) | \(best.displayPath)")
                    self.setStatus("Scan done — \(scanned.count) slots, best at \(best.offsetHex)")
                } else {
                    self.log("[!] No suitable slot found")
                    self.setStatus("Scan done — no good slot found", error: true)
                }
            }
        }
    }

    // MARK: - INJECT & PATCH (port of inject_patch)
    // *The slot holds the path. I'm about to change what it remembers.*

    func injectAndPatch() {
        guard let dylibData = dylibData else {
            setStatus("No dylib selected", error: true); return
        }
        guard let dyld4Data = dyld4Data else {
            setStatus("No dyld4 loaded", error: true); return
        }
        guard !containerUUID.isEmpty else {
            setStatus("No container UUID", error: true); return
        }
        guard selectedSlotIndex >= 0 && selectedSlotIndex < slots.count else {
            setStatus("No slot selected", error: true); return
        }

        let slot = slots[selectedSlotIndex]
        var dylib = dylibName.trimmingCharacters(in: .whitespaces)
        if !dylib.hasSuffix(".dylib") { dylib += ".dylib" }
        var dyld4Out = outputDyld4Name.trimmingCharacters(in: .whitespaces)
        if !dyld4Out.hasSuffix(".dyld4") { dyld4Out += ".dyld4" }

        let newPath = DyldPatcher.buildTargetPath(
            containerUUID: containerUUID,
            dylibName: dylib
        )

        isInjecting = true
        setStatus("Injecting...")
        log("=" + String(repeating: "=", count: 54))
        log("[*] Injecting...")
        log("[*] UUID: \(containerUUID)")
        log("[*] Slot: \(slot.offsetHex) | \(slot.displayPath)")
        log("[*] New path: \(newPath)")

        Task.detached(priority: .userInitiated) {
            do {
                // 1. Patch dyld4
                let result = try DyldPatcher.patch(data: dyld4Data, slot: slot, newPath: newPath)
                await self.log("[+] dyld4 patched at \(slot.offsetHex)")

                // 2. Create target dylib directory
                let dyldCacheDir: String
                if !self.containerPath.isEmpty {
                    dyldCacheDir = "\(self.containerPath)/Library/Caches/com.apple.dyld"
                } else {
                    // Fallback: reconstruct from UUID
                    dyldCacheDir = "/private/var/mobile/Containers/Data/Application/\(self.containerUUID)/Library/Caches/com.apple.dyld"
                }

                try FileManager.default.createDirectory(
                    atPath: dyldCacheDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // 3. Write dylib to container
                let dylibDest = "\(dyldCacheDir)/\(dylib)"
                try dylibData.write(to: URL(fileURLWithPath: dylibDest), options: .atomic)
                await self.log("[+] Dylib written: \(dylibDest)")

                // 4. Write patched dyld4 back
                let dyld4Dest = "\(dyldCacheDir)/\(dyld4Out)"
                try result.data.write(to: URL(fileURLWithPath: dyld4Dest), options: .atomic)
                await self.log("[+] Patched dyld4 written: \(dyld4Dest)")

                // 5. Write README
                let readme = self.buildReadme(
                    uuid: self.containerUUID,
                    slot: slot,
                    newPath: newPath,
                    dylibName: dylib,
                    dyld4Name: dyld4Out
                )
                let readmePath = "\(dyldCacheDir)/INJECT_README.txt"
                try readme.write(toFile: readmePath, atomically: true, encoding: .utf8)

                await MainActor.run {
                    self.isInjecting = false
                    self.log("[✅] INJECT SUCCESSFUL")
                    self.log("[+] Output dir: \(dyldCacheDir)")
                    self.setStatus("✅ Inject successful!", success: true)
                }

            } catch {
                await MainActor.run {
                    self.isInjecting = false
                    self.log("[!] Error: \(error.localizedDescription)")
                    self.setStatus("Inject failed: \(error.localizedDescription)", error: true)
                }
            }
        }
    }

    private func buildReadme(uuid: String, slot: DyldSlot, newPath: String,
                             dylibName: String, dyld4Name: String) -> String {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        return """
        ============================================================
          SMART INJECTOR — on-device patch
        ============================================================
        Time:        \(ts)
        UUID:        \(uuid)
        Slot offset: \(slot.offsetHex)
        Old path:    \(slot.path)
        New path:    \(newPath)
        ============================================================
        FILES:
          \(dylibName) — dylib (renamed)
          \(dyld4Name)  — patched dyld4
        ============================================================
        INSTALL:
          1. Kill the target app
          2. Both files are already in the correct directory
          3. Launch the target app — dylib will load via dyld4
        ============================================================
        """
    }

    // MARK: - Reset

    func reset() {
        dylibData = nil
        dylibFileName = ""
        dyld4Data = nil
        dyld4FileName = ""
        dyld4Path = ""
        slots = []
        selectedSlotIndex = -1
        bestSlotIndex = -1
        logLines = []
        setStatus("Reset")
        log("[*] Reset. Ready.")
    }
}

// MARK: - View

struct InjectDylibView: View {
    @ObservedObject var appManager: AppManager
    @StateObject private var vm = InjectViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                appSection
                Divider().background(Color(hex: "#252525"))
                dylibSection
                Divider().background(Color(hex: "#252525"))
                dyld4Section
                Divider().background(Color(hex: "#252525"))
                scanSection
                Divider().background(Color(hex: "#252525"))
                injectSection
                Divider().background(Color(hex: "#252525"))
                consoleSection
            }
        }
        .background(Color(hex: "#1a1a1a"))
        .onChange(of: appManager.selectedApp) { app in
            if let app = app { vm.onAppSelected(app) }
        }
        .onAppear {
            if let app = appManager.selectedApp { vm.onAppSelected(app) }
        }
        .fileImporter(
            isPresented: $vm.showDylibPicker,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.loadDylib(url: url)
            }
        }
        .fileImporter(
            isPresented: $vm.showDyld4Picker,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vm.loadDyld4FromPicker(url: url)
            }
        }
    }

    // MARK: - Sections

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Target App", systemImage: "square.stack.fill")
                .font(.headline).foregroundColor(.white)

            if let app = vm.selectedApp {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).foregroundColor(.green).bold()
                        Text(app.bundleId).font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(vm.containerUUID.isEmpty ? "UUID: —" : "UUID: \(vm.containerUUID.prefix(8))…")
                            .font(.caption2).foregroundColor(.blue)
                        if !vm.containerPath.isEmpty {
                            Text("Container: ✓").font(.caption2).foregroundColor(.green)
                        }
                    }
                }
                .padding(10).background(Color(hex: "#2a2a2a")).cornerRadius(8)
            } else {
                Text("Select an app in the Apps tab first")
                    .font(.caption).foregroundColor(.orange)
                    .padding(10).background(Color(hex: "#2a2a2a")).cornerRadius(8)
            }
        }
        .padding()
    }

    private var dylibSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dylib File", systemImage: "arrow.down.doc.fill")
                .font(.headline).foregroundColor(.white)

            HStack {
                Text(vm.dylibFileName.isEmpty ? "No file selected" : vm.dylibFileName)
                    .font(.caption).foregroundColor(vm.dylibFileName.isEmpty ? .gray : .green)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Browse") { vm.showDylibPicker = true }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
            }
            .padding(10).background(Color(hex: "#2a2a2a")).cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name on device").font(.caption).foregroundColor(.gray)
                TextField("e.g. LocketGold.dylib", text: $vm.dylibName)
                    .textFieldStyle(.plain)
                    .padding(8).background(Color(hex: "#222")).cornerRadius(6)
                    .foregroundColor(.white).autocapitalization(.none)
                    .font(.system(.caption, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Output dyld4 name").font(.caption).foregroundColor(.gray)
                TextField("e.g. Locket.dyld4", text: $vm.outputDyld4Name)
                    .textFieldStyle(.plain)
                    .padding(8).background(Color(hex: "#222")).cornerRadius(6)
                    .foregroundColor(.white).autocapitalization(.none)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
    }

    private var dyld4Section: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("dyld4 File", systemImage: "memorychip")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                Button("Pick manually") { vm.showDyld4Picker = true }
                    .font(.caption).foregroundColor(.blue)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.dyld4FileName.isEmpty ? "Not loaded (auto-discovery attempted)" : vm.dyld4FileName)
                        .font(.caption).foregroundColor(vm.dyld4FileName.isEmpty ? .gray : .green)
                    if !vm.dyld4Path.isEmpty {
                        Text(vm.dyld4Path).font(.caption2).foregroundColor(.gray)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                if vm.dyld4Data != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
            }
            .padding(10).background(Color(hex: "#2a2a2a")).cornerRadius(8)
        }
        .padding()
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Smart Scan", systemImage: "magnifyingglass")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                if !vm.slots.isEmpty {
                    Text("\(vm.slots.count) slots")
                        .font(.caption).foregroundColor(.gray)
                }
            }

            Button(action: { vm.smartScan() }) {
                HStack {
                    if vm.isScanning {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "waveform.and.magnifyingglass")
                    }
                    Text(vm.isScanning ? "Scanning…" : "SMART SCAN")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(10)
                .background(vm.dyld4Data == nil ? Color.gray : Color(hex: "#0a84ff"))
                .foregroundColor(.white).cornerRadius(8)
            }
            .disabled(vm.dyld4Data == nil || vm.isScanning)

            if !vm.slots.isEmpty {
                slotList
            }
        }
        .padding()
    }

    private var slotList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Select slot to patch:").font(.caption).foregroundColor(.gray)

            ForEach(Array(vm.slots.enumerated()), id: \.offset) { (i, slot) in
                Button(action: { vm.selectedSlotIndex = i }) {
                    HStack(spacing: 6) {
                        // Best star
                        if slot.isBest {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow).font(.caption2)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray).font(.caption2)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.offsetHex)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(vm.selectedSlotIndex == i ? .white : .blue)
                            Text(slot.displayPath)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(vm.selectedSlotIndex == i ? .white.opacity(0.85) : .gray)
                                .lineLimit(1).truncationMode(.middle)
                        }

                        Spacer()

                        Text(slot.typeLabel)
                            .font(.caption2)
                            .foregroundColor(slotTypeColor(slot.type))
                    }
                    .padding(8)
                    .background(
                        vm.selectedSlotIndex == i
                            ? Color(hex: "#0a84ff").opacity(0.3)
                            : Color(hex: "#222")
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                vm.selectedSlotIndex == i ? Color(hex: "#0a84ff") : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func slotTypeColor(_ type: DyldSlot.SlotType) -> Color {
        switch type {
        case .priority: return .green
        case .path:     return .yellow
        case .gap:      return .orange
        }
    }

    private var injectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Inject", systemImage: "syringe.fill")
                .font(.headline).foregroundColor(.white)

            // Status
            if !vm.statusMsg.isEmpty {
                HStack {
                    Circle()
                        .fill(vm.statusIsError ? Color.red : vm.statusIsSuccess ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(vm.statusMsg)
                        .font(.caption)
                        .foregroundColor(vm.statusIsError ? .red : vm.statusIsSuccess ? .green : .orange)
                }
                .padding(8).background(Color(hex: "#222")).cornerRadius(6)
            }

            HStack(spacing: 10) {
                // Inject button
                Button(action: { vm.injectAndPatch() }) {
                    HStack {
                        if vm.isInjecting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "syringe.fill")
                        }
                        Text(vm.isInjecting ? "Injecting…" : "INJECT & PATCH")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity).padding(12)
                    .background(injectDisabled ? Color.gray : Color(hex: "#30d158"))
                    .foregroundColor(.black).cornerRadius(8)
                }
                .disabled(injectDisabled)

                // Reset
                Button(action: { vm.reset() }) {
                    Text("Reset")
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(hex: "#2a2a2a")).foregroundColor(.white)
                        .cornerRadius(8)
                }
            }

            // Pre-flight checklist
            preFlightView
        }
        .padding()
    }

    private var injectDisabled: Bool {
        vm.dylibData == nil
        || vm.dyld4Data == nil
        || vm.containerUUID.isEmpty
        || vm.selectedSlotIndex < 0
        || vm.isInjecting
        || vm.isScanning
    }

    private var preFlightView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pre-flight").font(.caption2).foregroundColor(.gray)
            checkRow("App selected", ok: vm.selectedApp != nil)
            checkRow("Container UUID", ok: !vm.containerUUID.isEmpty)
            checkRow("Dylib loaded", ok: vm.dylibData != nil)
            checkRow("dyld4 loaded", ok: vm.dyld4Data != nil)
            checkRow("Slot selected", ok: vm.selectedSlotIndex >= 0)
        }
        .padding(8).background(Color(hex: "#1e1e1e")).cornerRadius(6)
    }

    private func checkRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundColor(ok ? .green : .gray).font(.caption2)
            Text(label).font(.caption2).foregroundColor(ok ? .white : .gray)
        }
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Console", systemImage: "terminal.fill")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                Button("Clear") { vm.logLines = [] }
                    .font(.caption).foregroundColor(.gray)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(vm.logLines.enumerated()), id: \.offset) { (i, line) in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(consoleColor(line))
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 180)
                .background(Color(hex: "#0d0d0d"))
                .cornerRadius(8)
                .onChange(of: vm.logLines.count) { _ in
                    if let last = vm.logLines.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .padding()
    }

    private func consoleColor(_ line: String) -> Color {
        if line.contains("[✅]") || line.contains("[+]") { return Color(hex: "#30d158") }
        if line.contains("[!]") { return Color(hex: "#ff453a") }
        if line.contains("[*]") { return Color(hex: "#ff9f0a") }
        return Color(hex: "#8e8e93")
    }
}

// MARK: - Color Hex extension (if not already in codebase)

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
