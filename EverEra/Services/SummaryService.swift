//
//  SummaryService.swift
//  EverEra
//
//  On-device document summarisation using Apple's FoundationModels framework
//  (Apple Intelligence). Runs entirely locally — no network calls required.
//
//  Usage:
//    let result = try await SummaryService.shared.summarise(ocrText: doc.ocrContent)
//    doc.inferredSummary = result.oneLiner
//
//  Availability:
//    FoundationModels requires macOS 26+ with Apple Intelligence enabled.
//    Always check `SummaryService.isAvailable` before calling `summarise`.
//

import Foundation
import FoundationModels

// MARK: - Generable output type

/// Structured summary generated from a document's OCR text.
@Generable
struct DocumentSummary {
    /// A single-sentence summary of the document (shown in the inspector).
    @Guide(description: "A single sentence summarising the document's main purpose.")
    var oneLiner: String

    /// Up to five key facts or data points extracted from the document.
    @Guide(description: "Up to five bullet-point facts extracted from the document. Each fact should be concise — one short sentence.")
    var keyFacts: [String]

    /// Dates explicitly mentioned in the document (ISO-8601 or natural language).
    @Guide(description: "Any specific dates mentioned in the document, e.g. '2023-04-15' or 'March 2022'. Empty array if none.")
    var datesMentioned: [String]

    /// Suggested display name for the document (may improve on the filename).
    @Guide(description: "A short, human-readable title for this document, suitable as a filename without extension.")
    var suggestedTitle: String
}

// MARK: - SummaryService

/// Actor-based service wrapping FoundationModels for document summarisation.
/// Each call creates a fresh `LanguageModelSession` (single-turn — no history needed).
actor SummaryService {

    static let shared = SummaryService()
    private init() {}

    // MARK: - Availability

    /// Returns true if the on-device foundation model is ready to use.
    /// Gate all UI and calls behind this check.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    // MARK: - Public API

    /// Summarises the supplied OCR text using the on-device language model.
    ///
    /// - Parameter ocrText: The raw OCR-extracted string from `LSDocument.ocrContent`.
    /// - Returns: A `DocumentSummary` with structured fields.
    /// - Throws: `LanguageModelSession.GenerationError` or `SummaryError` if the
    ///   model is unavailable or the text is too short to summarise meaningfully.
    func summarise(ocrText: String) async throws -> DocumentSummary {
        guard SummaryService.isAvailable else {
            throw SummaryError.modelUnavailable
        }
        guard ocrText.count > 50 else {
            throw SummaryError.textTooShort
        }

        // Truncate to stay well within the 4 096-token context window.
        // ~3 chars/token → ~3 000 chars = ~1 000 tokens, leaving room for
        // the schema injection and the generated response.
        let truncated = ocrText.count > 3_000
            ? String(ocrText.prefix(3_000)) + "\n[… text truncated …]"
            : ocrText

        let session = LanguageModelSession(
            instructions: """
            You are a personal-records assistant. Your job is to analyse the \
            text extracted from an imported document and produce a concise, \
            factual summary. Do not invent information that is not present \
            in the text. Respond only with the structured fields requested.
            """
        )

        let prompt = "Document text:\n\n\(truncated)"
        let response = try await session.respond(
            to: prompt,
            generating: DocumentSummary.self
        )
        return response.content
    }
}

// MARK: - SummaryError

enum SummaryError: LocalizedError {
    case modelUnavailable
    case textTooShort

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple Intelligence is not available on this device or has not been enabled in Settings."
        case .textTooShort:
            return "The document does not contain enough text to generate a meaningful summary."
        }
    }
}
