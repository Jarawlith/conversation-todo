# Conversation Todo

[简体中文](README.md) · [English](README.en.md)

A floating Windows desktop widget that passively reads supported AI conversations, extracts next actions, and orders them by priority. You do not need to copy each action into a task list manually.

**All application code, UI, packaging configuration, and documentation in this project were generated and iterated by AI, including this README. The author supplied the product idea, requirements, and feedback. Third-party tools such as Node.js and Inno Setup were developed by their respective authors and are excluded from this claim.**

Only the **mainland China preview edition** is currently released. Its UI is Simplified Chinese; English documentation does not imply an overseas release.

## Install

Download `ConversationTodo-Mainland-Setup-0.9.0.exe` from [Releases](https://github.com/Jarawlith/conversation-todo/releases) and run it. The installer includes Node.js; no separate Node installation, manual PowerShell execution, or administrator privileges are required. Windows 10 / 11 x64 is supported.

Choose desktop shortcuts and startup behavior during installation. On first launch, select an analysis method and authorize sending necessary conversation text to that service. Closing the widget minimizes it to the tray; use its tray menu to exit.

The preview installer is unsigned and may appear as an unknown publisher. Uninstall through Windows Apps; tasks, settings, and encrypted credentials remain in `%LOCALAPPDATA%\CodexTodo`.

## Features

- Passively reads retained local Codex and Claude Code conversations. Internal agent messages, reasoning, and tool output are excluded.
- Captures opened, loaded ChatGPT / Claude conversations through a Chrome extension. No automatic scrolling or access to unopened cloud history.
- Explicit user commitments become tasks; AI suggestions require confirmation.
- Displays the top three actions by priority. Expand the rest, complete, ignore, reprioritize, restore, or inspect source evidence.
- Explicit completion or cancellation updates existing tasks while retaining records. Sources remain separate across conversations; there is no automatic cross-conversation deduplication.
- Pause collection and analysis, or exclude a conversation. Exclusion removes derived tasks and locally captured web text without editing original logs.
- Dark, draggable, collapsible, always-on-top widget with tray and startup support.
- Hold F2 to capture an idea and release to transcribe locally in the background. Text is saved automatically to My Ideas without opening a window or switching apps. Supports Mandarin, Cantonese and English, configurable keyboard shortcuts and mouse side buttons 1 / 2.

![Settings example](docs/settings.png)

## Analysis methods

### Quick voice capture

Hold **F2** to record and release to transcribe. First use downloads an INT8 SenseVoiceSmall model (about 160 MB compressed, 239 MB on disk) from GitHub; after downloading, hold the shortcut again. Subsequent recognition works offline, without Windows voice typing, cloud transcription or subscription/API token costs. Original model rights belong to its authors.

Settings now has a left sidebar: Analysis, Voice capture, Web collection, and Privacy. In Voice capture, click the shortcut field and press a new key or mouse side button, choose a language, and save. Supports F1–F11, modifier-key combinations and mouse side buttons 1 / 2. Shortcuts pause while Settings is open and resume when it closes. Choose another keyboard shortcut if occupied. The selected mouse button records instead of navigating back/forward. Recording uses the Windows default microphone and requires desktop microphone permission.

Recording and recognition run in the background. Successful text is automatically saved as an idea; empty or failed results create nothing. Click My Ideas in the widget or tray to edit later or add an idea to your task list. Existing voice tasks retain their status. Audio is transient and removed after inference; crash leftovers are cleaned on next launch. Ideas are stored separately and never submitted to the conversation analyzer. Voice capture does not require an analysis subscription or key.

Each recording is limited to two minutes, with bounded inference chunks for longer audio; boundaries may affect recognition. The model loads per capture and the worker exits afterward to release RAM. Review and correct names, numbers and accents in My Ideas. [Model adapter architecture](docs/SPEECH-ENGINES.md)

| Method | Requirements and cost |
| --- | --- |
| Your Codex subscription | Requires an installed, authenticated official Codex tool and an account-accessible model. Model dropdown uses the local Codex catalog when available; choose a supported reasoning effort. Default: `gpt-6-luna`, medium reasoning. Logging into the ChatGPT website alone is insufficient. Uses your account's quota. |
| Your Claude subscription | Requires installed, authenticated Claude Code. Default: `haiku`; choose Haiku, Sonnet, Opus, Fable or a specific version from a dropdown, or enter a custom model. Fable may bill additional usage credits. The executable path is configurable. Uses your account's quota. |
| App-provided AI | **The public service is not open. GitHub downloaders cannot currently use the author's API credits.** When enabled, the backend address will be preset; ordinary users do not enter it. |
| Your API key | Select DeepSeek, Doubao, OpenAI, Claude or another provider. Presets configure the endpoint and protocol; supply your model ID and key. Other providers allow custom connections. Supports OpenAI-compatible APIs (including DeepSeek and Doubao) and native Anthropic requests. Availability and compatibility depend on the provider; not all have been tested. You pay the provider. |

The app does not collect ChatGPT / Claude passwords, purchase subscriptions, or log into official tools on your behalf. Your own subscriptions or keys do not spend the author's OpenRouter credits.

### Optional Chrome setup

Local log collection needs no extension. For web conversations, choose Web collection in the Settings sidebar and click the button to open Chrome and copy the extension directory. Enable Developer Mode at `chrome://extensions`, choose **Load unpacked**, paste the copied path, then refresh your chat tabs. This is a one-time step.

The extension is not published in the Chrome Web Store. Chrome on ordinary Windows computers does not permit silent installation of unpublished extensions, so an EXE cannot complete this confirmation for you. [Official Chrome documentation](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions)

### Frequency and token usage

Default: **30 minutes**; alternatives: 5, 15, 30, 60 minutes, or daily. Checking for changes does not call a model. Only pending new or edited messages trigger analysis. The first scan automatically continues through all readable, non-excluded history in small batches without waiting for the next scheduled check. Pause and failure checkpoints preserve completed work. Initial analysis consumes quota. Web history remains limited to loaded messages.

Message fingerprints and batch checkpoints avoid repeatedly uploading the full history. Requests contain changed messages, limited context, and compact existing-task summaries. Network/service failures are not automatically retried and models are not silently substituted. A failed conversation ID or source quote gets at most one additional correction call for that conversation, which consumes quota. Persistent quote failures retain their checkpoint while other conversations continue. Whitespace/full-width differences map back to the original text; fabricated or cross-message quotations are rejected.

## App-funded model and cost controls

The mainland app-provided service is pinned to **DeepSeek V4 Flash 0731**, `deepseek/deepseek-v4-flash-0731`. Both the settings list and mainland backend enforce this exact model. These restrictions apply to the author's paid service, not users' own subscriptions or API keys.

The [OpenRouter model directory](https://openrouter.ai/api/v1/models), checked on 2026-10-10, listed this model with the lowest DeepSeek text-model input quote at that time, but the lowest-price route did not support this app's required JSON parameters. The [provider endpoint directory](https://openrouter.ai/api/v1/models/deepseek/deepseek-v4-flash-0731/endpoints) listed the lowest parameter-compatible endpoint at **$0.00869 per million input tokens** and **$0.27 per million output tokens**. A live synthetic request succeeded under these limits. This suits input-heavy, short-output extraction; it is not the cheapest for every workload, and prices can change.

The relay sorts providers by price and caps accepted input/output unit prices at those quotes. If no provider meets the limits, the request fails rather than accepting a higher-priced route. Optional reasoning is disabled. Per-account daily request and input-character limits and concurrency limits are also enforced. These are **not a global dollar spending cap**. Public HTTPS, safe identity issuance, and a global budget remain prerequisites for opening the public service; operators should also cap the dedicated key in OpenRouter. See [Deployment](docs/DEPLOYMENT.md).

## Privacy and limitations

Collection is local, but **necessary text is sent to the chosen cloud service for analysis**. With OpenRouter, OpenRouter and the selected model provider receive it. The mainland edition does not guarantee China-only data processing. Web capture does not read passwords, cookies, or unopened chats.

API keys and client tokens are encrypted with the current Windows user's DPAPI. Public source and installers exclude the author's API key, server credentials, personal conversations, and tasks. The relay persists usage counters rather than conversation bodies.

This is an early preview. AI can misclassify, miss, or incorrectly prioritize tasks; check source evidence for important actions. Long logs and pages can be truncated, unloaded web history cannot be captured, and upstream format/layout changes may break collection. Real-page Chrome capture, all-provider compatibility, and installation on other computers still need more testing.

## Source, build, and feedback

Application source: `src/`. Installer: `installer/`. Build instructions: [BUILD.md](docs/BUILD.md). No source license has been selected; do not assume an MIT or similar grant. Third-party notices are in `third-party/`.

Report your Windows version, analysis method, reproduction steps, and sanitized errors in [Issues](https://github.com/Jarawlith/conversation-todo/issues). Do not upload credentials, API keys, or full private conversations.
