# Cai - macOS Smart Clipboard Actions

## What It Is
Native macOS menu bar app (SwiftUI) that detects clipboard content types and offers context-aware actions powered by local AI. Built-in LLM runs in-process via MLX-Swift on Apple Silicon for zero-config experience, or works with Apple Intelligence (macOS 26+) / LM Studio / Ollama / any OpenAI-compatible endpoint. Privacy-first, no cloud, no telemetry.

## Core Flow
1. **Option+C** anywhere → `HotKeyManager` fires
2. Capture frontmost app name (`sourceApp`) for LLM context
3. `ClipboardService` simulates **Cmd+C** via CGEvent (private event source to isolate modifier state)
4. `ContentDetector` analyzes clipboard → returns type + entities
5. `ActionGenerator` generates context-aware actions (always shows all actions regardless of LLM availability)
6. `WindowController` shows floating panel with fade animation → user picks action
7. Action executes (LLM call / system action) → result auto-copied → user pastes with Cmd+V

## Content Detection Priority
| Priority | Type | Detection Method | Confidence |
|----------|------|-----------------|------------|
| 0 | Extension | `# cai-extension` header in YAML | 1.0 |
| 1 | URL | Regex `https?://\|www\.` | 1.0 |
| 2 | JSON | Starts `{`/`[` + JSONSerialization | 1.0 |
| 3 | Address | International street regex + NSDataDetector (≤200 chars) | 0.8 |
| 4 | Meeting | NSDataDetector.date + preprocessing (14h→14:00) (≤200 chars) | 0.7-0.9 |
| 5 | Image | NSPasteboardType.tiff or image file | 1.0 |
| 6 | Word | ≤2 words, <30 chars | 1.0 |
| 7 | Short Text | <100 chars | 1.0 |
| 8 | Long Text | ≥100 chars | 1.0 |

**Filters**: Currency ($50), durations ("for 5 minutes"), pure numbers

## Actions Per Content Type

Structure: Custom Action (⌘1, always first) → type-specific actions → universal text actions.
Universal text actions appear for relevant content types. Filter-to-reveal lets users type to surface any action regardless of detected content type, so misdetection never locks the user out.

- **Word**: Define + Explain, Translate, Search (no Reply/Proofread)
- **Short Text**: Explain, Reply, Proofread, Translate, Search
- **Long Text**: Summarize, Explain, Reply, Proofread, Translate (no Search)
- **Meeting**: Create Event, Open in Maps (if location) + all text actions
- **Address/Venue**: Open in Maps + all text actions
- **URL (bare)**: Open in Browser only
- **URL+text**: text actions + Open in Browser
- **JSON**: Pretty Print only
- **Image**: Extract Text (OCR via Apple Vision) + text actions on extracted text

Meeting/address detection is skipped for text >200 chars — long text always gets text actions.

## Features
- **Type-to-filter**: Start typing to filter actions and shortcuts by prefix
- **Filter-to-reveal**: Typing also reveals actions hidden for the current content type (so misdetection never blocks an action)
- **Custom shortcuts**: User-defined prompts, URL templates (%s), and shell commands ({{result}})
- **Shell shortcuts**: Run shell commands on clipboard text, display output in result view (15s timeout, stdin piping, follow-up LLM queries on output)
- **Community extensions**: In-app extension browser fetches from curated GitHub repo. Search, one-tap install, shell confirmation. Also installable by copying YAML to clipboard.
- **Output destinations**: Send text to external apps/services (Email, Notes, Reminders built-in; Webhook, AppleScript, Deeplink, Shell custom)
- **MCP connectors**: GitHub + Linear via MCP protocol. Create issues with LLM-generated titles, duplicate detection, label fetching.
- **App context**: Frontmost app name passed to LLM prompts (e.g., "from Mail")
- **Clipboard history**: Last 9 unique entries with pin support (Cmd+0)
- **Multi-turn follow-ups**: Tab to ask follow-up questions, session reused across turns
- **Window resume**: Dismissed window cached for 10s, restores state on reopen
- **Permission indicator**: Shield icon in Settings header (green/orange)
- **Auto-updates**: Sparkle framework for checking/installing updates
- **OCR**: Apple Vision framework for image text extraction

