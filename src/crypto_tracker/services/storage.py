"""Data persistence: JSON load/save, user list, price cache, and data migrations."""

from __future__ import annotations

import json
import os
import shutil
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from crypto_tracker.config.constants import (
    BASE_DIR,
    DATA_FILE,
    DEFAULT_EXCHANGES,
    PRICE_CACHE_FILE,
    USERS_FILE,
)


def get_user_data_file(username: str) -> str:
    """Return the absolute path to the data file for the given username."""
    safe = username.lower().replace(" ", "_")
    return str(BASE_DIR / f"crypto_data_{safe}.json")


def load_users() -> List[str]:
    """Load list of usernames from the users file."""
    if os.path.exists(USERS_FILE):
        try:
            with open(USERS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("users", ["Default"])
        except Exception:
            pass
    return ["Default"]


def save_users(users: List[str]) -> None:
    """Save list of usernames. Raises on I/O error (caller may show UI message)."""
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        json.dump({"users": users}, f, indent=4)


def add_user(username: str) -> bool:
    """Add a new user. Returns False if username already exists."""
    users = load_users()
    if username in users:
        return False
    users.append(username)
    save_users(users)
    return True


def delete_user(username: str) -> bool:
    """Remove a user. Returns False if user does not exist or is the last user."""
    users = load_users()
    if username not in users or len(users) == 1:
        return False
    users.remove(username)
    save_users(users)
    path = get_user_data_file(username)
    if os.path.exists(path):
        try:
            os.remove(path)
        except OSError:
            pass
    return True


def migrate_exchange_fees(old_exchanges: Dict[str, Any]) -> Dict[str, Dict[str, float]]:
    """Migrate old single-fee exchange structure to maker/taker structure."""
    migrated: Dict[str, Dict[str, float]] = {}
    for exchange, fee in old_exchanges.items():
        if isinstance(fee, dict) and "maker" in fee and "taker" in fee:
            migrated[exchange] = dict(fee)
        else:
            f = float(fee) if not isinstance(fee, dict) else (fee.get("maker", 0) or fee.get("taker", 0))
            migrated[exchange] = {"maker": f, "taker": f}
    return migrated


def create_account_group_in_data(data: Dict[str, Any], name: str) -> str:
    """Create an account group in the data structure. Returns the new group id."""
    group_id = str(uuid.uuid4())
    group = {"id": group_id, "name": name, "accounts": []}
    if "account_groups" not in data:
        data["account_groups"] = []
    data["account_groups"].append(group)
    return group_id


def create_account_in_data(
    data: Dict[str, Any],
    name: str,
    group_id: Optional[str] = None,
) -> str:
    """Create an account in the data structure. Returns the new account id."""
    account_id = str(uuid.uuid4())
    account = {
        "id": account_id,
        "name": name,
        "account_group_id": group_id,
        "created_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }
    if "accounts" not in data:
        data["accounts"] = []
    data["accounts"].append(account)
    if group_id and "account_groups" in data:
        for group in data["account_groups"]:
            if group.get("id") == group_id:
                if account_id not in group.get("accounts", []):
                    group.setdefault("accounts", []).append(account_id)
                break
    return account_id


def migrate_to_account_structure(data: Dict[str, Any], username: str) -> Dict[str, Any]:
    """Migrate existing data to account/group structure. Modifies data in place and returns it."""
    if "account_groups" not in data:
        data["account_groups"] = []
    if "accounts" not in data:
        data["accounts"] = []

    if not data["accounts"]:
        default_group_id = create_account_group_in_data(data, "My Portfolio")
        default_account_id = create_account_in_data(data, "Main", default_group_id)
        if "settings" not in data:
            data["settings"] = {}
        data["settings"]["default_account_id"] = default_account_id
        if "trades" in data:
            for trade in data["trades"]:
                trade["account_id"] = default_account_id
                trade.pop("is_client_trade", None)
                trade.pop("client_name", None)
                trade.pop("client_percentage", None)

    if "settings" not in data:
        data["settings"] = {}

    if "trades" in data:
        had_client = any(t.get("is_client_trade", False) for t in data["trades"])
        if had_client and "is_client" not in data["settings"]:
            client_trades = [t for t in data["trades"] if t.get("is_client_trade")]
            if client_trades:
                data["settings"]["is_client"] = True
                data["settings"]["client_percentage"] = client_trades[0].get("client_percentage", 0.0)

    return data


def get_account_groups(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Return all account groups from data."""
    return data.get("account_groups", [])


def get_accounts(
    data: Dict[str, Any],
    group_id: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Return accounts, optionally filtered by group_id."""
    accounts = data.get("accounts", [])
    if not group_id:
        return accounts
    group = next((g for g in data.get("account_groups", []) if g.get("id") == group_id), None)
    member_ids = set(group["accounts"]) if group and group.get("accounts") else set()
    if member_ids:
        return [a for a in accounts if a.get("account_group_id") == group_id and a.get("id") in member_ids]
    return [a for a in accounts if a.get("account_group_id") == group_id]


def assign_trade_to_account(data: Dict[str, Any], trade_id: str, account_id: str) -> bool:
    """Assign a trade to an account. Returns True if the trade was found and updated."""
    for trade in data.get("trades", []):
        if trade.get("id") == trade_id:
            trade["account_id"] = account_id
            return True
    return False


def get_default_data() -> Dict[str, Any]:
    """Return a fresh default data structure (no file I/O)."""
    default_data: Dict[str, Any] = {
        "trades": [],
        "settings": {
            "default_exchange": "Bitstamp",
            "fee_structure": dict(DEFAULT_EXCHANGES),
            "cost_basis_method": "average",
            "is_client": False,
            "client_percentage": 0.0,
            "default_account_id": None,
        },
        "account_groups": [],
        "accounts": [],
    }
    default_group_id = create_account_group_in_data(default_data, "My Portfolio")
    default_account_id = create_account_in_data(default_data, "Main", default_group_id)
    default_data["settings"]["default_account_id"] = default_account_id
    return default_data


def load_data(username: str = "Default") -> Dict[str, Any]:
    """
    Load application data from JSON with migrations.
    Uses get_user_data_file(username). Migrates legacy DATA_FILE into user file for Default if needed.
    """
    data_file = get_user_data_file(username)
    if username == "Default" and os.path.exists(DATA_FILE) and not os.path.exists(data_file):
        try:
            shutil.copy(DATA_FILE, data_file)
        except OSError:
            pass

    if os.path.exists(data_file):
        try:
            with open(data_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            if "settings" in data and "fee_structure" in data["settings"]:
                data["settings"]["fee_structure"] = migrate_exchange_fees(data["settings"]["fee_structure"])
            data = migrate_to_account_structure(data, username)
            if "trades" in data:
                for trade in data["trades"]:
                    if "id" not in trade:
                        trade["id"] = str(uuid.uuid4())
                    if "account_id" not in trade:
                        if data.get("accounts"):
                            trade["account_id"] = data["accounts"][0]["id"]
                        else:
                            trade["account_id"] = None
            if "settings" in data and "cost_basis_method" not in data["settings"]:
                data["settings"]["cost_basis_method"] = "average"
            if "settings" not in data:
                data["settings"] = {}
            s = data["settings"]
            if "fee_structure" not in s:
                s["fee_structure"] = dict(DEFAULT_EXCHANGES)
            for name, fees in (("Bitstamp", {"maker": 0.30, "taker": 0.40}), ("Wallet", {"maker": 0.0, "taker": 0.0})):
                if name not in s["fee_structure"]:
                    s["fee_structure"][name] = fees
            s.setdefault("is_client", False)
            s.setdefault("client_percentage", 0.0)
            s.setdefault("default_account_id", None)
            data.setdefault("account_groups", [])
            data.setdefault("accounts", [])
            return data
        except Exception:
            raise

    return get_default_data()


def save_data(data: Dict[str, Any], username: str = "Default") -> None:
    """Save application data to JSON. Raises on I/O error."""
    path = get_user_data_file(username)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)


def load_price_cache() -> Dict[str, Any]:
    """Load price cache from file. Returns empty dict on missing or invalid file."""
    if not os.path.exists(PRICE_CACHE_FILE):
        return {}
    try:
        with open(PRICE_CACHE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_price_cache(cache: Dict[str, Any]) -> None:
    """Save price cache to file. Ignores I/O errors (non-fatal)."""
    try:
        with open(PRICE_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f, indent=4)
    except OSError:
        pass
