import Foundation
import UniformTypeIdentifiers

/// Pure, testable extractor that turns [NSItemProvider] into [URL].
/// Used by TrackListView (and reusable by PlayerView/DataDiscView) for drag-and-drop.
public enum FileDropExtractor {
    /// Parse a loaded item (from NSItemProvider callback) into a file URL.
    /// This is the pure URL-extraction logic — handles URL, Data (bookmark/plain), and String items.
    /// - Parameter item: The item loaded from NSItemProvider.loadItem callback.
    /// - Returns: A file URL if the item could be parsed, nil otherwise.
    public static func parseLoadedItem(_ item: Any?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data {
            var isStale = false
            if let bookmarkURL = try? URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return bookmarkURL
            }
            if let plainURL = URL(dataRepresentation: data, relativeTo: nil) {
                return plainURL
            }
        }
        if let path = item as? String {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    
    /// Synchronously extracts file URLs from the given providers.
    /// Uses loadItem(forTypeIdentifier:) for each provider; blocks until all complete.
    /// Returns all parsed URLs. Does NOT filter by fileExists — security-scoped URLs
    /// from Finder can fail fileExists without startAccessingSecurityScopedResource.
    /// The receiver (view/session) handles security scope and invalid URLs.
    public static func extractURLs(from providers: [NSItemProvider]) -> [URL] {
        // Thread-safe mutable container for concurrent loadItem callbacks
        final class Box: @unchecked Sendable {
            var urls: [URL] = []
        }
        let box = Box()
        let group = DispatchGroup()
        for provider in providers {
            // Prefer the public.file-url type; fall back to public.url
            let typeIds = provider.registeredTypeIdentifiers.filter {
                $0 == "public.file-url" || $0 == "public.url" || $0 == UTType.fileURL.identifier
            }
            let typeId = typeIds.first ?? UTType.fileURL.identifier
            group.enter()
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                defer { group.leave() }
                if let url = parseLoadedItem(item) {
                    box.urls.append(url)
                }
            }
        }
        _ = group.wait(timeout: .now() + 10)
        // Do NOT filter by fileExists — Finder drops yield security-scoped URLs where
        // fileExists is false without startAccessingSecurityScopedResource. The receiver
        // (view/session) handles invalid URLs. Filtering here caused dropped files to vanish.
        return box.urls
    }
}
