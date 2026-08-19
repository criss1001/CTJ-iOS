import Foundation

@MainActor
enum LargeDiscStore {
    static var reader: FileBackedPSXDisc?
}

final class FileBackedPSXDisc {
    struct Layout {
        let sectorSize: Int
        let fixedUserOffset: Int?
        let logicalSectorBias: Int
        let rawHeader: Bool
    }

    let url: URL
    let fileSize: UInt64
    let layout: Layout
    private var handle: FileHandle
    private(set) var files: [PSXDiscFile] = []

    init(url: URL) throws {
        self.url = url
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize >= 64 * 1024 else { throw PSXDiscError.unsupportedImage }
        self.handle = try FileHandle(forUpdating: url)
        guard let detected = try Self.detectLayout(handle: handle, fileSize: fileSize) else {
            try? handle.close()
            throw PSXDiscError.unsupportedImage
        }
        self.layout = detected
        try scan()
    }

    deinit { try? handle.close() }

    private static func read(_ handle: FileHandle, offset: UInt64, count: Int, fileSize: UInt64) throws -> Data {
        guard count >= 0, offset <= fileSize, UInt64(count) <= fileSize - offset else { throw PSXDiscError.invalidISO9660 }
        try handle.seek(toOffset: offset)
        guard let d = try handle.read(upToCount: count), d.count == count else { throw PSXDiscError.invalidISO9660 }
        return d
    }

    private static func detectLayout(handle: FileHandle, fileSize: UInt64) throws -> Layout? {
        let candidates: [(Int,[Int],Bool)] = [
            (2048,[0],false), (2336,[8],false), (2352,[24,16],true), (2448,[24,16],true)
        ]
        for (stride, offsets, raw) in candidates {
            let total = Int(min(fileSize / UInt64(stride), 450))
            guard total > 16 else { continue }
            for physical in 0..<total {
                for off in offsets {
                    let pos = UInt64(physical * stride + off)
                    if pos + 7 > fileSize { continue }
                    let d = try read(handle, offset: pos, count: 7, fileSize: fileSize)
                    if d[0] == 1, String(data: d[1..<6], encoding: .ascii) == "CD001" {
                        let bias = physical - 16
                        if bias >= 0 { return Layout(sectorSize: stride, fixedUserOffset: raw ? nil : off, logicalSectorBias: bias, rawHeader: raw) }
                    }
                }
            }
        }
        return nil
    }

    private func physicalSector(_ lba: Int) -> Int { lba + layout.logicalSectorBias }

    private func userOffset(lba: Int) throws -> Int {
        if let fixed = layout.fixedUserOffset { return fixed }
        let physical = physicalSector(lba)
        guard physical >= 0 else { throw PSXDiscError.unsupportedSector(lba) }
        let base = UInt64(physical * layout.sectorSize)
        let h = try Self.read(handle, offset: base, count: min(layout.sectorSize, 24), fileSize: fileSize)
        guard h.count >= 16 else { throw PSXDiscError.unsupportedSector(lba) }
        switch h[15] { case 1: return 16; case 2: return 24; default: throw PSXDiscError.unsupportedSector(lba) }
    }

    func payload(lba: Int) throws -> Data {
        let physical = physicalSector(lba)
        guard physical >= 0 else { throw PSXDiscError.unsupportedSector(lba) }
        let off = try userOffset(lba: lba)
        let byteOffset = UInt64(physical * layout.sectorSize + off)
        return try Self.read(handle, offset: byteOffset, count: 2048, fileSize: fileSize)
    }

