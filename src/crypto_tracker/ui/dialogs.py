"""Dialog windows for Crypto Tracker: users, accounts, about, export/import."""

from __future__ import annotations

import json
import os
import uuid
from datetime import datetime
import tkinter as tk
from tkinter import W, EW, filedialog, messagebox
from tkinter import ttk

import ttkbootstrap as tb
from ttkbootstrap.constants import DANGER, PRIMARY, SUCCESS

from crypto_tracker.theming.style import APPLE_PADDING, APPLE_SPACING_LARGE, APPLE_SPACING_MEDIUM
from crypto_tracker.services import storage

# Re-export storage helpers used by dialogs (with messagebox on error for UI)
def _load_users():
    return storage.load_users()

def _save_users(users):
    try:
        storage.save_users(users)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving users: {e}")

def _load_data(username: str):
    try:
        return storage.load_data(username)
    except Exception as e:
        messagebox.showerror("Data Load Error", f"Error loading data: {e}")
        return storage.get_default_data()

def _save_data(data, username: str):
    try:
        storage.save_data(data, username)
    except Exception as e:
        messagebox.showerror("Save Error", f"Error saving data: {e}")


def show_about(app) -> None:
    """Show about dialog."""
    messagebox.showinfo(
        "About",
        "CryptoPnL Tracker\n\nA cryptocurrency portfolio tracking application\n"
        "with support for multiple users, accounts, and client tracking.",
    )


def add_user_dialog(app) -> None:
    """Show dialog to add a new user."""
    dialog = tk.Toplevel(app)
    dialog.title("Add User")
    dialog.geometry("300x150")
    dialog.transient(app)
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
        if username in app.users:
            messagebox.showwarning("Input Error", "User already exists.")
            return
        if storage.add_user(username):
            app.users = _load_users()
            app.data = _load_data(username)
            app.current_user = username
            app.refresh_account_groups_sidebar()
            app.update_summary_panel()
            app.update_dashboard()
            dialog.destroy()
            app.log_activity(f"Created new user: {username}")
        else:
            messagebox.showerror("Error", "Failed to add user.")

    tb.Button(frame, text="Add", command=add_user_action, bootstyle=SUCCESS).pack(pady=10)
    tb.Button(frame, text="Cancel", command=dialog.destroy).pack()


def delete_user_dialog(app) -> None:
    """Show dialog to delete a user."""
    if len(app.users) <= 1:
        messagebox.showwarning("Cannot Delete", "Cannot delete the last user.")
        return

    username = app.current_user
    if messagebox.askyesno(
        "Confirm Delete",
        f"Are you sure you want to delete user '{username}'?\n\nThis will delete all their trade data.",
    ):
        if storage.delete_user(username):
            app.users = _load_users()
            if app.current_user == username:
                app.current_user = app.users[0]
                app.data = _load_data(app.current_user)
            app.refresh_account_groups_sidebar()
            app.update_summary_panel()
            app.update_dashboard()
            app.log_activity(f"Deleted user: {username}")
        else:
            messagebox.showerror("Error", "Failed to delete user.")


