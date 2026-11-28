# Linux AppImage: adding App Studio to the app menu

Status: **draft, 2026-11-27.** Follows PR 4 (`make appimage`,
`tool/linux/build_appimage.sh`) on the step branch `linux/4b-appimage`, which
merges into `linux/port` like the other steps.

## The plan in short

The AppImage works well **once a tool has added it to the app menu**:
[Gear Lever](https://github.com/mijorus/gearlever) (an app for managing
AppImages), [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher)
(which steps in when an AppImage it has not integrated yet starts, and asks
"Integrate and run" or "Run once") or
[appimaged](https://github.com/probonopd/go-appimage) (a daemon that adds
every AppImage it finds in the folders it watches). Without one of them, App
Studio never appears in the app menu and the dock shows a generic icon,
because no desktop entry names it. Part A closes that gap from inside App
Studio.

| Part | What | Where | State |
|---|---|---|---|
| A | **Add to Applications**: on start, until it is in the app menu, App Studio offers to add itself; **Remove from Applications** undoes it | App Studio (Dart), Linux only | being built |
| B | Updates from inside the app | App Studio and Serverpod's release pipeline | later (below) |
| C | **A clear message on a system that cannot load App Studio**, instead of nothing happening | `AppRun` in the AppImage | done |
| D | **Download page text** for Serverpod's website | text in this spec | written; needs A |
| E | Uninstall removes what A added | App Studio (Dart) | with PR 5 |

**B, updates, come later.** Until then **Help → Check for Updates** stays
greyed out on Linux, and the AppImage carries no update information: where
builds are hosted, and with it the `.zsync` URL Gear Lever would read
(`specs/linux_port.md` 4.5), is Serverpod's to decide together with the
updater. Part A's fixed path (A2) lets that updater replace the file in place
without touching the menu entry.

This spec covers the AppImage. Whether the `.deb` and `.rpm` of
`specs/linux_port.md` (4.5) still follow is open with Serverpod.

### Decisions

