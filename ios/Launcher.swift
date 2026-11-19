// RHCM ONLINE - Launcher.swift (muguet fork)
// Customized for RHCM community - dark emerald theme

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Foundation

let configURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("config.json")

// MARK: - RHCM Theme

enum RHCM {
    static let bg        = Color(red: 0.020, green: 0.055, blue: 0.045)   // deep green-black
    static let panel     = Color(red: 0.045, green: 0.110, blue: 0.085)   // dark green panel
    static let panel2    = Color(red: 0.070, green: 0.160, blue: 0.115)   // lighter panel
    static let accent    = Color(red: 0.13,  green: 0.83,  blue: 0.50)    // emerald
    static let accentDim = Color(red: 0.08,  green: 0.55,  blue: 0.35)
    static let gold      = Color(red: 0.95,  green: 0.80,  blue: 0.30)
    static let text      = Color(red: 0.93,  green: 0.98,  blue: 0.95)
    static let sub       = Color(red: 0.55,  green: 0.75,  blue: 0.65)
    static let danger    = Color(red: 0.95,  green: 0.35,  blue: 0.30)
}

// MARK: - Settings (unchanged logic)

final class Settings: ObservableObject {
    @Published var mode = 2
    @Published var scale = 0.5
    @Published var fps = 60
    @Published var textures = 0
    @Published var touch = 1.0
    @Published var mute = false
    @Published var multiplayer = false
    @Published var host = false
    @Published var server = ""
    @Published var name = UIDevice.current.name
    var extra: [String: Any] = [:]

    init() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        extra = json
        if let v = json["start_mode"] as? Int, (1...2).contains(v) { mode = v }
        if let v = json["scale"] as? Double { scale = v }
        if let v = json["fps_limit"] as? Int { fps = v == 30 ? 30 : 60 }
        if let v = json["texture_quality"] as? Int, (0...2).contains(v) { textures = v }
        if let v = json["touch_sensitivity"] as? Double { touch = v }
        if let v = json["mute"] as? Bool { mute = v }
        if let v = json["multiplayer"] as? Bool { multiplayer = v }
        if let v = json["host"] as? Bool { host = v }
        if let v = json["server"] as? String { server = v }
        if let v = json["player_name"] as? String, !v.isEmpty { name = v }
    }

    func save() throws {
        var json = extra
        json["start_mode"] = mode
        json["scale"] = scale
        json["fps_limit"] = fps
        json["texture_quality"] = textures
        json["touch_sensitivity"] = (touch * 100).rounded() / 100
        json["mute"] = mute
        json["multiplayer"] = multiplayer
        json["host"] = host
        json["server"] = server.trimmingCharacters(in: .whitespaces)
        json["player_name"] = name.trimmingCharacters(in: .whitespaces)
        if json["extra_args"] == nil { json["extra_args"] = [String]() }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL)
    }
}

@_silgen_name("muguet_import")
func muguet_import(_ zip: UnsafePointer<CChar>, _ progress: @convention(c) (UInt64, UInt64) -> Void) -> Bool
@_silgen_name("muguet_import_error")
func muguet_import_error() -> UnsafePointer<CChar>?
@_silgen_name("muguet_game_ready")
func muguet_game_ready() -> Bool
@_silgen_name("muguet_has_game_code")
func muguet_has_game_code() -> Bool

final class Importer: ObservableObject {
    static let shared = Importer()
    @Published var ready = muguet_game_ready()
    @Published var progress: Double?
    @Published var error: String?
    @Published var local: [URL] = []

    func scan() {
        let docs = configURL.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        local = files.filter { $0.pathExtension.lowercased() == "zip" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func run(_ url: URL) {
        error = nil
        progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ok = url.path.withCString { muguet_import($0) { done, total in
                let p = total > 0 ? Double(done) / Double(total) : 0
                DispatchQueue.main.async { Importer.shared.progress = p }
            } }
            let message = ok ? nil : muguet_import_error().map { String(cString: $0) } ?? "unknown error"
            DispatchQueue.main.async {
                self.progress = nil
                self.ready = muguet_game_ready()
                if let message { self.error = "Import failed: \(message)" }
            }
        }
    }
}


// MARK: - RHCM Server List

struct ServerEntry: Identifiable, Decodable, Equatable {
    let name: String
    let address: String
    var players: Int? = nil
    var max: Int? = nil
    var id: String { address }
}

final class ServerList: ObservableObject {
    static let shared = ServerList()
    // URL of the community server list JSON (host this file on your website)
    static let listURL = URL(string: "https://rhcmonlinenew.wasmer.app/muguet-servers.json")!
    @Published var servers: [ServerEntry] = []
    @Published var loaded = false

