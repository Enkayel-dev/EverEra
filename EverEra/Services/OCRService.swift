//
//  OCRService.swift
//  EverEra
//
//  On-device text extraction from PDFs and images using Apple's Vision
//  and PDFKit frameworks. Runs entirely locally — no network calls.
//

import Foundation
import Vision
import PDFKit
import AppKit

// MARK: - OCRService

actor OCRService {

    static let shared = OCRService()
    private init() {}

    // MARK: - Public API

    /// Extracts all recognisable text from a file at the given URL.
    /// Supports PDF (multi-page), PNG, JPEG, HEIC, and other image formats.
    /// Returns an empty string if no text is found or the file type is unsupported.
    func extractText(from url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try await extractFromPDF(url: url)
        } else {
            return try await extractFromImage(url: url)
        }
    }

    // MARK: - PDF extraction

    private func extractFromPDF(url: URL) async throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw OCRError.unreadableFile
        }

        var pages: [String] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            // First try native PDF text (fast, perfect for digital PDFs)
            let nativeText = page.string ?? ""
            if nativeText.count > 20 {
                pages.append(nativeText)
                continue
            }

            // Fall back to Vision OCR (for scanned / image PDFs)
            let thumbnail = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
            if let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let text = try await recogniseText(in: cgImage)
                if !text.isEmpty { pages.append(text) }
            }
        }

        return pages.joined(separator: "\n\n— Page Break —\n\n")
    }

    // MARK: - Image extraction

    private func extractFromImage(url: URL) async throws -> String {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.unreadableFile
        }
        return try await recogniseText(in: cgImage)
    }

    // MARK: - Vision OCR

    private func recogniseText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - OCRError

enum OCRError: LocalizedError {
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "The file could not be read for text extraction."
        }
    }
}
