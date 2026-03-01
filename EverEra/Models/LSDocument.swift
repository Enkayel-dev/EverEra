//
//  LSDocument.swift
//  EverEra
//
//  A first-class file asset (PDF, image, receipt) attached to an LSEvent.
//  Files are copied into the app's container for self-contained storage.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - DocumentKind

enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case pdf         = "PDF"
    case image       = "Image"
    case receipt     = "Receipt"
    case contract    = "Contract"
    case taxForm     = "Tax Form"
    case insurance   = "Insurance"
    case other       = "Other"

    var systemImage: String {
        switch self {
        case .pdf:        return "doc.fill"
        case .image:      return "photo.fill"
        case .receipt:    return "receipt.fill"
        case .contract:   return "doc.text.fill"
        case .taxForm:    return "doc.richtext.fill"
        case .insurance:  return "shield.fill"
        case .other:      return "paperclip"
        }
    }

    /// Infers the document kind from the file's UTType or extension.
    static func infer(from url: URL) -> DocumentKind {
        let ext = url.pathExtension.lowercased()
        let utType = UTType(filenameExtension: ext)

        if utType?.conforms(to: .pdf) == true || ext == "pdf" {
            return .pdf
        }
        if utType?.conforms(to: .image) == true
            || ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "bmp", "webp"].contains(ext) {
            return .image
        }
        return .other
    }
}

// MARK: - LSDocument

@Model
final class LSDocument {
    var id: UUID
    var displayName: String
    var kind: DocumentKind

    /// Filename within the app's ImportedFiles directory.
    /// This is the primary storage mechanism — files are copied into the app container.
    var storedFileName: String?

    /// Legacy bookmark data (kept for backward compatibility).
    var bookmarkData: Data?

    /// Full-text content extracted via on-device OCR / Apple Intelligence.
    var ocrContent: String

    /// AI-extracted summary of the document's key facts.
    var inferredSummary: String

    var importedAt: Date

    // Back-reference to owning event; SwiftData manages the inverse.
    var event: LSEvent?

    init(
        id: UUID = UUID(),
        displayName: String,
        kind: DocumentKind,
        storedFileName: String? = nil,
        bookmarkData: Data? = nil,
        ocrContent: String = "",
        inferredSummary: String = "",
        importedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.storedFileName = storedFileName
        self.bookmarkData = bookmarkData
        self.ocrContent = ocrContent
        self.inferredSummary = inferredSummary
        self.importedAt = importedAt
    }

    // MARK: - File Storage

    /// The directory where imported files are stored inside the app container.
    static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("EverEra/ImportedFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Kicks off background OCR for this document.
    /// The result is written back on the MainActor after extraction completes.
    /// Safe to call immediately after inserting the document into a model context.
    @MainActor
    func runOCRIfNeeded() {
        guard ocrContent.isEmpty, let url = resolvedURL() else { return }
        // Capture the URL (a value type) — avoids capturing self across concurrency boundary.
        let capturedURL = url
        let doc = self
        Task {
            do {
                let text = try await OCRService.shared.extractText(from: capturedURL)
                doc.ocrContent = text
            } catch {
                // OCR is best-effort; silently ignore failures.
            }
        }
    }

    /// Copies a file into the app's storage directory and returns the stored filename.
    /// The filename is prefixed with a UUID to prevent collisions.
    @discardableResult
    static func importFile(from sourceURL: URL) throws -> String {
        let storedName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
        let destination = storageDirectory.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return storedName
    }

    // MARK: - URL Resolution

    /// Returns the URL of the stored file, or falls back to the legacy bookmark.
    func resolvedURL() -> URL? {
        // Primary: resolve from stored file in app container
        if let name = storedFileName {
            let url = LSDocument.storageDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fallback: legacy security-scoped bookmark
        guard let data = bookmarkData else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
