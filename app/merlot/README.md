# Native game-launcher host

`GameLauncher.m` owns the macOS application identity and handles both initial
launch and `applicationShouldHandleReopen`. The Wine process must not own a
game-specific bundle identity: Finder normally reactivates an existing app,
without rerunning its executable. A shell wrapper blocked on long-lived Steam
therefore appears to work with `open -n` but fails on later double-clicks.

## Bundle contract

- `Contents/MacOS/GameLauncher`: compile with
  `clang -fobjc-arc -Wall -Wextra -Werror -framework Cocoa GameLauncher.m -o GameLauncher`.
- `Contents/Resources/launch.command`: a bash worker defining the intended
  engine, prefix, graphics environment and actual game/client handoff.
- `CFBundleExecutable=GameLauncher`, `CFBundlePackageType=APPL`,
  `LSUIElement=true`, and a stable game-launcher-specific bundle identifier.
- Re-sign the completed bundle, not just its executable. Preserve original
  icon resources and retain a complete original bundle for rollback.
- Remove or archive obsolete executables from `Contents/MacOS`; an unsigned
  legacy executable there prevents strict bundle signature verification.

The host launches workers with an allowlisted environment so LaunchServices
identity and unrelated Wine routing do not leak into Steam. It remains alive
and accepts later reopen requests even while its first worker waits on Steam.
Requests within two seconds are coalesced to avoid duplicate initial events.
Host events are appended to
`~/.cache/chardonnay-launcher/<bundle-identifier>/host.log`.

Quitting the native host does not kill Steam, EA or any game. It does not
restart Steam automatically, infer a game executable, alter a prefix, or clear
saved authentication. The worker remains responsible for game routing and
application-level duplicate-launch handling.

## Validation and deployment boundary

Run `python3 tests/test_game_launcher_macos.py` on a Mac. The GUI regression
opens a private probe bundle twice using ordinary `open`, keeps the first
worker alive, and requires one host with two distinct worker requests. It
cleans up only its own probe processes and files. Linux skips this GUI test.

After deployment, verify a normal cold open, a normal reopen delivered to the
same host, and the actual Steam -> EA -> game chain. An existing Wine process
registered under the old bundle path can still intercept Open after replacing
files. Retire that association once, only while no game is running, by stopping
the verified old Steam/client-helper PIDs; preserve the EA process and prefix
wineserver. Then verify Steam's process no longer carries the game bundle
identity. Do not use `open -n` as the repeat-open acceptance test.

The source and regression currently support the manually promoted experimental
game bundle. Automatic packaging by `install_merlot.command --games` is not
implemented here. Do not claim fresh-install or upgrade integration from a
working manually deployed bundle.
