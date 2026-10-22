#!/bin/bash
# Install Seats for Claude Code on macOS: the seats CLI into ~/.local/bin and
# the menu into SwiftBar's plugin folder. Safe to run again to update.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"
bin="$HOME/.local/bin"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ $(uname) != Darwin ]]; then
  echo "This installer is for macOS. On Omarchy, use: omarchy plugin add <repo-url> --enable" >&2
  exit 1
fi

if ! command -v python3 >/dev/null; then
  say "python3 is missing. Install the Xcode command line tools first:"
  echo "  xcode-select --install"
  exit 1
fi

if ! command -v claude >/dev/null && [[ ! -x $HOME/.local/bin/claude ]]; then
  say "Claude Code (the claude command) isn't installed yet — the menu will work once it is."
fi

say "Installing the seats CLI to $bin"
mkdir -p "$bin"
install -m 0755 "$repo/seats" "$bin/seats"
# Earlier versions were called claude-account; remove that copy if it is ours.
if [[ -f $bin/claude-account ]] && grep -q "saved subscription logins" "$bin/claude-account"; then
  rm -f "$bin/claude-account"
fi
case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "  Note: $bin isn't on your PATH. Add this to ~/.zshrc to use the CLI in a terminal:"
     echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

if [[ ! -d /Applications/SwiftBar.app && ! -d $HOME/Applications/SwiftBar.app ]]; then
  if command -v brew >/dev/null; then
    say "Installing SwiftBar with Homebrew"
    brew install --cask swiftbar
  else
    say "SwiftBar isn't installed. Get it from https://swiftbar.app (or: brew install --cask swiftbar), then run this again."
    exit 1
  fi
fi

plugins="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [[ -z $plugins ]]; then
  plugins="$HOME/Library/Application Support/SwiftBar/Plugins"
  mkdir -p "$plugins"
  defaults write com.ameba.SwiftBar PluginDirectory -string "$plugins"
  say "Set SwiftBar's plugin folder to $plugins"
fi
plugins="${plugins/#\~/$HOME}"
mkdir -p "$plugins"

say "Installing the menu into $plugins"
install -m 0755 "$here/seats.5m.py" "$plugins/seats.5m.py"
rm -f "$plugins/claude-account.5m.py"   # the menu's name before the rename

if ! command -v terminal-notifier >/dev/null; then
  echo "  Tip: brew install terminal-notifier makes the limit alert clickable (click to switch)."
fi

open -g "swiftbar://refreshallplugins" 2>/dev/null || open -a SwiftBar

echo
say "Done. Next:"
echo "  1. Click the person icon in the menu bar."
echo "  2. Choose 'Save this login…' for the account you're logged in with now"
echo "     (or run: seats save work)."
echo "  3. Choose '+ Add account…' to log in with your other account."
echo
echo "  Seats switches accounts through macOS's 'security' tool, the same way Claude Code"
echo "  reads its own login, so there is usually no prompt. If macOS does ask about the"
echo "  'Claude Code-credentials' item, see the wiki's Security and Privacy page before"
echo "  choosing 'Always Allow'."