| # | Decision |
|---|---|
| A1 | **App Studio asks before it writes anything outside its own folders**, at most once per start. It does not offer to add itself when it is in the app menu already, whoever put it there; which tools are installed does not matter. The one question it asks then is about a second copy of its own (see Another copy). |
| A2 | **An added AppImage lives at one fixed path, `~/AppImages/AppStudio-x86_64.AppImage`.** No version in the name, so replacing the file keeps the menu entry valid. `~/AppImages` is Gear Lever's default folder, and by default neither AppImageLauncher nor appimaged watches it; both add whatever appears in `~/Applications`, so a file moved there would show up in the menu twice. (Either can be told to watch more folders; appimaged also watches every folder on `PATH`.) |
| A3 | **The desktop entry App Studio writes carries a marker**, `X-AppStudio-AddedBy=appstudio`, so Remove from Applications (and PR 5's uninstall) removes only that entry. An entry another tool wrote stays. |
| C1 | **No older build base.** The AppImage needs glibc 2.38 (Ubuntu 24.04 and later); part C makes that readable rather than lower. |

---

## A. Add to Applications

### Four states

Everything in part A follows from one of four states, read from the disk
whenever a question or the Help menu needs it:

| State | Meaning |
|---|---|
| `unavailable` | Not running as an AppImage (condition 1 below). Nothing to offer. |
| `managedByOther` | In the app menu through another tool, or a package. Theirs. |
| `addedByAppStudio` | App Studio's own entry (A3), and the file its `TryExec` names exists. |
| `notAdded` | None of the above: App Studio offers to add itself. |

1. **Running as an AppImage** means: the AppImage runtime set `$APPIMAGE`
   (the file's path) and `$APPDIR` (where the image is mounted), **and** App
   Studio's executable is inside `$APPDIR`. The variables are inherited by
   child processes, so a development build started from a terminal inside
   another AppImage (an editor, say) sees that one's; only the executable
   tells them apart. A *portable* AppImage, one with a `<file>.AppImage.home`
   folder beside it, counts as `unavailable` too: the runtime points `HOME`
   there, so an entry written under it never reaches the desktop.
2. **In the app menu** means a desktop entry, in `$XDG_DATA_HOME/applications`
   (default `~/.local/share/applications`) or an `applications` folder under
   `$XDG_DATA_DIRS`, sub-folders included (one that cannot be read is
   skipped), that is called
   `dev.serverpod.appstudio.desktop` or names
   `StartupWMClass=dev.serverpod.appstudio`. Gear Lever, AppImageLauncher and
   appimaged name their entries after the app or a hash, but keep the
   AppImage's own `StartupWMClass`, so one check finds all of them, and a
   copy they added is found even when started from a terminal.
   - An entry whose `TryExec` names a file that no longer exists does not
     count: it is left over from an AppImage the user deleted. This covers
     App Studio's own entry too, which the next Add then writes over.
     (appimaged's `TryExec` names appimaged itself, so its entries always
     count.)
   - An installed tool that did not add App Studio does not count. With
     AppImageLauncher, a user who chose "Run once" in its question is then
     asked by App Studio as well.

### When App Studio asks

Over the start page: on a normal start once it shows, and on a first run as
soon as setup ends, in the same run, so the question never lands among
setup's own dialogs. The checks read the disk; if a project opens before they
are done, no question comes that run. A project opened while the question is
up closes it (the routes over the start page are cleared, as for every
project open).

In state `notAdded` it asks to add itself, unless the user said "Don't ask
again" (preference `linux.add_to_applications_declined`). In state
`addedByAppStudio` it may ask about another copy (below). In the other two
states it asks nothing.

### The question

```text
Add App Studio to your applications?

App Studio will appear in your app menu, and the file moves from
~/Downloads to ~/AppImages.

[ ] Don't ask again                      [Not now]  [Add]
```

The sentence about the file names the folder it is in now. It is left out
when the file is in `~/AppImages` already (where Add at most renames it to the
fixed name), and when an earlier Add in the same run already moved it. When
another file is at `~/AppImages/AppStudio-x86_64.AppImage` already (a copy
left there by Remove, or whose entry was deleted by hand), the question adds
"It replaces the App Studio already at ~/AppImages/AppStudio-x86_64.AppImage.",
since that copy may be newer.
**Not now** asks again on the next start; with the box ticked it never asks
again on start.

### The Help menu

Exactly one of two items shows in Help on Linux, or neither:

- **Add to Applications...** in state `notAdded`, so "Don't ask again" is
  never a dead end. It opens the same dialog with **Cancel** instead of
  Not now, and no checkbox.
- **Remove from Applications...** in state `addedByAppStudio`. It confirms
  first:

  ```text
  Remove App Studio from your applications?

  App Studio leaves your app menu. The file stays at
  ~/AppImages/AppStudio-x86_64.AppImage, and App Studio will not ask to
  add itself again.

  [Cancel]  [Remove]
  ```

Neither shows in states `unavailable` and `managedByOther`.

### What Add does

The dialog stays open while it runs and shows any error in it.

1. **Moves the AppImage to `~/AppImages/AppStudio-x86_64.AppImage`** (A2),
   creating the folder if needed. A rename where it can be. Where the rename
   fails (another file system, or a folder the file cannot be taken out of,
   such as a root-owned `/opt`), a copy to a temporary name in `~/AppImages`,
   made executable, then renamed onto the target, and the original deleted.
   A file already at the target is replaced only by a rename, so it is never
   half-written. If the original cannot be deleted, the copy is added anyway
   and the original stays.

   Moving a running AppImage is safe. The runtime's squashfuse opens the file
   once, when it mounts the image, and reads every block through that
   descriptor. Checked with the 0.4.1 AppImage: after the file was copied to
   another file system and the original deleted, all of `libcef.so` read back
   from the mount and the loader still resolved the executable's libraries.
2. **Copies the icons** from `$APPDIR/usr/share/icons/hicolor/` into
   `$XDG_DATA_HOME/icons/hicolor/`, under the same names.
3. **Writes `$XDG_DATA_HOME/applications/dev.serverpod.appstudio.desktop`**
   from the AppImage's own entry: `Exec` set to the new path, quoted as the
   Desktop Entry spec requires for an argument; `TryExec` set to the same
   path as a plain, unquoted string; the marker (A3); and the running version
   as `X-AppStudio-Version` and `X-AppStudio-Build`. Every other key and group
   is kept. It is written to a temporary name and renamed, so a launcher never
   reads half an entry. The file name is the application id, so on Wayland
   the dock can match the window to it by its app id as well as by
   `StartupWMClass`.
4. **Rebuilds the icon cache if there is one**: when
   `$XDG_DATA_HOME/icons/hicolor/icon-theme.cache` exists, it runs
   `gtk-update-icon-cache -f -t` on that folder (best effort). Without a
   cache, icons are looked up on disk.
5. **Shows a toast**: "Added to your applications".

`update-desktop-database` is not run: it only writes `mimeinfo.cache` from
`MimeType=` keys, and the entry has none. GNOME (through GLib's file monitor
on each `applications` folder) and KDE (through kded's directory watch) pick a
new entry up on their own, going by their source; to confirm in the VM.

**If a step fails**, the icons and entry that this Add created are removed;
ones that were there before (a Replace, below) are kept, so the entry already
in the menu still shows its icon. The dialog shows the step and the reason. A
moved file is not moved back, since App Studio runs on from its new place, so
the error then also says that the AppImage is now at
`~/AppImages/AppStudio-x86_64.AppImage`. Pressing Add again (or Help → Add
later) finds the file there, though `$APPIMAGE` still names its old place,
and carries on from step 2; if the original could not be deleted, it is
copied again.

### What Remove does

Deletes the entry App Studio wrote and the `dev.serverpod.appstudio.png`
icons under `$XDG_DATA_HOME/icons/hicolor/`, only when the entry carries the
marker, and rebuilds the icon cache as Add does. The AppImage stays where it
is. Removing sets "Don't ask again" first (the user just said no), so a
removal that fails halfway does not bring the question back either. A toast
says "Removed from your applications", or, on failure, "Could not remove App
Studio from your applications" with the reason. Finding no entry of App
Studio's to remove is a failure too: another tool may have rewritten it since
the Help menu last looked.

### Another copy than the one in the app menu

Someone who downloads App Studio again and starts the new file is in state
`addedByAppStudio`, so the question above never comes. When the running file
is not the one App Studio's entry names, App Studio compares the two by build
number, which orders releases:

- **This copy is newer:**

  ```text
  Replace App Studio 0.4.1 with this version?

  This copy is App Studio 0.4.2, newer than the 0.4.1 in your app menu.
  Replace moves it from ~/Downloads to ~/AppImages, in place of the older
  one.

  [Not now]  [Replace]
  ```

  When the copy is in `~/AppImages` already, the second sentence reads
  "Replace puts it in place of the older one." Replace runs Add, so
  everything above applies: the file is renamed over the old one, and the
  entry is rewritten with the new version. Once the move has happened the
  older copy is gone; if a later step fails, the existing entry and icons
  stay and point at the new file. The entry then no longer records a
  version: the one it named is gone, and compared with the next download it
  could offer to replace a newer copy with an older one. Until an Add writes
  the entry again, no copy is compared with it. A toast says "App Studio
  0.4.2 is in your applications".
- **This copy is older:**

  ```text
  A newer App Studio is in your app menu

  This copy is App Studio 0.4.0. Your app menu has 0.4.1.

  [Keep using this one]  [Open 0.4.1]
  ```

  Open quits this copy, through the same teardown as File → Quit, and starts
  the newer one once this process has ended: the two share the preview's
  browser profile, which only one can hold at a time. (A small detached `sh`
  waits for the process, for at most 30 s.) If the added file is gone, Open
  says so in a toast and nothing quits. Replacing the newer copy with the
  older one is not offered: a downgrade is too easy to click by accident. It
  stays possible in two deliberate steps, Remove and then Add.
- **The same build:** nothing is said. It is a second download.

The versions shown are the marketing versions, with the build added when
both copies share one. The running copy's comes from the `version.json`
Flutter writes into the bundle. The added copy's is not mounted, so Add
records it in the entry as `X-AppStudio-Version` and `X-AppStudio-Build`.
Without them nothing is said. A copy Gear Lever or another tool added is
theirs: Gear Lever has its own update. There is no "Don't ask again" here;
the question is about one file, and comes up only when someone starts a
second copy by hand.

Nothing stops two copies running at once (the GTK application is
`G_APPLICATION_NON_UNIQUE`, as before this spec). Replace while the added copy
also runs swaps its file underneath it, which the running copy does not
notice (its image stays mounted); Open while it runs starts a second
instance of it. Both are left as they are.

### Living alongside the other tools

- **AppImageLauncher** asks when an AppImage it has not integrated yet
  starts, before App Studio runs. After "Integrate and run" App Studio finds
  its entry and stays quiet; after "Run once" App Studio asks too. By default
  its daemon does not watch `~/AppImages`, so App Studio's Add gets no second
  entry from it.
- **appimaged** adds every AppImage in the Downloads folder, the desktop,
  `~/Applications`, the folders on `PATH` and more, but not `~/AppImages`. A
  downloaded App Studio is already in the menu by the time it starts, and the
  entry check finds it.
- **Gear Lever** lists an entry in `~/.local/share/applications` as one of
  its own when its `TryExec` names a file in Gear Lever's folder (default
  `~/AppImages`), or anywhere while its "manage files outside the default
  folder" setting is on (the default). So the entry App Studio writes
  usually shows up there too. Removing it in Gear Lever moves the AppImage to
  the trash and deletes the entry; the icons App Studio copied stay behind.
  Updating it through Gear Lever rewrites the entry from the AppImage's own,
  which drops App Studio's marker: App Studio then reads it as
  `managedByOther`, which is what it has become.

### Where it lives

- `lib/platform/linux/desktop_integration.dart`: the states, Add, Remove and
  the comparison of copies, with the environment and the executable injected
  so the tests point `HOME` at a temporary folder and run on every host; and
  `DesktopIntegrationController`, the state the menu strip listens to.
- `lib/platform/linux/app_version.dart`: a version and build, and how two
  copies compare; free of `dart:io`.
- `lib/platform/linux/desktop_integration_status.dart`: the four states,
  free of `dart:io` so the menu strip can read them.
- `lib/ui/add_to_applications_dialog.dart`: the dialogs, free of `dart:io`
  so Widgetbook shows them.
- `lib/ui/desktop_integration_commands.dart`: what the question and the Help
  items run, including the preference, which the caller writes as the
  project notices do.

---

## C. A system that cannot load App Studio (done)

On a system with an older glibc (Ubuntu 22.04, Debian 12, Linux Mint 21), or
without a library such as GTK, `appstudio` fails before any of App Studio
runs: a double-click does **nothing visible**, and only a terminal shows the
loader's error. Dart never runs, so the check sits in `AppRun`.

- **`AppRun` asks the loader first.** `LD_TRACE_LOADED_OBJECTS=1` lists what
  the executable needs without running it, with "not found" for each library
  or symbol version the system lacks. With nothing missing it starts App
  Studio. Otherwise it says why, in one of three ways:
  - **a symbol version missing** (any, such as `GLIBC_2.38` or
    `GLIBCXX_3.4.29`): "App Studio needs a newer Linux", naming the glibc
    version needed, distributions that have it, the system's glibc and the
    versions it lacks. Missing libraries are left out of this message: a
    newer Linux is the fix either way, and on an old system the list runs to
    dozens;
  - **no glibc at all** (`getconf` knows none, as on Alpine): "App Studio
    needs a Linux with glibc";
  - **only libraries missing**: "App Studio is missing system libraries",
    listing them, with a hint to install them with the distribution's
    package manager.
- The message goes to stderr always and, when there is a display, to a
  window through the first of `zenity`, `kdialog` or `notify-send` that
  manages to show it. Then `AppRun` exits with 1.
- **The glibc version is read from the build**: the highest `GLIBC_x.y` any
  ELF file in the bundle references, `data/` excluded (today 2.38). The
  distributions the message names are tied to that version, so a build that
  needs another one stops until they are updated.
- Tested by hand with the packed AppImage in containers: Debian 11 (glibc
  2.31) shows "needs a newer Linux", Alpine shows "needs a Linux with glibc",
  and on Ubuntu 24.04 the check passes and App Studio's executable is
  started. There is no automated test.

---

## D. Download page text

For Serverpod's website, next to the macOS and Windows downloads, once part A
ships. The requirement line follows part C's glibc version; the
distributions named have that glibc, which is not the same as tested (App
Studio is tested on Ubuntu 26.04 and Arch).

```text
App Studio for Linux (x86_64)

Needs a 64-bit Linux with glibc 2.38 or later, such as Ubuntu 24.04,
Fedora 39 or Debian 13, or newer. Tested on Ubuntu and Arch.

Allow the downloaded file to run, then double-click it:
  - GNOME (Ubuntu, Fedora): right-click → Properties → "Executable as Program"
  - KDE: right-click → Properties → Permissions → "Allow executing file as
    program" ("Is executable" on older versions)
  - Terminal: chmod +x AppStudio-*-x86_64.AppImage
Once its setup is done, App Studio offers to add itself to your app menu.

If you use Gear Lever, open the file with it and choose
"Move to the app menu" instead.
```

---

## E. Uninstall (PR 5)

App Studio's uninstall on Linux, in PR 5, runs the same removal as Remove
from Applications, and counts "not in your app menu" as done: Remove reports
it as a failure, which is right for the Help item but not for an uninstall
on a machine where nothing was ever added. Whether it also deletes the AppImage itself is decided
there.

## Testing

- **Unit tests on every host** through `HostPlatform.linux`
  (`test/platform/linux/desktop_integration_test.dart`): each condition of
  the four states (inherited variables, a portable AppImage, entries in
  sub-folders, an unreadable sub-folder, a deleted `TryExec`), the entry it
  writes (including an `Exec` path that needs quoting), a move within and
  across file systems and out of a folder the file cannot leave, a Replace
  across file systems, a failed step undoing only what it created, a retry
  after the move, a failed Replace dropping the recorded version, Remove
  leaving an entry without the marker alone and saying so, how another copy
  compares (newer, older, the same, no recorded version), and Open starting
  the added copy only once the given process has ended. The dialogs and the
  Help items have widget tests, and
  `test/ui/desktop_integration_commands_test.dart` pins the preference both
  ways ("Don't ask again" and Remove set it, Not now, Add and a cancelled
  Remove do not), the question asked once per run and only on Linux, and
  Open quitting this copy only when the newer one could be started.
- **Widgetbook:** the question (from Downloads, already in `~/AppImages`,
  replacing a copy left there, from the Help menu), another copy (newer, older) and the Remove
  confirmation.
- **Ubuntu VM from `clean-install`:**
  - without Gear Lever: download in Firefox, allow it to run, start; after
    setup the question appears; Add; App Studio is in the app menu with its
    icon, starts from there, and the question does not come back;
  - Remove from Applications: the menu entry goes, the file stays;
  - after Gear Lever added it: no question, and no Help item;
  - with Gear Lever installed but not used: the question appears;
  - another copy: start a newer build from `~/Downloads` and Replace; start
    an older one and Open, and the newer copy comes up once the older one
    has quit.
- **Omarchy:** the same Add and Remove, through Walker.
