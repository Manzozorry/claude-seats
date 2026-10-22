# Installation guide

Claude Account runs on **Omarchy** (as a bar widget) and on **macOS** (as a
menu-bar item through SwiftBar). Both use the same `claude-account` command
underneath, so the behaviour is the same on each.

- [Omarchy](#omarchy)
- [macOS](#macos)
- [First-time setup (both)](#first-time-setup-both)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)

---

## Omarchy

**Needs:** Omarchy with the shell plugin system (the bar with the built-in
**Agents** widget) and Claude Code.

1. Add the plugin and put it on the bar:

   ```bash
   omarchy plugin add https://github.com/Manzozorry/omarchy-claude-account --enable
   ```

   It lands at `~/.config/omarchy/plugins/zorry.claude-account/`. To place it
   right next to the Agents widget:

   ```bash
   omarchy bar move zorry.claude-account --before omarchy.agents
   ```

2. *(Optional)* Put the CLI on your `PATH` so you can use it in a terminal:

   ```bash
   ln -s ~/.config/omarchy/plugins/zorry.claude-account/claude-account ~/.local/bin/
   ```

3. Continue with [first-time setup](#first-time-setup-both).

Settings live in the Omarchy settings panel, or:

```bash
omarchy bar set zorry.claude-account alertAt 85      # alert threshold in %
omarchy bar set zorry.claude-account alerts false    # turn alerts off
```

---

## macOS

**Needs:** macOS 12 or newer, `python3` (comes with the Xcode command line
tools: `xcode-select --install`), Claude Code, and
[SwiftBar](https://swiftbar.app) (the installer gets it through Homebrew if
you have Homebrew).

1. Download the repository and run the installer:

   ```bash
   git clone https://github.com/Manzozorry/omarchy-claude-account.git
   cd omarchy-claude-account
   ./macos/install.sh
   ```

   This copies the CLI to `~/.local/bin/claude-account`, installs SwiftBar if
   it is missing, and puts the menu into SwiftBar's plugin folder. You can
   delete the downloaded folder afterwards.

2. *(Optional, recommended)* Make the limit alert clickable:

   ```bash
   brew install terminal-notifier
   ```

   Without it you still get the alert, but you switch from the menu instead
   of by clicking the notification.

3. Continue with [first-time setup](#first-time-setup-both).

**Keychain prompt:** on macOS, Claude Code keeps its login in the Keychain.
The first time you switch, macOS asks whether `security` may use the
*Claude Code-credentials* item. Choose **Always Allow**. Saved accounts are
stored in the Keychain too, as items named *claude-account: &lt;name&gt;*.

Settings are environment variables in SwiftBar's plugin settings
(SwiftBar → the plugin → *Edit environment*), or at the top of the plugin
file:

| Variable | Default | |
| --- | --- | --- |
| `CLAUDE_ACCOUNT_ALERT_AT` | `90` | Alert threshold in % |
| `CLAUDE_ACCOUNT_ALERTS` | `1` | `0` turns alerts off |
| `CLAUDE_ACCOUNT_CLI` | — | Path to `claude-account`, if it isn't in `~/.local/bin` |

---

## First-time setup (both)

You save each account once. After that, switching is one click.

1. **Save the account you're logged in with now.** Open the widget (Omarchy)
   or the menu (macOS) and choose **Save this login**, then type a name such
   as `work`. Or in a terminal:

   ```bash
   claude-account save work
   ```

2. **Add your other account.** Choose **+ Add** (Omarchy) or
   **+ Add account…** (macOS). A terminal opens, asks for a name (e.g.
   `private`) and runs `claude auth login`, which opens your browser.

   > **Pick the right account in the browser.** The browser uses whichever
   > claude.ai account it is signed in to. If that's the wrong one, sign out
   > there first or use a private window.

3. That's it. Click an account to switch to it. New `claude` sessions use the
   selected account.

**Don't** use `/logout` inside Claude Code to change accounts. It can revoke the
saved login. Just switch, or log in again.

---

## Updating

**Omarchy:**

```bash
omarchy plugin update zorry.claude-account
```

**macOS:** pull the repository again and re-run `./macos/install.sh`. Your
saved accounts are kept.

---

## Uninstalling

Your saved accounts stay where they are unless you remove them as well.

**Omarchy:**

```bash
omarchy plugin remove zorry.claude-account
rm -f ~/.local/bin/claude-account            # if you linked the CLI
```

Saved accounts: `~/.local/share/claude-accounts/` (delete it to forget them).

**macOS:**

```bash
rm -f ~/.local/bin/claude-account
rm -f "$(defaults read com.ameba.SwiftBar PluginDirectory)/claude-account.5m.py"
```

Saved accounts: run `claude-account forget <name>` for each one before
removing the CLI (that also deletes its Keychain item), or remove the
*claude-account: &lt;name&gt;* items in Keychain Access and delete
`~/Library/Application Support/claude-accounts/`.

---

## Troubleshooting

**The widget or menu says "Unsaved login".** The account you're logged in with
hasn't been saved yet. Use **Save this login**.

**An account's limits say "2H AGO" or "IDLE SIGN-IN EXPIRED".** Only the active
account's login is kept fresh by Claude Code. An account you haven't used for a
few hours shows its last known numbers, and any limit that has reset since then
shows as 0%. Switch to it once and the numbers are live again.

**Switching doesn't affect a running Claude Code session.** That's expected:
sessions keep the account they started with. Start a new session. It's best to
switch when no session is running, because a running session can later write
its own login back as the active one.

**"That login is the same account as …".** The browser logged you in with an
account you'd already saved. Sign in to the other account in the browser (or
use a private window) and try **+ Add** again.

**Omarchy: the widget doesn't appear.** Check that it's on the bar
(`omarchy bar put zorry.claude-account --before omarchy.agents`) and restart the
shell with `omarchy restart shell`.

**macOS: the menu shows "claude-account CLI not found".** Re-run
`./macos/install.sh`, or set `CLAUDE_ACCOUNT_CLI` to the CLI's path.

**macOS: switching fails with a Keychain error.** Open Keychain Access, find
*Claude Code-credentials*, and under *Access Control* allow `/usr/bin/security`,
or choose **Always Allow** the next time macOS asks.
