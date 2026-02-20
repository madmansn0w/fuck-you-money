"""
Crypto PnL Tracker Application for macOS

A GUI application for tracking cryptocurrency trades, calculating P&L, ROI,
and projections with support for multiple exchanges and cost basis methods.
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from tkinter.constants import W, EW, E
import ttkbootstrap as tb
from ttkbootstrap.constants import SUCCESS, DANGER, PRIMARY, INFO, SECONDARY
import json
import os
import uuid
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple
import requests

from crypto_tracker.config.constants import (
    USERS_FILE,
    DATA_FILE,
    PRICE_CACHE_FILE,
    COINGECKO_API_URL,
    DEFAULT_EXCHANGES,
    COMMON_ASSETS,
    TRANSACTION_ASSETS,
    TRADE_TYPES_ALL,
    TRADE_TYPES_CRYPTO,
    TRADE_TYPES_USD,
    NON_INVESTMENT_TYPES,
)
from crypto_tracker.theming.style import (
    APPLE_FONT_FAMILY,
    APPLE_FONT_DEFAULT,
    APPLE_COLOR_PROFIT,
    APPLE_COLOR_LOSS,
    APPLE_SPACING_SMALL,
    APPLE_SPACING_MEDIUM,
    APPLE_SPACING_LARGE,
    APPLE_SPACING_XLARGE,
    APPLE_PADDING,
    APPLE_BORDER_RADIUS,
    MAX_SIDEBAR_WIDTH,
    MAX_SUMMARY_WIDTH,
    SUMMARY_PAD,
    SUMMARY_OUTER_PAD,
    SUMMARY_CONTENT_PADX,
    SUMMARY_SECTIONS_WIDTH,
    SUMMARY_VALUE_FONT,
    SUMMARY_DESC_FONT,
    SUMMARY_DESC_COLOR,
    setup_styles,
)
from crypto_tracker.ui.utils import bind_mousewheel_recursive as _bind_mousewheel_recursive, color_for_value
from crypto_tracker.ui import dialogs as ui_dialogs
from crypto_tracker.services import storage
from crypto_tracker.services import pricing as pricing_service
from crypto_tracker.services import metrics as metrics_service

# Thin wrappers so UI can show messagebox on I/O errors; rest delegate to storage/pricing
def get_user_data_file(username: str) -> str:
    return storage.get_user_data_file(username)


def load_users() -> List[str]:
    return storage.load_users()


def save_users(users: List[str]) -> None:
    try:
        storage.save_users(users)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving users: {e}")


def add_user(username: str) -> bool:
    return storage.add_user(username)


def delete_user(username: str) -> bool:
    return storage.delete_user(username)


def load_data(username: str = "Default") -> Dict:
    try:
        return storage.load_data(username)
    except Exception as e:
        messagebox.showerror("Data Load Error", f"Error loading data: {e}")
        return storage.get_default_data()


def save_data(data: Dict, username: str = "Default") -> None:
    try:
        storage.save_data(data, username)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving data: {e}")


def load_price_cache() -> Dict:
    return storage.load_price_cache()


def save_price_cache(cache: Dict) -> None:
    storage.save_price_cache(cache)


get_account_groups = storage.get_account_groups
get_accounts = storage.get_accounts
create_account_group_in_data = storage.create_account_group_in_data
create_account_in_data = storage.create_account_in_data
assign_trade_to_account = storage.assign_trade_to_account

try:
    from tkcalendar import DateEntry
    HAS_TKCALENDAR = True
except ImportError:
    HAS_TKCALENDAR = False
    DateEntry = None
try:
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    from matplotlib.ticker import FuncFormatter
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False
    Figure = None
    FigureCanvasTkAgg = None
    FuncFormatter = None

# Descriptor tooltips for summary Assets values (shown on single-click)
SUMMARY_ASSET_QTY_TOOLTIP = (
    "Quantity: Total units of this asset you hold (from buys and sells). "
    "Shown with 4 decimal places."
)
SUMMARY_ASSET_VALUE_TOOLTIP = (
    "Current value: Quantity × current market price. "
    "Reflects the current USD value of your holdings in this asset."
)
SUMMARY_ASSET_LIFETIME_PNL_TOOLTIP = (
    "Lifetime P&L: Realized gains/losses from closed positions plus unrealized on open positions. "
    "Green = profit, red = loss."
)
SUMMARY_ASSET_24H_TOOLTIP = (
    "24h %: Percentage change in the asset's price over the last 24 hours "
    "from the current market price source."
)

# Descriptor tooltips for top Summary metrics (shown on single-click)
SUMMARY_PORTFOLIO_VALUE_TOOLTIP = (
    "Portfolio value: Current total USD value of all assets plus cash in this scope. "
    "Computed from current market prices and cash balances."
)
SUMMARY_TOTAL_PNL_TOOLTIP = (
    "Total P&L: Realized P&L from closed trades plus unrealized P&L on open positions. "
    "Positive = profit, negative = loss."
)
SUMMARY_CAPITAL_IN_TOOLTIP = (
    "Capital in: Net USD you have deposited into this portfolio "
    "(all USD deposits minus all USD withdrawals)."
)
SUMMARY_ROI_TOOLTIP = (
    "ROI: Total P&L divided by capital in, expressed as a percentage. "
    "Shows overall return on your contributed capital."
)
SUMMARY_REALIZED_PNL_TOOLTIP = (
    "Realized P&L: Profit or loss from trades that have been fully closed (sells). "
    "Does not include open positions."
)
SUMMARY_UNREALIZED_PNL_TOOLTIP = (
    "Unrealized P&L: Profit or loss on your current open positions only, "
    "valued at current market prices."
)
SUMMARY_ROI_ON_COST_TOOLTIP = (
    "ROI on cost: Total P&L divided by total cost basis when there are no USD deposits. "
    "Useful for evaluating performance when funding is entirely in crypto."
)
SUMMARY_PORTFOLIO_24H_TOOLTIP = (
    "Portfolio 24h: Total change in USD value of the portfolio over the last 24 hours. "
    "Includes both price movement and any trades during that period."
)
SUMMARY_BTC_PNL_TOOLTIP = (
    "BTC P&L: Lifetime profit or loss for BTC positions in USD, "
    "using your accumulated BTC and the current BTC price."
)


# Sidebar (account groups pane) smaller typography
SIDEBAR_HEADER_FONT = ("SF Pro Display", 11, "bold")
SIDEBAR_BUTTON_WIDTH = 12

# Unicode symbols for assets (hover shows ticker)
ASSET_ICONS = {"BTC": "₿", "ETH": "Ξ", "USDC": "◎", "USDT": "₮", "SOL": "◎", "DOGE": "Ð"}


def _ordered_exchanges(fee_structure: Dict) -> List[str]:
    """Return exchange names with Bitstamp first, Wallet second, then rest sorted."""
    keys = list(fee_structure.keys())
    ordered = [x for x in ("Bitstamp", "Wallet") if x in keys]
    ordered.extend(sorted(x for x in keys if x not in ("Bitstamp", "Wallet")))
    return ordered if ordered else list(keys)


# Cost basis and portfolio metrics are in crypto_tracker.services.metrics
calculate_cost_basis_fifo = metrics_service.calculate_cost_basis_fifo
calculate_cost_basis_lifo = metrics_service.calculate_cost_basis_lifo
calculate_cost_basis_average = metrics_service.calculate_cost_basis_average


def compute_realized_pnl_per_trade(
    trades: List[Dict], method: str = "average"
) -> Dict[str, float]:
    """
    Compute realized P&L for each SELL trade (by cost basis method).

    Args:
        trades: List of trades (will be sorted by date).
        method: One of "average", "fifo", "lifo".

    Returns:
        Dict mapping trade id to realized P&L (only keys for SELL trades).
    """
    sorted_trades = sorted(trades, key=lambda t: t["date"])
    # Per-asset state: units_held, cost_basis. For fifo/lifo we'd need lots; here we do average only.
    units: Dict[str, float] = {}
    cost_basis: Dict[str, float] = {}
    result: Dict[str, float] = {}

    for trade in sorted_trades:
        asset = trade.get("asset", "")
        tid = trade.get("id", "")
        ttype = trade.get("type", "")
        if asset == "USD" or ttype not in ("BUY", "SELL", "Transfer"):
            if ttype == "SELL" and asset and tid:
                result[tid] = 0.0  # non-crypto SELL or unsupported
            continue

        if ttype in ("BUY", "Transfer"):
            qty = trade.get("quantity", 0) or 0
            cost = (trade.get("total_value") or 0) + (trade.get("fee") or 0)
            units[asset] = units.get(asset, 0) + qty
            cost_basis[asset] = cost_basis.get(asset, 0) + cost
            continue

        if ttype == "SELL":
            qty = trade.get("quantity", 0) or 0
            price = trade.get("price") or 0
            fee = trade.get("fee") or 0
            u = units.get(asset, 0)
            c = cost_basis.get(asset, 0)
            if u <= 0:
                result[tid] = 0.0
                continue
            # Average cost: cost of sold = (c/u) * min(qty, u)
            sold = min(qty, u)
            cost_per_unit = c / u
            cost_of_sold = cost_per_unit * sold
            proceeds = price * sold
            result[tid] = proceeds - cost_of_sold - fee
            units[asset] = u - sold
            cost_basis[asset] = c - cost_of_sold

    return result


def compute_buy_profit_per_trade(trades: List[Dict]) -> Dict[str, float]:
    """
    For each BUY trade, compute profit from price difference vs previous SELL of same asset:
    (previous_sell_price - buy_price) * quantity_bought.
    Only includes BUYs that have a prior SELL for that asset.

    Args:
        trades: List of trades (will be sorted by date).

    Returns:
        Dict mapping trade id to buy-profit in USD (only keys for BUY trades with a prior sell).
    """
    sorted_trades = sorted(trades, key=lambda t: t["date"])
    last_sell_price: Dict[str, float] = {}
    result: Dict[str, float] = {}

    for trade in sorted_trades:
        asset = trade.get("asset", "")
        tid = trade.get("id", "")
        ttype = trade.get("type", "")
        if asset == "USD":
            continue
        if ttype == "SELL":
            price = trade.get("price") or 0
            if price > 0:
                last_sell_price[asset] = price
            continue
        if ttype == "BUY" and asset in last_sell_price:
            buy_price = trade.get("price") or 0
            qty = trade.get("quantity") or 0
            if buy_price > 0 and qty > 0:
                result[tid] = (last_sell_price[asset] - buy_price) * qty
            continue

    return result


# --- Main Application Class ---
class CryptoTrackerApp(tb.Window):
    """Main application window for crypto PnL tracking."""

    def __init__(self):
        """Initialize the application."""
        super().__init__(themename="darkly")
        self.title("CryptoPnL Tracker")
        self.geometry("1280x800")
        self.minsize(1100, 700)

        # User State
        self.current_user = "Default"
        self.users = load_users()
        if not self.users:
            self.users = ["Default"]
            save_users(self.users)

        # Data State
        self.data = load_data(self.current_user)
        self.price_cache = load_price_cache()

        # Centralized ttk/ttkbootstrap styles (Apple-like look and feel)
        setup_styles(self)

        self.create_widgets()
        self._restore_window_layout()
        self.update_dashboard()
        # Single delayed sash apply so PanedWindow has real width (avoids flash from multiple restores)
        self.after(80, self._delayed_sash_apply)

        # Periodic market update (e.g. every 5 minutes)
        self._price_refresh_interval_ms = 5 * 60 * 1000
        self.after(self._price_refresh_interval_ms, self._schedule_price_refresh)

        # macOS specific improvements
        self.setup_macos_features()

    def _schedule_price_refresh(self):
        """Cron-like periodic refresh of market prices."""
        try:
            self.refresh_all_prices()
        except Exception:
            pass
        self.after(self._price_refresh_interval_ms, self._schedule_price_refresh)

    def setup_macos_features(self):
        """Setup macOS-specific features."""
        try:
            # Improve window appearance on macOS
            self.tk.call("::tk::unsupported::MacWindowStyle",
                        self._w, "style", "document", "closeBox collapseBox resizable")
        except:
            pass

    def _delayed_sash_apply(self) -> None:
        """Apply saved pane sash positions once after layout has real dimensions (reduces flash)."""
        try:
            self.update_idletasks()
            total = self.main_paned.winfo_width()
            if total >= self._min_sidebar + self._min_summary + self._min_content:
                self._apply_sash_positions(total)
        except (tk.TclError, AttributeError):
            pass

    def create_menu_bar(self):
        """Create macOS menu bar."""
        menubar = tk.Menu(self)
        self.config(menu=menubar)

        # File menu
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="File", menu=file_menu)
        file_menu.add_command(label="Export Trades...", command=self.export_trades)
        file_menu.add_command(label="Import Trades...", command=self.import_trades)
        file_menu.add_separator()
        file_menu.add_command(label="Quit", command=lambda: self._quit_with_save(), accelerator="Cmd+Q")

        # Edit menu
        edit_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Edit", menu=edit_menu)
        edit_menu.add_command(label="Settings...", command=self.show_preferences)

        # Accounts menu
        accounts_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Accounts", menu=accounts_menu)
        accounts_menu.add_command(label="Add Account to Group...", command=self.new_account_dialog)
        accounts_menu.add_command(label="Manage Accounts...", command=self.manage_accounts_dialog)

        # Users menu
        users_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Users", menu=users_menu)
        users_menu.add_command(label="New User...", command=self.add_user_dialog)
        users_menu.add_command(label="Manage Users...", command=self.manage_users_dialog)
        users_menu.add_separator()
        users_menu.add_command(label="Switch User...", command=self.switch_user_dialog)

        # View menu
        view_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="View", menu=view_menu)
        view_menu.add_command(label="Refresh Prices", command=self.refresh_all_prices)

        # Help menu
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Help", menu=help_menu)
        help_menu.add_command(label="About", command=self.show_about)

        # Bind keyboard shortcuts
        self.bind("<Command-q>", lambda e: self._quit_with_save())

    def create_widgets(self):
        """Create all UI widgets with three-column layout."""
        # Placeholder so menu Quit can reference it before panes exist
        self._quit_with_save = lambda: self.quit()
        # Create menu bar
        self.create_menu_bar()

        # Initialize selected account/group (before summary panel uses them)
        self.selected_group_id = None
        self.selected_account_id = None
        # Asset filter for metrics: None = all, "BTC" / "USDC" = single-asset view
        self.selected_asset_filter: Optional[str] = None
        # Profit column in transactions table: "USD" or "BTC"
        self.profit_display_currency = "USD"

        # Main container: resizable three columns via tk.PanedWindow (sash positions saved/restored)
        main_container = tb.Frame(self)
        main_container.pack(fill="both", expand=True, padx=0, pady=0)
        default_sidebar_w, default_summary_w = 220, 224  # summary ~30% narrower
        min_sidebar, min_summary, min_content = 180, 182, 400

        self.main_paned = tk.PanedWindow(main_container, orient=tk.HORIZONTAL, sashwidth=4, bg="#2b2b2b")
        self.main_paned.pack(fill="both", expand=True)

        self.main_container = main_container
        self.sidebar_frame = tk.Frame(self.main_paned, width=default_sidebar_w, bg="#2b2b2b")
        self.main_paned.add(self.sidebar_frame, minsize=min_sidebar, width=default_sidebar_w)
        self.create_account_groups_sidebar()

        self.summary_frame = tk.Frame(self.main_paned, width=default_summary_w, bg="#2b2b2b")
        self.main_paned.add(self.summary_frame, minsize=min_summary, width=default_summary_w)
        self.create_summary_panel()

        self.content_frame = tb.Frame(self.main_paned)
        self.main_paned.add(self.content_frame, minsize=min_content)
        self.create_content_area()
        self.minsize(900, 600)

        def _apply_sash_positions(total: int) -> bool:
            """Apply sash positions once. Uses saved positions or defaults (summary pane always visible)."""
            saved = self.data.get("settings", {}).get("pane_positions")
            if saved and len(saved) >= 2 and (saved[1] - saved[0]) >= min_summary:
                x0 = max(min_sidebar, min(int(saved[0]), total - min_summary - min_content))
                x1 = max(x0 + min_summary, min(int(saved[1]), total - min_content))
            else:
                x0, x1 = default_sidebar_w, default_sidebar_w + default_summary_w
            x0 = max(min_sidebar, min(x0, total - min_summary - min_content))
            x1 = max(x0 + min_summary, min(x1, total - min_content))
            if x1 <= x0:
                x1 = x0 + min_summary
            try:
                self.main_paned.sash_place(0, x0, 0)
                self.main_paned.sash_place(1, x1, 0)
                return True
            except tk.TclError:
                return False

        self._apply_sash_positions = _apply_sash_positions
        self._min_sidebar, self._min_summary, self._min_content = min_sidebar, min_summary, min_content

        def _restore_window_layout():
            geom = self.data.get("settings", {}).get("window_geometry")
            if geom:
                try:
                    self.geometry(geom)
                    w = self.winfo_width()
                    if w > 0 and w < min_sidebar + min_summary + min_content:
                        self.geometry(f"{min_sidebar + min_summary + min_content + 50}x{self.winfo_height() or 700}")
                except tk.TclError:
                    pass
            else:
                self.geometry("1200x700")
            self.update_idletasks()
            self.update()
            total = self.main_paned.winfo_width()
            if total >= min_sidebar + min_summary + min_content:
                _apply_sash_positions(total)

        self._restore_window_layout = _restore_window_layout

        def _save_window_layout():
            try:
                self.update_idletasks()
                geom = self.geometry()
                if geom:
                    self.data.setdefault("settings", {})["window_geometry"] = geom
                try:
                    pos0 = self.main_paned.sash_coord(0)
                    pos1 = self.main_paned.sash_coord(1)
                    if pos0 is not None and pos1 is not None and len(pos0) >= 1 and len(pos1) >= 1:
                        x0, x1 = int(pos0[0]), int(pos1[0])
                        if x1 - x0 >= min_summary:
                            self.data.setdefault("settings", {})["pane_positions"] = [x0, x1]
                except (tk.TclError, IndexError, TypeError):
                    pass
                save_data(self.data, self.current_user)
            except Exception:
                pass

        def _quit_with_save():
            _save_window_layout()
            self.quit()

        self._save_window_layout = _save_window_layout
        self._quit_with_save = _quit_with_save
        self.protocol("WM_DELETE_WINDOW", _quit_with_save)

    def show_preferences(self):
        """Open Settings in an independent window (menu bar)."""
        win = tk.Toplevel(self)
        win.title("Settings")
        win.geometry("600x650")
        win.transient(self)
        self._build_settings_into(win)

    def _build_settings_into(self, parent: tk.Widget):
        """Build settings UI into the given parent (frame or toplevel)."""
        canvas = tk.Canvas(parent, bg="#2b2b2b")
        scrollbar = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        def _on_settings_scroll(event):
            d = getattr(event, "delta", 0) or (120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0)
            if d:
                step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
                canvas.yview_scroll(step, "units")
        canvas.bind("<MouseWheel>", _on_settings_scroll)
        scrollable_frame.bind("<MouseWheel>", _on_settings_scroll)
        for w in (canvas, scrollable_frame):
            w.bind("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
            w.bind("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        settings_inner = tb.Frame(scrollable_frame, padding=20)
        settings_inner.pack(fill="both", expand=True)

        tk.Label(settings_inner, text="Default Exchange for new trades:",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(0, 5))
        exchanges = _ordered_exchanges(self.data["settings"]["fee_structure"])
        self.default_exchange_var = tb.StringVar(
            value=self.data["settings"].get("default_exchange", "Bitstamp"))
        ex_combo = ttk.Combobox(settings_inner, textvariable=self.default_exchange_var,
                               values=exchanges, state="readonly")
        ex_combo.pack(fill="x", pady=10)

        tk.Label(settings_inner, text="Cost Basis Calculation Method:",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(20, 5))
        self.cost_basis_method_var = tb.StringVar(
            value=self.data["settings"].get("cost_basis_method", "average"))
        method_combo = ttk.Combobox(settings_inner, textvariable=self.cost_basis_method_var,
                                    values=["fifo", "lifo", "average"], state="readonly")
        method_combo.pack(fill="x", pady=10)

        client_frame = tb.LabelFrame(settings_inner, text="Client Profile Settings")
        client_frame.pack(fill="x", pady=(20, 10))
        self.is_client_var = tb.BooleanVar(value=self.data["settings"].get("is_client", False))
        client_check = tb.Checkbutton(client_frame, text="This profile is a client",
                                     variable=self.is_client_var,
                                     command=self.toggle_client_percentage)
        client_check.pack(anchor=W, pady=APPLE_SPACING_MEDIUM)
        tk.Label(client_frame, text="Client Percentage (your share of profits):",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(APPLE_SPACING_MEDIUM, APPLE_SPACING_SMALL))
        percentage_frame = tb.Frame(client_frame)
        percentage_frame.pack(fill="x", pady=APPLE_SPACING_SMALL)
        self.client_percentage_var = tb.StringVar(value=str(self.data["settings"].get("client_percentage", 0.0)))
        self.client_percentage_entry = tb.Entry(percentage_frame, textvariable=self.client_percentage_var,
                                               width=15, font=APPLE_FONT_DEFAULT)
        self.client_percentage_entry.pack(side=tk.LEFT, padx=(0, APPLE_SPACING_SMALL))
        tk.Label(percentage_frame, text="%", font=APPLE_FONT_DEFAULT).pack(side=tk.LEFT)
        self.toggle_client_percentage()

        tk.Label(settings_inner, text="Exchange Fee Configuration:",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(20, 5))
        exchange_config_frame = tb.Frame(settings_inner)
        exchange_config_frame.pack(fill="both", expand=True, pady=10)
        exchange_list_frame = tb.Frame(exchange_config_frame)
        exchange_list_frame.pack(side="left", fill="both", expand=True, padx=(0, 10))
        tb.Label(exchange_list_frame, text="Exchanges:").pack(anchor=W)
        self.exchange_listbox = tk.Listbox(exchange_list_frame, height=8, selectmode=tk.SINGLE)
        self.exchange_listbox.pack(fill="both", expand=True)
        self.exchange_listbox.bind("<<ListboxSelect>>", self.on_exchange_select)
        details_frame = tb.LabelFrame(exchange_config_frame, text="Exchange Details")
        details_frame.pack(side="right", fill="both", expand=True)
        details_inner = tb.Frame(details_frame, padding=10)
        details_inner.pack(fill="both", expand=True)
        self.exchange_name_var = tb.StringVar()
        tb.Label(details_inner, text="Exchange Name:").grid(row=0, column=0, sticky=W, pady=5)
        tb.Entry(details_inner, textvariable=self.exchange_name_var, width=25).grid(row=0, column=1, pady=5, padx=5)
        self.maker_fee_var = tb.DoubleVar()
        tb.Label(details_inner, text="Maker Fee (%):").grid(row=1, column=0, sticky=W, pady=5)
        tb.Entry(details_inner, textvariable=self.maker_fee_var, width=25).grid(row=1, column=1, pady=5, padx=5)
        self.taker_fee_var = tb.DoubleVar()
        tb.Label(details_inner, text="Taker Fee (%):").grid(row=2, column=0, sticky=W, pady=5)
        tb.Entry(details_inner, textvariable=self.taker_fee_var, width=25).grid(row=2, column=1, pady=5, padx=5)
        exchange_buttons = tb.Frame(details_inner)
        exchange_buttons.grid(row=3, column=0, columnspan=2, pady=10)
        tb.Button(exchange_buttons, text="Add Exchange", command=self.add_exchange,
                 bootstyle=SUCCESS).pack(side=tk.LEFT, padx=5)
        tb.Button(exchange_buttons, text="Update Exchange", command=self.update_exchange,
                 bootstyle=PRIMARY).pack(side=tk.LEFT, padx=5)
        tb.Button(exchange_buttons, text="Remove Exchange", command=self.remove_exchange,
                 bootstyle=DANGER).pack(side=tk.LEFT, padx=5)
        self.refresh_exchange_list()

        def save_and_maybe_close():
            self.save_settings()
            top = parent.winfo_toplevel()
            if top != self:
                top.destroy()

        save_settings_btn = tb.Button(settings_inner, text="Save All Settings",
                                      command=save_and_maybe_close, bootstyle=SUCCESS)
        save_settings_btn.pack(pady=20)
        tk.Label(settings_inner, text="Data Management:",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(20, 5))
        data_buttons = tb.Frame(settings_inner)
        data_buttons.pack(fill="x", pady=10)
        tb.Button(data_buttons, text="Export Trades (JSON)", command=self.export_trades).pack(side=tk.LEFT, padx=5)
        tb.Button(data_buttons, text="Import Trades (JSON)", command=self.import_trades).pack(side=tk.LEFT, padx=5)
        tk.Label(settings_inner, text="Reset Data (Deletes all trades)",
                fg="red").pack(anchor=W, pady=(20, 5))
        reset_btn = tb.Button(settings_inner, text="Reset All Data", bootstyle=DANGER,
                             command=self.reset_data)
        reset_btn.pack(anchor=W)
        _bind_mousewheel_recursive(scrollable_frame, _on_settings_scroll)

    def new_account_dialog(self):
        """Show dialog to create a new account."""
        ui_dialogs.new_account_dialog(self)

    def manage_accounts_dialog(self):
        """Show dialog to manage accounts."""
        ui_dialogs.manage_accounts_dialog(self)

    def manage_users_dialog(self):
        """Show dialog to manage users."""
        ui_dialogs.manage_users_dialog(self)

    def switch_user_dialog(self):
        """Show dialog to switch users."""
        ui_dialogs.switch_user_dialog(self)

    def show_about(self):
        """Show about dialog."""
        ui_dialogs.show_about(self)

    def create_account_groups_sidebar(self):
        """Create the account groups sidebar (Column 1): Account Groups section + Accounts section."""
        # Scrollable container for groups and accounts; profit toggle at bottom of pane
        list_container = tb.Frame(self.sidebar_frame)
        list_container.pack(fill="both", expand=True, padx=APPLE_PADDING, pady=APPLE_PADDING)

        canvas = tk.Canvas(list_container, bg="#2b2b2b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        def _update_sidebar_region(*args):
            canvas.update_idletasks()
            canvas.configure(scrollregion=canvas.bbox("all"))

        scrollable_frame.bind("<Configure>", lambda e: _update_sidebar_region())
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        self._sidebar_canvas = canvas

        def _on_sidebar_scroll(event):
            d = getattr(event, "delta", 0) or (120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0)
            if d:
                step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
                canvas.yview_scroll(step, "units")

        canvas.bind("<MouseWheel>", _on_sidebar_scroll)
        scrollable_frame.bind("<MouseWheel>", _on_sidebar_scroll)
        for w in (canvas, scrollable_frame):
            w.bind("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
            w.bind("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))
        self._on_sidebar_scroll = _on_sidebar_scroll

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # --- Account Groups section ---
        tk.Label(scrollable_frame, text="Account Groups", font=SIDEBAR_HEADER_FONT).pack(anchor=W, pady=(0, APPLE_SPACING_SMALL))
        self.account_groups_list_frame = tb.Frame(scrollable_frame)
        self.account_groups_list_frame.pack(fill="x", pady=(0, APPLE_SPACING_SMALL))

        btn_grp_frame = tb.Frame(scrollable_frame)
        btn_grp_frame.pack(fill="x", pady=(0, APPLE_SPACING_LARGE))
        tb.Button(btn_grp_frame, text="Add Portfolio", command=self.add_account_group_dialog,
                 bootstyle=PRIMARY, width=SIDEBAR_BUTTON_WIDTH).pack(fill="x")

        # --- Accounts section ---
        tk.Label(scrollable_frame, text="Accounts", font=SIDEBAR_HEADER_FONT).pack(anchor=W, pady=(APPLE_SPACING_LARGE, APPLE_SPACING_SMALL))
        self.sidebar_accounts_list_frame = tb.Frame(scrollable_frame)
        self.sidebar_accounts_list_frame.pack(fill="x", pady=(0, APPLE_SPACING_SMALL))

        btn_acc_frame = tb.Frame(scrollable_frame)
        btn_acc_frame.pack(fill="x")
        tb.Button(btn_acc_frame, text="Add New", command=self.new_account_dialog,
                 bootstyle=PRIMARY, width=SIDEBAR_BUTTON_WIDTH).pack(fill="x")

        self.refresh_account_groups_sidebar()
        self.refresh_sidebar_accounts()
        _update_sidebar_region()
        _bind_mousewheel_recursive(scrollable_frame, _on_sidebar_scroll)

        # Profit column display at bottom of pane (outside scroll area)
        profit_toggle_frame = tb.Frame(self.sidebar_frame)
        profit_toggle_frame.pack(side="bottom", fill="x", padx=APPLE_PADDING, pady=APPLE_SPACING_SMALL)
        self.profit_display_label = tk.Label(
            profit_toggle_frame,
            text=f"Profit in {self.profit_display_currency}",
            font=SUMMARY_DESC_FONT,
            fg=APPLE_COLOR_PROFIT,
            cursor="hand2",
        )
        self.profit_display_label.pack(anchor=W)

        def _toggle_profit_currency(event=None):
            self.profit_display_currency = "BTC" if self.profit_display_currency == "USD" else "USD"
            self.profit_display_label.config(text=f"Profit in {'BTC' if self.profit_display_currency == 'BTC' else 'USD'}")
            self.update_dashboard()

        self.profit_display_label.bind("<Button-1>", _toggle_profit_currency)

    def refresh_account_groups_sidebar(self):
        """Refresh the account groups list (no nested accounts)."""
        for widget in self.account_groups_list_frame.winfo_children():
            widget.destroy()

        groups = get_account_groups(self.data)
        is_selected = lambda gid: (gid is None and self.selected_group_id is None) or (gid == self.selected_group_id)

        # ALL
        all_frame = tb.Frame(self.account_groups_list_frame, padding=APPLE_SPACING_SMALL)
        all_frame.pack(fill="x", pady=APPLE_SPACING_SMALL)
        all_btn = tb.Button(all_frame, text="ALL", command=lambda: self.select_group(None),
                           bootstyle="primary" if is_selected(None) else "outline", width=SIDEBAR_BUTTON_WIDTH)
        all_btn.pack(fill="x")
        all_btn.bind("<Double-1>", lambda e: None)  # no edit for ALL

        for group in groups:
            gid = group["id"]
            group_frame = tb.Frame(self.account_groups_list_frame, padding=APPLE_SPACING_SMALL)
            group_frame.pack(fill="x", pady=APPLE_SPACING_SMALL)
            group_btn = tb.Button(group_frame, text=group["name"],
                                 command=lambda gid=gid: self.select_group(gid),
                                 bootstyle="primary" if is_selected(gid) else "outline", width=SIDEBAR_BUTTON_WIDTH)
            group_btn.pack(fill="x")
            group_btn.bind("<Double-1>", lambda e, gid=gid: self.edit_account_group_dialog(gid))
        if hasattr(self, "_on_sidebar_scroll"):
            _bind_mousewheel_recursive(self.account_groups_list_frame, self._on_sidebar_scroll)

    def refresh_sidebar_accounts(self):
        """Refresh the accounts list in sidebar. When an account is selected, show only that account (no other accounts). When a group is selected, show only accounts in that group."""
        if not hasattr(self, "sidebar_accounts_list_frame"):
            return
        for widget in self.sidebar_accounts_list_frame.winfo_children():
            widget.destroy()

        if self.selected_account_id:
            # Single account selected: show only this account (no other accounts)
            accounts = [a for a in get_accounts(self.data) if a.get("id") == self.selected_account_id]
        elif self.selected_group_id:
            accounts = get_accounts(self.data, self.selected_group_id)
        else:
            accounts = get_accounts(self.data)

        for account in accounts:
            aid = account["id"]
            acc_frame = tb.Frame(self.sidebar_accounts_list_frame, padding=APPLE_SPACING_SMALL)
            acc_frame.pack(fill="x", pady=APPLE_SPACING_SMALL)
            is_sel = self.selected_account_id == aid
            acc_btn = tb.Button(acc_frame, text=account["name"],
                               command=lambda aid=aid: self.select_account(aid),
                               bootstyle="primary" if is_sel else "outline", width=SIDEBAR_BUTTON_WIDTH)
            acc_btn.pack(fill="x")
            acc_btn.bind("<Double-1>", lambda e, aid=aid: self.edit_account_dialog(aid))
        if hasattr(self, "_on_sidebar_scroll"):
            _bind_mousewheel_recursive(self.sidebar_accounts_list_frame, self._on_sidebar_scroll)

    def select_group(self, group_id: Optional[str]):
        """Select an account group."""
        self.selected_group_id = group_id
        self.selected_account_id = None
        self.refresh_account_groups_sidebar()
        self.refresh_sidebar_accounts()
        self.update_summary_panel()

    def select_account(self, account_id: str):
        """Select an account."""
        self.selected_account_id = account_id
        accounts = get_accounts(self.data)
        account = next((a for a in accounts if a["id"] == account_id), None)
        if account and account.get("account_group_id"):
            self.selected_group_id = account["account_group_id"]
        else:
            self.selected_group_id = None
        self.refresh_account_groups_sidebar()
        self.refresh_sidebar_accounts()
        self.update_summary_panel()

    def add_account_group_dialog(self):
        """Show dialog to add an account group."""
        dialog = tk.Toplevel(self)
        dialog.title("Add Account Group")
        dialog.geometry("350x150")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)

        tk.Label(frame, text="Group Name:", font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)
        name_var = tb.StringVar()
        tb.Entry(frame, textvariable=name_var, width=30, font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)

        def create_group():
            name = name_var.get().strip()
            if not name:
                messagebox.showwarning("Input Error", "Please enter a group name.")
                return

            # Check for duplicate names
            groups = get_account_groups(self.data)
            if any(g["name"] == name for g in groups):
                messagebox.showwarning("Input Error", "A group with this name already exists.")
                return

            create_account_group_in_data(self.data, name)
            save_data(self.data, self.current_user)
            self.refresh_account_groups_sidebar()
            self.refresh_sidebar_accounts()
            self.update_summary_panel()
            dialog.destroy()
            self.log_activity(f"Created account group: {name}")

        btn_frame = tb.Frame(frame)
        btn_frame.pack(pady=APPLE_SPACING_LARGE)
        tb.Button(btn_frame, text="Create", command=create_group, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def edit_account_group_dialog(self, group_id: str):
        """Edit account group name (double-click)."""
        group = next((g for g in get_account_groups(self.data) if g["id"] == group_id), None)
        if not group:
            return
        dialog = tk.Toplevel(self)
        dialog.title("Edit Account Group")
        dialog.geometry("350x120")
        dialog.transient(self)
        dialog.grab_set()
        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)
        tk.Label(frame, text="Group Name:", font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)
        name_var = tb.StringVar(value=group["name"])
        tb.Entry(frame, textvariable=name_var, width=30, font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)
        def save():
            name = name_var.get().strip()
            if not name:
                messagebox.showwarning("Input Error", "Please enter a group name.")
                return
            for g in self.data["account_groups"]:
                if g["id"] == group_id:
                    g["name"] = name
                    break
            save_data(self.data, self.current_user)
            self.refresh_account_groups_sidebar()
            self.refresh_sidebar_accounts()
            dialog.destroy()
            self.log_activity(f"Renamed account group to: {name}")
        btn_frame = tb.Frame(frame)
        btn_frame.pack(pady=APPLE_SPACING_LARGE)
        tb.Button(btn_frame, text="Save", command=save, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def edit_account_dialog(self, account_id: str):
        """Edit account name/group (double-click)."""
        account = next((a for a in get_accounts(self.data) if a["id"] == account_id), None)
        if not account:
            return
        dialog = tk.Toplevel(self)
        dialog.title("Edit Account")
        dialog.geometry("400x200")
        dialog.transient(self)
        dialog.grab_set()
        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)
        tk.Label(frame, text="Account Name:", font=APPLE_FONT_DEFAULT).grid(row=0, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM)
        name_var = tb.StringVar(value=account["name"])
        tb.Entry(frame, textvariable=name_var, width=30, font=APPLE_FONT_DEFAULT).grid(row=0, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        tk.Label(frame, text="Account Group:", font=APPLE_FONT_DEFAULT).grid(row=1, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM)
        groups = get_account_groups(self.data)
        group_names = ["None"] + [g["name"] for g in groups]
        group_var = tb.StringVar()
        current_group = next((g for g in groups if g["id"] == account.get("account_group_id")), None)
        group_var.set(current_group["name"] if current_group else "None")
        group_combo = ttk.Combobox(frame, textvariable=group_var, values=group_names, state="readonly", width=27)
        group_combo.grid(row=1, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        frame.grid_columnconfigure(1, weight=1)
        def save():
            name = name_var.get().strip()
            if not name:
                messagebox.showwarning("Input Error", "Please enter an account name.")
                return
            selected_group = group_var.get()
            new_group_id = None
            if selected_group != "None":
                for g in groups:
                    if g["name"] == selected_group:
                        new_group_id = g["id"]
                        break
            for a in self.data["accounts"]:
                if a["id"] == account_id:
                    a["name"] = name
                    a["account_group_id"] = new_group_id
                    break
            if "account_groups" in self.data:
                for g in self.data["account_groups"]:
                    if account_id in g.get("accounts", []):
                        g["accounts"].remove(account_id)
                    if new_group_id and g["id"] == new_group_id:
                        if "accounts" not in g:
                            g["accounts"] = []
                        if account_id not in g["accounts"]:
                            g["accounts"].append(account_id)
            save_data(self.data, self.current_user)
            self.refresh_account_groups_sidebar()
            self.refresh_sidebar_accounts()
            self.update_summary_panel()
            dialog.destroy()
            self.log_activity(f"Updated account: {name}")
        btn_frame = tb.Frame(frame)
        btn_frame.grid(row=2, column=0, columnspan=2, pady=APPLE_SPACING_LARGE)
        tb.Button(btn_frame, text="Save", command=save, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def create_summary_panel(self):
        """Create the summary panel (Column 2). Section width constrained to SUMMARY_SECTIONS_WIDTH."""
        # Scrollable container
        canvas = tk.Canvas(self.summary_frame, bg="#2b2b2b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(self.summary_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)
        # Sections container: fixed width so section content does not expand the pane (height large for scroll)
        sections_container = tb.Frame(scrollable_frame, width=SUMMARY_SECTIONS_WIDTH, height=3000)
        sections_container.pack_propagate(False)
        sections_container.pack(side=tk.LEFT, fill=tk.Y, anchor=tk.NW)

        def _update_summary_region(*args):
            canvas.update_idletasks()
            canvas.configure(scrollregion=canvas.bbox("all"))

        scrollable_frame.bind("<Configure>", lambda e: _update_summary_region())
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        self.summary_content_frame = sections_container
        self._summary_canvas = canvas

        def _on_summary_scroll(event):
            """Handle touchpad / mouse wheel scrolling for the summary pane."""
            d = getattr(event, "delta", 0) or (120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0)
            if d:
                step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
                canvas.yview_scroll(step, "units")

        canvas.bind("<MouseWheel>", _on_summary_scroll)
        scrollable_frame.bind("<MouseWheel>", _on_summary_scroll)
        for w in (canvas, scrollable_frame):
            w.bind("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
            w.bind("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))
        self._on_summary_scroll = _on_summary_scroll
        self._summary_scrollable_frame = scrollable_frame

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.update_summary_panel()
        _update_summary_region()
        # Allow scrolling when the pointer is over any child within the summary frame
        _bind_mousewheel_recursive(self.summary_frame, _on_summary_scroll)

    def update_summary_panel(self):
        """Update the summary panel content."""
        # Clear existing content
        for widget in self.summary_content_frame.winfo_children():
            widget.destroy()

        # Get filtered trades based on selection
        all_trades = self.data.get("trades", [])
        if self.selected_account_id:
            filtered_trades = [t for t in all_trades if t.get("account_id") == self.selected_account_id]
        elif self.selected_group_id:
            # Get all accounts in group
            group_accounts = get_accounts(self.data, self.selected_group_id)
            account_ids = [acc["id"] for acc in group_accounts]
            filtered_trades = [t for t in all_trades if t.get("account_id") in account_ids]
        else:
            filtered_trades = all_trades

        # Scope label: what selection these numbers refer to (all accounts vs one account vs group)
        scope_text = "All accounts"
        if self.selected_account_id:
            acc = next((a for a in get_accounts(self.data) if a.get("id") == self.selected_account_id), None)
            scope_text = f"Account: {acc['name']}" if acc else "One account"
        elif self.selected_group_id:
            grp = next((g for g in get_account_groups(self.data) if g.get("id") == self.selected_group_id), None)
            scope_text = f"Group: {grp['name']}" if grp else "One group"

        # Summary Section: scope + asset filter (cycle) on one row, then metrics
        summary_frame = tb.LabelFrame(self.summary_content_frame, text="Summary")
        summary_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        scope_row = tb.Frame(summary_frame)
        scope_row.pack(fill="x", padx=SUMMARY_CONTENT_PADX, pady=(SUMMARY_PAD, SUMMARY_PAD))
        tk.Label(scope_row, text=scope_text, font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
        # Asset filter: cycle through 3 options (All + first 2 assets), inline right
        asset_options = ["All"] + sorted(set(t.get("asset") for t in filtered_trades if t.get("asset") and t.get("asset") != "USD"))[:2]
        current_display = "All" if not self.selected_asset_filter else self.selected_asset_filter
        if current_display not in asset_options:
            current_display = asset_options[0]
        self._asset_filter_cycle_options = asset_options

        def _cycle_asset_filter(event=None):
            idx = asset_options.index("All" if not self.selected_asset_filter else self.selected_asset_filter)
            idx = (idx + 1) % len(asset_options)
            self.selected_asset_filter = None if asset_options[idx] == "All" else asset_options[idx]
            self.update_summary_panel()
            self.update_dashboard()

        asset_btn = tk.Label(
            scope_row, text=current_display, font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR,
            cursor="hand2",
        )
        asset_btn.pack(side=tk.RIGHT)
        asset_btn.bind("<Button-1>", _cycle_asset_filter)

        metrics_trades = self._trades_for_metric_scope(filtered_trades, self.selected_asset_filter)
        metrics = self.compute_portfolio_metrics(metrics_trades)
        total_value = metrics["total_value"]
        total_external_cash = metrics["total_external_cash"]
        realized_pnl = metrics["realized_pnl"]
        unrealized_pnl = metrics["unrealized_pnl"]
        total_pnl = metrics["total_pnl"]
        roi = metrics["roi_pct"]
        roi_on_cost = metrics.get("roi_on_cost_pct")
        portfolio_24h_usd = self.portfolio_24h_usd(metrics["per_asset"]) if hasattr(self, "portfolio_24h_usd") else None

        summary_grid = tb.Frame(summary_frame)
        summary_grid.pack(fill="x", pady=SUMMARY_PAD, padx=SUMMARY_CONTENT_PADX)
        # Row 0: Portfolio value (crypto + USD cash) | Total P&L (all assets)
        left0 = tb.Frame(summary_grid)
        left0.grid(row=0, column=0, sticky=W, padx=(0, APPLE_SPACING_LARGE), pady=2)
        # Portfolio value is informational (not P&L), keep neutral color
        pv_lbl = tk.Label(left0, text=f"${total_value:,.2f}", font=SUMMARY_VALUE_FONT, fg="white")
        pv_lbl.pack(anchor=W)
        pv_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_PORTFOLIO_VALUE_TOOLTIP, e))
        right0 = tb.Frame(summary_grid)
        right0.grid(row=0, column=1, sticky=E, pady=2)
        tpnl_lbl = tk.Label(right0, text=f"${total_pnl:,.2f}", font=SUMMARY_VALUE_FONT, fg=color_for_value(total_pnl))
        tpnl_lbl.pack(anchor=E)
        tpnl_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_TOTAL_PNL_TOOLTIP, e))
        # Row 1: Capital in (USD in − out) | ROI (P&L ÷ capital)
        left1 = tb.Frame(summary_grid)
        left1.grid(row=1, column=0, sticky=W, padx=(0, APPLE_SPACING_LARGE), pady=2)
        # Capital in is also informational; P&L color is reserved for true profit/loss metrics
        cap_lbl = tk.Label(left1, text=f"${total_external_cash:,.2f}", font=SUMMARY_VALUE_FONT, fg="white")
        cap_lbl.pack(anchor=W)
        cap_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_CAPITAL_IN_TOOLTIP, e))
        right1 = tb.Frame(summary_grid)
        right1.grid(row=1, column=1, sticky=E, pady=2)
        if total_external_cash > 0:
            roi_lbl = tk.Label(right1, text=f"{roi:.2f}%", font=SUMMARY_VALUE_FONT, fg=color_for_value(roi))
            roi_lbl.pack(anchor=E)
            roi_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_ROI_TOOLTIP, e))
        else:
            tk.Label(right1, text="—", font=SUMMARY_VALUE_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=E)
        summary_grid.columnconfigure(1, weight=1)
        # Row 2: Realized P&L | Unrealized P&L
        left2 = tb.Frame(summary_grid)
        left2.grid(row=2, column=0, sticky=W, padx=(0, APPLE_SPACING_LARGE), pady=2)
        rpnl_lbl = tk.Label(left2, text=f"${realized_pnl:,.2f}", font=SUMMARY_VALUE_FONT, fg=color_for_value(realized_pnl))
        rpnl_lbl.pack(anchor=W)
        rpnl_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_REALIZED_PNL_TOOLTIP, e))
        right2 = tb.Frame(summary_grid)
        right2.grid(row=2, column=1, sticky=E, pady=2)
        upnl_lbl = tk.Label(right2, text=f"${unrealized_pnl:,.2f}", font=SUMMARY_VALUE_FONT, fg=color_for_value(unrealized_pnl))
        upnl_lbl.pack(anchor=E)
        upnl_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_UNREALIZED_PNL_TOOLTIP, e))
        # Row 3: ROI on cost (if no USD deposits) | Portfolio 24h (below right column)
        if roi_on_cost is not None and total_external_cash <= 0:
            row3 = tb.Frame(summary_grid)
            row3.grid(row=3, column=0, columnspan=2, sticky=W, pady=2)
            roi_cost_lbl = tk.Label(row3, text=f"ROI on cost: {roi_on_cost:.2f}%", font=SUMMARY_VALUE_FONT, fg=color_for_value(roi_on_cost))
            roi_cost_lbl.pack(anchor=W)
            roi_cost_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_ROI_ON_COST_TOOLTIP, e))
        # Portfolio 24h: below right column; color on value only
        right3 = tb.Frame(summary_grid)
        right3.grid(row=3, column=1, sticky=E, pady=2)
        if portfolio_24h_usd is not None:
            p24_lbl = tk.Label(right3, text=f"${portfolio_24h_usd:+,.2f}", font=SUMMARY_VALUE_FONT, fg=color_for_value(portfolio_24h_usd))
            p24_lbl.pack(anchor=E)
            p24_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_PORTFOLIO_24H_TOOLTIP, e))
        else:
            tk.Label(right3, text="—", font=SUMMARY_VALUE_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=E)

        # Row 4: BTC P&L (realized + unrealized) in USD — from BTC accumulation × current price
        btc_data = metrics.get("per_asset", {}).get("BTC", {})
        btc_lifetime_pnl = btc_data.get("lifetime_pnl", 0.0) if btc_data else 0.0
        right4 = tb.Frame(summary_grid)
        right4.grid(row=4, column=1, sticky=E, pady=2)
        btc_lbl = tk.Label(right4, text=f"${btc_lifetime_pnl:,.2f}", font=SUMMARY_VALUE_FONT, fg=color_for_value(btc_lifetime_pnl))
        btc_lbl.pack(anchor=E)
        btc_lbl.bind("<Button-1>", lambda e: _show_summary_value_tooltip(SUMMARY_BTC_PNL_TOOLTIP, e))

        # Accounts Section (tighter spacing)
        accounts_frame = tb.LabelFrame(self.summary_content_frame, text="Accounts")
        accounts_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _af_inner = tb.Frame(accounts_frame)
        _af_inner.pack(fill="x", padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)

        if self.selected_group_id:
            accounts = get_accounts(self.data, self.selected_group_id)
        else:
            accounts = get_accounts(self.data)

        for account in accounts:
            acc_trades = [t for t in all_trades if t.get("account_id") == account["id"]]
            if not acc_trades:
                continue
            acc_metrics_trades = self._trades_for_metric_scope(acc_trades, self.selected_asset_filter)
            acc_metrics = self.compute_portfolio_metrics(acc_metrics_trades)
            acc_value = acc_metrics["total_value"]
            acc_pnl = acc_metrics["total_pnl"]
            acc_row = tb.Frame(_af_inner)
            acc_row.pack(fill="x", pady=2)
            tk.Label(acc_row, text=f"{account['name']}: ${acc_value:,.2f}", font=APPLE_FONT_DEFAULT).pack(side=tk.LEFT)
            tk.Label(acc_row, text=f"({acc_pnl:+,.2f})", font=APPLE_FONT_DEFAULT, fg=color_for_value(acc_pnl)).pack(side=tk.RIGHT)

        # Assets Section: 2x2 grid per asset (Asset | Qty / Value ; Lifetime P&L / 24h %). Descriptors in click tooltip.
        assets_frame = tb.LabelFrame(self.summary_content_frame, text="Assets")
        assets_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _asf_inner = tb.Frame(assets_frame)
        _asf_inner.pack(fill="both", expand=True, padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)

        def _ensure_summary_value_tooltip():
            if not hasattr(self, "_summary_value_tooltip_win") or not self._summary_value_tooltip_win.winfo_exists():
                self._summary_value_tooltip_win = tk.Toplevel(self)
                self._summary_value_tooltip_win.wm_overrideredirect(True)
                try:
                    self._summary_value_tooltip_win.wm_attributes("-topmost", True)
                except tk.TclError:
                    pass
                self._summary_value_tooltip_label = tk.Label(
                    self._summary_value_tooltip_win, text="", font=SUMMARY_DESC_FONT,
                    bg="#404040", fg="white", padx=8, pady=4, justify=tk.LEFT, wraplength=280,
                )
                self._summary_value_tooltip_label.pack()
            return self._summary_value_tooltip_win, self._summary_value_tooltip_label

        def _show_summary_value_tooltip(text: str, event: tk.Event) -> None:
            win, lbl = _ensure_summary_value_tooltip()
            lbl.config(text=text)
            win.update_idletasks()
            # Position tooltip slightly up and to the right of the cursor
            rx = event.x_root + 24
            ry = event.y_root - 40
            win.geometry(f"+{rx}+{ry}")
            win.deiconify()
            win.lift()

        if metrics_trades:
            asset_metrics = metrics["per_asset"]
            def _asset_icon(a: str) -> str:
                return ASSET_ICONS.get(a, a[:2] if len(a) >= 2 else a)

            for asset in sorted(asset_metrics.keys()):
                data = asset_metrics[asset]
                total_units = data["units_held"] + data["holding_qty"]
                current_value = data["current_value"]
                lifetime_pnl = data.get("lifetime_pnl", data["unrealized_pnl"])
                pct_24h_val = self.get_24h_pct(asset) if hasattr(self, "get_24h_pct") else None
                pct_24h_str = f"{pct_24h_val:+.2f}%" if pct_24h_val is not None else "—"
                icon_or_ticker = _asset_icon(asset)
                suffix = " (closed)" if total_units <= 0 else ""
                # Grid: row0 = Asset | Qty | Lifetime P&L ; row1 = (empty) | Value | 24h %
                card = tb.Frame(_asf_inner)
                card.pack(fill="x", pady=4)
                card.grid_columnconfigure(1, weight=1)
                card.grid_columnconfigure(2, weight=1)
                # Row 0: Asset (col 0), Qty value (col 1), Lifetime P&L value (col 2)
                tk.Label(card, text=icon_or_ticker + suffix, font=(APPLE_FONT_FAMILY, 11, "bold")).grid(row=0, column=0, sticky=tk.W, padx=(0, 8), pady=(0, 2))
                qty_lbl = tk.Label(card, text=f"{total_units:.4f}", font=APPLE_FONT_DEFAULT)
                qty_lbl.grid(row=0, column=1, sticky=tk.W, padx=4, pady=(0, 2))
                qty_lbl.bind("<Button-1>", lambda e, t=SUMMARY_ASSET_QTY_TOOLTIP: _show_summary_value_tooltip(t, e))
                pnl_lbl = tk.Label(card, text=f"${lifetime_pnl:,.2f}", font=APPLE_FONT_DEFAULT, fg=color_for_value(lifetime_pnl))
                pnl_lbl.grid(row=0, column=2, sticky=tk.E, padx=4, pady=(0, 2))
                pnl_lbl.bind("<Button-1>", lambda e, t=SUMMARY_ASSET_LIFETIME_PNL_TOOLTIP: _show_summary_value_tooltip(t, e))
                # Row 1: empty, Value, 24h %
                val_lbl = tk.Label(card, text=f"${current_value:,.2f}", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR)
                val_lbl.grid(row=1, column=1, sticky=tk.W, padx=4, pady=0)
                val_lbl.bind("<Button-1>", lambda e, t=SUMMARY_ASSET_VALUE_TOOLTIP: _show_summary_value_tooltip(t, e))
                color_24h = color_for_value(pct_24h_val) if pct_24h_val is not None else SUMMARY_DESC_COLOR
                pct_lbl = tk.Label(card, text=pct_24h_str, font=SUMMARY_DESC_FONT, fg=color_24h)
                pct_lbl.grid(row=1, column=2, sticky=tk.E, padx=4, pady=0)
                pct_lbl.bind("<Button-1>", lambda e, t=SUMMARY_ASSET_24H_TOOLTIP: _show_summary_value_tooltip(t, e))

        # Open Positions Section: two-row cards (only assets with current holding > 0)
        positions_frame = tb.LabelFrame(self.summary_content_frame, text="Open Positions")
        positions_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _pf_inner = tb.Frame(positions_frame)
        _pf_inner.pack(fill="x", padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)

        asset_metrics_for_positions = metrics["per_asset"]
        closed_assets: List[tuple] = []
        if asset_metrics_for_positions:
            for asset in sorted(asset_metrics_for_positions.keys()):
                data = asset_metrics_for_positions[asset]
                units_held = data["units_held"]
                holding_qty = data["holding_qty"]
                total_units_display = units_held + holding_qty
                if total_units_display > 0:
                    cost_basis = data["cost_basis"]
                    entry_price = cost_basis / units_held if units_held > 0 else 0
                    current_value = data["current_value"]
                    pnl = data["unrealized_pnl"]
                    card = tb.Frame(_pf_inner)
                    card.pack(fill="x", pady=4)
                    # Row 1: Asset (bold) × quantity -------- PnL (green/red, value only)
                    row1 = tb.Frame(card)
                    row1.pack(fill="x")
                    tk.Label(row1, text=asset, font=(APPLE_FONT_FAMILY, 12, "bold")).pack(side=tk.LEFT)
                    tk.Label(row1, text=f" × {total_units_display:.4f}", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                    tk.Label(row1, text=f"${pnl:,.2f}", font=APPLE_FONT_DEFAULT, fg=color_for_value(pnl)).pack(side=tk.RIGHT)
                    # Row 2: Entry (price) | Value (current value of holdings)
                    row2 = tb.Frame(card)
                    row2.pack(fill="x")
                    tk.Label(row2, text="Entry ", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                    tk.Label(row2, text=f"${entry_price:,.2f}", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                    # tk.Label(row2, text="Value ", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.RIGHT)
                    tk.Label(row2, text=f"${current_value:,.2f}", font=APPLE_FONT_DEFAULT, fg=color_for_value(pnl)).pack(side=tk.RIGHT)
                else:
                    lifetime_pnl = data.get("lifetime_pnl", data.get("realized_pnl", 0.0))
                    closed_assets.append((asset, lifetime_pnl))

        # Closed positions: show exited assets with lifetime (realized) P&L
        if closed_assets:
            closed_frame = tb.LabelFrame(self.summary_content_frame, text="Closed Positions")
            closed_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
            _cf_inner = tb.Frame(closed_frame, padding=SUMMARY_PAD)
            _cf_inner.pack(fill="x", padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)
            for asset, lifetime_pnl in closed_assets:
                row = tb.Frame(_cf_inner)
                row.pack(fill="x", pady=2)
                tk.Label(row, text=asset, font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                tk.Label(row, text=f"Lifetime P&L: ${lifetime_pnl:,.2f}", font=APPLE_FONT_DEFAULT, fg=color_for_value(lifetime_pnl)).pack(side=tk.RIGHT)

        if hasattr(self, "_summary_canvas"):
            self._summary_canvas.update_idletasks()
            self._summary_canvas.configure(scrollregion=self._summary_canvas.bbox("all"))
        if hasattr(self, "_on_summary_scroll"):
            _bind_mousewheel_recursive(self.summary_content_frame, self._on_summary_scroll)

    def create_content_area(self):
        """Create the content area with tabs (Column 3)."""
        # Tab Control
        self.tab_control = ttk.Notebook(self.content_frame)
        self.tab_trades = tb.Frame(self.tab_control)
        self.tab_stats = tb.Frame(self.tab_control)
        self.tab_pnl = tb.Frame(self.tab_control)

        self.tab_control.add(self.tab_trades, text='Transactions')
        self.tab_control.add(self.tab_stats, text='Dashboard')
        self.tab_control.add(self.tab_pnl, text='PnL Chart')
        self.tab_control.pack(expand=1, fill="both", padx=APPLE_PADDING, pady=APPLE_PADDING)
        self._tab_drag_index = None
        self._tab_press_x = None
        self.tab_control.bind("<ButtonPress-1>", self._on_tab_press)
        self.tab_control.bind("<ButtonRelease-1>", self._on_tab_release)
        self.tab_control.bind("<B1-Motion>", self._on_tab_motion)
        self._tab_drop_indicator = None
        # Restore saved tab order (so selecting a tab doesn't change order)
        saved_order = self.data.get("settings", {}).get("tab_order")
        if saved_order and isinstance(saved_order, list) and len(saved_order) == 3:
            self._apply_tab_order(saved_order)

        self.create_trades_tab()
        self.create_stats_tab()
        self.create_pnl_chart_tab()


    def add_user_dialog(self):
        """Show dialog to add a new user."""
        ui_dialogs.add_user_dialog(self)

    def delete_user_dialog(self):
        """Show dialog to delete a user."""
        ui_dialogs.delete_user_dialog(self)

    def create_trades_tab(self):
        """Create the trades/transactions tab."""
        trade_container = tb.Frame(self.tab_trades, padding=APPLE_PADDING)
        trade_container.pack(fill="both", expand=True)

        # Input Form
        form_frame = tb.LabelFrame(trade_container, text="New Trade Log")
        form_frame.pack(fill="x", pady=(0, APPLE_PADDING))
        form_inner = tb.Frame(form_frame, padding=APPLE_PADDING)
        form_inner.pack(fill="both", expand=True)
        form_inner.grid_columnconfigure(1, weight=1)
        form_inner.grid_columnconfigure(3, weight=1)

        # Row 0: Asset and Type (type filtered by asset: USD -> Deposit/Withdrawal; crypto -> BUY/SELL/Holding/Transfer)
        tk.Label(form_inner, text="Asset:", font=APPLE_FONT_DEFAULT).grid(row=0, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.asset_var = tb.StringVar(value="BTC")
        asset_combo = ttk.Combobox(form_inner, textvariable=self.asset_var,
                                   values=TRANSACTION_ASSETS, state="readonly")
        asset_combo.grid(row=0, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        tk.Label(form_inner, text="Type:", font=APPLE_FONT_DEFAULT).grid(row=0, column=2, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.trade_type_var = tb.StringVar(value="BUY")
        type_combo = ttk.Combobox(form_inner, textvariable=self.trade_type_var,
                                  values=TRADE_TYPES_CRYPTO, state="readonly", width=10)
        type_combo.grid(row=0, column=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        def _sync_asset_type():
            a, t = self.asset_var.get().strip().upper(), self.trade_type_var.get()
            if a == "USD":
                types_ok = TRADE_TYPES_USD
                if t not in types_ok:
                    self.trade_type_var.set(types_ok[0])
                type_combo["values"] = types_ok
            else:
                types_ok = TRADE_TYPES_CRYPTO
                if t not in types_ok:
                    self.trade_type_var.set(types_ok[0])
                type_combo["values"] = types_ok
            _toggle_usd_deposit_fields()
        def _sync_type_asset():
            t = self.trade_type_var.get()
            if t in TRADE_TYPES_USD:
                if self.asset_var.get().strip().upper() != "USD":
                    self.asset_var.set("USD")
                type_combo["values"] = TRADE_TYPES_USD
            else:
                if self.asset_var.get().strip().upper() == "USD":
                    self.asset_var.set("BTC")
                type_combo["values"] = TRADE_TYPES_CRYPTO
            _toggle_usd_deposit_fields()
        def _toggle_usd_deposit_fields():
            a, t = self.asset_var.get().strip().upper(), self.trade_type_var.get()
            is_usd_fiat = (a == "USD" and t in ("Deposit", "Withdrawal"))
            is_transfer_or_holding = (t in ("Transfer", "Holding"))
            state_qty = "disabled" if is_usd_fiat else "normal"
            state_ord = "disabled" if (is_usd_fiat or is_transfer_or_holding) else "readonly"
            self.qty_entry.config(state=state_qty)
            order_type_combo.config(state=state_ord)
            pct_state = "disabled" if is_usd_fiat else "normal"
            for w in price_pct_frame.winfo_children():
                w.config(state=pct_state)
            for w in qty_pct_frame.winfo_children():
                w.config(state=pct_state)
            if is_usd_fiat:
                if not self.qty_var.get().strip():
                    self.price_var.set("")
                self.qty_var.set("")
                price_lbl.config(text="Amount (USD):")
                qty_lbl.config(text="Quantity: (N/A)")
            else:
                price_lbl.config(text="Price ($):")
                qty_lbl.config(text="Quantity:")

        self.asset_var.trace_add("write", lambda *a: _sync_asset_type())
        self.trade_type_var.trace_add("write", lambda *a: _sync_type_asset())

        # Row 1: Price and Quantity with 25/50/75/100% buttons inline
        price_lbl = tk.Label(form_inner, text="Price ($):", font=APPLE_FONT_DEFAULT)
        price_lbl.grid(row=1, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.price_var = tb.StringVar()
        price_cell = tb.Frame(form_inner)
        price_cell.grid(row=1, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        # Entry and % buttons (width=4 + Pct.TButton so "100%" fits)
        self.price_entry = tb.Entry(price_cell, textvariable=self.price_var, font=APPLE_FONT_DEFAULT, width=10)
        self.price_entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
        price_pct_frame = tb.Frame(price_cell)
        price_pct_frame.pack(side=tk.LEFT, padx=(APPLE_SPACING_SMALL, 0))
        def _apply_price_pct(pct: int):
            asset = self.asset_var.get().strip().upper()
            if asset == "USD":
                return
            price = self.get_current_price(asset) if hasattr(self, "get_current_price") else None
            if price is not None and price > 0:
                self.price_var.set(f"{(pct / 100.0) * price:,.2f}")
        for pct in (25, 50, 75, 100):
            tb.Button(price_pct_frame, text=f"{pct}%", width=4, style="Pct.TButton",
                      command=lambda p=pct: _apply_price_pct(p)).pack(side=tk.LEFT, padx=0)

        qty_lbl = tk.Label(form_inner, text="Quantity:", font=APPLE_FONT_DEFAULT)
        qty_lbl.grid(row=1, column=2, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.qty_var = tb.StringVar()
        qty_cell = tb.Frame(form_inner)
        qty_cell.grid(row=1, column=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.qty_entry = tb.Entry(qty_cell, textvariable=self.qty_var, font=APPLE_FONT_DEFAULT, width=10)
        self.qty_entry.pack(side=tk.LEFT, fill=tk.X, expand=True)
        qty_pct_frame = tb.Frame(qty_cell)
        qty_pct_frame.pack(side=tk.LEFT, padx=(APPLE_SPACING_SMALL, 0))
        def _holding_for_asset(asset: str, account_name: Optional[str] = None) -> float:
            """Return total units held for asset, optionally for a specific account."""
            trades = self.data.get("trades", [])
            if account_name:
                accounts = get_accounts(self.data)
                acc_id = next((a["id"] for a in accounts if a["name"] == account_name), None)
                if acc_id:
                    trades = [t for t in trades if t.get("account_id") == acc_id]
            metrics = self.compute_portfolio_metrics(trades)
            data = metrics.get("per_asset", {}).get(asset, {})
            return (data.get("units_held") or 0) + (data.get("holding_qty") or 0)
        def _apply_qty_pct(pct: int):
            asset = self.asset_var.get().strip().upper()
            if asset == "USD":
                return
            holding = _holding_for_asset(asset, self.account_var.get().strip() or None)
            if holding > 0:
                self.qty_var.set(f"{(pct / 100.0) * holding:.8f}")
        for pct in (25, 50, 75, 100):
            tb.Button(qty_pct_frame, text=f"{pct}%", width=4, style="Pct.TButton",
                      command=lambda p=pct: _apply_qty_pct(p)).pack(side=tk.LEFT, padx=0)

        # Row 2: Exchange/Wallet and Order Type (Order Type disabled when USD+Deposit or Transfer or Holding)
        tk.Label(form_inner, text="Platform:", font=APPLE_FONT_DEFAULT).grid(row=2, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        exchanges = _ordered_exchanges(self.data["settings"]["fee_structure"])
        self.exchange_var = tb.StringVar(value=self.data["settings"].get("default_exchange", "Bitstamp"))
        exchange_combo = ttk.Combobox(form_inner, textvariable=self.exchange_var,
                                      values=exchanges, state="readonly")
        exchange_combo.grid(row=2, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        tk.Label(form_inner, text="Order Type:", font=APPLE_FONT_DEFAULT).grid(row=2, column=2, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.order_type_var = tb.StringVar(value="maker")
        order_type_combo = ttk.Combobox(form_inner, textvariable=self.order_type_var,
                                        values=["maker", "taker"], state="readonly", width=10)
        order_type_combo.grid(row=2, column=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        _toggle_usd_deposit_fields()

        # Row 3: Account Selection
        tk.Label(form_inner, text="Account:", font=APPLE_FONT_DEFAULT).grid(row=3, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.account_var = tb.StringVar()
        accounts = get_accounts(self.data)
        account_names = [acc["name"] for acc in accounts]
        self.account_combo = ttk.Combobox(form_inner, textvariable=self.account_var,
                                         values=account_names, state="readonly")
        self.account_combo.grid(row=3, column=1, columnspan=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        # Set default account if available
        default_account_id = self.data["settings"].get("default_account_id")
        if default_account_id:
            accounts = get_accounts(self.data)
            default_account = next((a for a in accounts if a["id"] == default_account_id), None)
            if default_account:
                self.account_var.set(default_account["name"])

        # Row 4: Add Trade Button
        add_btn = tb.Button(form_inner, text="Add Transaction", bootstyle=SUCCESS,
                           command=self.add_trade, width=20)
        add_btn.grid(row=4, column=0, columnspan=4, pady=APPLE_PADDING)

        # Transactions table: canvas + grid of Labels so only Fees and Profit cells are colored
        table_frame = tb.Frame(trade_container)
        table_frame.pack(fill="both", expand=True)

        self._transactions_columns = ("Date", "Asset", "Type", "Price", "Quantity", "Platform", "Order Type", "Account", "Fees", "Total", "Profit")
        self._transactions_column_widths = {"Date": 150, "Asset": 80, "Type": 60, "Price": 100,
                                            "Quantity": 100, "Platform": 120, "Order Type": 80, "Account": 100, "Fees": 80, "Total": 100, "Profit": 90}
        self._tree_sort_col = None
        self._tree_sort_reverse = False
        self._transactions_selected_trade_id = None
        self._transactions_selected_row_frame = None
        self._transactions_table_bg = "#2b2b2b"
        self._transactions_table_highlight_bg = "#404040"

        trans_canvas = tk.Canvas(table_frame, bg=self._transactions_table_bg, highlightthickness=0)
        trans_vsb = ttk.Scrollbar(table_frame, orient="vertical", command=trans_canvas.yview)
        trans_hsb = ttk.Scrollbar(table_frame, orient="horizontal", command=trans_canvas.xview)
        self._transactions_inner = tb.Frame(trans_canvas)
        self._transactions_inner.bind("<Configure>", lambda e: trans_canvas.configure(scrollregion=trans_canvas.bbox("all")))
        trans_canvas.create_window((0, 0), window=self._transactions_inner, anchor="nw")
        trans_canvas.configure(yscrollcommand=trans_vsb.set, xscrollcommand=trans_hsb.set)
        self._transactions_canvas = trans_canvas

        # Header row (clickable for sort)
        for c, col in enumerate(self._transactions_columns):
            lbl = tk.Label(self._transactions_inner, text=col, font=APPLE_FONT_DEFAULT, bg=self._transactions_table_bg, fg="white")
            lbl.grid(row=0, column=c, sticky="ew", padx=2, pady=2)
            lbl.bind("<Button-1>", lambda e, col=col: self._sort_tree_by_column(col))
        for c in range(len(self._transactions_columns)):
            self._transactions_inner.grid_columnconfigure(c, minsize=self._transactions_column_widths.get(self._transactions_columns[c], 100))

        def _on_trans_scroll(event):
            d = getattr(event, "delta", 0) or (120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0)
            if d:
                step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
                trans_canvas.yview_scroll(step, "units")
        self._on_transactions_scroll = _on_trans_scroll
        trans_canvas.bind("<MouseWheel>", _on_trans_scroll)
        trans_canvas.bind("<Button-4>", lambda e: trans_canvas.yview_scroll(-1, "units"))
        trans_canvas.bind("<Button-5>", lambda e: trans_canvas.yview_scroll(1, "units"))
        table_frame.bind("<MouseWheel>", _on_trans_scroll)
        table_frame.bind("<Button-4>", lambda e: trans_canvas.yview_scroll(-1, "units"))
        table_frame.bind("<Button-5>", lambda e: trans_canvas.yview_scroll(1, "units"))

        trans_canvas.grid(row=0, column=0, sticky="nsew")
        trans_vsb.grid(row=0, column=1, sticky="ns")
        trans_hsb.grid(row=1, column=0, sticky="ew")
        table_frame.grid_rowconfigure(0, weight=1)
        table_frame.grid_columnconfigure(0, weight=1)

        # Context menu
        self.menu = tk.Menu(table_frame, tearoff=0)
        self.menu.add_command(label="Edit Trade", command=self.edit_trade)
        self.menu.add_command(label="Delete Selected", command=self.delete_trade)

    def _on_tab_press(self, event):
        """Remember tab index and x for drag detection (only reorder on drag, not click)."""
        try:
            self._tab_drag_index = self.tab_control.index(self.tab_control.select())
            self._tab_press_x = event.x
        except tk.TclError:
            self._tab_drag_index = None
            self._tab_press_x = None

    def _on_tab_motion(self, event):
        """Optional: could show drop indicator (e.g. highlight tab under cursor)."""
        pass

    def _apply_tab_order(self, order_texts):
        """Apply saved tab order by text (e.g. ['Dashboard', 'Transactions', 'PnL Chart'])."""
        try:
            tabs_by_text = {}
            for tab_id in self.tab_control.tabs():
                text = self.tab_control.tab(tab_id, "text")
                tabs_by_text[text] = tab_id
            for i, text in enumerate(order_texts):
                if text in tabs_by_text:
                    tab_id = tabs_by_text[text]
                    self.tab_control.forget(tab_id)
                    self.tab_control.insert(i, tab_id, text=text)
        except (tk.TclError, KeyError):
            pass

    def _save_tab_order(self):
        """Persist current tab order to settings."""
        try:
            order = [self.tab_control.tab(tid, "text") for tid in self.tab_control.tabs()]
            if "settings" not in self.data:
                self.data["settings"] = {}
            self.data["settings"]["tab_order"] = order
            save_data(self.data, self.current_user)
        except (tk.TclError, KeyError):
            pass

    def _on_tab_release(self, event):
        """Reorder tab only if user actually dragged (moved mouse), then save order."""
        if self._tab_drag_index is None:
            return
        try:
            # Only reorder if this was a drag (mouse moved), not a simple click
            drag_threshold = 5
            moved = (self._tab_press_x is not None and
                     abs(event.x - self._tab_press_x) > drag_threshold)
            if not moved:
                self._tab_drag_index = None
                self._tab_press_x = None
                return
            tabs = list(self.tab_control.tabs())
            if not tabs or self._tab_drag_index >= len(tabs):
                self._tab_drag_index = None
                return
            w = self.tab_control.winfo_width()
            if w <= 0:
                self._tab_drag_index = None
                return
            drop_index = min(int(event.x * len(tabs) / w), len(tabs) - 1)
            drop_index = max(0, drop_index)
            if drop_index == self._tab_drag_index:
                self._tab_drag_index = None
                return
            tab_id = tabs[self._tab_drag_index]
            text = self.tab_control.tab(tab_id, "text")
            self.tab_control.forget(tab_id)
            self.tab_control.insert(drop_index, tab_id, text=text)
            self._save_tab_order()
        except (tk.TclError, IndexError):
            pass
        self._tab_drag_index = None
        self._tab_press_x = None

    def _sort_tree_by_column(self, col: str):
        """Sort transactions table by column header click; repopulate via update_dashboard."""
        reverse = self._tree_sort_reverse if self._tree_sort_col == col else False
        self._tree_sort_col = col
        self._tree_sort_reverse = not reverse
        self.update_dashboard()

    def _repopulate_transactions_table(self, rows_data: List[Tuple[Dict, Tuple, float, Optional[float]]]) -> None:
        """Fill the transactions table. rows_data: (trade, values_tuple, fee_val, profit_usd). Color only Fees (col 8) and Profit (col 10). One frame per row for gapless highlight."""
        # Clear previous selection ref so we don't touch destroyed widgets
        self._transactions_selected_row_frame = None
        self._transactions_selected_row_labels = None
        for w in list(self._transactions_inner.winfo_children()):
            try:
                if int(w.grid_info().get("row", 0)) > 0:
                    w.destroy()
            except (ValueError, TypeError):
                w.destroy()
        default_fg = "white"
        table_font = (APPLE_FONT_FAMILY, 10)
        if not hasattr(self, "_trans_tooltip_win") or not self._trans_tooltip_win.winfo_exists():
            self._trans_tooltip_win = tk.Toplevel(self)
            self._trans_tooltip_win.wm_overrideredirect(True)
            try:
                self._trans_tooltip_win.wm_attributes("-topmost", True)
            except tk.TclError:
                pass
            self._trans_tooltip_label = tk.Label(
                self._trans_tooltip_win, text="", font=table_font,
                bg="#404040", fg="white", padx=6, pady=2,
            )
            self._trans_tooltip_label.pack()
        def _trans_tooltip_show(text: str, event):
            if not text:
                return
            self._trans_tooltip_label.config(text=text)
            self._trans_tooltip_win.update_idletasks()
            rx, ry = event.x_root + 12, event.y_root - 36
            self._trans_tooltip_win.geometry(f"+{rx}+{ry}")
            self._trans_tooltip_win.deiconify()
            self._trans_tooltip_win.lift()
        def _trans_tooltip_hide(event=None):
            if hasattr(self, "_trans_tooltip_win") and self._trans_tooltip_win.winfo_exists():
                self._trans_tooltip_win.withdraw()
        for r, (trade, values_tuple, fee_val, profit_usd) in enumerate(rows_data, start=1):
            tid = trade.get("id", "")
            row_frame = tk.Frame(self._transactions_inner, bg=self._transactions_table_bg)
            row_frame.grid(row=r, column=0, columnspan=len(self._transactions_columns), sticky="ew")
            for c in range(len(self._transactions_columns)):
                row_frame.grid_columnconfigure(c, minsize=self._transactions_column_widths.get(self._transactions_columns[c], 100))
            row_labels = []
            full_date = str(trade.get("date", ""))
            qty_raw = trade.get("quantity", 0)
            asset = trade.get("asset") or ""
            full_qty = f"{qty_raw:.2f}" if asset in ("USD", "USDC") else f"{qty_raw:.8f}"
            for c, text in enumerate(values_tuple):
                fg = default_fg
                if c == 8:
                    fg = color_for_value(-(fee_val or 0))
                elif c == 10:
                    fg = color_for_value(profit_usd) if profit_usd is not None else default_fg
                lbl = tk.Label(row_frame, text=text, font=table_font, bg=self._transactions_table_bg, fg=fg, anchor=tk.CENTER, highlightthickness=0)
                lbl.grid(row=0, column=c, sticky="ew", padx=0, pady=0)
                lbl._trade_id = tid
                lbl._cell_fg = fg
                if c == 0 and full_date:
                    lbl.bind("<Enter>", lambda e, t=full_date: _trans_tooltip_show(t, e))
                    lbl.bind("<Leave>", _trans_tooltip_hide)
                elif c == 4:
                    lbl.bind("<Enter>", lambda e, t=full_qty: _trans_tooltip_show(t, e))
                    lbl.bind("<Leave>", _trans_tooltip_hide)
                row_labels.append(lbl)
            # Force Fees/Profit fg to stick (theme can override on first display)
            for lbl in row_labels:
                fg_val = getattr(lbl, "_cell_fg", default_fg)
                lbl.after(0, lambda l=lbl, f=fg_val: l.config(fg=f) if l.winfo_exists() else None)
            def _select_row(tid: str, rframe: tk.Frame, labels_row: list):
                prev_frame = getattr(self, "_transactions_selected_row_frame", None)
                prev_labels = getattr(self, "_transactions_selected_row_labels", None)
                if prev_frame and prev_frame.winfo_exists():
                    prev_frame.config(bg=self._transactions_table_bg)
                if prev_labels:
                    for ll in prev_labels:
                        if ll.winfo_exists():
                            ll.config(bg=self._transactions_table_bg, fg=getattr(ll, "_cell_fg", "white"))
                self._transactions_selected_trade_id = tid
                self._transactions_selected_row_frame = rframe
                self._transactions_selected_row_labels = labels_row
                # Only update widgets if they still exist (table may have been repopulated)
                if rframe.winfo_exists():
                    rframe.config(bg=self._transactions_table_highlight_bg)
                    for ll in labels_row:
                        if ll.winfo_exists():
                            ll.config(bg=self._transactions_table_highlight_bg, fg=getattr(ll, "_cell_fg", "white"))
            def _on_click(event, tid=tid, rframe=row_frame, labels_row=row_labels):
                _select_row(tid, rframe, labels_row)
            def _on_right(event, tid=tid):
                self._transactions_selected_trade_id = tid
                _select_row(tid, row_frame, row_labels)
                try:
                    self.menu.tk_popup(event.x_root, event.y_root)
                finally:
                    self.menu.grab_release()
            for lbl in row_labels:
                lbl.bind("<Button-1>", _on_click)
                lbl.bind("<Double-1>", lambda e: self.edit_trade())
                lbl.bind("<Button-3>", _on_right)
            row_frame.bind("<Button-1>", _on_click)
            row_frame.bind("<Double-1>", lambda e: self.edit_trade())
            row_frame.bind("<Button-3>", _on_right)
        if hasattr(self, "_on_transactions_scroll"):
            _bind_mousewheel_recursive(self._transactions_inner, self._on_transactions_scroll)

    def update_account_combo(self):
        """Update account combo values."""
        accounts = get_accounts(self.data)
        account_names = [acc["name"] for acc in accounts]
        if hasattr(self, 'account_combo'):
            self.account_combo['values'] = account_names

    def create_stats_tab(self):
        """Create the dashboard/stats tab."""
        # Scrollable container
        canvas = tk.Canvas(self.tab_stats, bg="#2b2b2b", highlightthickness=0)
        self._stats_canvas = canvas
        scrollbar = ttk.Scrollbar(self.tab_stats, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        def _update_stats_scroll_region(*args):
            canvas.update_idletasks()
            canvas.configure(scrollregion=canvas.bbox("all"))

        self._update_stats_scroll_region = _update_stats_scroll_region
        scrollable_frame.bind("<Configure>", lambda e: _update_stats_scroll_region())

        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        def _on_stats_scroll(event):
            d = getattr(event, "delta", 0) or (120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0)
            if d:
                step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
                canvas.yview_scroll(step, "units")

        canvas.bind("<MouseWheel>", _on_stats_scroll)
        scrollable_frame.bind("<MouseWheel>", _on_stats_scroll)
        for w in (canvas, scrollable_frame):
            w.bind("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
            w.bind("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))
        self.tab_stats.bind("<MouseWheel>", _on_stats_scroll)
        # When mouse enters dashboard area, focus canvas so scroll works (macOS)
        def _focus_canvas(e):
            try:
                canvas.focus_set()
                _update_stats_scroll_region()
            except tk.TclError:
                pass
        self.tab_stats.bind("<Enter>", _focus_canvas)
        canvas.bind("<Enter>", _focus_canvas)
        scrollable_frame.bind("<Enter>", _focus_canvas)
        # When Dashboard tab is selected, refresh scroll region and focus canvas
        def _on_tab_changed(event):
            try:
                if self.tab_control.select() == str(self.tab_stats):
                    self.after(50, lambda: (_update_stats_scroll_region(), canvas.focus_set()))
            except (tk.TclError, AttributeError):
                pass
        self.tab_control.bind("<<NotebookTabChanged>>", _on_tab_changed)

        # Price Management Section
        price_frame = tb.LabelFrame(scrollable_frame, text="Price Management")
        price_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        price_inner = tb.Frame(price_frame, padding=APPLE_PADDING)
        price_inner.pack(fill="both", expand=True)

        price_controls = tb.Frame(price_inner)
        price_controls.pack(fill="x")

        tk.Label(price_controls, text="Refresh Prices:", font=APPLE_FONT_DEFAULT).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        # Spacer so button and status sit at top right
        spacer = tb.Frame(price_controls)
        spacer.pack(side=tk.LEFT, fill="x", expand=True)
        self.price_status_label = tk.Label(price_controls, text="", font=APPLE_FONT_DEFAULT)
        self.price_status_label.pack(side=tk.RIGHT, padx=APPLE_SPACING_MEDIUM)
        refresh_btn = tb.Button(price_controls, text="Fetch All Prices",
                               command=self.refresh_all_prices, bootstyle=INFO)
        refresh_btn.pack(side=tk.RIGHT, padx=APPLE_SPACING_MEDIUM)

        # Portfolio Summary (all accounts, all assets: BTC, ETH, USDC, etc. + USD cash)
        stats_container = tb.LabelFrame(scrollable_frame, text="Portfolio Summary (all accounts, all assets)")
        stats_container.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        stats_inner = tb.Frame(stats_container, padding=APPLE_PADDING)
        stats_inner.pack(fill="both", expand=True)

        stats_grid = tb.Frame(stats_inner)
        stats_grid.pack(fill="x", pady=10)

        # Labels (not colored); value labels (green/red when positive/negative)
        tk.Label(stats_grid, text="Capital in (USD):", font=(APPLE_FONT_FAMILY, 14)).grid(row=0, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.total_invested_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 14))
        self.total_invested_label.grid(row=0, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Current Value:", font=(APPLE_FONT_FAMILY, 14)).grid(row=0, column=2, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.current_portfolio_value_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 14))
        self.current_portfolio_value_label.grid(row=0, column=3, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Total P&L:", font=(APPLE_FONT_FAMILY, 16, "bold")).grid(row=0, column=4, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.total_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 16, "bold"))
        self.total_pnl_label.grid(row=0, column=5, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="ROI (P&L ÷ capital):", font=(APPLE_FONT_FAMILY, 14)).grid(row=1, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.roi_label = tk.Label(stats_grid, text="0.00%", font=(APPLE_FONT_FAMILY, 14))
        self.roi_label.grid(row=1, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Realized P&L:", font=(APPLE_FONT_FAMILY, 12)).grid(row=1, column=2, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.realized_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.realized_pnl_label.grid(row=1, column=3, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Unrealized P&L:", font=(APPLE_FONT_FAMILY, 12)).grid(row=1, column=4, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.unrealized_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.unrealized_pnl_label.grid(row=1, column=5, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        self.roi_on_cost_label = tk.Label(stats_grid, text="", font=(APPLE_FONT_FAMILY, 12))
        self.roi_on_cost_label.grid(row=2, column=0, columnspan=6, sticky=W, padx=(APPLE_PADDING, 0), pady=(0, APPLE_SPACING_MEDIUM))

        tk.Label(stats_grid, text="USD cash:", font=(APPLE_FONT_FAMILY, 12)).grid(row=3, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.usd_cash_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.usd_cash_label.grid(row=3, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)
        tk.Label(stats_grid, text="Portfolio 24h:", font=(APPLE_FONT_FAMILY, 12)).grid(row=3, column=2, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.portfolio_24h_label = tk.Label(stats_grid, text="—", font=(APPLE_FONT_FAMILY, 12))
        self.portfolio_24h_label.grid(row=3, column=3, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)
        tk.Label(stats_grid, text="Cost basis (crypto):", font=(APPLE_FONT_FAMILY, 12)).grid(row=3, column=4, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.cost_basis_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.cost_basis_label.grid(row=3, column=5, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        help_row = tb.Frame(stats_inner)
        help_row.pack(fill="x", pady=(0, 5))
        tk.Label(help_row, text="Capital in = USD deposits − withdrawals. Cost basis = crypto cost.", font=(APPLE_FONT_FAMILY, 10), fg=SUMMARY_DESC_COLOR).pack(anchor=W)

        tk.Label(stats_grid, text="Total fees:", font=(APPLE_FONT_FAMILY, 12)).grid(row=4, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.total_fees_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.total_fees_label.grid(row=4, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        # Per-Asset Breakdown
        asset_frame = tb.LabelFrame(scrollable_frame, text="Per-Asset Breakdown")
        asset_frame.pack(fill="both", expand=True, padx=APPLE_PADDING, pady=APPLE_PADDING)
        asset_inner = tb.Frame(asset_frame, padding=APPLE_PADDING)
        asset_inner.pack(fill="both", expand=True)

        asset_columns = ("Asset", "Quantity", "Avg Cost Basis", "Current Price", "Current Value", "Realized P&L", "Unrealized P&L", "Lifetime P&L", "24h %", "ROI %")
        self.asset_tree = ttk.Treeview(asset_inner, columns=asset_columns, show='headings', height=8, style="Asset.Treeview")

        for col in asset_columns:
            self.asset_tree.heading(col, text=col)
            self.asset_tree.column(col, width=95, anchor=tk.CENTER)

        asset_vsb = ttk.Scrollbar(asset_inner, orient="vertical", command=self.asset_tree.yview)
        self.asset_tree.configure(yscrollcommand=asset_vsb.set)

        self.asset_tree.pack(side="left", fill="both", expand=True)
        asset_vsb.pack(side="right", fill="y")
        self._asset_tree_row_asset = {}
        self.asset_tree.bind("<Motion>", self._asset_tree_tooltip_show)
        self.asset_tree.bind("<Leave>", self._asset_tree_tooltip_hide)

        # Client P&L Section (above Pro-forma; hide when current user is a client)
        self.client_frame = tb.LabelFrame(scrollable_frame, text="Client P&L Summary")
        if not self.data.get("settings", {}).get("is_client", False):
            self.client_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        else:
            self.client_frame.pack_forget()
        client_inner = tb.Frame(self.client_frame, padding=APPLE_PADDING)
        client_inner.pack(fill="both", expand=True)

        self.client_pnl_tree = ttk.Treeview(client_inner, columns=("Client", "Your %", "Client P&L", "Your Share"),
                                           show='headings', height=5)
        for col in ("Client", "Your %", "Client P&L", "Your Share"):
            self.client_pnl_tree.heading(col, text=col)
            self.client_pnl_tree.column(col, width=150, anchor=tk.CENTER)

        client_vsb = ttk.Scrollbar(client_inner, orient="vertical", command=self.client_pnl_tree.yview)
        self.client_pnl_tree.configure(yscrollcommand=client_vsb.set)

        self.client_pnl_tree.pack(side="left", fill="both", expand=True)
        client_vsb.pack(side="right", fill="y")

        # Projections Section: P&L + Cost/Value at top, Add button top-right, then table
        projection_frame = tb.LabelFrame(scrollable_frame, text="Projections & Pro forma")
        projection_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        proj_inner = tb.Frame(projection_frame, padding=APPLE_PADDING)
        proj_inner.pack(fill="both", expand=True)

        proj_top = tb.Frame(proj_inner)
        proj_top.pack(fill="x", pady=(0, 8))
        proj_stats_left = tb.Frame(proj_top)
        proj_stats_left.pack(side=tk.LEFT)
        tk.Label(proj_stats_left, text="Projected P&L:", font=(APPLE_FONT_FAMILY, 12, "bold")).pack(side=tk.LEFT, padx=(0, 4))
        self.proj_result_label = tk.Label(proj_stats_left, text="--", font=(APPLE_FONT_FAMILY, 12, "bold"))
        self.proj_result_label.pack(side=tk.LEFT, padx=(0, 12))
        tk.Label(proj_stats_left, text="Cost:", font=(APPLE_FONT_FAMILY, 11)).pack(side=tk.LEFT, padx=(0, 2))
        self.proj_cost_label = tk.Label(proj_stats_left, text="--", font=(APPLE_FONT_FAMILY, 11))
        self.proj_cost_label.pack(side=tk.LEFT, padx=(0, 12))
        tk.Label(proj_stats_left, text="Value:", font=(APPLE_FONT_FAMILY, 11)).pack(side=tk.LEFT, padx=(0, 2))
        self.proj_value_label = tk.Label(proj_stats_left, text="--", font=(APPLE_FONT_FAMILY, 11))
        self.proj_value_label.pack(side=tk.LEFT)
        # Note: Cost/Value labels show only the number (e.g. $X); static "Cost:" and "Value:" are separate labels above
        tb.Button(proj_top, text="Add", command=self._proj_add_row, bootstyle=SUCCESS, width=6).pack(side=tk.RIGHT, padx=5)

        proj_columns = ("Asset", "Type", "Price ($)", "Qty", "Amount ($)", "Account")
        self.proj_tree = ttk.Treeview(proj_inner, columns=proj_columns, show='headings', height=5)
        for c in proj_columns:
            self.proj_tree.heading(c, text=c)
            self.proj_tree.column(c, width=85, anchor=tk.CENTER)
        proj_vsb = ttk.Scrollbar(proj_inner, orient="vertical", command=self.proj_tree.yview)
        self.proj_tree.configure(yscrollcommand=proj_vsb.set)
        self.proj_tree.pack(side=tk.LEFT, fill="both", expand=True)
        proj_vsb.pack(side=tk.RIGHT, fill="y")
        self.proj_tree.bind("<Button-3>", self._show_proj_context_menu)
        self.proj_tree.bind("<Double-1>", lambda e: self._proj_edit_row())

        # Activity Log
        log_frame = tb.LabelFrame(scrollable_frame, text="Activity Log")
        log_frame.pack(fill="both", expand=True, padx=APPLE_PADDING, pady=APPLE_PADDING)
        log_inner = tb.Frame(log_frame, padding=APPLE_PADDING)
        log_inner.pack(fill="both", expand=True)
        self.log_text = tk.Text(log_inner, height=6, state='disabled',
                               background="#3a3a3a", foreground="white", wrap=tk.WORD)
        log_vsb = ttk.Scrollbar(log_inner, orient="vertical", command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=log_vsb.set)

        self.log_text.pack(side="left", fill="both", expand=True)
        log_vsb.pack(side="right", fill="y")

        _bind_mousewheel_recursive(scrollable_frame, _on_stats_scroll)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

    def create_pnl_chart_tab(self):
        """Create the PnL chart tab with time period selection."""
        if not MATPLOTLIB_AVAILABLE:
            error_frame = tb.Frame(self.tab_pnl, padding=20)
            error_frame.pack(fill="both", expand=True)
            tb.Label(error_frame, text="Matplotlib is required for PnL charts.\nPlease install it with: pip install matplotlib",
                    font=("Helvetica", 12), justify=tk.CENTER).pack(expand=True)
            return

        chart_container = tb.Frame(self.tab_pnl, padding=10)
        chart_container.pack(fill="both", expand=True)

        # Controls frame
        controls_frame = tb.LabelFrame(chart_container, text="Chart Controls")
        controls_frame.pack(fill="x", pady=(0, 10))
        controls_inner = tb.Frame(controls_frame, padding=10)
        controls_inner.pack(fill="x")

        # Asset selection
        tk.Label(controls_inner, text="Asset:", font=APPLE_FONT_DEFAULT).grid(row=0, column=0, sticky=W, padx=5, pady=5)
        self.chart_asset_var = tb.StringVar()
        trades = self.data.get("trades", [])
        chart_assets = sorted(set(t["asset"] for t in trades)) if trades else ["BTC"]
        if not chart_assets:
            chart_assets = ["BTC"]
        self.chart_asset_combo = ttk.Combobox(controls_inner, textvariable=self.chart_asset_var,
                                             values=chart_assets, state="readonly", width=12)
        self.chart_asset_combo.set(chart_assets[0] if chart_assets else "BTC")
        self.chart_asset_combo.grid(row=0, column=1, padx=5, pady=5)
        self.chart_asset_var.trace_add("write", lambda *a: self.update_pnl_chart())

        # Time period buttons: 1D, 1W, 1M, 3M, 6M, 1Y, Custom
        tk.Label(controls_inner, text="Period:", font=APPLE_FONT_DEFAULT).grid(row=0, column=2, sticky=W, padx=(15, 5), pady=5)
        self.chart_period_var = tb.StringVar(value="7d")
        period_btns_frame = tb.Frame(controls_inner)
        period_btns_frame.grid(row=0, column=3, padx=5, pady=5)
        for label, period in [("1D", "1d"), ("1W", "7d"), ("1M", "30d"), ("3M", "90d"), ("6M", "180d"), ("1Y", "365d"), ("Custom", "all")]:
            b = tb.Button(period_btns_frame, text=label, width=4,
                         command=lambda p=period: self._set_chart_period(p),
                         bootstyle="primary" if period == "7d" else "outline")
            b.pack(side=tk.LEFT, padx=2)

        # Value in
        tk.Label(controls_inner, text="Value in:", font=APPLE_FONT_DEFAULT).grid(row=0, column=4, sticky=W, padx=(15, 5), pady=5)
        self.chart_value_type_var = tb.StringVar(value="USD")
        value_type_combo = ttk.Combobox(controls_inner, textvariable=self.chart_value_type_var,
                                        values=["USD", "Asset"], state="readonly", width=8)
        value_type_combo.grid(row=0, column=5, padx=5, pady=5)
        self.chart_value_type_var.trace_add("write", lambda *a: self.update_pnl_chart())

        # Chart frame
        chart_frame = tb.Frame(chart_container)
        chart_frame.pack(fill="both", expand=True)

        # Create matplotlib figure
        if Figure is None or FigureCanvasTkAgg is None:
            return
        self.chart_figure = Figure(figsize=(10, 6), facecolor='#2b2b2b')
        self.chart_ax = self.chart_figure.add_subplot(111, facecolor='#2b2b2b')
        self.chart_ax.tick_params(colors='white')
        self.chart_ax.xaxis.label.set_color('white')
        self.chart_ax.yaxis.label.set_color('white')
        self.chart_ax.spines['bottom'].set_color('white')
        self.chart_ax.spines['top'].set_color('white')
        self.chart_ax.spines['right'].set_color('white')
        self.chart_ax.spines['left'].set_color('white')

        self.chart_canvas = FigureCanvasTkAgg(self.chart_figure, chart_frame)
        self.chart_canvas.get_tk_widget().pack(fill="both", expand=True)

        self.update_pnl_chart()

    def _set_chart_period(self, period: str):
        """Set chart period and update (period is 1d, 7d, 30d, 90d, 180d, 365d, or all)."""
        self.chart_period_var.set(period)
        self.update_pnl_chart()

    def update_pnl_chart(self):
        """Update the PnL chart based on selected parameters (line graph, auto on change)."""
        if not hasattr(self, "chart_ax"):
            return
        try:
            asset = self.chart_asset_var.get() or "BTC"
            period = self.chart_period_var.get() or "7d"
            value_type = self.chart_value_type_var.get() or "USD"

            trades = self.data.get("trades", [])
            if not trades:
                self.chart_ax.clear()
                self.chart_ax.text(0.5, 0.5, "No trades available",
                                  ha='center', va='center', color='white', fontsize=14)
                self.chart_ax.set_facecolor('#2b2b2b')
                self.chart_canvas.draw()
                return

            # Filter trades for selected asset
            asset_trades = [t for t in trades if t["asset"] == asset]
            if not asset_trades:
                self.chart_ax.clear()
                self.chart_ax.text(0.5, 0.5, f"No trades for {asset}",
                                  ha='center', va='center', color='white', fontsize=14)
                self.chart_ax.set_facecolor('#2b2b2b')
                self.chart_canvas.draw()
                return

            # Sort trades by date
            asset_trades.sort(key=lambda x: x["date"])

            # Time range: from first transaction (when period is "all") or last N days
            now = datetime.now()
            first_trade_date = min(datetime.strptime(t["date"], "%Y-%m-%d %H:%M:%S") for t in asset_trades)
            if period == "1d":
                start_date = now - timedelta(days=1)
            elif period == "7d":
                start_date = now - timedelta(days=7)
            elif period == "30d":
                start_date = now - timedelta(days=30)
            elif period == "90d":
                start_date = now - timedelta(days=90)
            elif period == "180d":
                start_date = now - timedelta(days=180)
            elif period == "365d":
                start_date = now - timedelta(days=365)
            else:  # "all" = from first transaction to now
                start_date = first_trade_date

            if start_date:
                filtered_trades = [t for t in asset_trades
                                 if datetime.strptime(t["date"], "%Y-%m-%d %H:%M:%S") >= start_date]
            else:
                filtered_trades = asset_trades

            if not filtered_trades:
                self.chart_ax.clear()
                self.chart_ax.text(0.5, 0.5, f"No trades in selected period",
                                  ha='center', va='center', color='white', fontsize=14)
                self.chart_ax.set_facecolor('#2b2b2b')
                self.chart_canvas.draw()
                return

            # Calculate cumulative values over time (and cumulative realized P&L when USD)
            dates = []
            values = []
            quantities = []
            realized_cumul = []  # cumulative realized P&L at each date (for USD chart)
            cost_basis = 0.0
            quantity_held = 0.0
            cumulative_realized = 0.0

            cost_basis_method = self.data["settings"].get("cost_basis_method", "average")

            for trade in filtered_trades:
                trade_date = datetime.strptime(trade["date"], "%Y-%m-%d %H:%M:%S")
                dates.append(trade_date)

                if trade["type"] == "BUY":
                    quantity_held += trade["quantity"]
                    cost_basis += trade["total_value"] + trade["fee"]
                else:  # SELL
                    qty_sold = trade["quantity"]
                    proceeds = (trade.get("total_value") or 0) - (trade.get("fee") or 0)
                    if quantity_held + qty_sold > 0:
                        cost_of_sold = cost_basis * (qty_sold / (quantity_held + qty_sold))
                    else:
                        cost_of_sold = cost_basis
                    cumulative_realized += proceeds - cost_of_sold
                    quantity_held -= qty_sold
                    if quantity_held > 0:
                        if cost_basis_method == "average":
                            avg_cost = cost_basis / (quantity_held + qty_sold)
                            cost_basis = quantity_held * avg_cost
                        else:
                            avg_cost = cost_basis / (quantity_held + qty_sold)
                            cost_basis = quantity_held * avg_cost
                    else:
                        cost_basis = 0.0

                quantities.append(quantity_held)
                if value_type == "USD":
                    realized_cumul.append(cumulative_realized)

                if value_type == "USD":
                    # Calculate value in USD using canonical valuation helper at each step
                    step_trades = [t for t in filtered_trades if datetime.strptime(t["date"], "%Y-%m-%d %H:%M:%S") <= trade_date]
                    step_metrics = self.compute_portfolio_metrics(step_trades)
                    values.append(step_metrics["total_value"])
                else:  # Asset
                    values.append(quantity_held)

            # Add current point if we have holdings (for asset-quantity view)
            if quantity_held > 0 and value_type == "Asset":
                dates.append(now)
                quantities.append(quantity_held)
                values.append(quantity_held)

            # Clear and plot
            self.chart_ax.clear()
            self.chart_ax.set_facecolor('#2b2b2b')
            self.chart_ax.tick_params(colors='white')
            self.chart_ax.xaxis.label.set_color('white')
            self.chart_ax.yaxis.label.set_color('white')
            self.chart_ax.spines['bottom'].set_color('white')
            self.chart_ax.spines['top'].set_color('white')
            self.chart_ax.spines['right'].set_color('white')
            self.chart_ax.spines['left'].set_color('white')

            if dates and values:
                numeric_values = [float(v) for v in values]
                self.chart_ax.plot(dates, numeric_values, color='#4cc9f0', linewidth=2, marker='o', markersize=4, label='Portfolio value')
                if value_type == "USD" and len(realized_cumul) == len(dates):
                    self.chart_ax.plot(dates, realized_cumul, color='#30D158', linewidth=1.5, linestyle='--', marker='s', markersize=3, label='Cumulative realized P&L')

                # Format labels
                if value_type == "USD":
                    self.chart_ax.set_ylabel(f'Portfolio Value (USD)', color='white')
                    if FuncFormatter:
                        self.chart_ax.yaxis.set_major_formatter(
                            FuncFormatter(lambda x, p: f'${x:,.0f}')
                        )
                    if realized_cumul:
                        self.chart_ax.legend(loc='upper left', facecolor='#2b2b2b', edgecolor='white', labelcolor='white')
                else:
                    self.chart_ax.set_ylabel(f'Quantity ({asset})', color='white')

                self.chart_ax.set_xlabel('Date', color='white')
                self.chart_ax.set_title(f'{asset} Portfolio Value Over Time', color='white', fontsize=14, fontweight='bold')

                # Format x-axis dates
                self.chart_figure.autofmt_xdate()

                # Grid
                self.chart_ax.grid(True, alpha=0.3, color='gray')

            self.chart_canvas.draw()

        except Exception as e:
            messagebox.showerror("Chart Error", f"Error updating chart: {e}")

    def refresh_exchange_list(self):
        """Refresh the exchange listbox."""
        self.exchange_listbox.delete(0, tk.END)
        for exchange in sorted(self.data["settings"]["fee_structure"].keys()):
            self.exchange_listbox.insert(tk.END, exchange)

    def on_exchange_select(self, event):
        """Handle exchange selection in listbox."""
        selection = self.exchange_listbox.curselection()
        if selection:
            exchange_name = self.exchange_listbox.get(selection[0])
            fees = self.data["settings"]["fee_structure"].get(exchange_name, {"maker": 0.1, "taker": 0.1})
            self.exchange_name_var.set(exchange_name)
            self.maker_fee_var.set(fees["maker"])
            self.taker_fee_var.set(fees["taker"])

    def add_exchange(self):
        """Add a new exchange."""
        name = self.exchange_name_var.get().strip()
        if not name:
            messagebox.showwarning("Input Error", "Please enter an exchange name.")
            return

        if name in self.data["settings"]["fee_structure"]:
            messagebox.showwarning("Input Error", "Exchange already exists. Use Update instead.")
            return

        try:
            maker_fee = self.maker_fee_var.get()
            taker_fee = self.taker_fee_var.get()
            if maker_fee < 0 or taker_fee < 0:
                raise ValueError("Fees must be non-negative")

            self.data["settings"]["fee_structure"][name] = {"maker": maker_fee, "taker": taker_fee}
            self.refresh_exchange_list()
            messagebox.showinfo("Success", f"Exchange '{name}' added successfully.")
        except Exception as e:
            messagebox.showerror("Input Error", f"Invalid fee values: {e}")

    def update_exchange(self):
        """Update an existing exchange."""
        name = self.exchange_name_var.get().strip()
        if not name:
            messagebox.showwarning("Input Error", "Please select an exchange to update.")
            return

        if name not in self.data["settings"]["fee_structure"]:
            messagebox.showwarning("Input Error", "Exchange not found. Use Add instead.")
            return

        try:
            maker_fee = self.maker_fee_var.get()
            taker_fee = self.taker_fee_var.get()
            if maker_fee < 0 or taker_fee < 0:
                raise ValueError("Fees must be non-negative")

            self.data["settings"]["fee_structure"][name] = {"maker": maker_fee, "taker": taker_fee}
            self.refresh_exchange_list()
            messagebox.showinfo("Success", f"Exchange '{name}' updated successfully.")
        except Exception as e:
            messagebox.showerror("Input Error", f"Invalid fee values: {e}")

    def remove_exchange(self):
        """Remove an exchange."""
        name = self.exchange_name_var.get().strip()
        if not name:
            messagebox.showwarning("Input Error", "Please select an exchange to remove.")
            return

        if name not in self.data["settings"]["fee_structure"]:
            messagebox.showwarning("Input Error", "Exchange not found.")
            return

        confirm_msg = (f"Are you sure you want to remove exchange '{name}'?\n\n"
                       f"This will not delete trades, but the exchange will no longer be available for new trades.")
        if messagebox.askyesno("Confirm Delete", confirm_msg):
            del self.data["settings"]["fee_structure"][name]
            self.refresh_exchange_list()
            self.exchange_name_var.set("")
            self.maker_fee_var.set(0.0)
            self.taker_fee_var.set(0.0)
            messagebox.showinfo("Success", f"Exchange '{name}' removed successfully.")

    def add_trade(self):
        """Add a new trade entry."""
        try:
            asset = self.asset_var.get().strip().upper()
            trade_type = self.trade_type_var.get()
            price_str = self.price_var.get().strip()
            qty_str = self.qty_var.get().strip()
            exchange = self.exchange_var.get()
            order_type = self.order_type_var.get()

            # USD Deposit/Withdrawal: use Amount (USD) in price field; store price=0, exchange/order_type blank
            is_usd_fiat = (asset == "USD" and trade_type in ("Deposit", "Withdrawal"))
            is_transfer_holding = (trade_type in ("Transfer", "Holding"))
            if is_usd_fiat:
                if not price_str:
                    raise ValueError("Amount (USD) is required")
                try:
                    amount_usd = float(price_str)
                except ValueError:
                    raise ValueError("Amount must be a valid number")
                if amount_usd <= 0:
                    raise ValueError("Amount must be greater than 0")
                price, qty = 0.0, amount_usd  # price 0 = display blank for USD fiat
                fee = 0.0
                order_type = ""
                exchange = ""
            else:
                if not asset:
                    raise ValueError("Asset name is required")
                if not price_str:
                    raise ValueError("Price is required")
                if not qty_str:
                    raise ValueError("Quantity is required")
                try:
                    price = float(price_str)
                    qty = float(qty_str)
                except ValueError:
                    raise ValueError("Price and quantity must be valid numbers")
                if price <= 0:
                    raise ValueError("Price must be greater than 0")
                if qty <= 0:
                    raise ValueError("Quantity must be greater than 0")
                if trade_type == "Holding":
                    available = self.get_available_quantity(asset)
                    if qty > available:
                        raise ValueError(f"Holding amount cannot exceed available. Available: {available:.8f}, Requested: {qty:.8f}")
                if not is_transfer_holding:
                    if exchange not in self.data["settings"]["fee_structure"]:
                        raise ValueError("Invalid exchange selected")
                    fee_structure = self.data["settings"]["fee_structure"][exchange]
                    fee_rate = fee_structure.get(order_type, fee_structure.get("maker", 0.1))
                    total_amount = price * qty
                    fee = total_amount * (fee_rate / 100)
                else:
                    order_type = ""
                    if not exchange:
                        exchange = ""
                    total_amount = price * qty
                    fee = 0.0

            # Check if selling/withdrawing more than owned
            if trade_type == "SELL" or (asset == "USD" and trade_type == "Withdrawal"):
                available_qty = self.get_available_quantity(asset)
                if qty > available_qty:
                    raise ValueError(f"Insufficient amount. Available: {available_qty:.8f}, Requested: {qty:.8f}")

            # Account selection validation
            account_name = self.account_var.get()
            if not account_name:
                raise ValueError("Account is required")

            accounts = get_accounts(self.data)
            selected_account = next((acc for acc in accounts if acc["name"] == account_name), None)
            if not selected_account:
                raise ValueError("Invalid account selected")

            account_id = selected_account["id"]

            if not is_usd_fiat:
                total_amount = price * qty
            else:
                total_amount = qty  # USD amount

            trade_entry = {
                "id": str(uuid.uuid4()),
                "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "asset": asset,
                "type": trade_type,
                "price": round(price, 8),
                "quantity": qty,
                "exchange": exchange if not is_usd_fiat else "",
                "order_type": order_type,
                "fee": round(fee, 8),
                "total_value": round(total_amount, 8),
                "account_id": account_id
            }

            self.data["trades"].append(trade_entry)
            save_data(self.data, self.current_user)

            # Reset Form
            self.asset_var.set("BTC")
            self.price_var.set("")
            self.qty_var.set("")

            self.update_dashboard()
            self.update_summary_panel()
            # Update chart asset list if new asset
            if hasattr(self, 'chart_asset_combo') and asset not in self.chart_asset_combo['values']:
                current_assets = list(self.chart_asset_combo['values'])
                current_assets.append(asset)
                self.chart_asset_combo['values'] = sorted(current_assets)

            # Granular activity log
            self.log_activity(f"Added {trade_type} order: {qty:.8f} {asset} @ ${price:,.2f} on {exchange} to account {account_name}")

        except Exception as e:
            messagebox.showerror("Input Error", f"Please check your input: {e}")

    def get_available_quantity(self, asset: str) -> float:
        """Calculate available quantity for an asset (sellable/withdrawable).

        - USD: uses canonical USD cash balance from compute_portfolio_metrics.
        - Crypto: BUY + Transfer - SELL - Holding, consistent with cost-basis units.
        """
        trades = self.data.get("trades", [])
        if asset == "USD":
            metrics = self.compute_portfolio_metrics(trades)
            return max(0.0, float(metrics.get("usd_balance", 0.0)))

        asset_trades = [t for t in trades if t["asset"] == asset]
        asset_trades.sort(key=lambda x: x["date"])

        qty = 0.0
        for t in asset_trades:
            ttype = t["type"]
            if ttype in ("BUY", "Transfer"):
                qty += t["quantity"]
            elif ttype == "SELL":
                qty -= t["quantity"]
            # Holding: reduces sellable amount (locked, not tradeable)
            elif ttype == "Holding":
                qty -= t["quantity"]
        return max(0.0, qty)

    def get_holding_quantity(self, asset: str) -> float:
        """Return total quantity in Holding transactions for the asset (included in portfolio value)."""
        trades = self.data.get("trades", [])
        return sum(t["quantity"] for t in trades if t["asset"] == asset and t["type"] == "Holding")

    def _trades_for_metric_scope(self, trades: List[Dict], asset_filter: Optional[str]) -> List[Dict]:
        """Filter trades for metric scope: when asset_filter is set, only that asset + USD (for capital in)."""
        if not asset_filter:
            return list(trades)
        return [t for t in trades if t.get("asset") == asset_filter or t.get("asset") == "USD"]

    def compute_portfolio_metrics(self, trades: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Compute canonical portfolio metrics; delegates to services.metrics with self.get_current_price."""
        cost_basis_method = self.data["settings"].get("cost_basis_method", "average")
        return metrics_service.compute_portfolio_metrics(trades, cost_basis_method, self.get_current_price)

    def get_account_portfolio_value(self, account_id: Optional[str]) -> float:
        """Return total USD value of an account (crypto positions at current price + USD cash)."""
        trades = self.data.get("trades", [])
        if account_id:
            trades = [t for t in trades if t.get("account_id") == account_id]
        metrics = self.compute_portfolio_metrics(trades)
        return max(0.0, float(metrics.get("total_value", 0.0)))

    def _parse_numeric_display(self, text: str) -> Tuple[Optional[float], str, str]:
        """Parse label text like '$1,234.56' or '12.34%' into (number, prefix, suffix). Returns (None, '', '') if not parseable."""
        import re
        s = (text or "").strip()
        prefix = ""
        suffix = ""
        if s.startswith("$"):
            prefix = "$"
            s = s[1:]
        if s.endswith("%"):
            suffix = "%"
            s = s[:-1]
        s = s.replace(",", "")
        try:
            return float(s), prefix, suffix
        except ValueError:
            return None, prefix, suffix

    def _animate_numeric_label(self, label: tk.Label, target_text: str, fg: Optional[str] = None, steps: int = 8, duration_ms: int = 280) -> None:
        """Slot-machine style: animate label from current numeric value to target. target_text e.g. '$1,234.56' or '12.34%'. Optional fg color."""
        current = label.cget("text")
        target_val, pfx, sfx = self._parse_numeric_display(target_text)
        curr_val, _, _ = self._parse_numeric_display(current)
        if target_val is None or curr_val is None:
            label.config(text=target_text)
            if fg is not None:
                label.config(fg=fg)
            return
        step_ms = max(20, duration_ms // steps)
        start_val = curr_val

        def _step(step_index: int) -> None:
            if step_index >= steps:
                label.config(text=target_text)
                if fg is not None:
                    label.config(fg=fg)
                return
            t = (step_index + 1) / steps
            # Ease-out so final step is exact
            interp = 1.0 - (1.0 - t) ** 2
            val = start_val + (target_val - start_val) * interp
            label.config(text=f"{pfx}{val:,.2f}{sfx}")
            if fg is not None and step_index == steps - 1:
                label.config(fg=fg)
            label.after(step_ms, lambda: _step(step_index + 1))

        _step(0)

    def edit_trade(self):
        """Edit an existing trade."""
        trade_id = getattr(self, "_transactions_selected_trade_id", None)
        if not trade_id:
            messagebox.showwarning("No Selection", "Please select a trade to edit (e.g. click a row then use Edit, or right-click the row and choose Edit Trade).")
            return

        trade = next((t for t in self.data["trades"] if t.get("id") == trade_id), None)
        if not trade:
            messagebox.showerror("Error", "Could not find trade to edit.")
            return

        # Create edit dialog
        dialog = tk.Toplevel(self)
        dialog.title("Edit Trade")
        dialog.geometry("450x480")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=20)
        frame.pack(fill="both", expand=True)

        # Date/Time (editable with picker)
        tb.Label(frame, text="Date / Time:").grid(row=0, column=0, sticky=W, pady=5)
        try:
            dt = datetime.strptime(trade["date"], "%Y-%m-%d %H:%M:%S")
        except (ValueError, KeyError):
            dt = datetime.now()
        date_str = dt.strftime("%Y-%m-%d")
        time_str = dt.strftime("%H:%M:%S")
        date_var = tb.StringVar(value=date_str)
        time_var = tb.StringVar(value=time_str)
        date_time_frame = tb.Frame(frame)
        date_time_frame.grid(row=0, column=1, sticky=EW, pady=5, padx=5)
        if HAS_TKCALENDAR and DateEntry:
            date_entry = DateEntry(date_time_frame, textvariable=date_var, width=12, date_pattern="y-mm-dd")
            date_entry.pack(side=tk.LEFT, padx=(0, 5))
        else:
            tb.Entry(date_time_frame, textvariable=date_var, width=12).pack(side=tk.LEFT, padx=(0, 5))
        tb.Entry(date_time_frame, textvariable=time_var, width=10).pack(side=tk.LEFT)

        # Asset (USD + crypto)
        tb.Label(frame, text="Asset:").grid(row=1, column=0, sticky=W, pady=5)
        asset_var = tb.StringVar(value=trade["asset"])
        asset_combo_edit = ttk.Combobox(frame, textvariable=asset_var, values=TRANSACTION_ASSETS,
                        state="readonly")
        asset_combo_edit.grid(row=1, column=1, sticky=EW, pady=5, padx=5)

        # Type (filter by asset: USD -> Deposit/Withdrawal; crypto -> BUY/SELL/Holding/Transfer)
        tb.Label(frame, text="Type:").grid(row=2, column=0, sticky=W, pady=5)
        type_var = tb.StringVar(value=trade["type"])
        type_values = TRADE_TYPES_USD if trade["asset"] == "USD" else TRADE_TYPES_CRYPTO
        if trade["type"] not in type_values:
            type_var.set(type_values[0])
        type_combo_edit = ttk.Combobox(frame, textvariable=type_var, values=type_values,
                    state="readonly")
        type_combo_edit.grid(row=2, column=1, sticky=EW, pady=5, padx=5)

        # Price (for USD Deposit/Withdrawal this is "Amount (USD)" and we show quantity there)
        is_usd_edit = (trade["asset"] == "USD" and trade["type"] in ("Deposit", "Withdrawal"))
        price_initial = trade["quantity"] if is_usd_edit else trade["price"]
        price_var = tb.DoubleVar(value=price_initial)
        price_lbl_edit = tb.Label(frame, text="Amount (USD):" if is_usd_edit else "Price ($):")
        price_lbl_edit.grid(row=3, column=0, sticky=W, pady=5)
        tb.Entry(frame, textvariable=price_var).grid(row=3, column=1, sticky=EW, pady=5, padx=5)

        # Quantity
        tb.Label(frame, text="Quantity:").grid(row=4, column=0, sticky=W, pady=5)
        qty_var = tb.DoubleVar(value=trade["quantity"])
        tb.Entry(frame, textvariable=qty_var).grid(row=4, column=1, sticky=EW, pady=5, padx=5)

        # Platform
        tb.Label(frame, text="Platform:").grid(row=5, column=0, sticky=W, pady=5)
        exchange_var = tb.StringVar(value=trade.get("exchange") or "")
        exchanges = _ordered_exchanges(self.data["settings"]["fee_structure"])
        ttk.Combobox(frame, textvariable=exchange_var, values=exchanges,
                    state="readonly").grid(row=5, column=1, sticky=EW, pady=5, padx=5)

        # Order Type (disabled for Transfer / Holding / USD fiat)
        tb.Label(frame, text="Order Type:").grid(row=6, column=0, sticky=W, pady=5)
        order_type_var = tb.StringVar(value=trade.get("order_type") or "maker")
        order_type_combo_edit = ttk.Combobox(frame, textvariable=order_type_var, values=["maker", "taker"],
                    state="readonly")
        order_type_combo_edit.grid(row=6, column=1, sticky=EW, pady=5, padx=5)
        def _edit_toggle_order_type(*a):
            t = type_var.get()
            is_disabled = (t in ("Transfer", "Holding") or (asset_var.get() == "USD" and t in ("Deposit", "Withdrawal")))
            order_type_combo_edit.config(state="disabled" if is_disabled else "readonly")
        type_var.trace_add("write", _edit_toggle_order_type)
        asset_var.trace_add("write", _edit_toggle_order_type)
        _edit_toggle_order_type()

        # Account Selection
        tb.Label(frame, text="Account:").grid(row=7, column=0, sticky=W, pady=5)
        account_var = tb.StringVar()
        accounts = get_accounts(self.data)
        account_names = [acc["name"] for acc in accounts]
        # Find current account
        current_account_id = trade.get("account_id")
        if current_account_id:
            current_account = next((acc for acc in accounts if acc["id"] == current_account_id), None)
            if current_account:
                account_var.set(current_account["name"])
        account_combo = ttk.Combobox(frame, textvariable=account_var, values=account_names,
                                    state="readonly")
        account_combo.grid(row=7, column=1, sticky=EW, pady=5, padx=5)

        frame.grid_columnconfigure(1, weight=1)

        def save_edit():
            try:
                date_s = date_var.get().strip()
                time_s = time_var.get().strip()
                if not date_s or not time_s:
                    raise ValueError("Date and time are required")
                if len(time_s) == 5 and time_s.count(":") == 1:
                    time_s = time_s + ":00"
                new_date_str = f"{date_s} {time_s}"
                datetime.strptime(new_date_str, "%Y-%m-%d %H:%M:%S")

                asset = asset_var.get().strip().upper()
                trade_type = type_var.get()
                price = price_var.get()
                qty = qty_var.get()
                exchange = exchange_var.get()
                order_type = order_type_var.get()

                is_usd_fiat = (asset == "USD" and trade_type in ("Deposit", "Withdrawal"))
                is_transfer_holding = (trade_type in ("Transfer", "Holding"))
                if is_usd_fiat:
                    if price <= 0:
                        raise ValueError("Amount (USD) must be greater than 0")
                    qty = price  # amount
                    price = 0.0   # store 0 so UI can display blank for USD fiat
                    fee = 0.0
                    order_type = ""
                    exchange = ""
                    total_amount = qty
                else:
                    if not asset or price <= 0 or qty <= 0:
                        raise ValueError("Invalid input values")
                    if trade_type == "Holding":
                        available = self.get_available_quantity(asset)
                        if qty > available:
                            raise ValueError(f"Holding amount cannot exceed available. Available: {available:.8f}, Requested: {qty:.8f}")
                    if not is_transfer_holding:
                        if exchange not in self.data["settings"]["fee_structure"]:
                            raise ValueError("Invalid exchange selected")
                        fee_structure = self.data["settings"]["fee_structure"].get(exchange, {})
                        fee_rate = fee_structure.get(order_type, fee_structure.get("maker", 0.1))
                        total_amount = price * qty
                        fee = total_amount * (fee_rate / 100)
                    else:
                        order_type = ""
                        exchange = exchange or ""  # allow blank for Transfer/Holding
                        total_amount = price * qty
                        fee = 0.0

                # Account validation
                account_name = account_var.get()
                if not account_name:
                    raise ValueError("Account is required")
                selected_account = next((acc for acc in accounts if acc["name"] == account_name), None)
                if not selected_account:
                    raise ValueError("Invalid account selected")

                # Update trade
                trade["asset"] = asset
                trade["type"] = trade_type
                trade["price"] = round(price, 8)
                trade["quantity"] = qty
                trade["date"] = new_date_str
                trade["exchange"] = exchange
                trade["order_type"] = order_type
                trade["fee"] = round(fee, 8)
                trade["total_value"] = round(total_amount, 8)
                trade["account_id"] = selected_account["id"]
                # Remove old client fields if they exist
                trade.pop("is_client_trade", None)
                trade.pop("client_name", None)
                trade.pop("client_percentage", None)

                save_data(self.data, self.current_user)
                self.update_dashboard()
                self.update_summary_panel()
                dialog.destroy()
                self.log_activity(f"Edited {trade_type} order: {qty:.8f} {asset} @ ${price:,.2f} on {exchange} in account {account_name}")
            except Exception as e:
                messagebox.showerror("Error", f"Error saving trade: {e}")

        # Action buttons
        btn_row = tb.Frame(frame)
        btn_row.grid(row=8, column=0, columnspan=2, pady=20, sticky=E)
        tb.Button(btn_row, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=(0, 10))
        tb.Button(btn_row, text="Accept", command=save_edit, bootstyle=SUCCESS).pack(side=tk.LEFT)

    def delete_trade(self):
        """Delete selected trade using transaction table selection."""
        trade_id = getattr(self, "_transactions_selected_trade_id", None)
        if not trade_id:
            return
        if not messagebox.askyesno("Confirm Delete", "Are you sure you want to delete the selected trade?"):
            return
        ids_to_remove = {trade_id}
        self.data["trades"] = [t for t in self.data["trades"] if t.get("id") not in ids_to_remove]
        deleted_count = len(ids_to_remove)
        if deleted_count > 0:
            save_data(self.data, self.current_user)
            self.update_dashboard()
            self.update_summary_panel()
            self.log_activity(f"Deleted {deleted_count} trade(s) from {self.current_user}'s portfolio")
        else:
            messagebox.showwarning("Warning", "Could not find trade(s) to delete.")

    def show_context_menu(self, event):
        """Show context menu (selection already set by row right-click binding)."""
        try:
            self.menu.tk_popup(event.x_root, event.y_root)
        finally:
            self.menu.grab_release()

    def refresh_all_prices(self):
        """Refresh prices for all assets in portfolio (crypto only; skip USD)."""
        trades = self.data.get("trades", [])
        assets = list(set(t["asset"] for t in trades if t["asset"] != "USD"))
        if not assets:
            self.price_status_label.config(text="No assets to fetch prices for.")
            return
        self.price_status_label.config(text="Fetching prices...")
        self.update()
        updated_count = pricing_service.refresh_prices(assets, self.price_cache, save_price_cache)
        self.price_status_label.config(text=f"Updated {updated_count}/{len(assets)} prices")
        self.update_dashboard()
        self.update_summary_panel()
        self.log_activity(f"Refreshed prices for {updated_count} asset(s): {', '.join(sorted(assets))}")

    def get_current_price(self, asset: str) -> Optional[float]:
        """Get current price for an asset from cache or API. USDC is always 1:1 with USD."""
        return pricing_service.get_current_price(asset, self.price_cache, save_price_cache)

    def get_24h_pct(self, asset: str) -> Optional[float]:
        """Return 24h % price change from cache, or None if not available. USDC returns 0.0."""
        return pricing_service.get_24h_pct(asset, self.price_cache)

    def portfolio_24h_pct(self, per_asset: Dict[str, Dict[str, Any]]) -> Optional[float]:
        """Value-weighted 24h % for portfolio from per_asset metrics (only assets with 24h data)."""
        total_value = 0.0
        weighted_sum = 0.0
        for asset, data in per_asset.items():
            val = data.get("current_value") or 0.0
            pct = self.get_24h_pct(asset) if hasattr(self, "get_24h_pct") else None
            if pct is not None and val > 0:
                total_value += val
                weighted_sum += val * pct
        if total_value <= 0:
            return None
        return weighted_sum / total_value

    def portfolio_24h_usd(self, per_asset: Dict[str, Dict[str, Any]]) -> Optional[float]:
        """USD P&L in the last 24h: current value minus value 24h ago (using 24h % change)."""
        total_usd = 0.0
        for asset, data in per_asset.items():
            val = data.get("current_value") or 0.0
            pct = self.get_24h_pct(asset) if hasattr(self, "get_24h_pct") else None
            if pct is not None and val > 0:
                # value_24h_ago = val / (1 + pct/100); change = val - value_24h_ago
                total_usd += val * (pct / (100 + pct))
        return total_usd if total_usd != 0.0 else None

    def _asset_tree_tooltip_show(self, event):
        """Show tooltip with asset ticker only when hovering over the Asset column (first column)."""
        if self.asset_tree.identify_column(event.x) != "#1":
            self._asset_tree_tooltip_hide()
            return
        row = self.asset_tree.identify_row(event.y)
        if not row:
            self._asset_tree_tooltip_hide()
            return
        ticker = getattr(self, "_asset_tree_row_asset", {}).get(row, "")
        if not ticker:
            self._asset_tree_tooltip_hide()
            return
        if not hasattr(self, "_asset_tooltip_win") or not self._asset_tooltip_win.winfo_exists():
            self._asset_tooltip_win = tk.Toplevel(self)
            self._asset_tooltip_win.wm_overrideredirect(True)
            try:
                self._asset_tooltip_win.wm_attributes("-topmost", True)
            except tk.TclError:
                pass
            self._asset_tooltip_label = tk.Label(
                self._asset_tooltip_win, text="", font=SUMMARY_DESC_FONT,
                bg="#404040", fg="white", padx=6, pady=2,
            )
            self._asset_tooltip_label.pack()
        self._asset_tooltip_label.config(text=ticker)
        rx = self.asset_tree.winfo_rootx() + event.x
        ry = self.asset_tree.winfo_rooty() + event.y
        self._asset_tooltip_win.geometry(f"+{rx + 12}+{ry - 36}")
        self._asset_tooltip_win.deiconify()
        self._asset_tooltip_win.update_idletasks()
        self._asset_tooltip_win.lift()

    def _asset_tree_tooltip_hide(self, event=None):
        if hasattr(self, "_asset_tooltip_win") and self._asset_tooltip_win.winfo_exists():
            self._asset_tooltip_win.withdraw()

    def update_dashboard(self):
        """Update the dashboard with current portfolio data."""
        # Show/hide Client P&L section based on whether current user is a client
        if hasattr(self, "client_frame"):
            if self.data.get("settings", {}).get("is_client", False):
                self.client_frame.pack_forget()
            else:
                self.client_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        # Clear transactions table (data rows; header stays)
        if hasattr(self, "_transactions_inner"):
            for w in list(self._transactions_inner.winfo_children()):
                try:
                    if int(w.grid_info().get("row", 0)) > 0:
                        w.destroy()
                except (ValueError, TypeError):
                    w.destroy()

        for item in self.asset_tree.get_children():
            self.asset_tree.delete(item)
        self._asset_tree_row_asset = {}

        trades = self.data.get("trades", [])
        if not trades:
            self.total_invested_label.config(text="$0.00")
            self.current_portfolio_value_label.config(text="$0.00")
            self.total_pnl_label.config(text="$0.00")
            self.roi_label.config(text="0.00%")
            self.realized_pnl_label.config(text="$0.00")
            self.unrealized_pnl_label.config(text="$0.00")
            if hasattr(self, "roi_on_cost_label"):
                self.roi_on_cost_label.config(text="")
            if hasattr(self, "usd_cash_label"):
                self.usd_cash_label.config(text="$0.00")
            if hasattr(self, "portfolio_24h_label"):
                self.portfolio_24h_label.config(text="—")
            if hasattr(self, "cost_basis_label"):
                self.cost_basis_label.config(text="$0.00")
            if hasattr(self, "total_fees_label"):
                self.total_fees_label.config(text="$0.00")
            return

        # Sort trades by date
        trades.sort(key=lambda x: x["date"])

        # Apply asset filter (All / BTC / USDC) so Dashboard metrics match Summary
        metrics_trades = self._trades_for_metric_scope(trades, self.selected_asset_filter)
        metrics = self.compute_portfolio_metrics(metrics_trades)
        total_portfolio_value = metrics["total_value"]
        total_external_cash = metrics["total_external_cash"]
        realized_pnl = metrics["realized_pnl"]
        total_unrealized_pnl = metrics["unrealized_pnl"]
        total_pnl = metrics["total_pnl"]
        total_roi = metrics["roi_pct"]
        roi_on_cost = metrics.get("roi_on_cost_pct")
        self._animate_numeric_label(self.total_invested_label, f"${total_external_cash:,.2f}", fg=color_for_value(total_external_cash))
        self._animate_numeric_label(self.current_portfolio_value_label, f"${total_portfolio_value:,.2f}", fg=color_for_value(total_portfolio_value))
        self._animate_numeric_label(self.total_pnl_label, f"${total_pnl:,.2f}", fg=color_for_value(total_pnl))
        if total_external_cash > 0:
            self._animate_numeric_label(self.roi_label, f"{total_roi:.2f}%", fg=color_for_value(total_roi))
            self.roi_on_cost_label.config(text="")
        else:
            self.roi_label.config(text="N/A (no USD deposits)")
            self.roi_label.config(fg=SUMMARY_DESC_COLOR)
            if roi_on_cost is not None:
                self.roi_on_cost_label.config(text=f"ROI on cost: {roi_on_cost:.2f}%", fg=color_for_value(roi_on_cost))
            else:
                self.roi_on_cost_label.config(text="")
        self._animate_numeric_label(self.realized_pnl_label, f"${realized_pnl:,.2f}", fg=color_for_value(realized_pnl))
        self._animate_numeric_label(self.unrealized_pnl_label, f"${total_unrealized_pnl:,.2f}", fg=color_for_value(total_unrealized_pnl))

        # USD cash, portfolio 24h (USD change), cost basis, total fees
        usd_balance = metrics.get("usd_balance", 0.0)
        if hasattr(self, "usd_cash_label"):
            self.usd_cash_label.config(text=f"${usd_balance:,.2f}")
        portfolio_24h_usd = self.portfolio_24h_usd(metrics["per_asset"]) if hasattr(self, "portfolio_24h_usd") else None
        if hasattr(self, "portfolio_24h_label"):
            if portfolio_24h_usd is not None:
                self.portfolio_24h_label.config(text=f"${portfolio_24h_usd:+,.2f}", fg=color_for_value(portfolio_24h_usd))
            else:
                self.portfolio_24h_label.config(text="—", fg=SUMMARY_DESC_COLOR)
        if hasattr(self, "cost_basis_label"):
            cost_basis_tot = metrics.get("total_cost_basis_assets", 0.0)
            self.cost_basis_label.config(text=f"${cost_basis_tot:,.2f}")
        total_fees = sum(float(t.get("fee") or 0) for t in metrics_trades)
        if hasattr(self, "total_fees_label"):
            self.total_fees_label.config(text=f"${total_fees:,.2f}")

        # Populate asset breakdown (include closed positions with lifetime P&L)
        per_asset = metrics["per_asset"]
        for asset in sorted(per_asset.keys()):
            data = per_asset[asset]
            total_units = data["units_held"] + data["holding_qty"]
            price = data["price"]
            price_str = f"${price:.2f}" if price else "N/A"
            realized = data.get("realized_pnl", 0.0)
            unrealized = data["unrealized_pnl"]
            lifetime = data.get("lifetime_pnl", realized + unrealized)
            pct_24h = self.get_24h_pct(asset) if hasattr(self, "get_24h_pct") else None
            pct_24h_str = f"{pct_24h:+.2f}%" if pct_24h is not None else "—"

            row_color = color_for_value(lifetime)
            asset_icon = ASSET_ICONS.get(asset, asset[:2] if len(asset) >= 2 else asset)
            asset_display = asset_icon + (" (closed)" if total_units <= 0 else "")
            iid = self.asset_tree.insert('', tk.END, values=(
                asset_display,
                f"{total_units:.8f}",
                f"${data['cost_basis'] / data['units_held']:.2f}" if data["units_held"] > 0 else "$0.00",
                price_str,
                f"${data['current_value']:,.2f}",
                f"${realized:,.2f}",
                f"${unrealized:,.2f}",
                f"${lifetime:,.2f}",
                pct_24h_str,
                f"{data['roi_pct']:.2f}%"
            ), tags=(row_color,))
            self.asset_tree.tag_configure(row_color, foreground=row_color)
            self._asset_tree_row_asset[iid] = asset

        # Client P&L Summary: when current user is NOT a client (manager view), show all client users' P&L
        if hasattr(self, "client_pnl_tree"):
            for item in self.client_pnl_tree.get_children():
                self.client_pnl_tree.delete(item)
            if self.data["settings"].get("is_client", False):
                # Current user is a client: show only their row
                client_buy_cost = sum(t["total_value"] + t["fee"] for t in trades if t["type"] in ("BUY", "Transfer"))
                client_sell_proceeds = sum(t["total_value"] - t["fee"] for t in trades if t["type"] == "SELL")
                client_current_value = total_portfolio_value
                client_pnl = (client_current_value + client_sell_proceeds) - client_buy_cost
                client_percentage = self.data["settings"].get("client_percentage", 0.0)
                your_share = client_pnl * (client_percentage / 100)
                self.client_pnl_tree.insert("", tk.END, values=(
                    self.current_user,
                    f"{client_percentage:.1f}%",
                    f"${client_pnl:,.2f}",
                    f"${your_share:,.2f}",
                ))
            else:
                # Manager view: load each client user's data and add a row
                for username in self.users:
                    try:
                        client_data = load_data(username)
                    except Exception:
                        continue
                    if not client_data.get("settings", {}).get("is_client", False):
                        continue
                    client_trades = client_data.get("trades", [])
                    if not client_trades:
                        continue
                    client_metrics = self.compute_portfolio_metrics(client_trades)
                    client_current_value = client_metrics["total_value"]
                    client_buy_cost = sum(t["total_value"] + (t.get("fee") or 0) for t in client_trades if t.get("type") in ("BUY", "Transfer"))
                    client_sell_proceeds = sum(t["total_value"] - (t.get("fee") or 0) for t in client_trades if t.get("type") == "SELL")
                    client_pnl = (client_current_value + client_sell_proceeds) - client_buy_cost
                    client_percentage = client_data["settings"].get("client_percentage", 0.0)
                    your_share = client_pnl * (client_percentage / 100)
                    self.client_pnl_tree.insert("", tk.END, values=(
                        username,
                        f"{client_percentage:.1f}%",
                        f"${client_pnl:,.2f}",
                        f"${your_share:,.2f}",
                    ))

        # Build trades table rows (Fees and Profit cells colored only)
        trades_sorted = sorted(trades, key=lambda x: x["date"], reverse=True)
        method = self.data.get("settings", {}).get("cost_basis_method", "average")
        realized_pnl = compute_realized_pnl_per_trade(trades, method)
        buy_profit = compute_buy_profit_per_trade(trades)
        accounts = get_accounts(self.data)
        account_dict = {acc["id"]: acc["name"] for acc in accounts}
        btc_price = self.get_current_price("BTC") if self.profit_display_currency == "BTC" else None

        rows_data: List[Tuple[Dict, Tuple, float, Optional[float]]] = []
        for trade in trades_sorted:
            is_usd_fiat = (trade["asset"] == "USD" and trade["type"] in ("Deposit", "Withdrawal"))
            order_type = trade.get("order_type") or ""
            account_id = trade.get("account_id")
            account_name = account_dict.get(account_id, "Unknown") if account_id else "None"
            price_display = "" if is_usd_fiat else f"${trade['price']:.2f}"
            exchange_display = trade.get("exchange") or ""
            order_type_display = (order_type.title() if order_type else "")
            fee_val = trade.get("fee") or 0
            fee_display = f"${fee_val:.2f}" if fee_val == 0 else f"-${fee_val:.2f}"
            tid = trade.get("id", "")
            profit_usd = realized_pnl.get(tid) if trade.get("type") == "SELL" else buy_profit.get(tid)
            if profit_usd is None:
                profit_display = "—"
            elif self.profit_display_currency == "BTC" and btc_price and btc_price > 0:
                profit_display = f"{profit_usd / btc_price:.8f} BTC"
            else:
                profit_display = f"${profit_usd:,.2f}"
            date_str = str(trade.get("date", ""))
            date_display = date_str.split()[0] if date_str and " " in date_str else date_str
            type_display = (trade.get("type") or "").title()
            qty = trade.get("quantity", 0)
            asset = trade.get("asset") or ""
            if asset in ("USD", "USDC"):
                quantity_display = f"{qty:.2f}"
            else:
                quantity_display = f"{qty:.4f}"
            values_tuple = (
                date_display, trade["asset"], type_display, price_display,
                quantity_display, exchange_display, order_type_display,
                account_name, fee_display, f"${trade['total_value']:.2f}", profit_display,
            )
            rows_data.append((trade, values_tuple, float(fee_val), profit_usd))

        if getattr(self, "_tree_sort_col", None) and rows_data:
            col = self._tree_sort_col
            def sort_key(row):
                trade, values_tuple, fee_val, profit_usd = row
                val = values_tuple[self._transactions_columns.index(col)]
                if col in ("Price", "Quantity", "Fees", "Total", "Profit"):
                    if not val or val == "—":
                        return 0.0
                    try:
                        return float(val.replace("$", "").replace(",", ""))
                    except ValueError:
                        return 0.0
                return val
            rows_data.sort(key=sort_key, reverse=getattr(self, "_tree_sort_reverse", False))

        if hasattr(self, "_repopulate_transactions_table"):
            self._repopulate_transactions_table(rows_data)

        # Restore persisted projections (per-user). Backward compat: 4-col rows -> 6 (Amount $, Account).
        if hasattr(self, "proj_tree"):
            for iid in self.proj_tree.get_children(""):
                self.proj_tree.delete(iid)
            for row in self.data.get("projections", []):
                if not isinstance(row, (list, tuple)) or len(row) < 4:
                    continue
                if len(row) >= 6:
                    self.proj_tree.insert("", tk.END, values=(row[0], row[1], row[2], row[3], row[4], row[5]))
                else:
                    try:
                        amt = float(str(row[2]).replace("$", "").replace(",", "")) * float(str(row[3]).replace(",", ""))
                        self.proj_tree.insert("", tk.END, values=(row[0], row[1], row[2], row[3], f"{amt:.2f}", ""))
                    except (ValueError, TypeError):
                        self.proj_tree.insert("", tk.END, values=(row[0], row[1], row[2], row[3], "", ""))
            self.run_projection_from_table()

        self.log_text.config(state='normal')
        self.log_text.insert(tk.END, f"Dashboard Updated: {datetime.now().strftime('%H:%M:%S')}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state='disabled')

    def _proj_add_row(self):
        """Add a row to the potential transactions table (dialog). BUY uses Amount (USD); SELL uses Quantity. Account and Qty % use account portfolio (BUY) or holding (SELL)."""
        d = tk.Toplevel(self)
        d.title("Add potential transaction")
        d.geometry("420x340")
        d.transient(self)
        d.grab_set()
        f = tb.Frame(d, padding=10)
        f.pack(fill="both", expand=True)
        tk.Label(f, text="Asset:").grid(row=0, column=0, sticky=W, pady=5)
        asset_var = tb.StringVar(value="BTC")
        asset_combo = ttk.Combobox(f, textvariable=asset_var, values=TRANSACTION_ASSETS, state="readonly", width=14)
        asset_combo.grid(row=0, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Type:").grid(row=1, column=0, sticky=W, pady=5)
        type_var = tb.StringVar(value="BUY")
        type_combo = ttk.Combobox(f, textvariable=type_var, values=TRADE_TYPES_CRYPTO, state="readonly", width=14)
        type_combo.grid(row=1, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Account:").grid(row=2, column=0, sticky=W, pady=5)
        accounts = get_accounts(self.data)
        account_names = [acc.get("name") or f"Account {acc.get('id', '')}" for acc in accounts]
        account_var = tb.StringVar(value=account_names[0] if account_names else "")
        account_combo = ttk.Combobox(f, textvariable=account_var, values=account_names, state="readonly", width=14)
        account_combo.grid(row=2, column=1, sticky=EW, pady=5, padx=5)
        price_lbl = tk.Label(f, text="Price ($):")
        price_lbl.grid(row=3, column=0, sticky=W, pady=5)
        price_var = tb.StringVar(value="0")
        price_entry = tb.Entry(f, textvariable=price_var, width=16)
        price_entry.grid(row=3, column=1, sticky=EW, pady=5, padx=5)
        qty_lbl = tk.Label(f, text="Quantity:")
        qty_lbl.grid(row=4, column=0, sticky=W, pady=5)
        qty_var = tb.StringVar(value="0")
        qty_entry = tb.Entry(f, textvariable=qty_var, width=16)
        qty_entry.grid(row=4, column=1, sticky=EW, pady=5, padx=5)
        f.grid_columnconfigure(1, weight=1)

        def _sync_proj_asset_type():
            a = asset_var.get().strip().upper()
            if a == "USD":
                type_combo["values"] = TRADE_TYPES_USD
                if type_var.get() not in TRADE_TYPES_USD:
                    type_var.set(TRADE_TYPES_USD[0])
            else:
                type_combo["values"] = TRADE_TYPES_CRYPTO
                if type_var.get() not in TRADE_TYPES_CRYPTO:
                    type_var.set(TRADE_TYPES_CRYPTO[0])
            _toggle_proj_usd_fields()

        def _toggle_proj_usd_fields():
            a, t = asset_var.get().strip().upper(), type_var.get()
            is_usd_fiat = (a == "USD" and t in ("Deposit", "Withdrawal"))
            is_buy = (t == "BUY" and a != "USD")
            state_qty = "disabled" if is_usd_fiat else "normal"
            qty_entry.config(state=state_qty)
            if is_usd_fiat:
                pct_row_outer.grid_remove()
                price_lbl.config(text="Amount (USD):")
                qty_lbl.config(text="Quantity: (N/A)")
            else:
                pct_row_outer.grid(row=5, column=0, columnspan=2, pady=5)
                price_lbl.config(text="Price ($):")
                qty_lbl.config(text="Amount (USD):" if is_buy else "Quantity:")

        asset_var.trace_add("write", lambda *a: _sync_proj_asset_type())
        type_var.trace_add("write", lambda *a: _toggle_proj_usd_fields())

        def add():
            try:
                a, t = asset_var.get().strip().upper(), type_var.get()
                p = float(price_var.get())
                account_name = (account_var.get() or "").strip()
                is_usd_fiat = (a == "USD" and t in ("Deposit", "Withdrawal"))
                is_buy = (t == "BUY" and a != "USD")
                if is_usd_fiat:
                    q = p
                    amount_usd = p
                elif is_buy:
                    amount_usd = float(qty_var.get())
                    q = amount_usd / p if p else 0.0
                else:
                    q = float(qty_var.get())
                    amount_usd = p * q
                self.proj_tree.insert("", tk.END, values=(a, t, f"{p:.2f}", f"{q:.8f}", f"{amount_usd:.2f}", account_name))
                d.destroy()
                self._save_projections()
                self.run_projection_from_table()
            except ValueError:
                messagebox.showwarning("Invalid", "Price and quantity/amount must be numbers.", parent=d)

        # Qty %: for BUY = % of account portfolio (USD to spend); for SELL = % of holding
        pct_row_outer = tb.Frame(f)
        pct_row_outer.grid(row=5, column=0, columnspan=2, pady=5)
        pct_row = tb.Frame(pct_row_outer)
        pct_row.pack()
        pct_label_var = tb.StringVar(value="Qty % of holding:")

        def set_pct(pct):
            try:
                a, t = asset_var.get().strip().upper(), type_var.get()
                if t == "BUY" and a != "USD":
                    acc_id = None
                    for acc in accounts:
                        if (acc.get("name") or f"Account {acc.get('id', '')}") == account_var.get():
                            acc_id = acc.get("id")
                            break
                    port_val = self.get_account_portfolio_value(acc_id)
                    amount_usd = port_val * pct / 100.0
                    qty_var.set(f"{amount_usd:.2f}")
                else:
                    av = self.get_available_quantity(a)
                    qty_var.set(f"{(av * pct / 100):.8f}")
            except Exception:
                pass

        def _update_pct_label():
            t = type_var.get()
            a = asset_var.get().strip().upper()
            if t == "BUY" and a != "USD":
                pct_label_var.set("Qty % of portfolio (Amount USD):")
            else:
                pct_label_var.set("Qty % of holding:")

        tk.Label(pct_row, textvariable=pct_label_var).pack(side=tk.LEFT, padx=(0, 8))
        for p in (25, 50, 75, 100):
            tb.Button(pct_row, text=f"{p}%", width=4, command=lambda x=p: set_pct(x), bootstyle=SECONDARY).pack(side=tk.LEFT, padx=2)
        type_var.trace_add("write", lambda *a: _update_pct_label())
        asset_var.trace_add("write", lambda *a: _update_pct_label())
        btn_row = tb.Frame(f)
        btn_row.grid(row=6, column=0, columnspan=2, pady=10)
        tb.Button(btn_row, text="Cancel", command=d.destroy).pack(side=tk.LEFT, padx=(0, 10))
        tb.Button(btn_row, text="Add", command=add, bootstyle=SUCCESS).pack(side=tk.LEFT)

    def _save_projections(self):
        """Persist projections table to user data so it survives session and user switch."""
        if not hasattr(self, "proj_tree"):
            return
        self.data["projections"] = [list(self.proj_tree.item(i, "values")) for i in self.proj_tree.get_children("")]
        save_data(self.data, self.current_user)

    def _proj_remove_row(self):
        """Remove selected row from potential transactions table."""
        sel = self.proj_tree.selection()
        for i in sel:
            self.proj_tree.delete(i)
        self._save_projections()
        self.run_projection_from_table()

    def _show_proj_context_menu(self, event):
        """Show right-click context menu on projections table: Delete, Edit."""
        sel = self.proj_tree.identify_row(event.y)
        if not sel:
            return
        self.proj_tree.selection_set(sel)
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Edit", command=self._proj_edit_row)
        menu.add_command(label="Delete", command=lambda: (self._proj_remove_row(), None))
        try:
            menu.tk_popup(event.x_root, event.y_root)
        finally:
            menu.grab_release()

    def _proj_edit_row(self):
        """Edit selected row in potential transactions table. BUY = Amount (USD); SELL = Quantity; Account stored."""
        sel = self.proj_tree.selection()
        if not sel:
            return
        row_id = sel[0]
        vals = self.proj_tree.item(row_id, "values")
        if len(vals) < 4:
            return
        account_name = (vals[5] if len(vals) > 5 else "") or ""
        accounts = get_accounts(self.data)
        account_names = [acc.get("name") or f"Account {acc.get('id', '')}" for acc in accounts]
        if account_name and account_name not in account_names:
            account_names.insert(0, account_name)
        d = tk.Toplevel(self)
        d.title("Edit potential transaction")
        d.geometry("420x320")
        d.transient(self)
        d.grab_set()
        f = tb.Frame(d, padding=10)
        f.pack(fill="both", expand=True)
        tk.Label(f, text="Asset:").grid(row=0, column=0, sticky=W, pady=5)
        asset_var = tb.StringVar(value=vals[0])
        ttk.Combobox(f, textvariable=asset_var, values=TRANSACTION_ASSETS, state="readonly", width=14).grid(row=0, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Type:").grid(row=1, column=0, sticky=W, pady=5)
        type_var = tb.StringVar(value=vals[1])
        type_values = TRADE_TYPES_USD if vals[0] == "USD" else TRADE_TYPES_CRYPTO
        if vals[1] not in type_values:
            type_var.set(type_values[0])
        type_combo = ttk.Combobox(f, textvariable=type_var, values=type_values, state="readonly", width=14)
        type_combo.grid(row=1, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Account:").grid(row=2, column=0, sticky=W, pady=5)
        account_var = tb.StringVar(value=account_name)
        ttk.Combobox(f, textvariable=account_var, values=account_names, state="readonly", width=14).grid(row=2, column=1, sticky=EW, pady=5, padx=5)
        price_lbl = tk.Label(f, text="Amount (USD):" if (vals[0] == "USD" and type_var.get() in ("Deposit", "Withdrawal")) else "Price ($):")
        price_lbl.grid(row=3, column=0, sticky=W, pady=5)
        price_var = tb.StringVar(value=vals[2])
        tb.Entry(f, textvariable=price_var, width=16).grid(row=3, column=1, sticky=EW, pady=5, padx=5)
        is_buy = (vals[1] == "BUY" and vals[0] != "USD")
        amt_usd = (vals[4] if len(vals) > 4 else "") or ""
        if is_buy and amt_usd:
            qty_initial = amt_usd
        else:
            qty_initial = vals[3]
        qty_lbl = tk.Label(f, text="Quantity: (N/A)" if (vals[0] == "USD" and type_var.get() in ("Deposit", "Withdrawal")) else ("Amount (USD):" if is_buy else "Quantity:"))
        qty_lbl.grid(row=4, column=0, sticky=W, pady=5)
        qty_var = tb.StringVar(value=qty_initial)
        qty_entry = tb.Entry(f, textvariable=qty_var, width=16)
        qty_entry.grid(row=4, column=1, sticky=EW, pady=5, padx=5)
        if vals[0] == "USD" and type_var.get() in ("Deposit", "Withdrawal"):
            qty_entry.config(state="disabled")
        f.grid_columnconfigure(1, weight=1)

        def _sync_edit_asset_type():
            a = asset_var.get().strip().upper()
            if a == "USD":
                type_combo["values"] = TRADE_TYPES_USD
                if type_var.get() not in TRADE_TYPES_USD:
                    type_var.set(TRADE_TYPES_USD[0])
            else:
                type_combo["values"] = TRADE_TYPES_CRYPTO
                if type_var.get() not in TRADE_TYPES_CRYPTO:
                    type_var.set(TRADE_TYPES_CRYPTO[0])
            _toggle_edit_usd()

        def _toggle_edit_usd():
            a, t = asset_var.get().strip().upper(), type_var.get()
            is_usd_fiat = (a == "USD" and t in ("Deposit", "Withdrawal"))
            is_buy = (t == "BUY" and a != "USD")
            qty_entry.config(state="disabled" if is_usd_fiat else "normal")
            if is_usd_fiat:
                price_lbl.config(text="Amount (USD):")
                qty_lbl.config(text="Quantity: (N/A)")
            else:
                price_lbl.config(text="Price ($):")
                qty_lbl.config(text="Amount (USD):" if is_buy else "Quantity:")

        asset_var.trace_add("write", lambda *a: _sync_edit_asset_type())
        type_var.trace_add("write", lambda *a: _toggle_edit_usd())

        def save_edit():
            try:
                a, t = asset_var.get().strip().upper(), type_var.get()
                p = float(price_var.get())
                account_name_s = (account_var.get() or "").strip()
                is_usd_fiat = (a == "USD" and t in ("Deposit", "Withdrawal"))
                is_buy = (t == "BUY" and a != "USD")
                if is_usd_fiat:
                    q = p
                    amount_usd = p
                elif is_buy:
                    amount_usd = float(qty_var.get())
                    q = amount_usd / p if p else 0.0
                else:
                    q = float(qty_var.get())
                    amount_usd = p * q
                try:
                    if row_id not in self.proj_tree.get_children(""):
                        d.destroy()
                        return
                    self.proj_tree.item(row_id, values=(a, t, f"{p:.2f}", f"{q:.8f}", f"{amount_usd:.2f}", account_name_s))
                except tk.TclError:
                    d.destroy()
                    return
                d.destroy()
                self._save_projections()
                self.run_projection_from_table()
            except ValueError:
                messagebox.showwarning("Invalid", "Price and quantity/amount must be numbers.", parent=d)

        btn_row = tb.Frame(f)
        btn_row.grid(row=5, column=0, columnspan=2, pady=10, sticky=E)
        tb.Button(btn_row, text="Cancel", command=d.destroy).pack(side=tk.LEFT, padx=(0, 10))
        tb.Button(btn_row, text="Save", command=save_edit, bootstyle=SUCCESS).pack(side=tk.LEFT)

    def run_projection_from_table(self):
        """Compute projected P&L, cost, and value from current holdings + potential transactions table.

        This uses the canonical portfolio valuation helper by adding synthetic trades
        representing the rows in the projections table on top of the real trades.
        """
        real_trades = list(self.data.get("trades", []))
        # Base time for synthetic trades: after the last real trade so projections apply sequentially
        if real_trades:
            try:
                last_dt = max(datetime.strptime(t["date"], "%Y-%m-%d %H:%M:%S") for t in real_trades)
            except (ValueError, KeyError):
                last_dt = datetime.now()
        else:
            last_dt = datetime.now()
        trades = list(real_trades)
        accounts = get_accounts(self.data)
        name_to_id = {acc.get("name") or f"Account {acc.get('id', '')}": acc.get("id") for acc in accounts}
        for i, row in enumerate(self.proj_tree.get_children("")):
            vals = self.proj_tree.item(row, "values")
            try:
                asset, typ, price_s, qty_s = vals[0], vals[1], vals[2], vals[3]
                price = float(price_s.replace("$", "").replace(",", ""))
                qty = float(qty_s.replace(",", ""))
                if price <= 0 or qty <= 0:
                    continue
                total = price * qty
                account_name = (vals[5] if len(vals) > 5 else "") or ""
                account_id = name_to_id.get(account_name)
                # Sequential timestamps so projection row 2 builds on row 1, etc.
                syn_dt = last_dt + timedelta(seconds=i + 1)
                syn_date = syn_dt.strftime("%Y-%m-%d %H:%M:%S")
                trades.append({
                    "id": str(uuid.uuid4()), "date": syn_date,
                    "asset": asset, "type": typ, "price": price, "quantity": qty, "fee": 0, "total_value": total,
                    "exchange": "", "order_type": "maker", "account_id": account_id
                })
            except (ValueError, IndexError):
                continue
        if not trades:
            self.proj_result_label.config(text="-- (add transactions)", fg="gray")
            if hasattr(self, "proj_cost_label"):
                self.proj_cost_label.config(text="--")
            if hasattr(self, "proj_value_label"):
                self.proj_value_label.config(text="--")
            return

        metrics = self.compute_portfolio_metrics(trades)
        total_value = metrics["total_value"]
        total_external_cash = metrics["total_external_cash"]
        total_pnl = metrics["total_pnl"]
        # For projections, we treat cost as external cash and value as projected portfolio value
        pnl = total_pnl
        self._animate_numeric_label(self.proj_result_label, f"${pnl:,.2f}", fg=color_for_value(pnl))
        if hasattr(self, "proj_cost_label"):
            self.proj_cost_label.config(text=f"${total_external_cash:,.2f}")
        if hasattr(self, "proj_value_label"):
            self.proj_value_label.config(text=f"${total_value:,.2f}")

    def run_projection(self):
        """Legacy: redirect to table-based projection."""
        self.run_projection_from_table()

    def toggle_client_percentage(self):
        """Enable/disable client percentage field based on checkbox."""
        if self.is_client_var.get():
            self.client_percentage_entry.config(state="normal")
        else:
            self.client_percentage_entry.config(state="disabled")

    def save_settings(self):
        """Save application settings."""
        self.data["settings"]["default_exchange"] = self.default_exchange_var.get()
        self.data["settings"]["cost_basis_method"] = self.cost_basis_method_var.get()
        self.data["settings"]["is_client"] = self.is_client_var.get()

        # Validate and save client percentage
        if self.is_client_var.get():
            try:
                client_pct = float(self.client_percentage_var.get().strip())
                if client_pct < 0 or client_pct > 100:
                    raise ValueError("Client percentage must be between 0 and 100")
                self.data["settings"]["client_percentage"] = client_pct
            except ValueError as e:
                messagebox.showerror("Input Error", f"Invalid client percentage: {e}")
                return
        else:
            self.data["settings"]["client_percentage"] = 0.0

        save_data(self.data, self.current_user)
        messagebox.showinfo("Settings", "Settings saved successfully.")
        self.update_dashboard()
        self.update_summary_panel()
        self.log_activity(f"Updated settings: default exchange={self.default_exchange_var.get()}, cost basis={self.cost_basis_method_var.get()}, is_client={self.is_client_var.get()}")

    def export_trades(self):
        """Export trades to JSON file."""
        ui_dialogs.export_trades(self)

    def import_trades(self):
        """Import trades from JSON file."""
        ui_dialogs.import_trades(self)

    def reset_data(self):
        """Reset all trade data."""
        if messagebox.askyesno("Reset Data",
                              "This will permanently delete all trade history. Continue?"):
            trade_count = len(self.data["trades"])
            self.data["trades"] = []
            save_data(self.data, self.current_user)
            self.update_dashboard()
            self.update_summary_panel()
            messagebox.showinfo("Reset", "Data reset successfully.")
            self.log_activity(f"Reset all data: deleted {trade_count} trade(s) for user {self.current_user}")

    def log_activity(self, msg: str):
        """Log activity message."""
        self.log_text.config(state='normal')
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"[{timestamp}] {msg}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state='disabled')


def main() -> None:
    """Entry point for the legacy Tkinter app: create window and run mainloop."""
    app = CryptoTrackerApp()
    app.mainloop()


# --- Run Application ---
if __name__ == "__main__":
    main()