    private func scan() throws {
        let pvd = try payload(lba: 16)
        guard pvd.count == 2048, pvd[0] == 1, String(data: pvd[1..<6], encoding: .ascii) == "CD001" else { throw PSXDiscError.invalidISO9660 }
        let root = try Self.parseDirectoryRecord(pvd, at: 156, parent: "")
        guard root.isDirectory, root.lba >= 0, root.size > 0, root.size <= 16 * 1024 * 1024 else { throw PSXDiscError.invalidISO9660 }
        var out:[PSXDiscFile] = []
        var visited = Set<Int>()
        try walkDirectory(lba: root.lba, size: root.size, path: "", depth: 0, visited: &visited, output: &out)
        files = out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func walkDirectory(lba: Int, size: Int, path: String, depth: Int, visited: inout Set<Int>, output: inout [PSXDiscFile]) throws {
        guard depth <= 24, output.count < 20000 else { throw PSXDiscError.invalidISO9660 }
        guard size > 0, size <= 16 * 1024 * 1024, visited.insert(lba).inserted else { return }
        let dirData = try readExtent(lba: lba, size: size, maxSize: 16 * 1024 * 1024)
        var pos = 0
        var records = 0
        while pos < dirData.count, records < 10000, output.count < 20000 {
            let len = Int(dirData[pos])
            if len == 0 { pos = ((pos / 2048) + 1) * 2048; continue }
            guard len >= 34, pos + len <= dirData.count else { throw PSXDiscError.invalidISO9660 }
            let nameLen = Int(dirData[pos + 32])
            guard nameLen >= 1, pos + 33 + nameLen <= pos + len else { throw PSXDiscError.invalidISO9660 }
            if nameLen == 1 {
                let marker = dirData[pos + 33]
                if marker == 0 || marker == 1 { pos += len; records += 1; continue }
            }
            let rec = try Self.parseDirectoryRecord(dirData, at: pos, parent: path)
            guard rec.lba >= 0, rec.size >= 0 else { throw PSXDiscError.invalidISO9660 }
            let sectors = (rec.size + 2047) / 2048
            let lastPhysical = physicalSector(rec.lba + max(0,sectors-1))
            guard lastPhysical >= 0, UInt64((lastPhysical + 1) * layout.sectorSize) <= fileSize + UInt64(layout.sectorSize) else { throw PSXDiscError.invalidISO9660 }
            output.append(rec)
            if rec.isDirectory, rec.size <= 16 * 1024 * 1024 {
                try walkDirectory(lba: rec.lba, size: rec.size, path: rec.path, depth: depth + 1, visited: &visited, output: &output)
            }
            pos += len; records += 1
        }
    }

    private static func parseDirectoryRecord(_ bytes: Data, at pos: Int, parent: String) throws -> PSXDiscFile {
        guard pos >= 0, pos + 34 <= bytes.count else { throw PSXDiscError.invalidISO9660 }
        let len = Int(bytes[pos]); guard len >= 34, pos + len <= bytes.count else { throw PSXDiscError.invalidISO9660 }
        let lba = Int(le32(bytes,pos+2)), size = Int(le32(bytes,pos+10)), flags = bytes[pos+25], nameLen = Int(bytes[pos+32])
        guard nameLen >= 1, nameLen <= 221, pos + 33 + nameLen <= pos + len else { throw PSXDiscError.invalidISO9660 }
        var name = String(data: bytes[(pos+33)..<(pos+33+nameLen)], encoding:.ascii) ?? "?"
        if let semi = name.firstIndex(of:";") { name = String(name[..<semi]) }
        let full = parent.isEmpty ? name : parent + "/" + name
        return PSXDiscFile(path: full, lba: lba, size: size, isDirectory: (flags & 0x02) != 0)
    }

    private static func le32(_ b:Data,_ p:Int)->UInt32 { UInt32(b[p]) | UInt32(b[p+1])<<8 | UInt32(b[p+2])<<16 | UInt32(b[p+3])<<24 }

    func readFile(_ file: PSXDiscFile, maxSize: Int = 64 * 1024 * 1024) throws -> Data {
        guard !file.isDirectory, file.size >= 0, file.size <= maxSize else { throw PSXDiscError.invalidISO9660 }
        return try readExtent(lba:file.lba,size:file.size,maxSize:maxSize)
    }

    private func readExtent(lba:Int,size:Int,maxSize:Int) throws -> Data {
        guard size >= 0, size <= maxSize else { throw PSXDiscError.invalidISO9660 }
        var out = Data(); out.reserveCapacity(min(size, 4 * 1024 * 1024))
        let sectors = (size + 2047) / 2048
        guard sectors <= (maxSize + 2047) / 2048 else { throw PSXDiscError.invalidISO9660 }
        for i in 0..<sectors { out.append(try payload(lba:lba+i)) }
        if out.count > size { out.removeSubrange(size..<out.count) }
        return out
    }

    func replaceFile(_ file: PSXDiscFile, with replacement: Data) throws {
        guard !file.isDirectory, replacement.count == file.size else { throw PSXDiscError.sizeChanged(expected:file.size, got:replacement.count) }
        var cursor = 0
        let sectors = (file.size + 2047) / 2048
        for i in 0..<sectors {
            let chunk = min(2048, file.size - cursor), lba = file.lba + i, physical = physicalSector(lba)
            guard physical >= 0 else { throw PSXDiscError.unsupportedSector(lba) }
            let off = try userOffset(lba:lba)
            let byteOffset = UInt64(physical * layout.sectorSize + off)
            guard byteOffset + UInt64(chunk) <= fileSize else { throw PSXDiscError.unsupportedSector(lba) }
            try handle.seek(toOffset: byteOffset)
            try handle.write(contentsOf: replacement[cursor..<(cursor+chunk)])
            if layout.sectorSize != 2048 { try repairRawSector(lba:lba) }
            cursor += chunk
        }
        try handle.synchronize()
    }

    private func repairRawSector(lba:Int) throws {
        let physical = physicalSector(lba), base = UInt64(physical * layout.sectorSize)
        if layout.sectorSize == 2336 {
            let raw2336 = try Self.read(handle,offset:base,count:2336,fileSize:fileSize)
            var full = [UInt8](repeating:0,count:2352); full.replaceSubrange(16..<2352,with:raw2336)
            if (full[18] & 0x20) != 0 { throw PSXDiscError.unsupportedSector(lba) }
            let edc=CDErrorCorrection.edc(Array(full[16..<2072])); CDErrorCorrection.putLE32(edc,into:&full,at:2072); CDErrorCorrection.ecc(&full,zeroAddressForMode2:true)
            try handle.seek(toOffset:base); try handle.write(contentsOf:Data(full[16..<2352])); return
        }
        guard layout.sectorSize == 2352 || layout.sectorSize == 2448 else { throw PSXDiscError.unsupportedSector(lba) }
        var sector=[UInt8](try Self.read(handle,offset:base,count:2352,fileSize:fileSize)); let mode=sector[15]
        if mode == 1 { let edc=CDErrorCorrection.edc(Array(sector[0..<2064])); CDErrorCorrection.putLE32(edc,into:&sector,at:2064); for i in 2068..<2076{sector[i]=0}; CDErrorCorrection.ecc(&sector,zeroAddressForMode2:false) }
        else if mode == 2 { if (sector[18]&0x20) != 0 { throw PSXDiscError.unsupportedSector(lba) }; let edc=CDErrorCorrection.edc(Array(sector[16..<2072])); CDErrorCorrection.putLE32(edc,into:&sector,at:2072); CDErrorCorrection.ecc(&sector,zeroAddressForMode2:true) }
        else { throw PSXDiscError.unsupportedSector(lba) }
        try handle.seek(toOffset:base); try handle.write(contentsOf:Data(sector))
    }
}

extension CTJModel {
    func importDiscFileBacked(url: URL) {
        status = "جارٍ تحليل ملف اللعبة…"
        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let reader = try FileBackedPSXDisc(url:url)
            LargeDiscStore.reader = reader
            discData = Data([1])
            discName = url.lastPathComponent
            discFiles = reader.files
            selectedDiscPath = reader.files.first(where:{ !$0.isDirectory && $0.name.uppercased()=="CAPTIN.EXE" })?.path ?? ""
            status = "✅ تم فتح \(discName) — \(discFileCount) ملف"
        } catch {
            LargeDiscStore.reader = nil; discData = Data(); discFiles = []
            status = "تعذر تحليل ملف اللعبة بدون كراش: \(error.localizedDescription)"
        }
    }
}

