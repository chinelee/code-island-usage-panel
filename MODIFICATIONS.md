# Fork and modification notice

This repository is a modified fork of [Code Island](https://github.com/rifqiakrm/code-island) by Rifqi Akram.

The upstream project and this fork are distributed under the GNU General Public License, version 3. The original copyright notices and `LICENSE` file are retained.

## Main changes in this fork

- Replaces the default expanded session list with an integrated usage dashboard.
- Keeps the collapsed notch close to the physical MacBook notch width.
- Shows the current Codex account, plan, weekly quota, reset time, Credits balance, and available models.
- Reads OpenToken's local dry-run output to render rolling 1-hour and 24-hour usage without uploading from this app.
- Breaks usage down by tool, model, input, output, cache read, and cache write.
- Displays live Codex, Claude, and WorkBuddy sessions with provider, model, status, current tool, reasoning effort, and duration.
- Derives per-session Token totals from local Claude and Codex session logs when a trustworthy session match exists.
- Adds parser and quota-classification tests.

## Privacy and data sources

The application reads only data already available on the local Mac:

- Codex usage is requested from the official ChatGPT usage endpoint using the user's existing local Codex access token.
- OpenToken is an optional external CLI dependency. It is not bundled, downloaded, authenticated, or configured by this repository. The dashboard invokes `opentoken upload --dry-run --full --v2` and parses its local output. That invocation does not upload data.
- OpenToken's independently installed background service or hooks may have their own upload behavior. Review them with `opentoken privacy` and `opentoken upload --dry-run --v2`.
- Claude and Codex per-session Token totals are read from matching local JSONL session logs. Message text is not displayed, retained, or transmitted by the dashboard.
- The dashboard does not read Claude Desktop subscription quota because no reliable supported endpoint is available.

Do not commit local screenshots, QA evidence, account identifiers, usage exports, access tokens, or agent configuration files. The repository ignores `qa/` and `design-qa.md` for this reason.
