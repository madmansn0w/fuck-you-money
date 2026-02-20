# CryptoTracker Local API (v1)

Base URL: `http://localhost:<port>` (port configurable in Settings; default 38472).

Optional future auth: API key in header (not required for localhost).

---

## Endpoints

### GET /v1/health

Returns empty JSON `{}`. Use for liveness checks.

**Response:** `200 OK`, `application/json`

---

### GET /v1/portfolio

Portfolio-level summary for a user.

**Query parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `user`    | No       | Username; defaults to current app user. |

**Response:** `200 OK`, `application/json`

```json
{
  "total_value": 12345.67,
  "total_pnl": 1234.56,
  "roi_pct": 11.1,
  "realized_pnl": 500.0,
  "unrealized_pnl": 734.56
}
```

**Errors:** `404` unknown user; `500` load failed.

---

### GET /v1/positions

Per-asset positions for a user (and optionally filtered by account or group). Enables bots (e.g. Crank) to size orders or enforce risk from the tracker state.

**Query parameters:**

| Parameter     | Required | Description |
|---------------|----------|-------------|
| `user`        | No       | Username; defaults to current user. |
| `account_id`  | No       | Filter to this account. |
| `group_id`    | No       | Filter to accounts in this group. |

**Response:** `200 OK`, `application/json`

```json
[
  {
    "asset": "BTC",
    "qty": 0.5,
    "cost_basis": 20000.0,
    "current_value": 22500.0,
    "unrealized_pnl": 2500.0,
    "realized_pnl": 100.0
  }
]
```

**Errors:** `404` unknown user; `500` load failed.

---

### GET /v1/trades

List trades with optional filters. Pagination via `since` and `limit`.

**Query parameters:**

| Parameter     | Required | Description |
|---------------|----------|-------------|
| `user`        | No       | Username; defaults to current user. |
| `account_id`  | No       | Filter to this account. |
| `asset`       | No       | Filter to this asset. |
| `since`       | No       | Return trades with `date >= since` (ISO or comparable string). |
| `limit`       | No       | Max number of trades to return (newest first). |

**Response:** `200 OK`, `application/json` — array of trade objects (id, date, asset, type, price, quantity, exchange, order_type, fee, total_value, account_id, …).

**Errors:** `404` unknown user; `500` load failed.

---

### POST /v1/trades

Add one or more trades. Bots (e.g. Crank) should POST each fill here so the app is the canonical ledger.

**Body (single trade):**

```json
{
  "asset": "BTC",
  "type": "BUY",
  "quantity": 0.1,
  "price": 43000.0,
  "exchange": "Binance",
  "order_type": "limit",
  "fee": 0.43,
  "date": "2025-02-19T12:00:00.000Z",
  "account_id": "<uuid>"
}
```

**Body (batch):** `{ "trades": [ { ... }, { ... } ] }`

Optional fields: `exchange` (default `"Wallet"`), `order_type`, `fee`, `date` (default now), `account_id` (default first account). Optional for Crank attribution: `source` (e.g. `"crank"`), `strategy_id` (e.g. `"grid_btcusdt"`).

**Response:** `201 Created`, `application/json` — array of created trade objects.

**Errors:** `400` invalid JSON or missing required fields.

---

### GET /v1/analytics/summary

Portfolio-level analytics: total value, ROI, P&L, max drawdown, Sharpe (if available).

**Query parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `user`    | No       | Username; defaults to current user. |

**Response:** `200 OK`, `application/json`

```json
{
  "total_value": 12345.67,
  "roi_pct": 11.1,
  "realized_pnl": 500.0,
  "unrealized_pnl": 734.56,
  "max_drawdown": 1200.0,
  "max_drawdown_pct": 10.0,
  "sharpe_ratio": 1.2,
  "sortino_ratio": 1.5,
  "win_rate_pct": 55.0,
  "total_trades": 42,
  "winning_trades": 23,
  "losing_trades": 19
}
```

**Errors:** `404` unknown user; `500` load failed.

### GET /v1/analytics/correlation

Pairwise Pearson correlation matrix of **daily returns** for held assets. Uses stored price history (`price_history.json`); data is recorded on each **Refresh prices** (last 365 days per asset).

