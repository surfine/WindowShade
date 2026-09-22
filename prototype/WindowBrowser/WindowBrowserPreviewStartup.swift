import Foundation

/// Startup has two suspension points: discovering a source and starting its stream.
/// Cancellation before the second point must never create a stream; cancellation
/// during it must dispose of the stream without publishing stale success or failure.
enum WindowBrowserPreviewStartup {
    @MainActor
    static func run<Source>(
        load: () async throws -> Source,
        start: (Source) async throws -> Void,
        isCurrent: () -> Bool,
        discard: () -> Void,
        ready: () -> Void,
        failed: (Error) -> Void
    ) async {
        func accepts() -> Bool { !Task.isCancelled && isCurrent() }
        do {
            guard accepts() else { discard(); return }
            let source = try await load()
            guard accepts() else { discard(); return }
            try await start(source)
            guard accepts() else { discard(); return }
            ready()
        } catch {
            discard()
            guard accepts() else { return }
            failed(error)
        }
    }
}
