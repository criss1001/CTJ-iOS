import Foundation

final class LargeDiscStore {
    static let shared = LargeDiscStore()
    private init() {}
    var data: Data?
    var sourceURL: URL?
}

extension CTJModel {
    @MainActor
    func importLargeDiscSafely(url: URL) {
        status = "جارٍ فتح ملف اللعبة…"
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0 else {
                status = "ملف اللعبة فارغ"
                return
            }

            // Map instead of copying the full BIN into RAM.
            let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard mapped.count > 32 * 1024 else {
                status = "ملف اللعبة صغير جدًا ليكون صورة قرص PS1"
                return
            }

            do {
                let image = try PSXDiscImage(data: mapped)

                // Keep the hundreds-of-megabytes image OUT of @Published discData.
                // Publishing such a large value can trigger extra copies / SwiftUI memory pressure.
                LargeDiscStore.shared.data = mapped
                LargeDiscStore.shared.sourceURL = url
                discData = Data([0x01])
                discName = url.lastPathComponent
                discFiles = image.files
                status = "تم فتح \(url.lastPathComponent) — \(fileSize / 1_048_576) MB — \(image.files.count) ملف"
            } catch {
                LargeDiscStore.shared.data = nil
                LargeDiscStore.shared.sourceURL = nil
                discData = Data()
                discFiles = []
                status = "تعذر تحليل صورة القرص: \(error.localizedDescription) — الحجم \(fileSize / 1_048_576) MB"
            }
        } catch {
            LargeDiscStore.shared.data = nil
            LargeDiscStore.shared.sourceURL = nil
            discData = Data()
            discFiles = []
            status = "فشل فتح ملف اللعبة: \(error.localizedDescription)"
        }
    }

    var effectiveDiscData: Data {
        LargeDiscStore.shared.data ?? discData
    }
}