def new_account_dialog(app) -> None:
    """Show dialog to create a new account."""
    from crypto_tracker.theming.style import APPLE_FONT_DEFAULT

    dialog = tk.Toplevel(app)
    dialog.title("New Account")
    dialog.geometry("400x200")
    dialog.transient(app)
    dialog.grab_set()

    frame = tb.Frame(dialog, padding=APPLE_PADDING)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="Account Name:", font=APPLE_FONT_DEFAULT).grid(
        row=0, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM
    )
    name_var = tb.StringVar()
    tb.Entry(frame, textvariable=name_var, width=30, font=APPLE_FONT_DEFAULT).grid(
        row=0, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM
    )

    tk.Label(frame, text="Account Group:", font=APPLE_FONT_DEFAULT).grid(
        row=1, column=0, sticky=W, pady=APPLE_SPACING_MEDIUM
    )
    group_var = tb.StringVar()
    groups = storage.get_account_groups(app.data)
    group_names = ["None"] + [g["name"] for g in groups]
    group_combo = ttk.Combobox(
        frame, textvariable=group_var, values=group_names, state="readonly", width=27
    )
    group_combo.set("None")
    if getattr(app, "selected_group_id", None):
        g = next((x for x in groups if x["id"] == app.selected_group_id), None)
        if g and g["name"] in group_names:
            group_var.set(g["name"])
    group_combo.grid(row=1, column=1, sticky=EW, pady=APPLE_SPACING_MEDIUM, padx=APPLE_SPACING_MEDIUM)

    frame.grid_columnconfigure(1, weight=1)

    def create_account():
        name = name_var.get().strip()
        if not name:
            messagebox.showwarning("Input Error", "Please enter an account name.")
            return

        existing_accounts = storage.get_accounts(app.data)
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

        storage.create_account_in_data(app.data, name, group_id)
        _save_data(app.data, app.current_user)
        app.refresh_account_groups_sidebar()
        app.refresh_sidebar_accounts()
        app.update_account_combo()
        app.update_summary_panel()
        app.update_dashboard()
        dialog.destroy()
        app.log_activity(f"Created account: {name}")

    btn_frame = tb.Frame(frame)
    btn_frame.grid(row=2, column=0, columnspan=2, pady=APPLE_SPACING_LARGE)
    tb.Button(btn_frame, text="Create", command=create_account, bootstyle=SUCCESS).pack(
        side="left", padx=APPLE_SPACING_MEDIUM
    )
    tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side="left", padx=APPLE_SPACING_MEDIUM)


def manage_accounts_dialog(app) -> None:
    """Show dialog to manage accounts."""
    messagebox.showinfo(
        "Manage Accounts",
        "Account management feature coming soon.\n\n"
        "Use 'New Account' to create accounts.\n"
        "Accounts can be edited/deleted from the sidebar.",
    )


def manage_users_dialog(app) -> None:
    """Show dialog to manage users (list and delete)."""
    from crypto_tracker.theming.style import APPLE_FONT_DEFAULT

    dialog = tk.Toplevel(app)
    dialog.title("Manage Users")
    dialog.geometry("400x300")
    dialog.transient(app)
    dialog.grab_set()

    frame = tb.Frame(dialog, padding=APPLE_PADDING)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="Users:", font=APPLE_FONT_DEFAULT).pack(anchor="w", pady=APPLE_SPACING_MEDIUM)

    listbox_frame = tb.Frame(frame)
    listbox_frame.pack(fill="both", expand=True, pady=APPLE_SPACING_MEDIUM)

    user_listbox = tk.Listbox(listbox_frame, height=8, font=APPLE_FONT_DEFAULT)
    user_listbox.pack(side="left", fill="both", expand=True)

    scrollbar = ttk.Scrollbar(listbox_frame, orient="vertical", command=user_listbox.yview)
    scrollbar.pack(side="right", fill="y")
    user_listbox.config(yscrollcommand=scrollbar.set)

    def _on_listbox_scroll(event):
        d = getattr(event, "delta", 0) or (
            120 if getattr(event, "num", None) == 4 else -120 if getattr(event, "num", None) == 5 else 0
        )
        if d:
            step = int(-d / 120) if abs(d) > 10 else (-1 if d > 0 else 1)
            user_listbox.yview_scroll(step, "units")

    user_listbox.bind("<MouseWheel>", _on_listbox_scroll)
    user_listbox.bind("<Button-4>", lambda e: user_listbox.yview_scroll(-1, "units"))
    user_listbox.bind("<Button-5>", lambda e: user_listbox.yview_scroll(1, "units"))

    for user in app.users:
        user_listbox.insert("end", user)

    btn_frame = tb.Frame(frame)
    btn_frame.pack(fill="x", pady=APPLE_SPACING_MEDIUM)

    def delete_selected():
        selection = user_listbox.curselection()
        if not selection:
            messagebox.showwarning("No Selection", "Please select a user to delete.")
            return

        username = user_listbox.get(selection[0])
        if len(app.users) <= 1:
            messagebox.showwarning("Cannot Delete", "Cannot delete the last user.")
            return

        if messagebox.askyesno(
            "Confirm Delete",
            f"Are you sure you want to delete user '{username}'?\n\nThis will delete all their trade data.",
        ):
            if storage.delete_user(username):
                app.users = _load_users()
                user_listbox.delete(0, "end")
                for user in app.users:
                    user_listbox.insert("end", user)
                if app.current_user == username:
                    app.current_user = app.users[0]
                    app.data = _load_data(app.current_user)
                    app.update_dashboard()
                app.log_activity(f"Deleted user: {username}")
                messagebox.showinfo("Success", f"User '{username}' deleted successfully.")
            else:
                messagebox.showerror("Error", "Failed to delete user.")

    tb.Button(btn_frame, text="Delete Selected", command=delete_selected, bootstyle=DANGER).pack(
        side="left", padx=APPLE_SPACING_MEDIUM
    )
    tb.Button(btn_frame, text="Close", command=dialog.destroy).pack(side="left", padx=APPLE_SPACING_MEDIUM)


