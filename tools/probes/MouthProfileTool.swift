import Foundation
@main struct MouthProfileTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 4 else {
            print("Usage: build <mandarin|cantonese|wu> <new-profile.json> <recording.json>... OR evaluate <profile.json> <new-report.json> <holdout.json>...")
            exit(64)
        }
        func read<T: Decodable>(_ path: String, as: T.Type) throws -> T {
            let url = URL(fileURLWithPath: path)
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000 else { throw Failure.invalid }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        let samples = try args.dropFirst(3).map { try read($0, as: WS2MouthRecording.self) }
        let output: Data
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if args[0] == "build" {
            let profile = WS2MouthProfile(speech: args[1], templates: samples, maximumDistance: 0.06, minimumMargin: 0.025)
            guard profile.valid else { throw Failure.invalid }
            output = try encoder.encode(profile)
        } else if args[0] == "evaluate" {
            let profile = try read(args[1], as: WS2MouthProfile.self)
            guard let evaluation = WS2MouthMatcher.evaluate(samples, speech: profile.speech, profile: profile) else { throw Failure.overlappingSessionsOrInvalidProfile }
            output = try encoder.encode(evaluation)
        } else { throw Failure.invalid }
        // Explicit export; do not replace existing personal profiles or measurements.
        try output.write(to: URL(fileURLWithPath: args[2]), options: .withoutOverwriting)
    }
    enum Failure: Error { case invalid, overlappingSessionsOrInvalidProfile }
}