extension CTJModel {
    var discFileCount: Int { discFiles.filter { !$0.isDirectory }.count }

    func loadDiscFileIntoEditor(path: String) {
        do {
            guard let reader = LargeDiscStore.reader else { throw PSXDiscError.fileNotFound }
            guard let file = reader.files.first(where: { $0.path == path && !$0.isDirectory }) else { throw PSXDiscError.fileNotFound }
            let bytes = try reader.readFile(file)
            if file.name.uppercased() == "CAPTIN.EXE" {
                captinData = bytes; captinName = file.path; loadShotCSV(); status = "✅ تم تحميل CAPTIN.EXE من ملف اللعبة"
            } else {
                teamData = bytes; teamDataName = file.path; selectedPlayer = 0; status = "✅ تم تحميل \(file.name) إلى Player Editor"
            }
            selectedDiscPath = file.path
        } catch { status = "فشل قراءة الملف من اللعبة: \(error.localizedDescription)" }
    }

    func writeCurrentEditorFileBack(path: String) {
        do {
            guard let reader = LargeDiscStore.reader else { throw PSXDiscError.fileNotFound }
            guard let file = reader.files.first(where: { $0.path == path && !$0.isDirectory }) else { throw PSXDiscError.fileNotFound }
            let replacement = file.name.uppercased() == "CAPTIN.EXE" ? captinData : teamData
            try reader.replaceFile(file, with: replacement)
            status = "✅ تم حقن \(file.name) داخل ملف اللعبة وإصلاح EDC/ECC"
        } catch { status = "فشل الحقن داخل ملف اللعبة: \(error.localizedDescription)" }
    }
}
