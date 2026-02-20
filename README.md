# Crypto PnL Tracker

Desktop crypto portfolio tracker with support for multiple users, accounts, cost basis methods (FIFO/LIFO/average), and a Tkinter UI.

## Install

From the repo root:

```bash
pip install -e .
```

Optional (for tests):

```bash
pip install -e ".[dev]"
```

## Run the app

**From repo root (no install):**

```bash
python crypto-tracker.py
```

The script adds `src` to `PYTHONPATH` so the package is found.

**After install:**

```bash
python -m crypto_tracker
# or
crypto-tracker
```

## Use the core API (no GUI)

For scripts or a future CLI you can use the core API without starting the desktop UI:

```python
from crypto_tracker.app import load_portfolio, list_trades, list_users

users = list_users()
data = load_portfolio(users[0] if users else "Default")
trades = list_trades(data)
```

Data files live in the project root by default: `crypto_data_<username>.json`, `users.json`, `price_cache.json`.

## Tests

**Python:**

```bash
# From repo root (no install)
PYTHONPATH=src pytest tests/ -v

# Or after: pip install -e .
pytest tests/ -v
```

**Swift:**

```bash
swift test
```

## Layout

- `src/crypto_tracker/` – main package
  - `app.py` – entrypoint and core API (`load_portfolio`, `list_trades`, `list_users`)
  - `config/` – constants and paths
  - `theming/` – styles and fonts
  - `services/` – storage, pricing, metrics
  - `models/` – typed structures
  - `ui/` – dialogs, utils, main window (legacy UI in `legacy_crypto_tracker.py`)

---

## External integration (Swift app and CLI)

A native **SwiftUI macOS app** and **CLI** live alongside the Python app. They use the same JSON data format so you can share files between Python and Swift. Other apps and scripts can drive the Swift app via URL scheme or optional local HTTP API.

### Swift app

**App overview:** The main window has a **sidebar** (accounts and groups), a **summary panel** (portfolio totals, portfolio 24h change, per-asset cards with qty/value/P&L/24h %, open and closed positions), and a **detail area** with multiple tabs. The tabs are **Dashboard** (KPI cards, trading analytics, scenario, **correlation heatmap** when per-asset return series are available, Fear & Greed Index, crypto + economic RSS news, noteworthy-filtered news, tax lots, benchmark), **Trading**, **Transactions**, **Charts**, **Assets** (per-asset: price & 24h, market metrics, performance, technicals/sentiment, asset info from CoinGecko; watchlist; "Add trade…" opens Transactions with asset pre-filled), **Assistant** (exchange balances and order UI; Kraken, Bitstamp, Binance, Binance Testnet), **Transactions** (add, edit, remove trades; filters and list), **Charts**, and **Assistant** (plain-language portfolio queries) (analytics: cumulative P&L, equity curve, drawdown, asset allocation, realized P&L by asset, monthly/quarterly P&L, trade volume, fees, cost vs value, ROI %, win/loss, profit factor, by-exchange views, deposits/withdrawals, net flow, rolling Sharpe, and more). Each chart has its own **time range** (1D, 1W, 1M, 3M, 6M, 1Y, All) or **aggregation** (Monthly/Quarterly) where relevant; these choices **persist across sessions**. The **Polymarket** tab shows crypto prediction markets (Gamma), intra-market and endgame arbitrage, CLOB order book with spread alerts, and systematic NO farming. You can **reorder the tabs** in **Settings → Tab order** (Move Up / Move Down); the order is saved.

- **Build**: Open `CryptoTrackerApp/CryptoTrackerApp.xcodeproj` in Xcode. If the project was opened without the Swift package (to avoid crashes), add it: **File → Add Package Dependencies… → Add Local…** and select the **repo root** (the folder containing `Package.swift`). Add the **CryptoTrackerCore** product to the CryptoTrackerApp target. See `CryptoTrackerApp/ADD_PACKAGE.md` for step-by-step instructions. Then select the **CryptoTrackerApp** scheme and Product → Run (⌘R).
- **Data directory**: By default the app uses `~/Library/Application Support/CryptoTracker/` for `crypto_data_<user>.json`, `users.json`, `price_cache.json`, and `price_history.json`. The last stores daily prices per asset (recorded on each **Refresh prices**; used for the Dashboard correlation heatmap and GET /v1/analytics/correlation). In **Settings → Data** you can choose **Use existing folder…** (e.g. your repo root or a folder with Python data files) so both Python and Swift use the same files; avoid running both apps while writing.
- **Assistant tab**: Plain-language queries (e.g. "portfolio", "positions", "pnl", "refresh") with built-in answers; no LLM required.
- **Backup**: **Settings → Data → Backup all data…** exports all users’ data and price history as a timestamped JSON file. **Restore from backup…** (same section) replaces all data with a chosen backup file (users, trades, settings, price history).
- **Alerts & news**: **Settings → Alerts** – enable portfolio/price/drawdown alerts and **Notify when new noteworthy news appears** (macOS notifications for new Fed, rates, SEC, crypto-style headlines when Dashboard news is loaded or refreshed).

### URL scheme

The Swift app registers the `cryptotracker` URL scheme. Use it from Terminal, Shortcuts, or Automator (e.g. when the app is running):

