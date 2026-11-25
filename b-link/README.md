# B.Link releases

`B.Link-Setup.exe` installs B.Link on Windows, updates it, or cancels. It reads `latest.json` from this repo,
downloads the app zip from here and the Electron runtime from the official Electron release, and checks every
SHA-256 before using it. Saves, keys and voice files stay in `%APPDATA%\B.Link`.

To publish a new version: add `B.Link-app-<version>.zip` and update `latest.json` (version, notes, app sha256 and bytes).
Source for the installer is in `installer/` of the Labyrinth source repo.