    func refresh() {
        let url = ServerList.listURL
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let list = try? JSONDecoder().decode([ServerEntry].self, from: data) else {
                DispatchQueue.main.async { self.loaded = true }
                return
            }
            DispatchQueue.main.async {
                self.servers = list.filter { !$0.address.isEmpty }
                self.loaded = true
            }
        }.resume()
    }
}

// MARK: - RHCM UI Components

struct RHCMPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(RHCM.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(RHCM.accentDim.opacity(0.35), lineWidth: 1))
    }
}

struct RHCMSectionTitle: View {
    let text: String
    var icon: String = "hexagon.fill"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(RHCM.accent)
            Text(text).font(.headline.weight(.bold)).foregroundStyle(RHCM.text)
        }
    }
}

// MARK: - Launcher View (RHCM redesign)

struct LauncherView: View {
    @StateObject private var s = Settings()
    @ObservedObject private var importer = Importer.shared
    @StateObject private var serverList = ServerList.shared
    @State private var error: String?
    @State private var picking = false
    @State private var showAdvanced = false
    @Environment(\.scenePhase) private var phase
    let play: () -> Void

    var body: some View {
        ZStack {
            // background gradient
            LinearGradient(colors: [RHCM.bg, Color(red: 0.01, green: 0.03, blue: 0.025)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // LEFT: brand + play
                leftPanel
                    .frame(maxWidth: .infinity)

                Divider().overlay(RHCM.accentDim.opacity(0.3))

                // RIGHT: settings
                rightPanel
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { importer.run(url) }
        }
        .onAppear {
            importer.scan(); serverList.refresh()
            // RHCM: force multiplayer join through community server only
            s.multiplayer = true
            s.host = false
            if s.server.isEmpty, let first = ServerList.shared.servers.first {
                s.server = first.address
            }
        }
        .onChange(of: serverList.servers) { list in
            if s.server.isEmpty, let first = list.first { s.server = first.address }
        }
        .onChange(of: phase) { p in if p == .active { importer.scan() } }
    }

    // MARK: Left panel - brand + play

    @ViewBuilder var leftPanel: some View {
        VStack(spacing: 20) {
            Spacer()

            // logo block
            VStack(spacing: 6) {
                ZStack {
                    Hexagon().stroke(RHCM.accent.opacity(0.6), lineWidth: 2)
                        .frame(width: 110, height: 110)
                    Hexagon().fill(RHCM.accent.opacity(0.12))
                        .frame(width: 110, height: 110)
                    VStack(spacing: 0) {
                        Text("RHCM")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(RHCM.text)
                        Text("ONLINE")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(RHCM.gold)
                            
                    }
                }
                Text("GTA V PORT — COMMUNITY EDITION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RHCM.sub)
                    
            }

            Spacer()

            // status / play area
            if !muguet_has_game_code() {
                statusCard("Build นี้ไม่มี game code — ต้อง build พร้อม game.zip", icon: "exclamationmark.triangle.fill", color: RHCM.danger)
            } else if !importer.ready || importer.progress != nil {
                importView
            } else {
                if let error {
                    statusCard(error, icon: "xmark.octagon.fill", color: RHCM.danger)
                }
                playButton
                Button {
                    picking = true
                } label: {
                    Label("เปลี่ยน game data (.zip)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
            }

            Text("RHCM ONLINE Community")
                .font(.caption2)
                .foregroundStyle(RHCM.sub.opacity(0.7))
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }

    func statusCard(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout).foregroundStyle(RHCM.text)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: Right panel - settings

    @ViewBuilder var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RHCMSectionTitle(text: "การตั้งค่า", icon: "slider.horizontal.3")

                RHCMPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("โหมดเกม", selection: $s.mode) {
                            Text("Story Mode").tag(1)
                            Text("Sandbox").tag(2)
                        }
                        .pickerStyle(.segmented)

                        Picker("ความละเอียด", selection: $s.scale) {
                            Text("35% (เร็วสุด)").tag(0.35)
                            Text("50%").tag(0.5)
                            Text("75%").tag(0.75)
                            Text("100% (คมสุด)").tag(1.0)
                        }

                        Picker("Texture", selection: $s.textures) {
                            Text("Normal").tag(0)
                            Text("High").tag(1)
                            Text("Very High").tag(2)
                        }

                        Picker("Frame limit", selection: $s.fps) {
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                    }
                }

                RHCMPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        RHCMSectionTitle(text: "Online", icon: "person.2.fill")
                        Text("ต้องเล่นผ่านเซิร์ฟเวอร์ RHCM เท่านั้น")
                            .font(.caption).foregroundStyle(RHCM.gold)
                        TextField("ชื่อของคุณ", text: $s.name)
                            .textFieldStyle(.roundedBorder)

                        // community server list - required
                        if serverList.servers.isEmpty {
                            if serverList.loaded {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(RHCM.danger)
                                    Text("เซิร์ฟเวอร์ RHCM ปิดอยู่ — ลองใหม่ภายหลัง")
                                        .font(.callout).foregroundStyle(RHCM.danger)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RHCM.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(RHCM.accent)
                                    Text("กำลังเชื่อมต่อเซิร์ฟเวอร์ RHCM…").font(.callout).foregroundStyle(RHCM.sub)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(serverList.servers) { srv in
                                    let selected = s.server == srv.address
                                    Button {
                                        s.server = srv.address
                                        s.multiplayer = true
                                        s.host = false
                                    } label: {
                                        HStack {
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected ? RHCM.accent : RHCM.sub)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(srv.name).font(.callout.weight(.semibold))
                                                    .foregroundStyle(selected ? RHCM.text : RHCM.sub)
                                                Text(srv.address).font(.caption2.monospaced())
                                                    .foregroundStyle(RHCM.sub.opacity(0.7))
                                            }
                                            Spacer()
                                            if let p = srv.players, let m = srv.max {
                                                Text("\(p)/\(m)").font(.caption2.monospacedDigit())
                                                    .foregroundStyle(RHCM.accent)
                                            }
                                            if selected {
                                                Text("กำลังเล่น").font(.caption2.weight(.bold))
                                                    .foregroundStyle(RHCM.accent)
                                            }
                                        }
                                        .padding(12)
                                        .background(selected ? RHCM.accent.opacity(0.15) : RHCM.panel2,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .stroke(selected ? RHCM.accent : RHCM.accentDim.opacity(0.25),
                                                    lineWidth: selected ? 2 : 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // advanced collapsible
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text("ขั้นสูง").font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(RHCM.sub)
                }

                if showAdvanced {
                    RHCMPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Look sensitivity")
                                Slider(value: $s.touch, in: 0.25...3, step: 0.25)
                                Text(String(format: "%.2f×", s.touch)).monospacedDigit().frame(width: 52, alignment: .trailing)
                            }
                            Toggle("ปิดเสียง", isOn: $s.mute)
                                .tint(RHCM.accent)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Import view

    @ViewBuilder var importView: some View {
        RHCMPanel {
            VStack(spacing: 12) {
                if let p = importer.progress {
                    ProgressView(value: p)
                        .tint(RHCM.accent)
                    Text("กำลัง import… \(Int(p * 100)) %")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(RHCM.text)
                } else {
                    Button {
                        picking = true
                    } label: {
                        Label("Import game data (.zip)", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RHCM.accent)
                    .controlSize(.large)

                    ForEach(importer.local, id: \.self) { url in
                        Button(url.lastPathComponent) { importer.run(url) }
                            .font(.callout)
                            .foregroundStyle(RHCM.accent)
                    }

                    Text("ย้ายไฟล์ .zip ไปที่ Files → On My iPhone → RHCM แล้วจะขึ้นที่นี่")
                        .font(.caption)
                        .foregroundStyle(RHCM.sub)
                        .multilineTextAlignment(.center)
                }
                if let e = importer.error {
                    Text(e).font(.callout).foregroundStyle(RHCM.danger)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 420)
    }

    // MARK: Play button

    @ViewBuilder var playButton: some View {
        Button(action: start) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                Text("PLAY").font(.title2.weight(.black))
            }
            .foregroundStyle(.white)
            .frame(width: 300, height: 64)
            .background(
                LinearGradient(colors: [RHCM.accent, RHCM.accentDim],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: RHCM.accent.opacity(0.45), radius: 16, y: 4)
        }
        .buttonStyle(.plain)
    }

    func start() {
        // RHCM: must play through community server only
        s.multiplayer = true
        s.host = false
        if s.server.trimmingCharacters(in: .whitespaces).isEmpty || serverList.servers.isEmpty {
            error = "เซิร์ฟเวอร์ RHCM ยังไม่พร้อม — กรุณาลองใหม่ภายหลัง"
            return
        }
        do { try s.save() } catch { self.error = "บันทึกการตั้งค่าไม่ได้: \(error.localizedDescription)"; return }
        play()
    }
}

// hexagon shape for logo
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

func localIPs() -> [String] {
    var out: [String] = []
    var ifs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifs) == 0, let first = ifs else { return ["?"] }
    defer { freeifaddrs(ifs) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") && !out.contains(ip) { out.append(ip) }
        }
    }
    return out.isEmpty ? ["?"] : out
}
