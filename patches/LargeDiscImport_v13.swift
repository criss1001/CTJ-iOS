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

            // Map the file into virtual memory instead of allocating/copying the whole BIN in RAM.
            let mapped = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard mapped.count > 32 * 1024 else {
                status = "ملف اللعبة صغير جدًا ليكون صورة قرص PS1"
                return
            }

            do {
                let image = try PSXDiscImage(data: mapped)
                discData = mapped
                discName = url.lastPathComponent
                discImage = image
                status = "تم فتح \(url.lastPathComponent) — \(fileSize / 1_048_576) MB"
            } catch {
                discData = Data()
                discImage = nil
                status = "تعذر تحليل صورة القرص: \(error.localizedDescription) — الحجم \(fileSize / 1_048_576) MB"
            }
        } catch {
            status = "فشل فتح ملف اللعبة: \(error.localizedDescription)"
        }
    }
}
