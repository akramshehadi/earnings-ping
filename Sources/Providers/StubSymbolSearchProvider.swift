import Foundation

/// Temporary local symbol search backed by a small bundled list of well-known
/// US tickers. Lets the Watchlist (add / validate / autocomplete) work end to
/// end before the Finnhub client (issue 03) replaces it behind the same
/// `SymbolSearchProviding` protocol.
struct StubSymbolSearchProvider: SymbolSearchProviding {
    private let catalog: [SymbolMatch] = [
        .init(symbol: "AAPL", companyName: "Apple Inc"),
        .init(symbol: "MSFT", companyName: "Microsoft Corp"),
        .init(symbol: "GOOGL", companyName: "Alphabet Inc"),
        .init(symbol: "AMZN", companyName: "Amazon.com Inc"),
        .init(symbol: "NVDA", companyName: "NVIDIA Corp"),
        .init(symbol: "META", companyName: "Meta Platforms Inc"),
        .init(symbol: "TSLA", companyName: "Tesla Inc"),
        .init(symbol: "AMD", companyName: "Advanced Micro Devices Inc"),
        .init(symbol: "NFLX", companyName: "Netflix Inc"),
        .init(symbol: "INTC", companyName: "Intel Corp"),
        .init(symbol: "AVGO", companyName: "Broadcom Inc"),
        .init(symbol: "CRM", companyName: "Salesforce Inc"),
        .init(symbol: "ADBE", companyName: "Adobe Inc"),
        .init(symbol: "ORCL", companyName: "Oracle Corp"),
        .init(symbol: "QCOM", companyName: "Qualcomm Inc"),
        .init(symbol: "CSCO", companyName: "Cisco Systems Inc"),
        .init(symbol: "PYPL", companyName: "PayPal Holdings Inc"),
        .init(symbol: "UBER", companyName: "Uber Technologies Inc"),
        .init(symbol: "DIS", companyName: "Walt Disney Co"),
        .init(symbol: "BA", companyName: "Boeing Co"),
        .init(symbol: "JPM", companyName: "JPMorgan Chase & Co"),
        .init(symbol: "BAC", companyName: "Bank of America Corp"),
        .init(symbol: "WMT", companyName: "Walmart Inc"),
        .init(symbol: "KO", companyName: "Coca-Cola Co"),
        .init(symbol: "PEP", companyName: "PepsiCo Inc"),
        .init(symbol: "MCD", companyName: "McDonald's Corp"),
        .init(symbol: "NKE", companyName: "Nike Inc"),
        .init(symbol: "COST", companyName: "Costco Wholesale Corp"),
        .init(symbol: "SBUX", companyName: "Starbucks Corp"),
        .init(symbol: "PFE", companyName: "Pfizer Inc"),
        .init(symbol: "JNJ", companyName: "Johnson & Johnson"),
        .init(symbol: "XOM", companyName: "Exxon Mobil Corp"),
        .init(symbol: "CVX", companyName: "Chevron Corp"),
        .init(symbol: "T", companyName: "AT&T Inc"),
        .init(symbol: "V", companyName: "Visa Inc"),
        .init(symbol: "MA", companyName: "Mastercard Inc"),
        .init(symbol: "HD", companyName: "Home Depot Inc"),
        .init(symbol: "IBM", companyName: "International Business Machines Corp"),
        .init(symbol: "GE", companyName: "General Electric Co"),
        .init(symbol: "F", companyName: "Ford Motor Co"),
        .init(symbol: "GM", companyName: "General Motors Co"),
    ]

    func searchSymbols(matching query: String) async throws -> [SymbolMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }
        return catalog
            .filter { $0.symbol.hasPrefix(q) || $0.companyName.uppercased().contains(q) }
            .sorted { lhs, rhs in
                // Prefer symbol-prefix hits, then alphabetical by symbol.
                let lp = lhs.symbol.hasPrefix(q), rp = rhs.symbol.hasPrefix(q)
                if lp != rp { return lp }
                return lhs.symbol < rhs.symbol
            }
    }
}