## Keyboard Shortcuts
| Key | Action |
|-----|--------|
| Option+C | Global trigger |
| ↑↓ | Navigate actions |
| Enter | Execute selected |
| Cmd+1-9 | Direct action shortcuts |
| Cmd+0 | Clipboard history |
| Cmd+N | New action (Ask AI without clipboard) |
| Cmd+Enter | Submit custom prompt / Copy result |
| Tab | Follow-up question (from result view) |
| A-Z | Type to filter actions and shortcuts |
| ESC | Clear filter / Back / Dismiss |

## Key Technical Decisions
- **No sandbox**: Required for CGEvent posting + global hotkey
- **CGEvent private source**: Prevents Option key leak from hotkey into simulated Cmd+C
- **CaiPanel (NSPanel subclass)**: Overrides `canBecomeKey` for keyboard events
- **PassThrough flag**: Lets TextEditor receive Enter/arrows during custom prompt input
- **acceptsFilterInput flag**: Prevents filter accumulation on non-action screens
- **LazyVStack `.id(action.id)`**: Prevents stale cached rows (not index-based)
- **ICS files for calendar**: No EventKit permissions needed
- **Notification-based keyboard routing**: WindowController posts, SwiftUI views subscribe
- **Actor-based services**: LLMService, MLXInference, OutputDestinationService, MCPClientService — thread-safe async/await
- **App context awareness**: Captures frontmost app before Cmd+C, passes to LLM
- **Built-in LLM**: In-process MLX-Swift inference on Apple Silicon (`MLXInference` actor wrapping `ModelContainer` + `ChatSession`). Default model: Ministral 3B 4-bit (~1.8 GB) from mlx-community. Curated catalog includes Qwen3 4B, Gemma 3 1B, Qwen 2.5 7B. Models cached in `~/.cache/huggingface/hub/`.
- **Multi-turn session reuse**: `ChatSession` is persisted across follow-up calls — same system prompt + matching turn count = reuse, otherwise fresh session. Avoids O(n) replay cost.
- **Concurrency guard**: `MLXInference.isGenerating` flag rejects concurrent generation requests with `MLXInferenceError.busy`.
- **Per-action generation config**: `GenerationConfig.forAction(_:)` returns tuned temperature, topP, maxTokens per LLM action (translate=0.0 deterministic, custom=0.6 creative, etc.)
- **Input cap**: 50K char limit on messages sent to LLM, prevents memory pressure on long clipboards
- **Apple Intelligence support**: macOS 26+ uses `LanguageModelSession` from FoundationModels framework, with same session reuse pattern

## Dependencies
- **HotKey** (SPM): soffes/HotKey v0.2.0+ — global keyboard shortcut
- **Sentry** (SPM): getsentry/sentry-cocoa v8.0.0+ — opt-in crash reporting
- **Yams** (SPM): jpsim/Yams v5.0.0+ — YAML parsing for community extensions
- **Sparkle** (SPM): sparkle-project/Sparkle — auto-updates
- **MLX-Swift** (SPM): ml-explore/mlx-swift v0.31.3 — Apple Silicon ML framework
- **MLX-Swift-LM** (SPM): ml-explore/mlx-swift-lm v2.31.3 — LLM inference layer for MLX
- **System**: AppKit, SwiftUI, Foundation, ApplicationServices, Carbon, ServiceManagement, Vision (OCR), FoundationModels (Apple Intelligence, macOS 26+ optional)

## Bundle IDs
- **Debug**: `com.soyasis.cai.dev` (separate accessibility entry)
- **Release**: `com.soyasis.cai` (production)

## Deployment Target
- **macOS 14.0+** (Sonoma) — required by MLX-Swift
