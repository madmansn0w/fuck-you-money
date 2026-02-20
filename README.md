# Fuck You Money

macOS crypto portfolio tracker with a native SwiftUI app and CLI. Supports multiple users, accounts, cost basis methods (FIFO/LIFO/average), and uses JSON data files for portfolio and price cache.

## Build and run

**Swift app:** Open `FuckYouMoneyApp/FuckYouMoneyApp.xcodeproj` in Xcode. If the project was opened without the Swift package, add it: **File → Add Package Dependencies… → Add Local…** and select the **repo root** (the folder containing `Package.swift`). Add the **FuckYouMoneyCore** product to the FuckYouMoneyApp target. See `FuckYouMoneyApp/ADD_PACKAGE.md` for step-by-step instructions. Then select the **FuckYouMoneyApp** scheme and Product → Run (⌘R).

**CLI:** From repo root run `swift build`; the binary is `.build/debug/fuck-you-money-cli` (or `release` with `-c release`).

## Tests

```bash
swift test
```

## Layout

- `FuckYouMoneyApp/` – SwiftUI macOS app (Xcode project)
- `Sources/FuckYouMoneyCore/` – shared core (metrics, storage, pricing, Polymarket, exchanges)
- `Sources/FuckYouMoneyCLI/` – CLI executable
- `Package.swift` – Swift package definition
- `tests/FuckYouMoneyCoreTests/` – Swift unit tests
- `docs/` – API spec (`API.md`), roadmap (`ROADMAP.md`)

Data files (when using a folder like repo root or Application Support): `crypto_data_<username>.json`, `users.json`, `price_cache.json`, `price_history.json`.

---

## App overview

The main window has a **sidebar** (accounts and groups), a **summary panel** (portfolio totals, portfolio 24h change, per-asset cards with qty/value/P&L/24h %, open and closed positions), and a **detail area** with multiple tabs:

- **Dashboard** – KPI cards, trading analytics, scenario, correlation heatmap (when per-asset return series are available), Fear & Greed Index, crypto + economic RSS news, noteworthy-filtered news, tax lots, benchmark
- **Trading** / **Transactions** – add, edit, remove trades; filters and list
- **Charts** – equity curve, drawdown, allocation; time range (1D, 1W, 1M, 3M, 6M, 1Y, All) or aggregation (Monthly/Quarterly)
- **Assets** – per-asset: price & 24h, market metrics, performance, technicals/sentiment, CoinGecko info; watchlist; "Add trade…" opens Transactions with asset pre-filled
- **Assistant** – exchange balances and order UI (Kraken, Bitstamp, Binance, Binance Testnet); plain-language portfolio queries
- **Polymarket** – crypto prediction markets (Gamma), intra-market / combinatorial / endgame arbitrage, CLOB order book with spread alerts, systematic NO farming

You can **reorder the tabs** in **Settings → Tab order** (Move Up / Move Down); the order is saved.

- **Data directory**: By default the app uses `~/Library/Application Support/FuckYouMoney/` for data and price history. In **Settings → Data** you can choose **Use existing folder…** (e.g. repo root) to use JSON files in that folder.
- **Backup**: **Settings → Data → Backup all data…** exports all users’ data and price history as a timestamped JSON file. **Restore from backup…** replaces all data with a chosen backup file.
- **Alerts & news**: **Settings → Alerts** – portfolio/price/drawdown alerts and **Notify when new noteworthy news appears** (macOS notifications when Dashboard news is loaded or refreshed).

## URL scheme

The app registers the `fuckyoumoney` URL scheme (e.g. when the app is running):

- **Activate app**: `open "fuckyoumoney://open"`
- **Refresh prices**: `open "fuckyoumoney://refresh"`
- **Add one trade**:  
  `open "fuckyoumoney://add-trade?user=Default&asset=BTC&type=BUY&quantity=0.5&price=40000&fee=20&exchange=Bitstamp"`  
  Optional query params: `user`, `asset`, `type`, `quantity`, `price`, `fee`, `total_value`, `exchange`, `account_id`, `date` (ISO or app format).

