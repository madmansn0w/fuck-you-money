# Opening the app and adding CryptoTrackerCore

## If Xcode crashes when opening the existing project

Generate a **new** Xcode project with XcodeGen (the current `.xcodeproj` may be corrupted):

```bash
brew install xcodegen
cd CryptoTrackerApp
xcodegen generate
open CryptoTrackerApp.xcodeproj
```

This creates a fresh project that already includes the **CryptoTrackerCore** local package (repo root). No further steps needed—build and run (⌘R).

---

## If you open the project manually (no XcodeGen)

This project can be opened without a Swift package to avoid Xcode crashes. Add the local package **after** opening:

1. In Xcode: **File → Add Package Dependencies…**
2. Click **Add Local…** (bottom left).
3. Select the **parent folder** of `CryptoTrackerApp` (the repo root—the folder that contains `Package.swift`, `Sources`, and `CryptoTrackerApp`).
4. Click **Add Package**.
5. Ensure **CryptoTrackerCore** is checked for the **CryptoTrackerApp** target. Click **Add Package** again.

The app should build and run (⌘R).
