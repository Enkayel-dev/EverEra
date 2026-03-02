import SwiftUI
import QuickLookUI
import QuickLookThumbnailing

// MARK: - QuickLookPreview

/// Wraps macOS QLPreviewView as a SwiftUI view.
/// Renders an inline Quick Look preview of any file URL (PDF, image, etc.).
struct QuickLookPreview: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        if let url {
            view.previewItem = url as QLPreviewItem
        }
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if let url {
            nsView.previewItem = url as QLPreviewItem
        } else {
            nsView.previewItem = nil
        }
    }
}

// MARK: - DocumentPreviewThumbnail

/// A compact square thumbnail suitable for use in list rows.
/// Uses `QLThumbnailGenerator` for lightweight async thumbnail generation
/// instead of embedding a full `QLPreviewView`. Falls back to a kind icon
/// if no URL is available or generation fails.
struct DocumentPreviewThumbnail: View {
    let document: LSDocument
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
            } else {
                kindIconPlaceholder
            }
        }
        .accessibilityLabel(thumbnail != nil
            ? "Thumbnail for \(document.displayName)"
            : "\(document.kind.rawValue) document, \(document.displayName)")
        .task(id: document.storedFileName) {
            await loadThumbnail()
        }
    }

    private var kindIconPlaceholder: some View {
        Image(systemName: document.kind.systemImage)
            .font(.system(size: size * 0.4))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.15))
    }

    private func loadThumbnail() async {
        guard let url = document.resolvedURL() else { return }

        // Request at 2x for Retina displays
        let scale: CGFloat = 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.nsImage
        } catch {
            // Fall back to kind-icon placeholder (thumbnail stays nil)
        }
    }
}
