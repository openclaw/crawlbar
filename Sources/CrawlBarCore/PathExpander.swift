import Foundation

public enum PathExpander {
    public static func expandHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: home).appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
}