def switch_user_dialog(app) -> None:
    """Show dialog to switch users."""
    from crypto_tracker.theming.style import APPLE_FONT_DEFAULT

    dialog = tk.Toplevel(app)
    dialog.title("Switch User")
    dialog.geometry("300x150")
    dialog.transient(app)
    dialog.grab_set()

    frame = tb.Frame(dialog, padding=APPLE_PADDING)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="Select User:", font=APPLE_FONT_DEFAULT).pack(pady=APPLE_SPACING_MEDIUM)
    user_var = tb.StringVar(value=app.current_user)
    user_combo = ttk.Combobox(
        frame, textvariable=user_var, values=app.users, state="readonly", width=25
    )
    user_combo.pack(pady=APPLE_SPACING_MEDIUM)

    def switch():
        new_user = user_var.get()
        if new_user != app.current_user:
            _save_data(app.data, app.current_user)
            app.current_user = new_user
            app.data = _load_data(app.current_user)
            app.users = _load_users()
            app.selected_group_id = None
            app.selected_account_id = None
            app.refresh_account_groups_sidebar()
            app.refresh_sidebar_accounts()
            app.update_account_combo()
            app.update_summary_panel()
            app.update_dashboard()
            if hasattr(app, "title"):
                app.title(f"CryptoPnL Tracker – {app.current_user}")
            app.log_activity(f"Switched to user: {app.current_user}")
        dialog.destroy()

    btn_frame = tb.Frame(frame)
    btn_frame.pack(pady=APPLE_SPACING_LARGE)
    tb.Button(btn_frame, text="Switch", command=switch, bootstyle=PRIMARY).pack(
        side="left", padx=APPLE_SPACING_MEDIUM
    )
    tb.Button(btn_frame, text="Cancel", command=dialog.destroy).pack(side="left", padx=APPLE_SPACING_MEDIUM)


def export_trades(app) -> None:
    """Export trades to JSON file."""
    filename = filedialog.asksaveasfilename(
        defaultextension=".json",
        filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
    )
    if filename:
        try:
            export_data = {
                "trades": app.data["trades"],
                "export_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            }
            with open(filename, "w") as f:
                json.dump(export_data, f, indent=4)
            messagebox.showinfo("Export", f"Trades exported to {filename}")
            app.log_activity(f"Exported trades to {filename}")
        except Exception as e:
            messagebox.showerror("Export Error", f"Error exporting trades: {e}")


def import_trades(app) -> None:
    """Import trades from JSON file."""
    filename = filedialog.askopenfilename(
        filetypes=[("JSON files", "*.json"), ("All files", "*.*")]
    )
    if filename:
        try:
            with open(filename, "r") as f:
                import_data = json.load(f)

            if "trades" in import_data:
                imported_trades = import_data["trades"]
                for trade in imported_trades:
                    if "id" not in trade:
                        trade["id"] = str(uuid.uuid4())
                    if "is_client_trade" not in trade:
                        trade["is_client_trade"] = False
                    if "client_name" not in trade:
                        trade["client_name"] = ""
                    if "client_percentage" not in trade:
                        trade["client_percentage"] = 0.0

                app.data["trades"].extend(imported_trades)
                _save_data(app.data, app.current_user)
                messagebox.showinfo("Import", f"Imported {len(imported_trades)} trades successfully.")
                app.update_dashboard()
                app.update_summary_panel()
                app.log_activity(f"Imported {len(imported_trades)} trade(s) from {os.path.basename(filename)}")
            else:
                messagebox.showerror("Import Error", "Invalid file format. Expected 'trades' key.")
        except Exception as e:
            messagebox.showerror("Import Error", f"Error importing trades: {e}")