- **Activate app**: `open "cryptotracker://open"`
- **Refresh prices**: `open "cryptotracker://refresh"`
- **Add one trade**:  
  `open "cryptotracker://add-trade?user=Default&asset=BTC&type=BUY&quantity=0.5&price=40000&fee=20&exchange=Bitstamp"`  
  Optional query params: `user`, `asset`, `type`, `quantity`, `price`, `fee`, `total_value`, `exchange`, `account_id`, `date` (ISO or app format).

Only use these URLs when the app is running (or they may launch the app and then handle the action).

### Local HTTP API (optional)

In the Swift app **Settings → Local API** you can enable a small HTTP server on localhost. Default port: **38472**. Bind to localhost only; no authentication (suitable for single-user Mac). Optional **Webhook URL**: the app POSTs to that URL when trades are added or portfolio is refreshed (e.g. for Crank or Slack). When the API is on, **Open API docs in browser** opens the full Markdown spec at `GET /v1/docs`.

| Method / path        | Description |
|----------------------|-------------|
| `GET /v1/health`     | 200 OK – check if the app is listening. |
| `GET /v1/portfolio?user=Default` | JSON: `total_value`, `total_pnl`, `roi_pct`, `realized_pnl`, `unrealized_pnl`. |
| `GET /v1/positions`  | Per-asset positions (optional `user`, `account_id`, `group_id`). |
| `GET /v1/trades`     | List trades (optional `user`, `account_id`, `asset`, `since`, `limit`). |
| `GET /v1/analytics/summary` | Portfolio metrics + max drawdown, Sharpe, volatility, win rate, etc. |
| `GET /v1/analytics/correlation` | Pairwise daily-return correlation for held assets (from stored price history; refresh on 2+ days for data). |
| `GET /v1/query?q=portfolio|positions|pnl_summary` | AI-friendly named queries (optional `asset`, `period=7d|30d`). |
| `POST /v1/command`   | Intent-based: `{ "intent": "refresh_prices" }` or `{ "intent": "add_trade", "params": { ... } }`. |
| `POST /v1/trades`    | Body: single trade `{ "asset", "type", "quantity", "price", ... }` or `{ "trades": [ ... ] }`. Optional `source`, `strategy_id` for Crank. Returns 201 + created trade(s). |
| `POST /v1/refresh`   | Trigger price refresh; returns 202 Accepted. |
| `GET /v1/docs`       | API documentation (Markdown). |

Full API spec: see `docs/API.md` in the repo or call `GET /v1/docs` when the API is running. Planned features and roadmap: see `docs/ROADMAP.md`.

Example:

```bash
curl -s http://localhost:38472/v1/health
curl -s "http://localhost:38472/v1/portfolio?user=Default"
curl -s "http://localhost:38472/v1/positions?user=Default"
curl -s -X POST http://localhost:38472/v1/trades -H "Content-Type: application/json" -d '{"asset":"BTC","type":"BUY","quantity":0.1,"price":50000,"exchange":"Binance","source":"crank"}'
```

### CLI tool

The **crypto-tracker-cli** executable is built from the same Swift package as the app. It reads and writes the same JSON files (no app required).

- **Build**: From repo root run `swift build`; the binary is `.build/debug/crypto-tracker-cli` (or `release` with `-c release`).
- **Data directory**: Set `CRYPTO_TRACKER_DATA_DIR` or use `--data-dir <path>`. Default is the app’s Application Support directory when not set; use `--data-dir .` to use the current directory (e.g. repo root with `crypto_data_default.json`).

**Commands:**

| Command | Description |
|---------|-------------|
| `list-trades [--user Default]` | Print trades (JSON). |
| `add-trade --asset BTC --type BUY --quantity 0.5 --price 40000 [--user Default] [--account-id <id>]` | Append one trade and save. |
| `import-trades --file path.json [--user Default]` | Merge trades from a JSON file (same format as export). |
| `export-trades [--user Default] [--output path]` | Write trades JSON. |
| `portfolio [--user Default]` | Print portfolio summary (total value, PnL, ROI) using cached prices. |
| `positions [--user Default] [--output path]` | Per-asset positions as JSON (same shape as GET /v1/positions). |
| `refresh [--notify-app]` | Fetch prices and update cache. Use `--notify-app` to tell the running Swift app to reload. |
| `restore-backup --file path [--data-dir <path>] [--notify-app]` | Restore users, data, and price history from a backup JSON file. |

**Notify running app:** Use `--notify-app` with `add-trade`, `import-trades`, `refresh`, or `restore-backup` to tell the Swift app to reload (tries HTTP `POST /v1/refresh` first; if the API is disabled, opens `cryptotracker://refresh`). Optional: `--api-port 38472` to match the app’s API port.

Example (repo root, Python-style data files):

```bash
swift build
.build/debug/crypto-tracker-cli --data-dir . --user Default list-trades
.build/debug/crypto-tracker-cli --data-dir . add-trade --asset BTC --type BUY --quantity 0.1 --price 50000
.build/debug/crypto-tracker-cli --data-dir . portfolio
.build/debug/crypto-tracker-cli --data-dir . positions
.build/debug/crypto-tracker-cli --data-dir . positions --output positions.json
```

After the CLI writes data, if the Swift app is open you can send `cryptotracker://refresh` or call `POST /v1/refresh` (if the local API is enabled) so the app reloads and shows the new data.