- When at least two held assets have at least two **common dates** in history, returns `assets` (ordered symbols) and symmetric N×N `matrix` (1.0 on diagonal).
- Otherwise returns empty `assets` and `matrix` with an explanatory `message` (e.g. refresh on at least two different days for two or more held assets).

**Query parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `user`    | No       | Username; defaults to current user. |

**Response:** `200 OK`, `application/json`

With data:

```json
{
  "message": "Pairwise Pearson correlation of daily returns (from stored price history).",
  "assets": ["BTC", "ETH", "SOL"],
  "matrix": [[1.0, 0.85, 0.72], [0.85, 1.0, 0.78], [0.72, 0.78, 1.0]]
}
```

Without sufficient history:

```json
{
  "message": "Insufficient price history: refresh prices on at least 2 days for 2+ held assets to see the correlation matrix.",
  "assets": [],
  "matrix": []
}
```

**Errors:** `500` internal error.

---

### POST /v1/refresh

Trigger a price refresh. Returns immediately; refresh runs asynchronously.

**Response:** `202 Accepted`, no body.

---

### GET /v1/docs

Returns this API documentation in Markdown format.

**Response:** `200 OK`, `text/markdown`

---

### GET /v1/query (AI-friendly)

Named queries returning JSON. For AI agents or Crank: predictable way to ask "what's my exposure?" or "what's my P&L?".

**Query parameters:**

| Parameter     | Required | Description |
|---------------|----------|-------------|
| `q`           | Yes      | `portfolio` (same as /v1/portfolio), `positions` (per-asset; optional `asset=` to filter), `pnl_summary` (optional `period=7d` or `period=30d` for realized P&L in that window). |
| `user`        | No       | Username; defaults to current user. |
| `account_id`  | No       | Filter to this account (positions/query). |
| `group_id`    | No       | Filter to this group (positions/query). |
| `asset`       | No       | Filter positions to this asset (only when `q=positions`). |
| `period`      | No       | For `q=pnl_summary`: `7d` or `30d` to include `realized_pnl_period` in the response. |

**Response:** `200 OK`, `application/json` — shape depends on `q` (portfolio blob, array of positions, or pnl summary with total_value, realized_pnl, unrealized_pnl, realized_pnl_period?).

**Errors:** `400` unknown query; `404` unknown user; `500` load failed.

---

### POST /v1/command (AI-friendly)

Intent-based payloads: AI as a client of the API without NLU in the app.

**Body:**

```json
{ "intent": "refresh_prices" }
```

or

```json
{ "intent": "add_trade", "params": { "asset": "BTC", "type": "BUY", "quantity": 0.01, "price": 43000, "exchange": "Binance", "fee": 0, "account_id": "...", "source": "crank", "strategy_id": "grid_btcusdt" } }
```

**Response:** `200 OK` or `201 Created`, `application/json`: `{ "success": true }` or `{ "success": true, "trade": { ... } }`.

**Errors:** `400` invalid JSON, missing intent, or unknown intent.

---

## Backup file format

The app **Backup all data…** (and optional **Restore from backup…**) and the CLI **restore-backup --file** use a single JSON file with this shape:

| Field | Type | Description |
|-------|------|-------------|
| `exported_at` | string | ISO8601 timestamp when the backup was created. |
| `users` | array of strings | List of usernames. |
| `data_by_user` | object | Map username → full `AppData` (trades, settings, accounts, account_groups, etc.). Same structure as `crypto_data_<user>.json`. |
| `price_history` | object (optional) | Map asset symbol → map date `"yyyy-MM-dd"` → price (number). Used for correlation heatmap. Older backups may omit this. |

Restore (app or CLI) overwrites `users.json`, each `crypto_data_<user>.json`, and `price_history.json` with the backup contents.

---

## Out of scope (app-only)

**Polymarket:** Prediction-market data (events, order book, arbitrage views) is loaded in the app from Polymarket’s Gamma API and CLOB API. It is not exposed by this local HTTP API. Optional base URLs are configurable in **Settings → Polymarket**.

---

## Error format

On 4xx/5xx the body is JSON: `{ "error": "human-readable message" }`.
