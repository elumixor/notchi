# Notchi (personal fork)

A fork of [sk-ruban/notchi](https://github.com/sk-ruban/notchi) with a spend
readout added to the notch companion.

## What this fork adds

- **Notch readout.** "Spend & Reset Time" and "Usage Ring + Spend & Reset"
  options for either notch side, next to the existing Usage Ring option. Spend
  is whole dollars; the reset time ("4.8h", "59m") sits inside a ring that
  empties over the five-hour window. Each figure is switched on or off under
  Appearance and hidden when it has no data. The usage ring shows its
  percentage in the middle. "Compare Against Limit" on the Budget screen turns "$12 / $100"
  into plain "$12" for a plan with no dollar cap.
- **Budget tracking.** A monthly dollar limit that no API exposes — a work
  account with a fixed allowance, for example — tracked from the cost computed
  out of the local Claude Code session logs. Green under an even burn, orange
  ahead of it, red once the limit is gone.
- **Provider figures when they exist.** Claude publishes a dollar spend and
  limit for the extra-usage pool, and `Use Claude's Extra Usage Figures` reads it
  straight through, no calibration involved. It is off by default because the
  figure only describes spend beyond what the subscription covers, so it reads
  zero for an account burning inside its plan.
- **Manual calibration otherwise.** For an allowance no API exposes, `Current
  Spend` on the Budget settings screen anchors to whatever the provider
  reports; usage from that moment on is added to the anchor. The anchor is
  exact to the minute, not the day. The screen says which of the three the
  number came from.
- **Budget detail in settings.** Spend against limit, where an even burn would
  have been by now, average per day, projected period total, and what is left
  per remaining day.
- **Session reset visibility.** The five-hour subscription window's remaining
  time sits in the notch, and a notification fires when it rolls over so a
  paused session can be picked up the moment tokens return. A second
  notification warns at 90% of the window.

Everything is configured from the Budget screen in the notch panel settings.
Auto-updates are disabled so upstream releases do not replace this build.

### Install

```sh
./scripts/create-signing-identity.sh   # once
./scripts/install.sh
```

The first script creates a self-signed certificate in the login keychain and
every build is signed with it, so the app keeps one identity across rebuilds.
The app's own keychain items are read and written through `/usr/bin/security`
rather than Security.framework, because items created by the upstream build are
bound to upstream's signing identity and every framework access from this build
raised a password dialog. Delete the old `com.ruban.notchi` items once:

```sh
security delete-generic-password -s com.ruban.notchi -a cachedOAuthToken
security delete-generic-password -s com.ruban.notchi -a anthropicApiKey
security delete-generic-password -s com.ruban.notchi -a openAIApiKey
```

This builds Release and replaces `/Applications/Notchi.app`. The fork keeps the
upstream bundle identifier, so it reuses the same preferences and hooks and only
one of the two can run at a time.

---

# Notchi

A macOS notch companion that reacts to Claude Code and Codex activity in real-time.

[![Download for macOS](assets/download-macos.svg)][dmg]

https://github.com/user-attachments/assets/e417bd40-cae8-47c0-998a-905166cf3513

## What it does

- Reacts to Claude Code and Codex events in real-time (thinking, working, permission requests, compaction, errors, completions)
- Analyzes prompt sentiment via Anthropic or OpenAI APIs to show emotions (happy, elated, sad, neutral, sob)
- Click to expand and see session time and usage quota
- Tracks daily cost and token usage over the last 30 days, per provider or combined
- Supports multiple concurrent sessions, each with its own mascot from the Claude or Codex sprite family
- Sound effects for events with support for importable custom sounds (optional, auto-muted when terminal is focused)
- Available in English, 日本語, 简体中文 / 繁體中文, 한국어, and Tiếng Việt (follows your system language)
- Auto-updates via Sparkle

## Requirements

- macOS 15.0+ (Sequoia)
- MacBook with notch
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and/or [Codex](https://openai.com/codex/) installed

## Install

1. [Download the latest DMG][dmg] (all versions are on the [releases page](https://github.com/sk-ruban/notchi/releases))
2. Open the DMG and drag Notchi to Applications
3. Launch Notchi, it auto-installs Claude Code and Codex hooks on first launch (whichever are present)
4. If a macOS keychain popup appears asking for access (used for API usage stats), click **Always Allow** so it won't prompt again

   <img src="assets/keychain-popup.png" alt="Keychain access popup" width="450">

5. *(Optional)* Click the notch to expand → open Settings → paste your Anthropic or OpenAI API key. This enables sentiment analysis of your prompts so the mascot reacts emotionally

   <img src="assets/emotion-settings.png" alt="Emotion analysis settings" width="400">

6. Start using Claude Code or Codex and watch Notchi react
7. Track usage by clicking on the usage bar

   <img src="assets/usage-dashboard.png" alt="Usage dashboard with cost chart and quota bars" width="450">

## How it works

```
Claude Code / Codex --> Hooks (shell scripts) --> Unix Socket --> Event Parser --> State Machine --> Animated Sprites
```

Notchi registers shell script hooks with Claude Code and Codex on launch. When either agent emits events (tool use, thinking, prompts, permission requests, compaction, session start/end), the hook script sends JSON payloads to a Unix socket. The app parses these events, runs them through a state machine that maps to sprite animations (idle, working, sleeping, compacting, waiting), and uses Anthropic or OpenAI to analyze user prompt sentiment for emotional reactions.

Each session gets its own sprite on the grass island, drawn from the Claude or Codex sprite family depending on which agent it came from. Clicking expands the notch panel to show a live activity feed, session info, and Claude/Codex usage stats.

## Contributing

If you have any bugs, ideas, or would like to contribute through pull requests, please check out [Contributing to Notchi](CONTRIBUTING.md).

## Support

Notchi is free and open source. If it's useful to you, you can [sponsor development](https://github.com/sponsors/sk-ruban), which helps cover the Apple Developer account that keeps builds signed and notarized.

## Community Ports

- [notchi-for-windows](https://github.com/AptatoX/notchi-for-windows) by [@AptatoX](https://github.com/AptatoX), a community-made Windows port of Notchi
- [pixel-companion](https://github.com/Emi-Dz/pixel-companion) by [@Emi-Dz](https://github.com/Emi-Dz), a community-made Windows desktop companion inspired by Notchi

## Credits

- [Claude Island](https://github.com/farouqaldori/claude-island): design inspiration for the app
- [Readout](https://readout.org): design inspiration for [notchi.app](https://notchi.app)
- [Aseprite](https://www.aseprite.org/): sprite design

## License

GPL-3.0-only. See [LICENSE](LICENSE).

[dmg]: https://github.com/sk-ruban/notchi/releases/download/v1.2.5/Notchi-1.2.5.dmg
