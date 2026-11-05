# MyBrowser

A macOS browser built with Swift, SwiftUI and WebKit. No AI features.

## Features
- **Spaces**: separate groups of tabs for different things you're working on (Work, School, a project). Each space has its own tabs and pinned tabs, a color and an icon. Switch with the icons at the bottom of the sidebar or Ctrl+1 to Ctrl+9. Right-click a space to rename it, change its color or icon, or delete it. Right-click a tab > Move to Space. Your last space and each space's last tab are remembered. Bookmarks, history and downloads are shared across spaces.
- **Two layouts**: tabs in a vertical sidebar, or across the top (a real window toolbar like Safari with back/forward, the address bar and buttons in the title bar row, tab strip below it, bookmarks row under that). Switch in Settings or with Opt+Cmd+\\.
- **Collapsible sidebar**: shrink it to a narrow icon rail with the sidebar button or Cmd+\\ (tabs and bookmarks show as lettered icons, spaces and History/Downloads stay at the bottom). Drag the edge of the expanded sidebar to resize it. In Settings, turn on "Shrink sidebar to icons automatically" to collapse it after you click a tab or bookmark in the sidebar, or click the page.
- **Tabs** in a vertical sidebar (new, close, switch, drag to reorder, loading spinner). Tabs, bookmarks and the icon rail show each site's own icon
- **Pinned tabs**: right-click a tab or press Opt+Cmd+P. They sit at the top of that space and come back on launch. Closing a pinned tab (right-click > Close Tab) unpins it.
- **Address bar** takes a URL or a search term, with a **suggestions** dropdown from your bookmarks and history
- Back / forward / reload / stop, swipe gestures, page load progress bar
- Cmd+click and `target=_blank` links open in a new tab
- **Bookmarks**: star button or Cmd+D. Right-click a bookmark > Move to Folder to create and use **folders**. Saved to `~/Library/Application Support/MyBrowser/bookmarks.json`
- **History**: Cmd+Y. Searchable, grouped by day
- **Downloads**: files WebKit can't display are saved to ~/Downloads. Cmd+Shift+J shows progress, Open and Show in Finder
- **Find in page**: Cmd+F, Cmd+G / Cmd+Shift+G for next / previous, Esc to close
- **Private windows**: Cmd+Shift+N. Nothing is saved to history or cookies
- **Settings** (Cmd+,): search engine, home page, automatic updates, clear history, clear cookies and website data
- **Auto-update** from GitHub Releases (see below)

## Shortcuts
| Key | Action |
| --- | --- |
| Cmd+T | New tab |
| Cmd+\\ | Shrink / expand sidebar |
| Opt+Cmd+\\ | Sidebar layout / top layout |
| Cmd+W | Close tab |
| Cmd+N / Cmd+Shift+N | New window / new private window |
| Cmd+Shift+W | Close window |
| Cmd+L | Focus address bar |
| Cmd+[ / Cmd+] | Back / forward |
| Cmd+R | Reload |
| Cmd+Shift+[ / ] | Previous / next tab |
| Ctrl+1 ... Ctrl+9 | Switch to space 1-9 |
| Cmd+D | Bookmark / unbookmark page |
| Cmd+Y | History |
| Cmd+Shift+J | Downloads |
| Cmd+F / Cmd+G / Cmd+Shift+G | Find / next / previous |
| Opt+Cmd+P | Pin / unpin tab |
| Cmd+, | Settings |

## Run
Requires macOS 13+ and the Xcode command line tools (`xcode-select --install`).

```
cd MyBrowser
swift run
```

## Install as an app
```
./build_app.sh --install
```
Builds a release version, wraps it as `MyBrowser.app` and copies it to /Applications.

## Auto-update
The installed app checks GitHub Releases at launch (at most every 6 hours) and from MyBrowser > Check for Updates. When there's a newer version it asks, downloads it, replaces itself and relaunches. Updates only work in the installed app, not under `swift run`.

Releases are built automatically. Every push to `main` that changes the code runs `.github/workflows/release.yml`, which builds MyBrowser on a GitHub Mac, and if the number in `VERSION` hasn't been released yet, publishes it as a new release (versions go 1.00, 1.01, 1.02, ...). To ship a change, push it with a higher `VERSION`.

`release.sh` is a manual fallback that builds and publishes from your own Mac (needs `gh auth login`).

## Known gaps
No arrow-key navigation in the suggestions list, no JavaScript alert/permission dialogs, no extensions, bookmarks aren't per-space, and each new window reloads your pinned tabs.
