import SwiftData
import SwiftUI

/// The Watchlist surface in the menu-bar popover: add via autocomplete, remove,
/// sort, and the per-ticker row. Earnings dates stay "no upcoming date" until
/// the refresh engine (issue 04) populates events.
struct WatchlistView: View {
    let symbolSearch: any SymbolSearchProviding

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Query private var tickers: [Ticker]

    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            AddTickerField(symbolSearch: symbolSearch, onSelect: add(_:))

            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            if tickers.isEmpty {
                emptyState
            } else {
                tickerList
            }
        }
        .padding(12)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.tint)
            Text("Watchlist")
                .font(.headline)
            Spacer()
            Text("\(tickers.count)/\(settings.maxWatchlistSize)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $settings.watchlistSortOrder) {
                ForEach(WatchlistSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort order")
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No tickers yet")
                .foregroundStyle(.secondary)
            Text("Add one above to start tracking earnings dates.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var tickerList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(sortedTickers) { ticker in
                    TickerRow(ticker: ticker) { remove(ticker) }
                    if ticker.id != sortedTickers.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Sorting

    private var sortedTickers: [Ticker] {
        WatchlistOperations.sorted(tickers, by: settings.watchlistSortOrder)
    }

    // MARK: - Mutations

    private func add(_ match: SymbolMatch) {
        addError = nil
        let symbol = match.symbol.uppercased()

        switch WatchlistOperations.validateAdd(
            symbol: symbol,
            existingSymbols: tickers.map(\.symbol),
            maxSize: settings.maxWatchlistSize
        ) {
        case .ok:
            modelContext.insert(Ticker(symbol: symbol, companyName: match.companyName))
            try? modelContext.save()
        case .duplicate(let existing):
            addError = "\(existing) is already on your watchlist."
        case .full(let max):
            addError = "Watchlist is full (max \(max)). Remove one to add another."
        }
    }

    private func remove(_ ticker: Ticker) {
        addError = nil
        modelContext.delete(ticker)
        try? modelContext.save()
    }
}

/// One Watchlist row: symbol, company, earnings state, and a remove control.
private struct TickerRow: View {
    let ticker: Ticker
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ticker.symbol)
                    .fontWeight(.semibold)
                Text(ticker.companyName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            earningsState
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.35)
            .help("Remove \(ticker.symbol)")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var earningsState: some View {
        if let event = ticker.event {
            VStack(alignment: .trailing, spacing: 1) {
                Text(event.date, format: .dateTime.month(.abbreviated).day())
                    .font(.callout)
                Text(event.session.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("no upcoming date")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
