import SwiftUI

/// Type-to-search field for adding a Ticker. Queries the symbol-search provider
/// (debounced) and surfaces matches; selecting one calls `onSelect`.
struct AddTickerField: View {
    let symbolSearch: any SymbolSearchProviding
    let onSelect: (SymbolMatch) -> Void

    @State private var query = ""
    @State private var results: [SymbolMatch] = []
    @State private var searchFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Add a ticker (e.g. AAPL)", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            if !results.isEmpty {
                resultList
            } else if searchFailed {
                Text("Couldn't search right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !trimmedQuery.isEmpty {
                Text("No matching US ticker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // `.task(id:)` cancels the in-flight task whenever `query` changes,
        // which both debounces typing and avoids out-of-order results.
        .task(id: query) { await runSearch() }
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            ForEach(results.prefix(8)) { match in
                Button {
                    onSelect(match)
                    query = ""
                    results = []
                } label: {
                    HStack(spacing: 8) {
                        Text(match.symbol)
                            .fontWeight(.semibold)
                            .frame(width: 56, alignment: .leading)
                        Text(match.companyName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runSearch() async {
        searchFailed = false
        let q = trimmedQuery
        guard !q.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        do {
            results = try await symbolSearch.searchSymbols(matching: q)
        } catch {
            results = []
            searchFailed = true
        }
    }
}
