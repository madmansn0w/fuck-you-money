# Fuck You Money Roadmap

## Completed (Pillars 1–6 + polish)

- **API & docs**: GET /v1/positions, /v1/trades, /v1/analytics/summary, /v1/docs; JSON error bodies; request logging.
- **Webhooks**: Configurable URL; POST on trade added and portfolio refresh.
- **Binance & Crank**: Binance/Binance Testnet in fees and API keys; Trade `source`/`strategy_id`; Recent API activity on Dashboard.
- **Structured AI**: GET /v1/query, POST /v1/command; Assistant tab (portfolio, positions, pnl, refresh).
- **Analytics**: Benchmark vs BTC, realized/rolling volatility, scenario (what-if), tax lots + CSV export, tax export by year, correlation matrix API + Dashboard placeholder.
- **Alerts**: Rules (portfolio value, asset % down 24h, drawdown, asset % of portfolio); evaluate on refresh; in-app + webhook/notification.
- **Polish**: Getting started + Open API docs in Settings; Backup all data (timestamped JSON); README and API docs updated.
- **CLI**: `positions` command (JSON, same shape as GET /v1/positions).

---

## Roadmap: New features

### Assets tab

Dedicated **Assets** tab with per-asset information for held (and optionally watched) assets.

| # | Feature | Description | Status |
|---|---------|-------------|--------|
| 1 | **Price since market open + % change** | Per-asset: price at market open and % change. **Done:** Price & 24h change (CoinGecko) as proxy. | Done (24h proxy) |
| 2 | **Trading volume 24h, market cap, FDV** | 24h volume; market cap; FDV; volume/market cap; circulating supply. **Done:** CoinGecko on Assets tab. | Done |
| 3 | **Asset performance** | Returns over 1W, 1M, 3M, 6M, YTD, 1Y. **Done:** 1W, 14d, 1M, 2M, ~6M, 1Y from CoinGecko; YTD from Jan 1 historical price (CoinGecko history API) on Assets tab. | Done |
| 4 | **Technicals (sentiment)** | Strong Sell … Strong Buy. **Done:** Community sentiment from CoinGecko (votes up %) on Assets tab. | Done (community) |
| 5 | **Asset-related info** | General asset info (description, links, supply stats). **Done:** Name, description (truncated), homepage link from CoinGecko on Assets tab. | Done |

### Dashboard: News & macro

News and macro items as Dashboard blocks (centered on relevance to crypto).

| # | Feature | Description | Status |
|---|---------|-------------|--------|
| 6 | **Crypto news (Bitcoin-centered)** | Feed of crypto news with emphasis on Bitcoin. **Done:** CoinDesk RSS on Dashboard (headlines + links). | Done |
| 7 | **Economic & financial news** | Government and private-company economic/financial news. **Done:** BBC Business RSS on Dashboard. | Done |
| 8 | **Noteworthy news impacting crypto** | Curated or filtered items that may move crypto. **Done:** Filtered view from crypto + economic feeds (Fed, rate, SEC, crypto, inflation, etc.). | Done |

### Additional ideas

| # | Feature | Description | Status |
|---|---------|-------------|--------|
| 9 | **Correlation heatmap (live)** | Show correlation matrix when per-asset historical return series are available. **Done:** Price history stored in `price_history.json` on each refresh (last 365 days per asset); Dashboard heatmap and GET /v1/analytics/correlation return real matrix when ≥2 held assets have ≥2 common dates. | Done |
| 10 | **GET /v1/analytics/correlation** | API endpoint for correlation matrix. **Done:** Returns assets + matrix when price history has ≥2 common dates for ≥2 held assets; otherwise empty + message. | Done |
| 11 | **Watchlist** | Non-held assets on Assets tab. **Done:** Watchlist (Add/Remove) in Assets tab; picker shows held + watchlist; market data for any selected. | Done |
| 12 | **Asset search & add to portfolio** | Search coins by name/symbol; quick-add to portfolio. **Done:** "Add trade…" on Assets tab opens Transactions with asset pre-filled; Transactions asset list includes watchlist + portfolio. | Done |
| 13 | **Fear & Greed / market sentiment** | Single metric or small widget. **Done:** Fear & Greed Index (alternative.me) on Dashboard (value + classification). | Done |
| 14 | **Notifications for news** | Optional alerts when “noteworthy” or high-impact news is published. **Done:** Settings → Alerts: Notify when new noteworthy news appears; macOS notification for up to 3 new headlines per Dashboard load/refresh; notified links persisted to avoid repeats. | Done |

