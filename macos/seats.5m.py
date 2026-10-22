#!/usr/bin/env python3
# <xbar.title>Seats for Claude Code</xbar.title>
# <xbar.version>v2.0.0</xbar.version>
# <xbar.author>zorry</xbar.author>
# <xbar.desc>Switch Claude Code between subscriptions and compare their limits.</xbar.desc>
# <xbar.dependencies>python3,seats</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
"""Seats for Claude Code, as a SwiftBar / xbar menu: the same panel as the
Omarchy widget, as a macOS menu. Runs every five minutes (the .5m. in the
name) and after every action; switching, logging in and alerts all go
through the seats CLI."""
import datetime as dt
import json
import os
import shutil
import subprocess
from pathlib import Path

ALERT_AT = float(os.environ.get("SEATS_ALERT_AT", "90")) / 100
ALERTS = os.environ.get("SEATS_ALERTS", "1") != "0"
URGENT = "#e5484d"
DIM = "#8b8d98"
MONO = "font=Menlo size=12"
STATE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / "Library/Caches") / "seats-alerts.json"


def find_cli():
  here = Path(__file__).resolve().parent
  for p in (os.environ.get("SEATS_CLI"), shutil.which("seats"),
            Path.home() / ".local/bin/seats", here / "seats", here.parent / "seats"):
    if p and Path(p).is_file():
      return str(p)
  return None


CLI = find_cli()


def run(*args):
  try:
    out = subprocess.run([CLI, *args], capture_output=True, text=True, timeout=30)
    return json.loads(out.stdout) if out.returncode == 0 else None
  except (OSError, ValueError, subprocess.TimeoutExpired):
    return None


def title_case(s):
  return s[:1].upper() + s[1:]


