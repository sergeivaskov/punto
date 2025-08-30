import Foundation

public enum Log {

    public static var enabled: Bool = true


    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func ts() -> String { isoFormatter.string(from: Date()) }

    public static func d(_ tag: String, _ message: String) {
        guard enabled else { return }
        print("[\(ts())] [\(tag)] \(message)")
        fflush(stdout)
    }
}