### Polymarket tab

Dedicated **Polymarket** tab for prediction-market discovery, trading, arbitrage, and scalping. Strategies are translated into inferable **data** (lists, scores, filters), **actions** (links, future order placement), and **information** (copy, tooltips, docs).

| # | Feature | Description | Status |
|---|---------|-------------|--------|
| 15 | **Crypto markets discovery** | List/filter Polymarket events and markets by crypto-related tags or keywords (e.g. Bitcoin, Ethereum); show event title, market outcomes, current prices. Data: Gamma API (events, markets, search). **Done:** Polymarket tab loads crypto events via Gamma; pull-to-refresh; "View on Polymarket" links. | Done |
| 16 | **Polymarket trading** | View order book, spread, last price per market. Later: wallet connection and place/cancel orders (CLOB + wallet). **Done (read-only):** Order book, spread, midpoint per market (Scalping section); Open on Polymarket links; fee note in footer. Backlog: wallet + place/cancel orders. | Done (read) |
| 17 | **Arbitrage opportunities** | Intra-market: show markets where YES + NO &lt; $1 (arb gap = 1 − yes_price − no_price). Combinatorial: multi-outcome sum &lt; $1. Endgame: filter by resolution date soon + high probability (95–99%), show implied yield. **Done:** Intra-market arb list; Combinatorial: section for markets with 3+ outcomes where sum of prices &lt; $1 (gap %); Endgame: outcomes ≥95% resolving within 14 days with implied yield. | Done |
| 18 | **Scalping / spread view** | Order book depth, spread, midpoint; optional "scalp opportunity" when spread exceeds configurable threshold (profitable after fees). **Done:** CLOB order book per market; Refresh book; "Notify when spread &gt; X%" threshold + Alert toggle (local notification when spread ≥ threshold on load/refresh). Fee note in footer. | Done |
| 19 | **Systematic NO farming** | List markets with high YES price and resolution date; show "NO value" or edge estimate (many prediction markets resolve NO). **Done:** Polymarket tab lists high-YES (≥65%) markets with end date; "NO value" blurb in footer. | Done |
| 20 | **Strategy breakdown (education)** | In-tab copy or collapsible section: short descriptions of intra-market arb, combinatorial arb, endgame arb, spread farming, systematic NO; links to Polymarket docs or external guides. Info only. **Done:** Polymarket tab has collapsible "Ways to make money" + Polymarket docs link. | Done |
| 21 | **Cross-platform arbitrage** | Same outcome at different price on Polymarket vs Kalshi etc. **Done (link):** Strategy breakdown includes Cross-platform row + links to Polymarket docs and Kalshi markets for manual comparison. Full integration out of scope for v1. | Done (link) |

---

## Backlog / future

- (None at this time.)

## Implementation notes

- **Data sources**: Asset metrics (volume, market cap, FDV, supply, performance) and “market open” typically require a data provider (e.g. CoinGecko, CoinMarketCap, or exchange APIs). Technicals/sentiment may come from a dedicated API or be computed locally.
- **News**: Crypto and economic news can be wired via RSS, NewsAPI, or crypto-specific feeds; “noteworthy” can be a filtered view or tagged subset.
- **Assets tab**: New tab `assets` in the app; layout: asset selector (or list of held assets) and sections for price since open, metrics, performance, technicals, and general info.
- **Dashboard news**: Three blocks (crypto news, economic/financial news, noteworthy for crypto); each can start as a placeholder with “Configure news source” or similar until feeds are integrated.
- **Polymarket**: Public Gamma API (events, markets, search, tags) and CLOB API (prices, order book, prices-history) are read-only and require no auth for discovery. Trading requires CLOB client (e.g. py-clob-client / @polymarket/clob-client) and wallet (USDC.e, POL for gas). Optional **PolymarketService** in app or Core for Gamma/CLOB HTTP calls; Settings can later add Polymarket section (base URLs, optional wallet/API keys).

---

## Changelog