## Local HTTP API (optional)

In **Settings → Local API** you can enable a small HTTP server on localhost. Default port: **38472**. Optional **Webhook URL**: the app POSTs when trades are added or portfolio is refreshed. When the API is on, **Open API docs in browser** opens the spec at `GET /v1/docs`.

| Method / path        | Description |
|----------------------|-------------|
| `GET /v1/health`     | 200 OK – liveness. |
| `GET /v1/portfolio?user=Default` | JSON: `total_value`, `total_pnl`, `roi_pct`, `realized_pnl`, `unrealized_pnl`. |
| `GET /v1/positions`  | Per-asset positions (optional `user`, `account_id`, `group_id`). |
| `GET /v1/trades`     | List trades (optional filters). |
| `GET /v1/analytics/summary` | Portfolio metrics, max drawdown, Sharpe, volatility, win rate, etc. |
| `GET /v1/analytics/correlation` | Pairwise daily-return correlation (from price history). |
| `GET /v1/query?q=portfolio\|positions\|pnl_summary` | AI-friendly named queries. |
| `POST /v1/command`   | Intent-based: `refresh_prices`, `add_trade`, etc. |
| `POST /v1/trades`    | Body: single trade or `{ "trades": [ ... ] }`. Returns 201. |
| `POST /v1/refresh`   | Trigger price refresh; 202 Accepted. |
| `GET /v1/docs`       | API documentation (Markdown). |

Full spec: `docs/API.md` or `GET /v1/docs` when the API is running. Roadmap: `docs/ROADMAP.md`.

Example:

```bash
curl -s http://localhost:38472/v1/health
curl -s "http://localhost:38472/v1/portfolio?user=Default"
curl -s "http://localhost:38472/v1/positions?user=Default"
curl -s -X POST http://localhost:38472/v1/trades -H "Content-Type: application/json" -d '{"asset":"BTC","type":"BUY","quantity":0.1,"price":50000,"exchange":"Binance","source":"crank"}'
```

## CLI

The **fuck-you-money-cli** executable reads and writes the same JSON files (no app required).

- **Data directory**: Set `FUCK_YOU_MONEY_DATA_DIR` or use `--data-dir <path>`. Default is the app’s Application Support directory; use `--data-dir .` to use the current directory (e.g. repo root).

**Commands:**

| Command | Description |
|---------|-------------|
| `list-trades [--user Default]` | Print trades (JSON). |
| `add-trade --asset BTC --type BUY --quantity 0.5 --price 40000 [--user Default] [--account-id <id>]` | Append one trade and save. |
| `import-trades --file path.json [--user Default]` | Merge trades from a JSON file. |
| `export-trades [--user Default] [--output path]` | Write trades JSON. |
| `portfolio [--user Default]` | Portfolio summary (total value, PnL, ROI) using cached prices. |
| `positions [--user Default] [--output path]` | Per-asset positions as JSON (same shape as GET /v1/positions). |
| `refresh [--notify-app]` | Fetch prices and update cache. Use `--notify-app` to tell the running app to reload. |
| `restore-backup --file path [--data-dir <path>] [--notify-app]` | Restore users, data, and price history from a backup file. |

**Notify running app:** Use `--notify-app` with `add-trade`, `import-trades`, `refresh`, or `restore-backup` (tries `POST /v1/refresh` first; else `fuckyoumoney://refresh`). Optional: `--api-port 38472`.

Example (repo root):

```bash
swift build
.build/debug/fuck-you-money-cli --data-dir . --user Default list-trades
.build/debug/fuck-you-money-cli --data-dir . add-trade --asset BTC --type BUY --quantity 0.1 --price 50000
.build/debug/fuck-you-money-cli --data-dir . portfolio
.build/debug/fuck-you-money-cli --data-dir . positions --output positions.json
```

After the CLI writes data, if the app is open use `fuckyoumoney://refresh` or `POST /v1/refresh` (if the API is enabled) so the app reloads.
