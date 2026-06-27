import Foundation

/// v1 `EarningsProvider`, backed by Finnhub's free tier (ADR-0003).
///
/// Two endpoints are used, both authenticated with the `X-Finnhub-Token` header:
/// - `GET /calendar/earnings?from=&to=&symbol=` — per-symbol earnings calendar.
/// - `GET /search?q=` — symbol autocomplete.
///
/// The key is read lazily through `APIKeyProviding` on each call, so onboarding
/// (issue 07) can populate it after this provider is constructed.
struct FinnhubProvider: EarningsProvider {
    private let apiKeyStore: any APIKeyProviding
    private let session: URLSession
    private let baseURL: URL

    init(
        apiKeyStore: any APIKeyProviding,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://finnhub.io/api/v1")!
    ) {
        self.apiKeyStore = apiKeyStore
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: SymbolSearchProviding

    func searchSymbols(matching query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let response: SearchResponse = try await get(
            path: "search",
            queryItems: [URLQueryItem(name: "q", value: q)]
        )

        return response.result
            // US-listed equities only: Finnhub tags foreign listings with an
            // exchange suffix (e.g. "2788.T", "603020.SS"), so drop anything with
            // a dot. Keep the equity types that actually report earnings — common
            // stock, ADRs (e.g. TSM, BABA) and REITs — and drop funds/ETPs.
            .filter { !$0.symbol.contains(".") && Self.searchableEquityTypes.contains($0.type.lowercased()) }
            .map { SymbolMatch(symbol: $0.symbol, companyName: $0.description) }
    }

    // MARK: EarningsProvider

    func fetchEarnings(symbol: String, within window: DateInterval) async throws -> [UpcomingEarnings] {
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !sym.isEmpty else { return [] }

        let response: EarningsCalendarResponse = try await get(
            path: "calendar/earnings",
            queryItems: [
                URLQueryItem(name: "from", value: Self.dayFormatter.string(from: window.start)),
                URLQueryItem(name: "to", value: Self.dayFormatter.string(from: window.end)),
                URLQueryItem(name: "symbol", value: sym),
            ]
        )

        let fetchedAt = Date()
        return response.earningsCalendar.compactMap { row -> UpcomingEarnings? in
            guard let date = Self.dayFormatter.date(from: row.date) else { return nil }
            return UpcomingEarnings(
                symbol: row.symbol,
                date: date,
                session: Session(finnhubHour: row.hour),
                fiscalPeriod: Self.fiscalPeriod(quarter: row.quarter, year: row.year),
                epsEstimate: row.epsEstimate,
                fetchedAt: fetchedAt
            )
        }
    }

    // MARK: Networking

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        guard let key = try apiKeyStore.apiKey(), !key.isEmpty else {
            throw EarningsProviderError.missingAPIKey
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw EarningsProviderError.invalidResponse(status: -1)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw EarningsProviderError.invalidResponse(status: -1)
        }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-Finnhub-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EarningsProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw EarningsProviderError.invalidResponse(status: -1)
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw EarningsProviderError.unauthorized
        case 429:
            throw EarningsProviderError.rateLimited
        default:
            throw EarningsProviderError.invalidResponse(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EarningsProviderError.decoding(error.localizedDescription)
        }
    }

    // MARK: Helpers

    /// Finnhub `/search` `type` values kept for the Watchlist: equity instruments
    /// that report earnings. Compared lower-cased. ETPs, mutual/closed-end funds,
    /// units, rights, warrants, etc. are excluded.
    private static let searchableEquityTypes: Set<String> = ["common stock", "adr", "reit"]

    /// Finnhub dates are bare `yyyy-MM-dd` strings; anchor them to midnight
    /// America/New_York so "the report day" is unambiguous across time zones.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "Q3 FY2026" — display only. Returns `nil` when the quarter is out of range.
    static func fiscalPeriod(quarter: Int?, year: Int?) -> String? {
        guard let quarter, (1...4).contains(quarter), let year else { return nil }
        return "Q\(quarter) FY\(year)"
    }
}

// MARK: - Session mapping

extension Session {
    /// Maps Finnhub's `hour` field to a `Session`. Known values are `bmo`,
    /// `amc`, `dmh`; anything else (including empty) is `unknown`.
    init(finnhubHour hour: String?) {
        switch hour?.lowercased() {
        case "bmo": self = .bmo
        case "amc": self = .amc
        case "dmh": self = .dmh
        default: self = .unknown
        }
    }
}

// MARK: - Finnhub DTOs

/// `GET /calendar/earnings` response.
private struct EarningsCalendarResponse: Decodable {
    let earningsCalendar: [Row]

    struct Row: Decodable {
        let symbol: String
        let date: String
        let hour: String?
        let quarter: Int?
        let year: Int?
        let epsEstimate: Double?
    }
}

/// `GET /search` response.
private struct SearchResponse: Decodable {
    let result: [Row]

    struct Row: Decodable {
        let description: String
        let symbol: String
        let type: String
    }
}
