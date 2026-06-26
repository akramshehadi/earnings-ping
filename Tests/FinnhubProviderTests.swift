import Foundation
import Testing
@testable import EarningsPing

// MARK: - Offline HTTP stub

/// Intercepts URLSession requests so the provider can be exercised without the
/// network. The responder is static, so the suite using it runs `.serialized`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// (status, body) to return, or a thrown error, for the next request.
    struct Stub {
        var statusCode: Int
        var body: Data
    }

    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> Stub)?
    nonisolated(unsafe) private(set) static var lastRequest: URLRequest?
    private static let lock = NSLock()

    static func setHandler(_ handler: @escaping (URLRequest) throws -> Stub) {
        lock.withLock {
            self.handler = handler
            self.lastRequest = nil
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            lastRequest = nil
        }
    }

    /// A URLSession whose only protocol is this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let handler = Self.lock.withLock { () -> ((URLRequest) throws -> Stub)? in
            Self.lastRequest = request
            return Self.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let stub = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private extension FinnhubProvider {
    /// Provider wired to the offline stub with a fixed test key.
    static func stubbed(key: String? = "test-key") -> FinnhubProvider {
        FinnhubProvider(
            apiKeyStore: InMemoryAPIKeyStore(key: key),
            session: StubURLProtocol.makeSession()
        )
    }
}

// MARK: - Fixtures

private enum Fixtures {
    /// Mirrors the live AAPL response shape captured during issue-03 verification.
    static let aaplEarnings = Data("""
    {"earningsCalendar":[
      {"symbol":"AAPL","date":"2026-10-28","hour":"amc","quarter":4,"year":2026,"epsEstimate":2.41,"epsActual":null,"revenueEstimate":1.4e11,"revenueActual":null},
      {"symbol":"AAPL","date":"2026-07-29","hour":"amc","quarter":3,"year":2026,"epsEstimate":1.9304,"epsActual":null,"revenueEstimate":8.9e10,"revenueActual":null}
    ]}
    """.utf8)

    static let emptyEarnings = Data(#"{"earningsCalendar":[]}"#.utf8)

    /// Mix of a US common stock, a US non-common type, and a foreign listing.
    static let search = Data("""
    {"count":3,"result":[
      {"description":"APPLE INC","displaySymbol":"AAPL","symbol":"AAPL","type":"Common Stock"},
      {"description":"APPLE HOSPITALITY REIT","displaySymbol":"APLE","symbol":"APLE","type":"REIT"},
      {"description":"TOYOTA MOTOR CORP","displaySymbol":"2788.T","symbol":"2788.T","type":"Common Stock"}
    ]}
    """.utf8)
}

private func makeWindow(from: String, days: Int = 90) -> DateInterval {
    let start = FinnhubProvider.dayFormatter.date(from: from)!
    return DateInterval(start: start, duration: TimeInterval(days * 86_400))
}

// MARK: - Tests

@Suite("FinnhubProvider (offline)", .serialized)
struct FinnhubProviderOfflineTests {
    init() { StubURLProtocol.reset() }

    @Test func parsesEarningsRows() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 200, body: Fixtures.aaplEarnings) }
        let provider = FinnhubProvider.stubbed()

        let events = try await provider.fetchEarnings(symbol: "aapl", within: makeWindow(from: "2026-07-01"))

        #expect(events.count == 2)
        let july = try #require(events.first { $0.fiscalPeriod == "Q3 FY2026" })
        #expect(july.symbol == "AAPL")
        #expect(july.session == .amc)
        #expect(july.epsEstimate == 1.9304)

        // Date is anchored to midnight America/New_York.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let c = cal.dateComponents([.year, .month, .day], from: july.date)
        #expect(c.year == 2026 && c.month == 7 && c.day == 29)
    }

    @Test func sendsAuthTokenHeader() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 200, body: Fixtures.emptyEarnings) }
        let provider = FinnhubProvider.stubbed(key: "secret-123")

        _ = try await provider.fetchEarnings(symbol: "AAPL", within: makeWindow(from: "2026-07-01"))

        let header = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Finnhub-Token")
        #expect(header == "secret-123")
    }

    @Test func nextUpcomingPicksSoonestOnOrAfterWindowStart() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 200, body: Fixtures.aaplEarnings) }
        let provider = FinnhubProvider.stubbed()

        let next = try await provider.nextUpcomingEarnings(symbol: "AAPL", within: makeWindow(from: "2026-07-01"))
        #expect(next?.fiscalPeriod == "Q3 FY2026")
    }

    @Test func searchKeepsUSCommonStockOnly() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 200, body: Fixtures.search) }
        let provider = FinnhubProvider.stubbed()

        let matches = try await provider.searchSymbols(matching: "apple")

        // REIT (APLE) and foreign listing (2788.T) are dropped.
        #expect(matches.map(\.symbol) == ["AAPL"])
        #expect(matches.first?.companyName == "APPLE INC")
    }

    @Test func unauthorizedMapsToTypedError() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 401, body: Data(#"{"error":"Invalid API key"}"#.utf8)) }
        let provider = FinnhubProvider.stubbed()

        await #expect(throws: EarningsProviderError.unauthorized) {
            _ = try await provider.fetchEarnings(symbol: "AAPL", within: makeWindow(from: "2026-07-01"))
        }
    }

    @Test func rateLimitMapsToTypedError() async throws {
        StubURLProtocol.setHandler { _ in .init(statusCode: 429, body: Data()) }
        let provider = FinnhubProvider.stubbed()

        await #expect(throws: EarningsProviderError.rateLimited) {
            _ = try await provider.fetchEarnings(symbol: "AAPL", within: makeWindow(from: "2026-07-01"))
        }
    }

    @Test func missingKeyFailsBeforeNetwork() async throws {
        // No handler set: if the provider hit the network this would fail
        // differently. It must short-circuit on the absent key instead.
        let provider = FinnhubProvider.stubbed(key: nil)

        await #expect(throws: EarningsProviderError.missingAPIKey) {
            _ = try await provider.fetchEarnings(symbol: "AAPL", within: makeWindow(from: "2026-07-01"))
        }
    }
}

// MARK: - Live integration (opt-in)

/// Hits the real Finnhub API. Skipped unless `FINNHUB_API_KEY` is set, so CI and
/// offline runs stay green; run locally with the key to confirm live behavior.
@Suite("FinnhubProvider (live)")
struct FinnhubProviderLiveTests {
    private static var hasKey: Bool {
        ProcessInfo.processInfo.environment["FINNHUB_API_KEY"]?.isEmpty == false
    }

    @Test(.enabled(if: hasKey))
    func fetchesAppleEarningsLive() async throws {
        let provider = FinnhubProvider(apiKeyStore: InMemoryAPIKeyStore())
        let window = DateInterval(start: .now, duration: 365 * 86_400)

        let next = try await provider.nextUpcomingEarnings(symbol: "AAPL", within: window)
        let event = try #require(next, "Expected an upcoming AAPL earnings date within a year")
        #expect(event.symbol == "AAPL")
        #expect(event.date >= window.start)
    }

    @Test(.enabled(if: hasKey))
    func searchesSymbolsLive() async throws {
        let provider = FinnhubProvider(apiKeyStore: InMemoryAPIKeyStore())
        let matches = try await provider.searchSymbols(matching: "apple")
        #expect(matches.contains { $0.symbol == "AAPL" })
        #expect(matches.allSatisfy { !$0.symbol.contains(".") })
    }
}
