# Opening the app and adding FuckYouMoneyCore

## If Xcode crashes when opening the existing project

Generate a **new** Xcode project with XcodeGen (the current `.xcodeproj` may be corrupted):

```bash
brew install xcodegen
cd FuckYouMoneyApp
xcodegen generate
open FuckYouMoneyApp.xcodeproj
```

This creates a fresh project that already includes the **FuckYouMoneyCore** local package (repo root). No further steps needed—build and run (⌘R).

---

## If you open the project manually (no XcodeGen)

This project can be opened without a Swift package to avoid Xcode crashes. Add the local package **after** opening:

1. In Xcode: **File → Add Package Dependencies…**
2. Click **Add Local…** (bottom left).
3. Select the **parent folder** of `FuckYouMoneyApp` (the repo root—the folder that contains `Package.swift`, `Sources`, and `FuckYouMoneyApp`).
4. Click **Add Package**.
5. Ensure **FuckYouMoneyCore** is checked for the **FuckYouMoneyApp** target. Click **Add Package** again.

The app should build and run (⌘R).
