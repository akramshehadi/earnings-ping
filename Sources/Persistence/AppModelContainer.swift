import Foundation
import SwiftData

/// Builds the app's single SwiftData container — the source-of-truth store for
/// the Watchlist and its Earnings Events (ADR-0001).
enum AppModelContainer {
    static let schema = Schema([Ticker.self, EarningsEvent.self])

    /// On-disk container used by the running app.
    static func makeShared() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    /// Ephemeral container for SwiftUI previews and tests.
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }
}
