import Foundation

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

            // Map the large BIN/ISO into virtual memory instead of allocating a second full copy in RAM.
            let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard mapped.count > 32 * 1024 else {
                status = "ملف اللعبة صغير جدًا ليكون صورة قرص PS1"
                return
            }

            do {
                // Validate the image before publishing it to the UI. PSXDiscImage is a value parser;
                // CTJModel keeps the mapped Data and derives the file list from it when needed.
                _ = try PSXDiscImage(data: mapped)
                discData = mapped
                discName = url.lastPathComponent
                status = "تم فتح \(url.lastPathComponent) — \(fileSize / 1_048_576) MB"
            } catch {
                discData = Data()
                discName = ""
                status = "تعذر تحليل صورة القرص: \(error.localizedDescription) — الحجم \(fileSize / 1_048_576) MB"
            }
        } catch {
            discData = Data()
            discName = ""
            status = "فشل فتح ملف اللعبة: \(error.localizedDescription)"
        }
    }
}
