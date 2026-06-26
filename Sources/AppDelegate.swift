import AppKit

/// Owns the composition root so it is created once, up front, and lives for the
/// app's lifetime. Provides a home for any future launch-time setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
}
