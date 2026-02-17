<<<<<<< Current (Your changes)
=======
"""
Crypto PnL Tracker Application for macOS

A GUI application for tracking cryptocurrency trades, calculating P&L, ROI,
and projections with support for multiple exchanges and cost basis methods.
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from tkinter.constants import W, EW, E
import ttkbootstrap as tb
from ttkbootstrap.constants import SUCCESS, DANGER, PRIMARY, INFO
import json
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import requests
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

# --- Configuration & Data Management ---
USERS_FILE = "users.json"
DATA_FILE = "crypto_data.json"
PRICE_CACHE_FILE = "price_cache.json"
COINGECKO_API_URL = "https://api.coingecko.com/api/v3/simple/price"


def get_user_data_file(username: str) -> str:
    """
    Get the data file path for a specific user.

    Args:
        username: The username

    Returns:
        Path to the user's data file
    """
    return f"crypto_data_{username.lower().replace(' ', '_')}.json"


def load_users() -> List[str]:
    """
    Load list of users from users file.

    Returns:
        List of usernames
    """
    if os.path.exists(USERS_FILE):
        try:
            with open(USERS_FILE, 'r') as f:
                users_data = json.load(f)
                return users_data.get("users", ["Default"])
        except:
            pass
    return ["Default"]


def save_users(users: List[str]) -> None:
    """
    Save list of users to users file.

    Args:
        users: List of usernames
    """
    try:
        with open(USERS_FILE, 'w') as f:
            json.dump({"users": users}, f, indent=4)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving users: {e}")


def add_user(username: str) -> bool:
    """
    Add a new user to the system.

    Args:
        username: The username to add

    Returns:
        True if successful, False otherwise
    """
    users = load_users()
    if username in users:
        return False
    users.append(username)
    save_users(users)
    return True


def delete_user(username: str) -> bool:
    """
    Delete a user from the system.

    Args:
        username: The username to delete

    Returns:
        True if successful, False otherwise
    """
    users = load_users()
    if username not in users or len(users) == 1:
        return False
    users.remove(username)
    save_users(users)
    # Optionally delete user's data file
    user_file = get_user_data_file(username)
    if os.path.exists(user_file):
        try:
            os.remove(user_file)
        except:
            pass
    return True

# Default exchange configuration with maker/taker fees
DEFAULT_EXCHANGES = {
    "Binance": {"maker": 0.10, "taker": 0.10},
    "Coinbase Pro": {"maker": 0.40, "taker": 0.50},
    "Kraken": {"maker": 0.16, "taker": 0.26},
    "Bybit": {"maker": 0.10, "taker": 0.10},
    "Crypto.com": {"maker": 0.40, "taker": 0.40},
    "Bitstamp": {"maker": 0.50, "taker": 0.50}
}

# Common cryptocurrency assets for dropdown (USD added for transactions)
COMMON_ASSETS = ["BTC", "ETH", "BNB", "ADA", "SOL", "XRP", "DOT", "DOGE", "MATIC", "AVAX", "LINK", "UNI", "ATOM", "LTC", "ALGO"]
TRANSACTION_ASSETS = ["USD"] + COMMON_ASSETS
# Transaction types: BUY/SELL for trading; Holding/Transfer = BTC (crypto) only; Withdrawal/Deposit = USD only
TRADE_TYPES_ALL = ["BUY", "SELL", "Holding", "Transfer", "Withdrawal", "Deposit"]
TRADE_TYPES_CRYPTO = ["BUY", "SELL", "Holding", "Transfer"]
TRADE_TYPES_USD = ["Deposit", "Withdrawal"]
# Types that are not part of "initial capital" for investment (Holding, Transfer, Withdrawal, Deposit)
NON_INVESTMENT_TYPES = {"Holding", "Transfer", "Withdrawal", "Deposit"}

# Apple Design Constants
APPLE_FONT_FAMILY = "SF Pro Display"  # Primary font, falls back to system default
APPLE_FONT_DEFAULT = ("SF Pro Display", 12)  # Use tuple so Tk doesn't parse family as "SF", size "Pro"
APPLE_COLOR_PROFIT = "#30D158"  # Green
APPLE_COLOR_LOSS = "#FF3B30"    # Red
APPLE_SPACING_SMALL = 4
APPLE_SPACING_MEDIUM = 8
APPLE_SPACING_LARGE = 16
APPLE_SPACING_XLARGE = 24
APPLE_PADDING = 16
APPLE_BORDER_RADIUS = 8
# Max widths for sidebar/summary so they don't exceed content (with padding)
MAX_SIDEBAR_WIDTH = 280
MAX_SUMMARY_WIDTH = 380
# Tighter spacing in summary panel; outer margins for summary/assets/positions
SUMMARY_PAD = 6
SUMMARY_OUTER_PAD = 20
SUMMARY_CONTENT_PADX = 12
SUMMARY_VALUE_FONT = ("SF Pro Display", 16, "bold")
SUMMARY_DESC_FONT = ("SF Pro Display", 9)
SUMMARY_DESC_COLOR = "#888888"


def migrate_exchange_fees(old_exchanges: Dict) -> Dict:
    """
    Migrate old single-fee exchange structure to maker/taker structure.

    Args:
        old_exchanges: Dictionary with exchange names as keys and single fee rates as values

    Returns:
        Dictionary with maker/taker fee structure
    """
    migrated = {}
    for exchange, fee in old_exchanges.items():
        if isinstance(fee, dict) and "maker" in fee and "taker" in fee:
            # Already in new format
            migrated[exchange] = fee
        else:
            # Old format - use same fee for both maker and taker
            migrated[exchange] = {"maker": fee, "taker": fee}
    return migrated


def load_data(username: str = "Default") -> Dict:
    """
    Load application data from JSON file with migration support.

    Args:
        username: The username to load data for

    Returns:
        Dictionary containing trades, settings, account_groups, accounts, and exchange configurations
    """
    data_file = get_user_data_file(username)

    # Migrate old default file if it exists and user is Default
    if username == "Default" and os.path.exists(DATA_FILE) and not os.path.exists(data_file):
        try:
            import shutil
            shutil.copy(DATA_FILE, data_file)
        except:
            pass

    if os.path.exists(data_file):
        try:
            with open(data_file, 'r') as f:
                data = json.load(f)

                # Migrate exchange fees if needed
                if "settings" in data and "fee_structure" in data["settings"]:
                    old_fees = data["settings"]["fee_structure"]
                    data["settings"]["fee_structure"] = migrate_exchange_fees(old_fees)

                # Migrate to new account/group structure
                data = migrate_to_account_structure(data, username)

                # Add unique IDs to trades that don't have them
                if "trades" in data:
                    for trade in data["trades"]:
                        if "id" not in trade:
                            trade["id"] = str(uuid.uuid4())
                        # Ensure account_id exists
                        if "account_id" not in trade:
                            # Assign to default account if exists
                            if "accounts" in data and data["accounts"]:
                                trade["account_id"] = data["accounts"][0]["id"]
                            else:
                                trade["account_id"] = None

                # Set default cost basis method if not present
                if "settings" in data and "cost_basis_method" not in data["settings"]:
                    data["settings"]["cost_basis_method"] = "average"

                # Initialize user settings
                if "settings" not in data:
                    data["settings"] = {}
                if "fee_structure" not in data["settings"]:
                    data["settings"]["fee_structure"] = DEFAULT_EXCHANGES.copy()
                if "is_client" not in data["settings"]:
                    data["settings"]["is_client"] = False
                if "client_percentage" not in data["settings"]:
                    data["settings"]["client_percentage"] = 0.0
                if "default_account_id" not in data["settings"]:
                    data["settings"]["default_account_id"] = None

                # Initialize account_groups and accounts if missing
                if "account_groups" not in data:
                    data["account_groups"] = []
                if "accounts" not in data:
                    data["accounts"] = []

                return data
        except Exception as e:
            messagebox.showerror("Data Load Error", f"Error loading data: {e}")

    # Return default structure with account migration
    default_data = {
        "trades": [],
        "settings": {
            "default_exchange": "Bitstamp",
            "fee_structure": DEFAULT_EXCHANGES.copy(),
            "cost_basis_method": "average",
            "is_client": False,
            "client_percentage": 0.0,
            "default_account_id": None
        },
        "account_groups": [],
        "accounts": []
    }

    # Create default account group and account
    default_group_id = create_account_group_in_data(default_data, "My Portfolio")
    default_account_id = create_account_in_data(default_data, "Main", default_group_id)
    default_data["settings"]["default_account_id"] = default_account_id

    return default_data


def migrate_to_account_structure(data: Dict, username: str) -> Dict:
    """
    Migrate existing data to account/group structure.

    Args:
        data: Existing data dictionary
        username: Username for migration context

    Returns:
        Migrated data dictionary
    """
    # Initialize account_groups and accounts if missing
    if "account_groups" not in data:
        data["account_groups"] = []
    if "accounts" not in data:
        data["accounts"] = []

    # If no accounts exist, create default structure
    if not data["accounts"]:
        # Create default account group
        default_group_id = create_account_group_in_data(data, "My Portfolio")
        # Create default account
        default_account_id = create_account_in_data(data, "Main", default_group_id)
        # Set as default
        if "settings" not in data:
            data["settings"] = {}
        data["settings"]["default_account_id"] = default_account_id

        # Assign all existing trades to default account
        if "trades" in data:
            for trade in data["trades"]:
                trade["account_id"] = default_account_id
                # Remove old client fields
                trade.pop("is_client_trade", None)
                trade.pop("client_name", None)
                trade.pop("client_percentage", None)

    # Migrate user settings for client tracking
    if "settings" not in data:
        data["settings"] = {}

    # Check if user was a client (if any trades had client_name)
    if "trades" in data:
        had_client_trades = any(trade.get("is_client_trade", False) for trade in data["trades"])
        if had_client_trades and "is_client" not in data["settings"]:
            # Find client percentage from trades
            client_trades = [t for t in data["trades"] if t.get("is_client_trade", False)]
            if client_trades:
                data["settings"]["is_client"] = True
                data["settings"]["client_percentage"] = client_trades[0].get("client_percentage", 0.0)

    return data


def create_account_group_in_data(data: Dict, name: str) -> str:
    """
    Create an account group in the data structure.

    Args:
        data: Data dictionary
        name: Group name

    Returns:
        Group ID (UUID)
    """
    group_id = str(uuid.uuid4())
    group = {
        "id": group_id,
        "name": name,
        "accounts": []
    }
    if "account_groups" not in data:
        data["account_groups"] = []
    data["account_groups"].append(group)
    return group_id


def create_account_in_data(data: Dict, name: str, group_id: Optional[str] = None) -> str:
    """
    Create an account in the data structure.

    Args:
        data: Data dictionary
        name: Account name
        group_id: Optional group ID to assign account to

    Returns:
        Account ID (UUID)
    """
    account_id = str(uuid.uuid4())
    account = {
        "id": account_id,
        "name": name,
        "account_group_id": group_id,
        "created_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    if "accounts" not in data:
        data["accounts"] = []
    data["accounts"].append(account)

    # Add to group if specified
    if group_id and "account_groups" in data:
        for group in data["account_groups"]:
            if group["id"] == group_id:
                if account_id not in group["accounts"]:
                    group["accounts"].append(account_id)
                break

    return account_id


def get_account_groups(data: Dict) -> List[Dict]:
    """
    Get all account groups from data.

    Args:
        data: Data dictionary

    Returns:
        List of account group dictionaries
    """
    return data.get("account_groups", [])


def get_accounts(data: Dict, group_id: Optional[str] = None) -> List[Dict]:
    """
    Get accounts, optionally filtered by group.

    Args:
        data: Data dictionary
        group_id: Optional group ID to filter by

    Returns:
        List of account dictionaries
    """
    accounts = data.get("accounts", [])
    if group_id:
        return [acc for acc in accounts if acc.get("account_group_id") == group_id]
    return accounts


def assign_trade_to_account(data: Dict, trade_id: str, account_id: str) -> bool:
    """
    Assign a trade to an account.

    Args:
        data: Data dictionary
        trade_id: Trade ID
        account_id: Account ID

    Returns:
        True if successful, False otherwise
    """
    if "trades" not in data:
        return False

    for trade in data["trades"]:
        if trade.get("id") == trade_id:
            trade["account_id"] = account_id
            return True
    return False


def save_data(data: Dict, username: str = "Default") -> None:
    """
    Save application data to JSON file.

    Args:
        data: The data dictionary to save
        username: The username to save data for
    """
    try:
        data_file = get_user_data_file(username)
        with open(data_file, 'w') as f:
            json.dump(data, f, indent=4)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving data: {e}")


def load_price_cache() -> Dict:
    """Load cached prices from file."""
    if os.path.exists(PRICE_CACHE_FILE):
        try:
            with open(PRICE_CACHE_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return {}


def save_price_cache(cache: Dict) -> None:
    """Save price cache to file."""
    try:
        with open(PRICE_CACHE_FILE, 'w') as f:
            json.dump(cache, f, indent=4)
    except:
        pass


def fetch_price_from_api(asset: str) -> Optional[float]:
    """
    Fetch current price for a cryptocurrency asset from CoinGecko API.

    Args:
        asset: Asset symbol (e.g., 'BTC', 'ETH')

    Returns:
        Current price in USD or None if fetch fails
    """
    # Map common symbols to CoinGecko IDs
    asset_map = {
        "BTC": "bitcoin",
        "ETH": "ethereum",
        "BNB": "binancecoin",
        "ADA": "cardano",
        "SOL": "solana",
        "XRP": "ripple",
        "DOT": "polkadot",
        "DOGE": "dogecoin",
        "MATIC": "matic-network",
        "AVAX": "avalanche-2",
        "LINK": "chainlink",
        "UNI": "uniswap",
        "ATOM": "cosmos",
        "LTC": "litecoin",
        "ALGO": "algorand"
    }

    coin_id = asset_map.get(asset.upper(), asset.lower())

    try:
        response = requests.get(
            COINGECKO_API_URL,
            params={"ids": coin_id, "vs_currencies": "usd"},
            timeout=5
        )
        response.raise_for_status()
        data = response.json()

        if coin_id in data and "usd" in data[coin_id]:
            return float(data[coin_id]["usd"])
    except Exception:
        pass

    return None


# --- Cost Basis Calculation Methods ---

def calculate_cost_basis_fifo(trades: List[Dict], asset: str) -> Tuple[float, float, List[Dict]]:
    """
    Calculate cost basis using FIFO (First In First Out) method.

    Args:
        trades: List of all trades sorted by date
        asset: Asset symbol to calculate for

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots)
    """
    # Filter trades for this asset and sort by date (oldest first)
    asset_trades = [t for t in trades if t["asset"] == asset]
    asset_trades.sort(key=lambda x: x["date"])

    lots = []  # List of (quantity, cost_per_unit, trade_id)
    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade["type"] in ("BUY", "Transfer"):
            cost_per_unit = (trade["total_value"] + trade["fee"]) / trade["quantity"] if trade["quantity"] else 0
            if cost_per_unit > 0:
                lots.append({
                    "quantity": trade["quantity"],
                    "cost_per_unit": cost_per_unit,
                    "trade_id": trade["id"],
                    "date": trade["date"]
                })
                units_held += trade["quantity"]
                total_cost += trade["total_value"] + trade["fee"]
        elif trade["type"] == "SELL":
            sell_qty = trade["quantity"]
            units_held -= sell_qty
            while sell_qty > 0 and lots:
                lot = lots[0]
                if lot["quantity"] <= sell_qty:
                    total_cost -= lot["quantity"] * lot["cost_per_unit"]
                    sell_qty -= lot["quantity"]
                    lots.pop(0)
                else:
                    total_cost -= sell_qty * lot["cost_per_unit"]
                    lot["quantity"] -= sell_qty
                    sell_qty = 0
        # Holding: ignore (not part of cost basis / sellable pool)

    return total_cost, units_held, lots


def calculate_cost_basis_lifo(trades: List[Dict], asset: str) -> Tuple[float, float, List[Dict]]:
    """
    Calculate cost basis using LIFO (Last In First Out) method.

    Args:
        trades: List of all trades sorted by date
        asset: Asset symbol to calculate for

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots)
    """
    # Filter trades for this asset and sort by date (oldest first)
    asset_trades = [t for t in trades if t["asset"] == asset]
    asset_trades.sort(key=lambda x: x["date"])

    lots = []  # List of (quantity, cost_per_unit, trade_id)
    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade["type"] in ("BUY", "Transfer"):
            cost_per_unit = (trade["total_value"] + trade["fee"]) / trade["quantity"] if trade["quantity"] else 0
            if cost_per_unit > 0:
                lots.append({
                    "quantity": trade["quantity"],
                    "cost_per_unit": cost_per_unit,
                    "trade_id": trade["id"],
                    "date": trade["date"]
                })
                units_held += trade["quantity"]
                total_cost += trade["total_value"] + trade["fee"]
        elif trade["type"] == "SELL":
            sell_qty = trade["quantity"]
            units_held -= sell_qty

            # Remove from lots using LIFO (last lot first)
            while sell_qty > 0 and lots:
                lot = lots[-1]  # Get last lot
                if lot["quantity"] <= sell_qty:
                    # Entire lot is sold
                    total_cost -= lot["quantity"] * lot["cost_per_unit"]
                    sell_qty -= lot["quantity"]
                    lots.pop()
                else:
                    total_cost -= sell_qty * lot["cost_per_unit"]
                    lot["quantity"] -= sell_qty
                    sell_qty = 0
        # Holding: ignore

    return total_cost, units_held, lots


def calculate_cost_basis_average(trades: List[Dict], asset: str) -> Tuple[float, float, List[Dict]]:
    """
    Calculate cost basis using Average Cost Basis method.

    Args:
        trades: List of all trades sorted by date
        asset: Asset symbol to calculate for

    Returns:
        Tuple of (total_cost_basis, units_held, remaining_lots)
    """
    # Filter trades for this asset and sort by date
    asset_trades = [t for t in trades if t["asset"] == asset]
    asset_trades.sort(key=lambda x: x["date"])

    total_cost = 0.0
    units_held = 0.0

    for trade in asset_trades:
        if trade["type"] in ("BUY", "Transfer"):
            units_held += trade["quantity"]
            total_cost += trade["total_value"] + trade["fee"]
        elif trade["type"] == "SELL":
            units_held -= trade["quantity"]
            if units_held > 0:
                avg_cost_per_unit = total_cost / (units_held + trade["quantity"])
                total_cost = units_held * avg_cost_per_unit
            else:
                total_cost = 0.0
        # Holding: ignore

    # Create a single lot representing average cost
    lots = []
    if units_held > 0:
        avg_cost_per_unit = total_cost / units_held if units_held > 0 else 0
        lots.append({
            "quantity": units_held,
            "cost_per_unit": avg_cost_per_unit,
            "trade_id": "average",
            "date": "average"
        })

    return total_cost, units_held, lots


# --- Main Application Class ---
class CryptoTrackerApp(tb.Window):
    """Main application window for crypto PnL tracking."""

    def __init__(self):
        """Initialize the application."""
        super().__init__(themename="darkly")
        self.title("CryptoPnL Tracker")
        self.geometry("1200x800")
        self.minsize(1000, 700)

        # User State
        self.current_user = "Default"
        self.users = load_users()
        if not self.users:
            self.users = ["Default"]
            save_users(self.users)

        # Data State
        self.data = load_data(self.current_user)
        self.price_cache = load_price_cache()

        # Apple-style thin scrollbars + rounded button appearance (extra padding for pill-like look)
        style = tb.Style()
        style.configure("Vertical.TScrollbar", gripcount=0, width=8, arrowsize=0)
        style.configure("Horizontal.TScrollbar", gripcount=0, width=8, arrowsize=0)
        style.map("Vertical.TScrollbar", background=[("active", "#404040")])
        style.map("Horizontal.TScrollbar", background=[("active", "#404040")])
        try:
            style.configure("TButton", padding=(14, 8))
            style.configure("primary.TButton", padding=(14, 8))
            style.configure("success.TButton", padding=(14, 8))
            style.configure("danger.TButton", padding=(14, 8))
        except tk.TclError:
            pass

        self.create_widgets()
        self.update_dashboard()

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
        file_menu.add_command(label="Quit", command=self.quit, accelerator="Cmd+Q")

        # Edit menu
        edit_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Edit", menu=edit_menu)
        edit_menu.add_command(label="Settings...", command=self.show_preferences)

        # Accounts menu
        accounts_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="Accounts", menu=accounts_menu)
        accounts_menu.add_command(label="New Account...", command=self.new_account_dialog)
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
        self.bind("<Command-q>", lambda e: self.quit())

    def create_widgets(self):
        """Create all UI widgets with three-column layout."""
        # Create menu bar
        self.create_menu_bar()

        # Initialize selected account/group (before summary panel uses them)
        self.selected_group_id = None
        self.selected_account_id = None
        
        # Main container for three-column layout
        main_container = tb.Frame(self)
        main_container.pack(fill="both", expand=True, padx=0, pady=0)
        
        # Use PanedWindow for resizable columns (1/5, 1/5, 3/5 with max on first two)
        self.main_paned = tk.PanedWindow(main_container, orient=tk.HORIZONTAL, sashwidth=4, bg="#2b2b2b")
        self.main_paned.pack(fill="both", expand=True)

        # Column 1: Account Groups Sidebar
        self.sidebar_frame = tb.Frame(self.main_paned, width=240)
        self.main_paned.add(self.sidebar_frame, minsize=180, width=240)
        self.create_account_groups_sidebar()

        # Column 2: Summary Panel
        self.summary_frame = tb.Frame(self.main_paned, width=240)
        self.main_paned.add(self.summary_frame, minsize=220, width=240)
        self.create_summary_panel()

        # Column 3: Content Area with Tabs
        self.content_frame = tb.Frame(self.main_paned)
        self.main_paned.add(self.content_frame, minsize=400)
        self.create_content_area()

        # Enforce column widths as 1/5, 1/5, 3/5 (with max on first two)
        def on_paned_configure(event):
            w = event.width
            if w > 0:
                c1 = min(w // 5, MAX_SIDEBAR_WIDTH)
                c2 = min(w // 5, MAX_SUMMARY_WIDTH)
                try:
                    self.main_paned.paneconfig(self.sidebar_frame, width=c1)
                    self.main_paned.paneconfig(self.summary_frame, width=c2)
                except tk.TclError:
                    pass
        main_container.bind("<Configure>", on_paned_configure)
        self.main_container = main_container

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
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        settings_inner = tb.Frame(scrollable_frame, padding=20)
        settings_inner.pack(fill="both", expand=True)

        tk.Label(settings_inner, text="Default Exchange for new trades:",
                font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=(0, 5))
        exchanges = list(self.data["settings"]["fee_structure"].keys())
        self.default_exchange_var = tb.StringVar(
            value=self.data["settings"].get("default_exchange", exchanges[0] if exchanges else "Bitstamp"))
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

    def new_account_dialog(self):
        """Show dialog to create a new account."""
        dialog = tk.Toplevel(self)
        dialog.title("New Account")
        dialog.geometry("400x200")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)

        tk.Label(frame, text="Account Name:", font=APPLE_FONT_DEFAULT).grid(row=0, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM)
        name_var = tb.StringVar()
        tb.Entry(frame, textvariable=name_var, width=30, font=APPLE_FONT_DEFAULT).grid(row=0, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        tk.Label(frame, text="Account Group:", font=APPLE_FONT_DEFAULT).grid(row=1, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM)
        group_var = tb.StringVar()
        groups = get_account_groups(self.data)
        group_names = ["None"] + [g["name"] for g in groups]
        group_combo = ttk.Combobox(frame, textvariable=group_var, values=group_names, state="readonly", width=27)
        group_combo.set("None")
        group_combo.grid(row=1, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        frame.grid_columnconfigure(1, weight=1)

        def create_account():
            name = name_var.get().strip()
            if not name:
                messagebox.showwarning("Input Error", "Please enter an account name.")
                return

            # Check for duplicate names
            existing_accounts = get_accounts(self.data)
            if any(acc["name"] == name for acc in existing_accounts):
                messagebox.showwarning("Input Error", "An account with this name already exists.")
                return

            selected_group = group_var.get()
            group_id = None
            if selected_group != "None":
                for g in groups:
                    if g["name"] == selected_group:
                        group_id = g["id"]
                        break

            account_id = create_account_in_data(self.data, name, group_id)
            save_data(self.data, self.current_user)
            self.refresh_account_groups_sidebar()
            self.refresh_sidebar_accounts()
            self.update_account_combo()
            self.update_summary_panel()
            dialog.destroy()
            self.log_activity(f"Created account: {name}")

        btn_frame = tb.Frame(frame)
        btn_frame.grid(row=2, column=0, columnspan=2, pady=APPLE_SPACING_LARGE)
        tb.Button(btn_frame, text="Create", command=create_account, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def manage_accounts_dialog(self):
        """Show dialog to manage accounts."""
        # For now, just show a message - can be expanded later
        messagebox.showinfo("Manage Accounts", "Account management feature coming soon.\n\nUse 'New Account' to create accounts.\nAccounts can be edited/deleted from the sidebar.")

    def manage_users_dialog(self):
        """Show dialog to manage users."""
        dialog = tk.Toplevel(self)
        dialog.title("Manage Users")
        dialog.geometry("400x300")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)

        tk.Label(frame, text="Users:", font=APPLE_FONT_DEFAULT).pack(anchor=W, pady=APPLE_SPACING_MEDIUM)

        listbox_frame = tb.Frame(frame)
        listbox_frame.pack(fill="both", expand=True, pady=APPLE_SPACING_MEDIUM)

        user_listbox = tk.Listbox(listbox_frame, height=8, font=APPLE_FONT_DEFAULT)
        user_listbox.pack(side=tk.LEFT, fill="both", expand=True)

        scrollbar = ttk.Scrollbar(listbox_frame, orient="vertical", command=user_listbox.yview)
        scrollbar.pack(side=tk.RIGHT, fill="y")
        user_listbox.config(yscrollcommand=scrollbar.set)

        for user in self.users:
            user_listbox.insert(tk.END, user)

        btn_frame = tb.Frame(frame)
        btn_frame.pack(fill="x", pady=APPLE_SPACING_MEDIUM)

        def delete_selected():
            selection = user_listbox.curselection()
            if not selection:
                messagebox.showwarning("No Selection", "Please select a user to delete.")
                return

            username = user_listbox.get(selection[0])
            if len(self.users) <= 1:
                messagebox.showwarning("Cannot Delete", "Cannot delete the last user.")
                return

            if messagebox.askyesno("Confirm Delete", f"Are you sure you want to delete user '{username}'?\n\nThis will delete all their trade data."):
                if delete_user(username):
                    self.users = load_users()
                    user_listbox.delete(0, tk.END)
                    for user in self.users:
                        user_listbox.insert(tk.END, user)
                    if self.current_user == username:
                        self.current_user = self.users[0]
                        self.data = load_data(self.current_user)
                        self.update_dashboard()
                    self.log_activity(f"Deleted user: {username}")
                    messagebox.showinfo("Success", f"User '{username}' deleted successfully.")
                else:
                    messagebox.showerror("Error", "Failed to delete user.")

        tb.Button(btn_frame, text="Delete Selected", command=delete_selected, bootstyle=DANGER).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Close", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def switch_user_dialog(self):
        """Show dialog to switch users."""
        dialog = tk.Toplevel(self)
        dialog.title("Switch User")
        dialog.geometry("300x150")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=APPLE_PADDING)
        frame.pack(fill="both", expand=True)

        tk.Label(frame, text="Select User:", font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)
        user_var = tb.StringVar(value=self.current_user)
        user_combo = ttk.Combobox(frame, textvariable=user_var, values=self.users, state="readonly", width=25)
        user_combo.pack(pady=APPLE_SPACING_MEDIUM)

        def switch():
            new_user = user_var.get()
            if new_user != self.current_user:
                save_data(self.data, self.current_user)
                self.current_user = new_user
                self.data = load_data(self.current_user)
                self.refresh_account_groups_sidebar()
                self.update_summary_panel()
                self.update_dashboard()
                self.log_activity(f"Switched to user: {self.current_user}")
            dialog.destroy()

        btn_frame = tb.Frame(frame)
        btn_frame.pack(pady=APPLE_SPACING_LARGE)
        tb.Button(btn_frame, text="Switch", command=switch, bootstyle=PRIMARY).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

    def show_about(self):
        """Show about dialog."""
        messagebox.showinfo("About", "CryptoPnL Tracker\n\nA cryptocurrency portfolio tracking application\nwith support for multiple users, accounts, and client tracking.")

    def create_account_groups_sidebar(self):
        """Create the account groups sidebar (Column 1): Account Groups section + Accounts section."""
        # Scrollable container for both sections
        list_container = tb.Frame(self.sidebar_frame)
        list_container.pack(fill="both", expand=True, padx=APPLE_PADDING, pady=APPLE_PADDING)

        canvas = tk.Canvas(list_container, bg="#2b2b2b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # --- Account Groups section ---
        tk.Label(scrollable_frame, text="Account Groups", font=(APPLE_FONT_FAMILY, 14, "bold")).pack(anchor=W, pady=(0, APPLE_SPACING_SMALL))
        self.account_groups_list_frame = tb.Frame(scrollable_frame)
        self.account_groups_list_frame.pack(fill="x", pady=(0, APPLE_SPACING_SMALL))

        btn_grp_frame = tb.Frame(scrollable_frame)
        btn_grp_frame.pack(fill="x", pady=(0, APPLE_SPACING_LARGE))
        tb.Button(btn_grp_frame, text="Add Account Group", command=self.add_account_group_dialog,
                 bootstyle=PRIMARY, width=20).pack(fill="x")

        # --- Accounts section ---
        tk.Label(scrollable_frame, text="Accounts", font=(APPLE_FONT_FAMILY, 14, "bold")).pack(anchor=W, pady=(APPLE_SPACING_LARGE, APPLE_SPACING_SMALL))
        self.sidebar_accounts_list_frame = tb.Frame(scrollable_frame)
        self.sidebar_accounts_list_frame.pack(fill="x", pady=(0, APPLE_SPACING_SMALL))

        btn_acc_frame = tb.Frame(scrollable_frame)
        btn_acc_frame.pack(fill="x")
        tb.Button(btn_acc_frame, text="Add new Account", command=self.new_account_dialog,
                 bootstyle=PRIMARY, width=20).pack(fill="x")

        self.refresh_account_groups_sidebar()
        self.refresh_sidebar_accounts()

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
                           bootstyle="primary" if is_selected(None) else "outline", width=20)
        all_btn.pack(fill="x")
        all_btn.bind("<Double-1>", lambda e: None)  # no edit for ALL

        for group in groups:
            gid = group["id"]
            group_frame = tb.Frame(self.account_groups_list_frame, padding=APPLE_SPACING_SMALL)
            group_frame.pack(fill="x", pady=APPLE_SPACING_SMALL)
            group_btn = tb.Button(group_frame, text=group["name"],
                                 command=lambda gid=gid: self.select_group(gid),
                                 bootstyle="primary" if is_selected(gid) else "outline", width=20)
            group_btn.pack(fill="x")
            group_btn.bind("<Double-1>", lambda e, gid=gid: self.edit_account_group_dialog(gid))

    def refresh_sidebar_accounts(self):
        """Refresh the accounts list in sidebar (filtered by selected group, with highlight)."""
        if not hasattr(self, "sidebar_accounts_list_frame"):
            return
        for widget in self.sidebar_accounts_list_frame.winfo_children():
            widget.destroy()

        if self.selected_group_id:
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
                               bootstyle="primary" if is_sel else "outline", width=20)
            acc_btn.pack(fill="x")
            acc_btn.bind("<Double-1>", lambda e, aid=aid: self.edit_account_dialog(aid))

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
        """Create the summary panel (Column 2)."""
        # Scrollable container
        canvas = tk.Canvas(self.summary_frame, bg="#2b2b2b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(self.summary_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        self.summary_content_frame = scrollable_frame

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.update_summary_panel()

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

        # Summary Section: 2x2 value/descriptor layout (compact, Apple-style)
        summary_frame = tb.LabelFrame(self.summary_content_frame, text="Summary")
        summary_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)

        cost_basis_method = self.data["settings"].get("cost_basis_method", "average")
        total_cost_basis = 0.0
        total_value = 0.0
        total_pnl = 0.0
        assets = set(t["asset"] for t in filtered_trades)
        for asset in assets:
            asset_trades = [t for t in filtered_trades if t["asset"] == asset]
            if cost_basis_method == "fifo":
                cost_basis, units_held, _ = calculate_cost_basis_fifo(asset_trades, asset)
            elif cost_basis_method == "lifo":
                cost_basis, units_held, _ = calculate_cost_basis_lifo(asset_trades, asset)
            else:
                cost_basis, units_held, _ = calculate_cost_basis_average(asset_trades, asset)
            current_price = self.get_current_price(asset)
            if current_price:
                current_value = units_held * current_price
                total_value += current_value
                total_cost_basis += cost_basis

        total_pnl = total_value - total_cost_basis
        roi = (total_pnl / total_cost_basis * 100) if total_cost_basis > 0 else 0.0
        pnl_color = APPLE_COLOR_PROFIT if total_pnl >= 0 else APPLE_COLOR_LOSS
        roi_color = APPLE_COLOR_PROFIT if roi >= 0 else APPLE_COLOR_LOSS

        summary_grid = tb.Frame(summary_frame, padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)
        summary_grid.pack(fill="x", pady=SUMMARY_PAD)
        # Row 0: value in $ (left), profit in $ (right)
        left0 = tb.Frame(summary_grid)
        left0.grid(row=0, column=0, sticky=W, padx=(0, APPLE_SPACING_LARGE), pady=2)
        tk.Label(left0, text=f"${total_value:,.2f}", font=SUMMARY_VALUE_FONT).pack(anchor=W)
        tk.Label(left0, text="value", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=W)
        right0 = tb.Frame(summary_grid)
        right0.grid(row=0, column=1, sticky=E, pady=2)
        tk.Label(right0, text=f"${total_pnl:,.2f}", font=SUMMARY_VALUE_FONT, fg=pnl_color).pack(anchor=E)
        tk.Label(right0, text="profit", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=E)
        # Row 1: invested (left), ROI (right)
        left1 = tb.Frame(summary_grid)
        left1.grid(row=1, column=0, sticky=W, padx=(0, APPLE_SPACING_LARGE), pady=2)
        tk.Label(left1, text=f"${total_cost_basis:,.2f}", font=SUMMARY_VALUE_FONT).pack(anchor=W)
        tk.Label(left1, text="invested", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=W)
        right1 = tb.Frame(summary_grid)
        right1.grid(row=1, column=1, sticky=E, pady=2)
        tk.Label(right1, text=f"{roi:.2f}%", font=SUMMARY_VALUE_FONT, fg=roi_color).pack(anchor=E)
        tk.Label(right1, text="ROI", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(anchor=E)
        summary_grid.columnconfigure(1, weight=1)

        # Accounts Section (tighter spacing)
        accounts_frame = tb.LabelFrame(self.summary_content_frame, text="Accounts")
        accounts_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _af_inner = tb.Frame(accounts_frame, padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)
        _af_inner.pack(fill="x")

        if self.selected_group_id:
            accounts = get_accounts(self.data, self.selected_group_id)
        else:
            accounts = get_accounts(self.data)

        for account in accounts:
            acc_trades = [t for t in all_trades if t.get("account_id") == account["id"]]
            # Calculate account value
            acc_value = 0.0
            acc_cost = 0.0
            for asset in set(t["asset"] for t in acc_trades):
                asset_trades = [t for t in acc_trades if t["asset"] == asset]
                if cost_basis_method == "fifo":
                    cost_basis, units_held, _ = calculate_cost_basis_fifo(asset_trades, asset)
                elif cost_basis_method == "lifo":
                    cost_basis, units_held, _ = calculate_cost_basis_lifo(asset_trades, asset)
                else:
                    cost_basis, units_held, _ = calculate_cost_basis_average(asset_trades, asset)
                acc_cost += cost_basis
                current_price = self.get_current_price(asset)
                if current_price:
                    acc_value += units_held * current_price

            acc_pnl = acc_value - acc_cost
            acc_pnl_color = APPLE_COLOR_PROFIT if acc_pnl >= 0 else APPLE_COLOR_LOSS

            acc_row = tb.Frame(_af_inner)
            acc_row.pack(fill="x", pady=2)
            tk.Label(acc_row, text=f"{account['name']}: ${acc_value:,.2f}", font=APPLE_FONT_DEFAULT).pack(side=tk.LEFT)
            tk.Label(acc_row, text=f"({acc_pnl:+,.2f})", font=APPLE_FONT_DEFAULT, fg=acc_pnl_color).pack(side=tk.RIGHT)

        # Assets Section (tighter spacing)
        assets_frame = tb.LabelFrame(self.summary_content_frame, text="Assets")
        assets_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _asf_inner = tb.Frame(assets_frame, padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)
        _asf_inner.pack(fill="both", expand=True)

        if assets:
            columns = ("Asset", "Qty", "Value", "P&L")
            assets_tree = ttk.Treeview(_asf_inner, columns=columns, show='headings', height=6)
            for col in columns:
                assets_tree.heading(col, text=col)
                assets_tree.column(col, width=80, anchor=tk.CENTER)

            for asset in sorted(assets):
                asset_trades = [t for t in filtered_trades if t["asset"] == asset]
                if cost_basis_method == "fifo":
                    cost_basis, units_held, _ = calculate_cost_basis_fifo(asset_trades, asset)
                elif cost_basis_method == "lifo":
                    cost_basis, units_held, _ = calculate_cost_basis_lifo(asset_trades, asset)
                else:
                    cost_basis, units_held, _ = calculate_cost_basis_average(asset_trades, asset)

                current_price = self.get_current_price(asset)
                if current_price and units_held > 0:
                    current_value = units_held * current_price
                    pnl = current_value - cost_basis
                    pnl_color = APPLE_COLOR_PROFIT if pnl >= 0 else APPLE_COLOR_LOSS
                    assets_tree.insert('', tk.END, values=(
                        asset,
                        f"{units_held:.8f}",
                        f"${current_value:,.2f}",
                        f"${pnl:,.2f}"
                    ), tags=(pnl_color,))
                    assets_tree.tag_configure(pnl_color, foreground=pnl_color)

            assets_tree.pack(fill="both", expand=True)

        # Open Positions Section: two-row cards (Asset × Qty | PnL; Entry Price | Value of Holdings)
        positions_frame = tb.LabelFrame(self.summary_content_frame, text="Open Positions")
        positions_frame.pack(fill="x", padx=SUMMARY_OUTER_PAD, pady=SUMMARY_OUTER_PAD)
        _pf_inner = tb.Frame(positions_frame, padx=SUMMARY_CONTENT_PADX, pady=SUMMARY_PAD)
        _pf_inner.pack(fill="x")

        if assets:
            for asset in sorted(assets):
                asset_trades = [t for t in filtered_trades if t["asset"] == asset]
                if cost_basis_method == "fifo":
                    cost_basis, units_held, lots = calculate_cost_basis_fifo(asset_trades, asset)
                elif cost_basis_method == "lifo":
                    cost_basis, units_held, lots = calculate_cost_basis_lifo(asset_trades, asset)
                else:
                    cost_basis, units_held, lots = calculate_cost_basis_average(asset_trades, asset)

                if units_held > 0:
                    current_price = self.get_current_price(asset)
                    entry_price = cost_basis / units_held if units_held > 0 else 0
                    current_value = units_held * current_price if current_price else 0.0
                    pnl = current_value - cost_basis
                    pnl_color = APPLE_COLOR_PROFIT if pnl >= 0 else APPLE_COLOR_LOSS

                    card = tb.Frame(_pf_inner)
                    card.pack(fill="x", pady=4)
                    # Row 1: Asset (bold) × quantity (gray, space before qty) -------- PnL (green/red)
                    row1 = tb.Frame(card)
                    row1.pack(fill="x")
                    tk.Label(row1, text=asset, font=(APPLE_FONT_FAMILY, 12, "bold")).pack(side=tk.LEFT)
                    tk.Label(row1, text=f" × {units_held:.8f}", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                    tk.Label(row1, text=f"${pnl:,.2f}", font=APPLE_FONT_DEFAULT, fg=pnl_color).pack(side=tk.RIGHT)
                    # Row 2: Entry Price (gray) -------- Value of Holdings (green/red)
                    row2 = tb.Frame(card)
                    row2.pack(fill="x")
                    tk.Label(row2, text=f"${entry_price:,.2f}", font=SUMMARY_DESC_FONT, fg=SUMMARY_DESC_COLOR).pack(side=tk.LEFT)
                    tk.Label(row2, text=f"${current_value:,.2f}", font=APPLE_FONT_DEFAULT, fg=pnl_color).pack(side=tk.RIGHT)

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
        self.tab_control.bind("<ButtonPress-1>", self._on_tab_press)
        self.tab_control.bind("<ButtonRelease-1>", self._on_tab_release)

        self.create_trades_tab()
        self.create_stats_tab()
        self.create_pnl_chart_tab()


    def add_user_dialog(self):
        """Show dialog to add a new user."""
        dialog = tk.Toplevel(self)
        dialog.title("Add User")
        dialog.geometry("300x150")
        dialog.transient(self)
        dialog.grab_set()

        frame = tb.Frame(dialog, padding=20)
        frame.pack(fill="both", expand=True)

        tb.Label(frame, text="Username:").pack(pady=10)
        username_var = tb.StringVar()
        tb.Entry(frame, textvariable=username_var, width=25).pack(pady=5)

        def add_user_action():
            username = username_var.get().strip()
            if not username:
                messagebox.showwarning("Input Error", "Please enter a username.")
                return
            if username in self.users:
                messagebox.showwarning("Input Error", "User already exists.")
                return
            if add_user(username):
                self.users = load_users()
                self.data = load_data(username)
                self.current_user = username
                self.refresh_account_groups_sidebar()
                self.update_summary_panel()
                self.update_dashboard()
                dialog.destroy()
                self.log_activity(f"Created new user: {username}")
            else:
                messagebox.showerror("Error", "Failed to add user.")

        tb.Button(frame, text="Add", command=add_user_action, bootstyle=SUCCESS).pack(pady=10)
        tb.Button(frame, text="Cancel", command=dialog.destroy).pack()

    def delete_user_dialog(self):
        """Show dialog to delete a user."""
        if len(self.users) <= 1:
            messagebox.showwarning("Cannot Delete", "Cannot delete the last user.")
            return

        username = self.current_user
        if messagebox.askyesno("Confirm Delete",
                              f"Are you sure you want to delete user '{username}'?\n\nThis will delete all their trade data."):
            if delete_user(username):
                self.users = load_users()
                if self.current_user == username:
                    self.current_user = self.users[0]
                    self.data = load_data(self.current_user)
                self.refresh_account_groups_sidebar()
                self.update_summary_panel()
                self.update_dashboard()
                self.log_activity(f"Deleted user: {username}")
            else:
                messagebox.showerror("Error", "Failed to delete user.")

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
            state_qty = "disabled" if is_usd_fiat else "normal"
            state_ord = "disabled" if is_usd_fiat else "readonly"
            self.qty_entry.config(state=state_qty)
            order_type_combo.config(state=state_ord)
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

        # Row 1: Price and Quantity (Amount when USD+Deposit)
        price_lbl = tk.Label(form_inner, text="Price ($):", font=APPLE_FONT_DEFAULT)
        price_lbl.grid(row=1, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.price_var = tb.StringVar()
        self.price_entry = tb.Entry(form_inner, textvariable=self.price_var, font=APPLE_FONT_DEFAULT)
        self.price_entry.grid(row=1, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        qty_lbl = tk.Label(form_inner, text="Quantity:", font=APPLE_FONT_DEFAULT)
        qty_lbl.grid(row=1, column=2, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.qty_var = tb.StringVar()
        self.qty_entry = tb.Entry(form_inner, textvariable=self.qty_var, font=APPLE_FONT_DEFAULT)
        self.qty_entry.grid(row=1, column=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        # Row 2: Exchange and Order Type (Order Type disabled when USD+Deposit)
        tk.Label(form_inner, text="Exchange:", font=APPLE_FONT_DEFAULT).grid(row=2, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        exchanges = list(self.data["settings"]["fee_structure"].keys())
        self.exchange_var = tb.StringVar(value=self.data["settings"].get("default_exchange", exchanges[0] if exchanges else "Bitstamp"))
        exchange_combo = ttk.Combobox(form_inner, textvariable=self.exchange_var,
                                      values=exchanges, state="readonly")
        exchange_combo.grid(row=2, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

        tk.Label(form_inner, text="Order Type:", font=APPLE_FONT_DEFAULT).grid(row=2, column=2, sticky=W, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)
        self.order_type_var = tb.StringVar(value="maker")
        order_type_combo = ttk.Combobox(form_inner, textvariable=self.order_type_var,
                                        values=["maker", "taker"], state="readonly", width=10)
        order_type_combo.grid(row=2, column=3, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

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

        # Treeview (Table)
        table_frame = tb.Frame(trade_container)
        table_frame.pack(fill="both", expand=True)

        columns = ("Date", "Asset", "Type", "Price", "Quantity", "Exchange", "Order Type", "Account", "Fees", "Total")
        self.tree = ttk.Treeview(table_frame, columns=columns, show='headings', height=12)

        column_widths = {"Date": 150, "Asset": 80, "Type": 60, "Price": 100,
                        "Quantity": 100, "Exchange": 120, "Order Type": 80, "Account": 100, "Fees": 80, "Total": 100}

        self._tree_sort_col = None
        self._tree_sort_reverse = False
        for col in columns:
            self.tree.heading(col, text=col, command=lambda c=col: self._sort_tree_by_column(c))
            self.tree.column(col, width=column_widths.get(col, 100), anchor=tk.CENTER)

        # Scrollbars
        vsb = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        hsb = ttk.Scrollbar(table_frame, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")

        table_frame.grid_rowconfigure(0, weight=1)
        table_frame.grid_columnconfigure(0, weight=1)

        # Context Menu
        self.menu = tk.Menu(self.tree, tearoff=0)
        self.menu.add_command(label="Edit Trade", command=self.edit_trade)
        self.menu.add_command(label="Delete Selected", command=self.delete_trade)

        self.tree.bind("<Button-3>", self.show_context_menu)
        self.tree.bind("<Double-1>", lambda e: self.edit_trade())

    def _on_tab_press(self, event):
        """Remember which tab was selected for potential reorder."""
        try:
            self._tab_drag_index = self.tab_control.index(self.tab_control.select())
        except tk.TclError:
            self._tab_drag_index = None

    def _on_tab_release(self, event):
        """Reorder tab if released over a different tab position."""
        if self._tab_drag_index is None:
            return
        try:
            tabs = list(self.tab_control.tabs())
            if not tabs or self._tab_drag_index >= len(tabs):
                return
            # Approximate drop index from x position
            w = self.tab_control.winfo_width()
            if w <= 0:
                return
            drop_index = min(int(event.x * len(tabs) / w), len(tabs) - 1)
            drop_index = max(0, drop_index)
            if drop_index == self._tab_drag_index:
                return
            tab_id = tabs[self._tab_drag_index]
            text = self.tab_control.tab(tab_id, "text")
            self.tab_control.forget(tab_id)
            self.tab_control.insert(drop_index, tab_id, text=text)
        except (tk.TclError, IndexError):
            pass
        self._tab_drag_index = None

    def _sort_tree_by_column(self, col: str):
        """Sort transactions tree by column header click."""
        col_idx = ("Date", "Asset", "Type", "Price", "Quantity", "Exchange", "Order Type", "Account", "Fees", "Total").index(col)
        reverse = self._tree_sort_reverse if self._tree_sort_col == col else False
        self._tree_sort_col = col
        self._tree_sort_reverse = not reverse
        items = [(self.tree.set(i, col), i) for i in self.tree.get_children("")]
        # Parse numbers for numeric columns
        def key_fn(item):
            val = item[0]
            if col in ("Price", "Quantity", "Fees", "Total"):
                try:
                    return float(val.replace("$", "").replace(",", ""))
                except ValueError:
                    return 0.0
            return val
        items.sort(key=key_fn, reverse=self._tree_sort_reverse)
        for _, iid in items:
            self.tree.move(iid, "", tk.END)

    def update_account_combo(self):
        """Update account combo values."""
        accounts = get_accounts(self.data)
        account_names = [acc["name"] for acc in accounts]
        if hasattr(self, 'account_combo'):
            self.account_combo['values'] = account_names

    def create_stats_tab(self):
        """Create the dashboard/stats tab."""
        # Scrollable container
        canvas = tk.Canvas(self.tab_stats, bg="#2b2b2b")
        scrollbar = ttk.Scrollbar(self.tab_stats, orient="vertical", command=canvas.yview)
        scrollable_frame = tb.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

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

        # Price Management Section
        price_frame = tb.LabelFrame(scrollable_frame, text="Price Management")
        price_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        price_inner = tb.Frame(price_frame, padding=APPLE_PADDING)
        price_inner.pack(fill="both", expand=True)

        price_controls = tb.Frame(price_inner)
        price_controls.pack(fill="x")

        tk.Label(price_controls, text="Refresh Prices:", font=APPLE_FONT_DEFAULT).pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)
        refresh_btn = tb.Button(price_controls, text="Fetch All Prices",
                               command=self.refresh_all_prices, bootstyle=INFO)
        refresh_btn.pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

        self.price_status_label = tk.Label(price_controls, text="", font=APPLE_FONT_DEFAULT)
        self.price_status_label.pack(side=tk.LEFT, padx=APPLE_SPACING_MEDIUM)

        # Portfolio Summary
        stats_container = tb.LabelFrame(scrollable_frame, text="Portfolio Summary")
        stats_container.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        stats_inner = tb.Frame(stats_container, padding=APPLE_PADDING)
        stats_inner.pack(fill="both", expand=True)

        stats_grid = tb.Frame(stats_inner)
        stats_grid.pack(fill="x", pady=10)

        # Labels (not colored); value labels (green/red when positive/negative)
        tk.Label(stats_grid, text="Total Invested:", font=(APPLE_FONT_FAMILY, 14)).grid(row=0, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.total_invested_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 14))
        self.total_invested_label.grid(row=0, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Current Value:", font=(APPLE_FONT_FAMILY, 14)).grid(row=0, column=2, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.current_portfolio_value_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 14))
        self.current_portfolio_value_label.grid(row=0, column=3, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Total P&L:", font=(APPLE_FONT_FAMILY, 16, "bold")).grid(row=0, column=4, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.total_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 16, "bold"))
        self.total_pnl_label.grid(row=0, column=5, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="ROI:", font=(APPLE_FONT_FAMILY, 14)).grid(row=1, column=0, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.roi_label = tk.Label(stats_grid, text="0.00%", font=(APPLE_FONT_FAMILY, 14))
        self.roi_label.grid(row=1, column=1, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Realized P&L:", font=(APPLE_FONT_FAMILY, 12)).grid(row=1, column=2, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.realized_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.realized_pnl_label.grid(row=1, column=3, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        tk.Label(stats_grid, text="Unrealized P&L:", font=(APPLE_FONT_FAMILY, 12)).grid(row=1, column=4, padx=(APPLE_PADDING, 0), pady=APPLE_SPACING_MEDIUM)
        self.unrealized_pnl_label = tk.Label(stats_grid, text="$0.00", font=(APPLE_FONT_FAMILY, 12))
        self.unrealized_pnl_label.grid(row=1, column=5, padx=(2, APPLE_PADDING), pady=APPLE_SPACING_MEDIUM)

        # Client P&L Section (only show if current user is a client)
        client_frame = tb.LabelFrame(scrollable_frame, text="Client P&L Summary")
        client_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        client_inner = tb.Frame(client_frame, padding=APPLE_PADDING)
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

        # Per-Asset Breakdown
        asset_frame = tb.LabelFrame(scrollable_frame, text="Per-Asset Breakdown")
        asset_frame.pack(fill="both", expand=True, padx=APPLE_PADDING, pady=APPLE_PADDING)
        asset_inner = tb.Frame(asset_frame, padding=APPLE_PADDING)
        asset_inner.pack(fill="both", expand=True)

        asset_columns = ("Asset", "Quantity", "Avg Cost Basis", "Current Price", "Current Value", "Unrealized P&L", "ROI %")
        self.asset_tree = ttk.Treeview(asset_inner, columns=asset_columns, show='headings', height=8)

        for col in asset_columns:
            self.asset_tree.heading(col, text=col)
            self.asset_tree.column(col, width=120, anchor=tk.CENTER)

        asset_vsb = ttk.Scrollbar(asset_inner, orient="vertical", command=self.asset_tree.yview)
        self.asset_tree.configure(yscrollcommand=asset_vsb.set)

        self.asset_tree.pack(side="left", fill="both", expand=True)
        asset_vsb.pack(side="right", fill="y")

        # Projections Section: table of potential transactions + Projected P&L row
        projection_frame = tb.LabelFrame(scrollable_frame, text="Projections & Pro forma")
        projection_frame.pack(fill="x", padx=APPLE_PADDING, pady=APPLE_PADDING)
        proj_inner = tb.Frame(projection_frame, padding=APPLE_PADDING)
        proj_inner.pack(fill="both", expand=True)

        proj_controls = tb.Frame(proj_inner)
        proj_controls.pack(fill="x")
        tb.Button(proj_controls, text="Add potential transaction", command=self._proj_add_row, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=5)

        proj_columns = ("Asset", "Type", "Price ($)", "Quantity")
        self.proj_tree = ttk.Treeview(proj_inner, columns=proj_columns, show='headings', height=5)
        for c in proj_columns:
            self.proj_tree.heading(c, text=c)
            self.proj_tree.column(c, width=100, anchor=tk.CENTER)
        proj_vsb = ttk.Scrollbar(proj_inner, orient="vertical", command=self.proj_tree.yview)
        self.proj_tree.configure(yscrollcommand=proj_vsb.set)
        self.proj_tree.pack(side=tk.LEFT, fill="both", expand=True)
        proj_vsb.pack(side=tk.RIGHT, fill="y")
        self.proj_tree.bind("<Button-3>", self._show_proj_context_menu)
        self.proj_tree.bind("<Double-1>", lambda e: self._proj_edit_row())

        proj_result_frame = tb.Frame(proj_inner)
        proj_result_frame.pack(fill="x", pady=(10, 0))
        tk.Label(proj_result_frame, text="Projected P&L:", font=(APPLE_FONT_FAMILY, 12, "bold")).pack(side=tk.LEFT, padx=(0, 10))
        self.proj_result_label = tk.Label(proj_result_frame, text="--",
                                 font=(APPLE_FONT_FAMILY, 12, "bold"))
        self.proj_result_label.pack(side=tk.LEFT)

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

            # Calculate cumulative values over time
            dates = []
            values = []
            quantities = []
            cost_basis = 0.0
            quantity_held = 0.0

            cost_basis_method = self.data["settings"].get("cost_basis_method", "average")

            for trade in filtered_trades:
                trade_date = datetime.strptime(trade["date"], "%Y-%m-%d %H:%M:%S")
                dates.append(trade_date)

                if trade["type"] == "BUY":
                    quantity_held += trade["quantity"]
                    cost_basis += trade["total_value"] + trade["fee"]
                else:  # SELL
                    quantity_held -= trade["quantity"]
                    # Reduce cost basis proportionally
                    if quantity_held > 0:
                        if cost_basis_method == "average":
                            avg_cost = cost_basis / (quantity_held + trade["quantity"])
                            cost_basis = quantity_held * avg_cost
                        else:
                            # Simplified for FIFO/LIFO - use average for chart
                            avg_cost = cost_basis / (quantity_held + trade["quantity"])
                            cost_basis = quantity_held * avg_cost
                    else:
                        cost_basis = 0.0

                quantities.append(quantity_held)

                if value_type == "USD":
                    # Calculate value in USD
                    current_price = self.get_current_price(asset)
                    if current_price:
                        value = quantity_held * current_price
                    else:
                        # Use trade price as fallback
                        value = quantity_held * trade["price"]
                    values.append(value)
                else:  # Asset
                    # Value in asset units (quantity held)
                    values.append(quantity_held)

            # Add current point if we have holdings
            if quantity_held > 0:
                dates.append(now)
                quantities.append(quantity_held)
                if value_type == "USD":
                    current_price = self.get_current_price(asset)
                    if current_price:
                        values.append(quantity_held * current_price)
                    else:
                        values.append(values[-1] if values else 0)
                else:
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
                # Line graph only (no fill under curve)
                self.chart_ax.plot(dates, numeric_values, color='#4cc9f0', linewidth=2, marker='o', markersize=4)

                # Format labels
                if value_type == "USD":
                    self.chart_ax.set_ylabel(f'Portfolio Value (USD)', color='white')
                    # Format y-axis as currency
                    if FuncFormatter:
                        self.chart_ax.yaxis.set_major_formatter(
                            FuncFormatter(lambda x, p: f'${x:,.0f}')
                        )
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

            # USD Deposit/Withdrawal: use Amount (USD) in price field, quantity=amount, price=1
            is_usd_fiat = (asset == "USD" and trade_type in ("Deposit", "Withdrawal"))
            if is_usd_fiat:
                if not price_str:
                    raise ValueError("Amount (USD) is required")
                try:
                    amount_usd = float(price_str)
                except ValueError:
                    raise ValueError("Amount must be a valid number")
                if amount_usd <= 0:
                    raise ValueError("Amount must be greater than 0")
                price, qty = 1.0, amount_usd
                fee = 0.0
                order_type = "maker"
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
                if exchange not in self.data["settings"]["fee_structure"]:
                    raise ValueError("Invalid exchange selected")
                fee_structure = self.data["settings"]["fee_structure"][exchange]
                fee_rate = fee_structure.get(order_type, fee_structure.get("maker", 0.1))
                total_amount = price * qty
                fee = total_amount * (fee_rate / 100)

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
        """Calculate available quantity for an asset (sellable/withdrawable). USD: Deposit - Withdrawal. Crypto: BUY + Transfer - SELL (Holding not included)."""
        trades = self.data.get("trades", [])
        asset_trades = [t for t in trades if t["asset"] == asset]
        asset_trades.sort(key=lambda x: x["date"])

        qty = 0.0
        if asset == "USD":
            for t in asset_trades:
                if t["type"] == "Deposit":
                    qty += t["quantity"]
                elif t["type"] == "Withdrawal":
                    qty -= t["quantity"]
        else:
            for t in asset_trades:
                if t["type"] in ("BUY", "Transfer"):
                    qty += t["quantity"]
                elif t["type"] == "SELL":
                    qty -= t["quantity"]
                # Holding: not added to available (not sellable)
        return max(0.0, qty)

    def edit_trade(self):
        """Edit an existing trade."""
        selection = self.tree.selection()
        if not selection:
            messagebox.showwarning("No Selection", "Please select a trade to edit.")
            return

        item = selection[0]
        values = self.tree.item(item, "values")

        # Find trade by matching key fields
        trade_id = None
        for trade in self.data["trades"]:
            # Try to match by displayed values
            if (str(trade["date"]) == values[0] and
                trade["asset"] == values[1] and
                trade["type"] == values[2] and
                abs(trade["price"] - float(values[3].replace("$", ""))) < 0.01):
                trade_id = trade["id"]
                break

        if not trade_id:
            messagebox.showerror("Error", "Could not find trade to edit.")
            return

        # Find the trade
        trade = next((t for t in self.data["trades"] if t["id"] == trade_id), None)
        if not trade:
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

        # Price
        tb.Label(frame, text="Price ($):").grid(row=3, column=0, sticky=W, pady=5)
        price_var = tb.DoubleVar(value=trade["price"])
        tb.Entry(frame, textvariable=price_var).grid(row=3, column=1, sticky=EW, pady=5, padx=5)

        # Quantity
        tb.Label(frame, text="Quantity:").grid(row=4, column=0, sticky=W, pady=5)
        qty_var = tb.DoubleVar(value=trade["quantity"])
        tb.Entry(frame, textvariable=qty_var).grid(row=4, column=1, sticky=EW, pady=5, padx=5)

        # Exchange
        tb.Label(frame, text="Exchange:").grid(row=5, column=0, sticky=W, pady=5)
        exchange_var = tb.StringVar(value=trade["exchange"])
        exchanges = list(self.data["settings"]["fee_structure"].keys())
        ttk.Combobox(frame, textvariable=exchange_var, values=exchanges,
                    state="readonly").grid(row=5, column=1, sticky=EW, pady=5, padx=5)

        # Order Type
        tb.Label(frame, text="Order Type:").grid(row=6, column=0, sticky=W, pady=5)
        order_type_var = tb.StringVar(value=trade.get("order_type", "maker"))
        ttk.Combobox(frame, textvariable=order_type_var, values=["maker", "taker"],
                    state="readonly").grid(row=6, column=1, sticky=EW, pady=5, padx=5)

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

        btn_row = tb.Frame(frame)
        btn_row.grid(row=8, column=0, columnspan=2, pady=20)
        tb.Button(btn_row, text="Save", command=save_edit, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=10)
        tb.Button(btn_row, text="Cancel", command=dialog.destroy).pack(side=tk.LEFT)

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
                if is_usd_fiat:
                    if price <= 0:
                        raise ValueError("Amount (USD) must be greater than 0")
                    qty = price  # amount
                    price = 1.0
                    fee = 0.0
                    order_type = "maker"
                    exchange = ""
                    total_amount = qty
                else:
                    if not asset or price <= 0 or qty <= 0:
                        raise ValueError("Invalid input values")
                    fee_structure = self.data["settings"]["fee_structure"].get(exchange, {})
                    fee_rate = fee_structure.get(order_type, fee_structure.get("maker", 0.1))
                    total_amount = price * qty
                    fee = total_amount * (fee_rate / 100)

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

    def delete_trade(self):
        """Delete selected trade(s) using unique IDs."""
        selection = self.tree.selection()
        if not selection:
            return

        if messagebox.askyesno("Confirm Delete", "Are you sure you want to delete the selected trade(s)?"):
            deleted_count = 0
            for item in selection:
                values = self.tree.item(item, "values")

                # Find trade by ID or matching values
                for i, trade in enumerate(self.data["trades"]):
                    # Try ID first if available in tree tags
                    item_tags = self.tree.item(item, "tags")
                    if item_tags and trade["id"] in item_tags:
                        del self.data["trades"][i]
                        deleted_count += 1
                        break
                    # Fallback to value matching
                    elif (str(trade["date"]) == values[0] and
                          trade["asset"] == values[1] and
                          trade["type"] == values[2] and
                          abs(trade["price"] - float(values[3].replace("$", ""))) < 0.01):
                        del self.data["trades"][i]
                        deleted_count += 1
                        break

            if deleted_count > 0:
                save_data(self.data, self.current_user)
                self.update_dashboard()
                self.log_activity(f"Deleted {deleted_count} trade(s) from {self.current_user}'s portfolio")
            else:
                messagebox.showwarning("Warning", "Could not find trade(s) to delete.")

    def show_context_menu(self, event):
        """Show context menu on right-click."""
        try:
            self.menu.tk_popup(event.x_root, event.y_root)
        finally:
            self.menu.grab_release()

    def refresh_all_prices(self):
        """Refresh prices for all assets in portfolio (crypto only; skip USD)."""
        trades = self.data.get("trades", [])
        assets = set(t["asset"] for t in trades if t["asset"] != "USD")

        if not assets:
            self.price_status_label.config(text="No assets to fetch prices for.")
            return

        self.price_status_label.config(text="Fetching prices...")
        self.update()

        updated_count = 0
        for asset in assets:
            price = fetch_price_from_api(asset)
            if price:
                self.price_cache[asset] = {
                    "price": price,
                    "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                updated_count += 1

        save_price_cache(self.price_cache)
        self.price_status_label.config(text=f"Updated {updated_count}/{len(assets)} prices")
        self.update_dashboard()
        self.log_activity(f"Refreshed prices for {updated_count} asset(s): {', '.join(sorted(assets))}")

    def get_current_price(self, asset: str) -> Optional[float]:
        """Get current price for an asset from cache or API."""
        # Check cache first
        if asset in self.price_cache:
            cache_entry = self.price_cache[asset]
            # Use cached price if less than 5 minutes old
            try:
                cache_time = datetime.strptime(cache_entry["timestamp"], "%Y-%m-%d %H:%M:%S")
                age_minutes = (datetime.now() - cache_time).total_seconds() / 60
                if age_minutes < 5:
                    return cache_entry["price"]
            except:
                pass

        # Try to fetch from API
        price = fetch_price_from_api(asset)
        if price:
            self.price_cache[asset] = {
                "price": price,
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            save_price_cache(self.price_cache)
            return price

        return None

    def update_dashboard(self):
        """Update the dashboard with current portfolio data."""
        # Clear tables
        for item in self.tree.get_children():
            self.tree.delete(item)

        for item in self.asset_tree.get_children():
            self.asset_tree.delete(item)

        trades = self.data.get("trades", [])
        if not trades:
            self.total_invested_label.config(text="Total Invested: $0.00")
            self.current_portfolio_value_label.config(text="Current Value: $0.00")
            self.total_pnl_label.config(text="Total P&L: $0.00")
            self.roi_label.config(text="ROI: 0.00%")
            self.realized_pnl_label.config(text="Realized P&L: $0.00")
            self.unrealized_pnl_label.config(text="Unrealized P&L: $0.00")
            return

        # Sort trades by date
        trades.sort(key=lambda x: x["date"])

        # Get cost basis method
        cost_basis_method = self.data["settings"].get("cost_basis_method", "average")

        # Calculate per-asset metrics (crypto only; USD handled separately as cash balance)
        crypto_assets = set(t["asset"] for t in trades if t["asset"] != "USD")
        total_portfolio_value = 0.0
        total_cost_basis = 0.0
        total_unrealized_pnl = 0.0
        realized_pnl = 0.0

        asset_data = {}

        for asset in crypto_assets:
            if cost_basis_method == "fifo":
                cost_basis, units_held, lots = calculate_cost_basis_fifo(trades, asset)
            elif cost_basis_method == "lifo":
                cost_basis, units_held, lots = calculate_cost_basis_lifo(trades, asset)
            else:  # average
                cost_basis, units_held, lots = calculate_cost_basis_average(trades, asset)

            current_price = self.get_current_price(asset)
            current_value = units_held * current_price if current_price else 0.0
            unrealized_pnl = current_value - cost_basis if current_price else 0.0
            roi = (unrealized_pnl / cost_basis * 100) if cost_basis > 0 else 0.0

            avg_cost_basis = cost_basis / units_held if units_held > 0 else 0.0

            asset_data[asset] = {
                "quantity": units_held,
                "cost_basis": cost_basis,
                "avg_cost_basis": avg_cost_basis,
                "current_price": current_price,
                "current_value": current_value,
                "unrealized_pnl": unrealized_pnl,
                "roi": roi
            }

            total_cost_basis += cost_basis
            total_portfolio_value += current_value
            total_unrealized_pnl += unrealized_pnl

        # Add USD balance (Deposit - Withdrawal) to portfolio value
        usd_balance = self.get_available_quantity("USD")
        total_portfolio_value += usd_balance

        # Calculate realized PnL (only BUY/SELL/Transfer for cost; Deposit/Withdrawal not investment)
        total_buy_cost = sum(t["total_value"] + t["fee"] for t in trades if t["type"] in ("BUY", "Transfer"))
        total_sell_proceeds = sum(t["total_value"] - t["fee"] for t in trades if t["type"] == "SELL")
        realized_pnl = total_sell_proceeds - (total_buy_cost - total_cost_basis)

        # Update summary value labels (values colored: green for profit/positive, red for loss; Current Value always green)
        self.total_invested_label.config(text=f"${total_cost_basis:,.2f}")
        self.current_portfolio_value_label.config(text=f"${total_portfolio_value:,.2f}", fg=APPLE_COLOR_PROFIT)
        total_pnl = total_unrealized_pnl + realized_pnl
        pnl_color = APPLE_COLOR_PROFIT if total_pnl >= 0 else APPLE_COLOR_LOSS
        self.total_pnl_label.config(text=f"${total_pnl:,.2f}", fg=pnl_color)
        total_roi = (total_pnl / total_cost_basis * 100) if total_cost_basis > 0 else 0.0
        roi_color = APPLE_COLOR_PROFIT if total_roi >= 0 else APPLE_COLOR_LOSS
        self.roi_label.config(text=f"{total_roi:.2f}%", fg=roi_color)

        realized_color = APPLE_COLOR_PROFIT if realized_pnl >= 0 else APPLE_COLOR_LOSS
        unrealized_color = APPLE_COLOR_PROFIT if total_unrealized_pnl >= 0 else APPLE_COLOR_LOSS
        self.realized_pnl_label.config(text=f"${realized_pnl:,.2f}", fg=realized_color)
        self.unrealized_pnl_label.config(text=f"${total_unrealized_pnl:,.2f}", fg=unrealized_color)

        # Populate asset breakdown (crypto only; USD can be shown as cash in summary if desired)
        for asset in sorted(crypto_assets):
            data = asset_data[asset]
            price_str = f"${data['current_price']:.2f}" if data['current_price'] else "N/A"

            pnl_color = APPLE_COLOR_PROFIT if data['unrealized_pnl'] >= 0 else APPLE_COLOR_LOSS
            roi_color = APPLE_COLOR_PROFIT if data['roi'] >= 0 else APPLE_COLOR_LOSS
            self.asset_tree.insert('', tk.END, values=(
                asset,
                f"{data['quantity']:.8f}",
                f"${data['avg_cost_basis']:.2f}",
                price_str,
                f"${data['current_value']:,.2f}",
                f"${data['unrealized_pnl']:,.2f}",
                f"{data['roi']:.2f}%"
            ), tags=(pnl_color, roi_color))
            self.asset_tree.tag_configure(pnl_color, foreground=pnl_color)
            self.asset_tree.tag_configure(roi_color, foreground=roi_color)

        # Calculate client P&L if current user is a client
        is_client = self.data["settings"].get("is_client", False)
        client_percentage = self.data["settings"].get("client_percentage", 0.0)

        if is_client and hasattr(self, 'client_pnl_tree'):
            client_buy_cost = sum(t["total_value"] + t["fee"] for t in trades if t["type"] in ("BUY", "Transfer"))
            client_sell_proceeds = sum(t["total_value"] - t["fee"] for t in trades if t["type"] == "SELL")
            client_current_value = total_portfolio_value
            client_pnl = (client_current_value + client_sell_proceeds) - client_buy_cost
            your_share = client_pnl * (client_percentage / 100)

            for item in self.client_pnl_tree.get_children():
                self.client_pnl_tree.delete(item)

            self.client_pnl_tree.insert('', tk.END, values=(
                self.current_user,
                f"{client_percentage:.1f}%",
                f"${client_pnl:,.2f}",
                f"${your_share:,.2f}"
            ))

        # Populate trades table
        trades.sort(key=lambda x: x["date"], reverse=True)
        accounts = get_accounts(self.data)
        account_dict = {acc["id"]: acc["name"] for acc in accounts}

        for trade in trades:
            order_type = trade.get("order_type", "maker")
            account_id = trade.get("account_id")
            account_name = account_dict.get(account_id, "Unknown") if account_id else "None"

            self.tree.insert('', tk.END, values=(
                trade["date"],
                trade["asset"],
                trade["type"],
                f"${trade['price']:.2f}",
                f"{trade['quantity']:.8f}",
                trade["exchange"],
                order_type.upper(),
                account_name,
                f"-${trade['fee']:.2f}",
                f"${trade['total_value']:.2f}"
            ), tags=(trade["id"],))

        self.log_text.config(state='normal')
        self.log_text.insert(tk.END, f"Dashboard Updated: {datetime.now().strftime('%H:%M:%S')}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state='disabled')

    def _proj_add_row(self):
        """Add a row to the potential transactions table (dialog)."""
        d = tk.Toplevel(self)
        d.title("Add potential transaction")
        d.geometry("380x240")
        d.transient(self)
        d.grab_set()
        f = tb.Frame(d, padding=10)
        f.pack(fill="both", expand=True)
        tk.Label(f, text="Asset:").grid(row=0, column=0, sticky=W, pady=5)
        asset_var = tb.StringVar(value="BTC")
        ttk.Combobox(f, textvariable=asset_var, values=COMMON_ASSETS, state="readonly", width=14).grid(row=0, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Type:").grid(row=1, column=0, sticky=W, pady=5)
        type_var = tb.StringVar(value="BUY")
        ttk.Combobox(f, textvariable=type_var, values=["BUY", "SELL"], state="readonly", width=14).grid(row=1, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Price ($):").grid(row=2, column=0, sticky=W, pady=5)
        price_var = tb.StringVar(value="0")
        tb.Entry(f, textvariable=price_var, width=16).grid(row=2, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Quantity:").grid(row=3, column=0, sticky=W, pady=5)
        qty_var = tb.StringVar(value="0")
        tb.Entry(f, textvariable=qty_var, width=16).grid(row=3, column=1, sticky=EW, pady=5, padx=5)
        f.grid_columnconfigure(1, weight=1)
        def add():
            try:
                p = float(price_var.get())
                q = float(qty_var.get())
                self.proj_tree.insert("", tk.END, values=(asset_var.get(), type_var.get(), f"{p:.2f}", f"{q:.8f}"))
                d.destroy()
                self.run_projection_from_table()
            except ValueError:
                messagebox.showwarning("Invalid", "Price and Quantity must be numbers.", parent=d)
        # Percentage row: 25%, 50%, 75%, 100% of available quantity for asset
        pct_row = tb.Frame(f)
        pct_row.grid(row=4, column=0, columnspan=2, pady=5)

        def set_pct(p):
            try:
                av = self.get_available_quantity(asset_var.get())
                qty_var.set(f"{(av * p / 100):.8f}")
            except Exception:
                pass

        tk.Label(pct_row, text="Qty % of holding:").pack(side=tk.LEFT, padx=(0, 8))
        for p in (25, 50, 75, 100):
            tb.Button(pct_row, text=f"{p}%", width=4, command=lambda x=p: set_pct(x), bootstyle=SECONDARY).pack(side=tk.LEFT, padx=2)
        btn_row = tb.Frame(f)
        btn_row.grid(row=5, column=0, columnspan=2, pady=10)
        tb.Button(btn_row, text="Add", command=add, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=10)
        tb.Button(btn_row, text="Cancel", command=d.destroy).pack(side=tk.LEFT, padx=10)

    def _proj_remove_row(self):
        """Remove selected row from potential transactions table."""
        sel = self.proj_tree.selection()
        for i in sel:
            self.proj_tree.delete(i)
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
        """Edit selected row in potential transactions table."""
        sel = self.proj_tree.selection()
        if not sel:
            return
        row_id = sel[0]
        vals = self.proj_tree.item(row_id, "values")
        if len(vals) < 4:
            return
        d = tk.Toplevel(self)
        d.title("Edit potential transaction")
        d.geometry("340x260")
        d.transient(self)
        d.grab_set()
        f = tb.Frame(d, padding=10)
        f.pack(fill="both", expand=True)
        tk.Label(f, text="Asset:").grid(row=0, column=0, sticky=W, pady=5)
        asset_var = tb.StringVar(value=vals[0])
        ttk.Combobox(f, textvariable=asset_var, values=COMMON_ASSETS, state="readonly", width=14).grid(row=0, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Type:").grid(row=1, column=0, sticky=W, pady=5)
        type_var = tb.StringVar(value=vals[1])
        ttk.Combobox(f, textvariable=type_var, values=["BUY", "SELL"], state="readonly", width=14).grid(row=1, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Price ($):").grid(row=2, column=0, sticky=W, pady=5)
        price_var = tb.StringVar(value=vals[2])
        tb.Entry(f, textvariable=price_var, width=16).grid(row=2, column=1, sticky=EW, pady=5, padx=5)
        tk.Label(f, text="Quantity:").grid(row=3, column=0, sticky=W, pady=5)
        qty_var = tb.StringVar(value=vals[3])
        tb.Entry(f, textvariable=qty_var, width=16).grid(row=3, column=1, sticky=EW, pady=5, padx=5)
        f.grid_columnconfigure(1, weight=1)

        def save_edit():
            try:
                p = float(price_var.get())
                q = float(qty_var.get())
                self.proj_tree.item(row_id, values=(asset_var.get(), type_var.get(), f"{p:.2f}", f"{q:.8f}"))
                d.destroy()
                self.run_projection_from_table()
            except ValueError:
                messagebox.showwarning("Invalid", "Price and Quantity must be numbers.", parent=d)

        btn_row = tb.Frame(f)
        btn_row.grid(row=4, column=0, columnspan=2, pady=10)
        tb.Button(btn_row, text="Save", command=save_edit, bootstyle=SUCCESS).pack(side=tk.LEFT, padx=10)
        tb.Button(btn_row, text="Cancel", command=d.destroy).pack(side=tk.LEFT, padx=10)

    def run_projection_from_table(self):
        """Compute projected P&L from current holdings + potential transactions table."""
        cost_basis_method = self.data["settings"].get("cost_basis_method", "average")
        trades = list(self.data.get("trades", []))
        for row in self.proj_tree.get_children(""):
            vals = self.proj_tree.item(row, "values")
            try:
                asset, typ, price_s, qty_s = vals[0], vals[1], vals[2], vals[3]
                price = float(price_s.replace("$", "").replace(",", ""))
                qty = float(qty_s.replace(",", ""))
                if price <= 0 or qty <= 0:
                    continue
                total = price * qty
                trades.append({
                    "id": str(uuid.uuid4()), "date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "asset": asset, "type": typ, "price": price, "quantity": qty, "fee": 0, "total_value": total,
                    "exchange": "", "order_type": "maker", "account_id": None
                })
            except (ValueError, IndexError):
                continue
        if not trades:
            self.proj_result_label.config(text="-- (add transactions)", fg="gray")
            return
        assets = set(t["asset"] for t in trades)
        total_cost = 0.0
        total_value = 0.0
        for asset in assets:
            at = [x for x in trades if x["asset"] == asset]
            if cost_basis_method == "fifo":
                cb, u, _ = calculate_cost_basis_fifo(at, asset)
            elif cost_basis_method == "lifo":
                cb, u, _ = calculate_cost_basis_lifo(at, asset)
            else:
                cb, u, _ = calculate_cost_basis_average(at, asset)
            total_cost += cb
            p = self.get_current_price(asset)
            if p:
                total_value += u * p
            else:
                total_value += cb
        pnl = total_value - total_cost
        color = APPLE_COLOR_PROFIT if pnl >= 0 else APPLE_COLOR_LOSS
        self.proj_result_label.config(text=f"${pnl:,.2f}", fg=color)

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
        filename = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")]
        )
        if filename:
            try:
                export_data = {
                    "trades": self.data["trades"],
                    "export_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                }
                with open(filename, 'w') as f:
                    json.dump(export_data, f, indent=4)
                messagebox.showinfo("Export", f"Trades exported to {filename}")
                self.log_activity(f"Exported trades to {filename}")
            except Exception as e:
                messagebox.showerror("Export Error", f"Error exporting trades: {e}")

    def import_trades(self):
        """Import trades from JSON file."""
        filename = filedialog.askopenfilename(
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")]
        )
        if filename:
            try:
                with open(filename, 'r') as f:
                    import_data = json.load(f)

                if "trades" in import_data:
                    imported_trades = import_data["trades"]
                    # Add IDs to imported trades if missing
                    for trade in imported_trades:
                        if "id" not in trade:
                            trade["id"] = str(uuid.uuid4())

                    # Add client fields if missing
                    for trade in imported_trades:
                        if "is_client_trade" not in trade:
                            trade["is_client_trade"] = False
                        if "client_name" not in trade:
                            trade["client_name"] = ""
                        if "client_percentage" not in trade:
                            trade["client_percentage"] = 0.0

                    self.data["trades"].extend(imported_trades)
                    save_data(self.data, self.current_user)
                    messagebox.showinfo("Import", f"Imported {len(imported_trades)} trades successfully.")
                    self.update_dashboard()
                    self.log_activity(f"Imported {len(imported_trades)} trade(s) from {os.path.basename(filename)}")
                else:
                    messagebox.showerror("Import Error", "Invalid file format. Expected 'trades' key.")
            except Exception as e:
                messagebox.showerror("Import Error", f"Error importing trades: {e}")

    def reset_data(self):
        """Reset all trade data."""
        if messagebox.askyesno("Reset Data",
                              "This will permanently delete all trade history. Continue?"):
            trade_count = len(self.data["trades"])
            self.data["trades"] = []
            save_data(self.data, self.current_user)
            self.update_dashboard()
            messagebox.showinfo("Reset", "Data reset successfully.")
            self.log_activity(f"Reset all data: deleted {trade_count} trade(s) for user {self.current_user}")

    def log_activity(self, msg: str):
        """Log activity message."""
        self.log_text.config(state='normal')
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.log_text.insert(tk.END, f"[{timestamp}] {msg}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state='disabled')


# --- Run Application ---
if __name__ == "__main__":
    app = CryptoTrackerApp()
    app.mainloop()
>>>>>>> Incoming (Background Agent changes)
