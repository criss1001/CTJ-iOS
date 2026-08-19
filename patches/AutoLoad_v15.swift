import Foundation
import UIKit

extension CTJModel {
    @MainActor
    func autoLoadGameAssets() {
        guard let reader = LargeDiscStore.reader else { return }
        let regular = reader.files.filter { !$0.isDirectory }

        // CAPTIN.EXE for shots/editor.
        if let captin = regular.first(where: { $0.name.uppercased() == "CAPTIN.EXE" }) {
            if let bytes = try? reader.readFile(captin, maxSize: 32 * 1024 * 1024) {
                captinData = bytes
                captinName = captin.path
                loadShotCSV()
            }
        }

        // Player stats: prefer TEAMDAT0, then any TEAMDAT* file.
        let teamCandidates = regular.filter { f in
            let n = f.name.uppercased()
            return n.hasPrefix("TEAMDAT")
        }.sorted { a, b in
            func rank(_ n: String) -> Int {
                let u = n.uppercased()
                if u == "TEAMDAT0" || u == "TEAMDAT0.BIN" { return 0 }
                if u == "TEAMDAT" || u == "TEAMDAT.BIN" { return 1 }
                if u == "TEAMDAT1" || u == "TEAMDAT1.BIN" { return 2 }
                if u == "TEAMDAT2" || u == "TEAMDAT2.BIN" { return 3 }
                return 10
            }
            return rank(a.name) < rank(b.name)
        }
        if let stats = teamCandidates.first,
           let bytes = try? reader.readFile(stats, maxSize: 32 * 1024 * 1024) {
            teamData = bytes
            teamDataName = stats.path
            selectedPlayer = 0
        }

        // Select first useful file for the disc browser.
        selectedDiscPath = captinName.isEmpty ? (teamDataName.isEmpty ? (regular.first?.path ?? "") : teamDataName) : captinName

        let loaded = [captinData.isEmpty ? nil : "CAPTIN", teamData.isEmpty ? nil : "TEAMDAT"].compactMap { $0 }.joined(separator: " + ")
        if loaded.isEmpty {
            status = "✅ تم فتح \(discName) — \(discFileCount) ملف، لكن لم أجد CAPTIN/TEAMDAT تلقائيًا"
        } else {
            status = "✅ تم فتح \(discName) — تحميل تلقائي: \(loaded)"
        }
    }

    func playerPortraitAuto(team: Int, player: Int) -> UIImage? {
        guard let reader = LargeDiscStore.reader else { return nil }
        let hex = String(format: "%02X", team)
        let regular = reader.files.filter { !$0.isDirectory }

        let candidates = regular.filter { f in
            let name = f.name.uppercased()
            let path = f.path.uppercased()
            if name == "TEAM\(hex).BIN" { return true }
            if name == "\(hex).BIN" && path.contains("TEAM") { return true }
            if name == "TEAM\(hex)" { return true }
            return false
        }

        for file in candidates {
            guard let data = try? reader.readFile(file, maxSize: 32 * 1024 * 1024) else { continue }
            let teamBytes = [UInt8](data)
            guard let top = CTJPortraitDecoder.offsetTable(teamBytes), !top.isEmpty,
                  let players = CTJPortraitDecoder.offsetTable(top[0]), player >= 0, player < players.count,
                  let expressions = CTJPortraitDecoder.offsetTable(players[player]), let first = expressions.first,
                  let raw = try? CTJPortraitDecoder.decompress(first), raw.count == 832 else { continue }
            if let image = CTJPortraitDecoder.image(raw) { return image }
        }
        return nil
    }
}