def duration(seconds):
  if seconds <= 0:
    return "now"
  m = int(seconds // 60)
  h, d = m // 60, m // 1440
  if d:
    return f"{d}d {h % 24}h"
  if h:
    return f"{h}h {m % 60}m"
  return f"{max(1, m)}m"


def window_title(entry):
  if entry.get("title"):
    return entry["title"]
  label = str(entry.get("label") or "").lower()
  if "week" in label or "7-day" in label:
    return "Weekly"
  if "session" in label or "5-hour" in label:
    return "Session"
  return title_case(str(entry.get("label") or ""))


def seconds_until(iso):
  try:
    return dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() - dt.datetime.now().timestamp()
  except (ValueError, AttributeError):
    return -1


def meter(percent, width=12):
  filled = round(max(0.0, min(1.0, percent)) * width)
  return "▰" * filled + "▱" * (width - filled)


def windows(data):
  return [dict(e, title=window_title(e)) for e in (data or {}).get("limits") or [] if float(e.get("percent", -1)) >= 0]


def esc(s):
  # SwiftBar splits on "|"; keep it out of free text.
  return str(s).replace("|", "¦")


def action(*args, terminal=False, refresh=True):
  params = " ".join(f'param{i + 1}="{a}"' for i, a in enumerate(args))
  return f'bash="{CLI}" {params} terminal={"true" if terminal else "false"} refresh={"true" if refresh else "false"}'


# ------------------------------------------------------------------ alerts


def notify(title, body, switch_to):
  if shutil.which("terminal-notifier"):
    cmd = ["terminal-notifier", "-title", "Seats", "-subtitle", title, "-message", body, "-group", "seats"]
    if switch_to:
      cmd += ["-execute", f'"{CLI}" use "{switch_to}" && open -g "swiftbar://refreshplugin?name=seats"']
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
  elif shutil.which("osascript"):
    script = f'display notification {json.dumps(body)} with title "Seats" subtitle {json.dumps(title)}'
    subprocess.Popen(["osascript", "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def check_alerts(current, limit_data):
  """Once per window per reset period, like the Omarchy widget."""
  if not ALERTS or not current:
    return
  try:
    alerted = json.loads(STATE.read_text())
  except (OSError, ValueError):
    alerted = {}
  for w in windows(limit_data.get(current)):
    if w["percent"] < ALERT_AT:
      continue
    # The API's reset time jitters by a second between probes; bucket it.
    key = f'{current}|{w["title"]}|{round((seconds_until(w.get("resetsAt") or "") + dt.datetime.now().timestamp()) / 600)}'
    if alerted.get(key):
      continue
    alerted[key] = True
    best = None
    for name, data in limit_data.items():
      if name == current:
        continue
      p = next((o["percent"] for o in windows(data) if o["title"] == w["title"]), 0)
      if p < ALERT_AT and (best is None or p < best[1]):
        best = (name, p)
    title = f'{title_case(current)} is at {round(w["percent"] * 100)}% of its {w["title"].lower()} limit'
    if best:
      how = "Click to switch" if shutil.which("terminal-notifier") else "Open the menu to switch"
      body = f'{how} to {title_case(best[0])} ({round(best[1] * 100)}% {w["title"].lower()} used).'
    else:
      body = "Your other accounts are near their limits too."
    notify(title, body, best[0] if best else None)
    break
  try:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(alerted))
  except OSError:
    pass


# -------------------------------------------------------------------- menu


def main():
  if not CLI:
    print("Claude | sfimage=person.crop.circle.badge.exclamationmark")
    print("---")
    print("seats CLI not found")
    print("Install it with macos/install.sh | href=https://github.com/Manzozorry/claude-seats/wiki/Installation-on-macOS")
    return

  status = run("status") or {"current": "", "accounts": [], "loggedIn": False}
  limit_data = (run("limits") or {}).get("accounts", {})
  current = status.get("current") or ""
  accounts = status.get("accounts") or []
  active = next((a for a in accounts if a["name"] == current), None)
  active_windows = windows(limit_data.get(current))
  alarming = any(w["percent"] >= ALERT_AT for w in active_windows)

  # ---------- Menu bar ----------
  label = title_case(current) if current else ("Unsaved" if status.get("loggedIn") else "Claude")
  icon = "person.crop.circle.badge.exclamationmark" if alarming else "person.crop.circle"
  print(f'{esc(label)} | sfimage={icon}' + (f" color={URGENT}" if alarming else ""))
  print("---")

  # ---------- Header ----------
  if active:
    org = active.get("org") if active.get("org") and active["email"] not in active.get("org", "") else (limit_data.get(current) or {}).get("plan", "")
    print(f'{esc(title_case(active["name"]))} | size=15')
    print(f'{esc(" · ".join(x for x in (active["email"], org) if x))} | color={DIM} size=12')
  elif status.get("loggedIn"):
    print(f'Unsaved login: {esc(status.get("liveEmail", ""))}')
    print(f'Save this login… | {action("save", terminal=True)}')
  else:
    print("Not logged in to Claude Code")
  print("---")

  # ---------- Switch ----------
  print(f"SWITCH ACCOUNT | size=11 color={DIM}")
  for a in accounts:
    print(f'{esc(title_case(a["name"]))} | {action("use", a["name"])} sfimage={"checkmark.circle.fill" if a["name"] == current else "circle"}')
    print(f'--{esc(a["email"])} | color={DIM}')
    print(f'--Log in again… | {action("login", a["name"], terminal=True)}')
  print(f'+ Add account… | {action("login", terminal=True)} sfimage=plus.circle')
  if len(accounts) == 1:
    print(f"Only one account saved. Use Add account for your other one. | color={DIM} size=11")

  # ---------- Limits ----------
  ordered = ([active] if active else []) + [a for a in accounts if a is not active]
  for a in ordered:
    name = a["name"]
    data = limit_data.get(name) or {}
    plan = data.get("plan") or ""
    is_active = name == current
    if is_active:
      state = data.get("status") or "active"
    elif data.get("live"):
      state = "live"
    elif data.get("fetchedAtMs"):
      age = duration(dt.datetime.now().timestamp() - data["fetchedAtMs"] / 1000).split(" ")[0]
      state = f"{age} ago"
    else:
      state = data.get("status") or "no data"
    print("---")
    switch = "" if is_active else " " + action("use", name)
    print(f'{esc(name.upper())}{" · " + esc(plan.upper()) if plan else ""}  —  {state.upper()} | size=11 color={DIM}{switch}')
    ws = windows(data)
    if not ws:
      print(f"No limits yet. Switch to it once to fetch them. | color={DIM} size=12{switch}")
    for w in ws:
      pct = "reset" if w.get("reset") else f'{round(w["percent"] * 100)}%'
      hot = w["percent"] >= ALERT_AT
      color = f" color={URGENT}" if hot else ""
      print(f'{w["title"]:<8} {meter(w["percent"])} {pct:>5} | {MONO}{color}{switch}')
      left = seconds_until(w.get("resetsAt") or "")
      if is_active and left > 0:
        print(f"Resets in {duration(left)} | color={DIM} size=11")

  # ---------- Footer ----------
  print("---")
  print(f'Refresh limits | {action("limits", "--force")} sfimage=arrow.clockwise')
  print(f"New Claude sessions use the selected account | color={DIM} size=11")

  check_alerts(current, limit_data)


if __name__ == "__main__":
  main()