- **2025-02**: Roadmap created; pillars 1–6 completed; Assets tab and Dashboard news features added to roadmap; correlation and extras listed.
- **2025-02**: #12 Done: Add trade from Assets tab (opens Transactions with asset pre-filled; Transactions asset picker includes watchlist + portfolio). Dashboard: Refresh button and pull-to-refresh for news + Fear & Greed.
- **2025-02**: #14 Done: Notifications for noteworthy news. Settings → Alerts: toggle "Notify when new noteworthy news appears"; on Dashboard load/refresh, new items (by link) trigger macOS notifications (up to 3 per run); notified links stored (last 80) to avoid duplicates.
- **2025-02**: #9 Done (UI): Correlation heatmap on Dashboard. When `AppState.loadCorrelationMatrix()` returns data (once per-asset return series are stored), Dashboard shows N×N heatmap (red/white/green); otherwise placeholder. README: correlation heatmap, Add trade from Assets, Alerts & news notifications.
- **2025-02**: #9 Done (data): Price history: Core `price_history.json` + load/save; record on every refresh (today’s price per asset, trim to 365 days); build aligned daily return series and compute correlation in `loadCorrelationMatrix` / `correlationMatrixSync`; API GET /v1/analytics/correlation returns real assets+matrix when data available. Unit tests: PriceHistoryStorageTests.
- **2025-02**: CLI `refresh` records price history; backup includes `price_history`; README updated (data dir, correlation API, backup).
- **2025-02**: Assets tab YTD: performance chip from Jan 1 → current price (fetchHistoricalPrice). Unit tests: AssetMarketDataTests (volumeToMarketCap).
- **2025-02**: Restore from backup. Settings → Data → "Restore from backup…" opens file picker; confirm alert; restores users, data_by_user, price_history to storage and reloads app state. Backup format: price_history optional for older backups.
- **2025-02**: Restore UX: confirmation alert shows backup timestamp (exported_at). CLI: restore-backup --file &lt;path&gt; [--data-dir] [--notify-app]. docs/API.md: Backup file format section.
- **2025-02**: Polymarket tab added to roadmap. New section "Polymarket tab" with feature table (crypto markets discovery, trading, arbitrage, scalping, systematic NO, strategy breakdown, cross-platform arb); strategies mapped to data/actions/info. Tab registered in app with placeholder view.
- **2025-02**: Polymarket tab implementation. FuckYouMoneyCore: PolymarketService + PolymarketEvent/PolymarketMarket (Gamma API). Tab: crypto markets list (pull-to-refresh), intra-market arb opportunities, scalping placeholder, strategy breakdown (collapsible + docs link). #15, #17 (intra), #20 Done. Settings: Polymarket section (optional Gamma/CLOB base URLs).
- **2025-02**: Polymarket CLOB + Systematic NO. Core: OrderBookSnapshot, fetchOrderBook(tokenId:), PolymarketMarket.clobTokenIds. Tab: Scalping section shows market selector and live order book (spread, midpoint, top 5 bids/asks). Systematic NO section: high-YES (≥65%) markets with end date and Open link. #18 (read), #19 Done.
- **2025-02**: Polymarket Endgame arb + Scalp alerts. Tab: Endgame arbitrage section (outcome ≥95%, resolves within 14 days; implied yield). Scalping: "Refresh book", threshold % + "Alert" toggle; local notification when spread ≥ threshold on load/refresh. #17 (endgame), #18 (scalp alerts) Done.
- **2025-02**: Roadmap #16 clarified: Polymarket trading marked Done (read-only) for order book/spread/midpoint and Open links; backlog remains wallet + place/cancel orders.
- **2025-02**: Polymarket combinatorial arbitrage (#17). Tab: "Combinatorial arbitrage" section for markets with 3+ outcomes where sum of outcome prices &lt; $1; shows outcome breakdown, sum, gap %, Open link.
- **2025-02**: Cross-platform arb (#21). Strategy breakdown: Cross-platform arbitrage row + links to Polymarket docs and Kalshi markets for manual comparison.
- **2025-02**: Polymarket unit tests. FuckYouMoneyCoreTests: PolymarketTests (arbGap, OrderBookSnapshot spread/midpoint, decodeOrderBook, decodeEvents).
- **2025-02**: Project is Swift-only. Python app (crypto-tracker.py), package (src/crypto_tracker), pyproject.toml, and Python tests removed. README and .gitignore updated.
