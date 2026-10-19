# Changelog

All notable changes to Workavera for iOS are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

Server-side changes are recorded separately, in the
[Workavera changelog](https://github.com/xusenlin/workavera/blob/main/CHANGELOG.md).

## [Unreleased]

### Added

- An Agenda home screen widget (medium and large) shows this month's calendar
  on the left and the next seven days of assigned task deadlines and Calendar
  events on the right, with a "next up" hint when the week is empty. Editing the widget chooses tasks and events, tasks only, or
  events only. A refresh button fetches the latest agenda from the server
  without opening the app; otherwise the widget refreshes every 30 minutes, at
  midnight, and whenever the Calendar changes in the app. Signing out clears
  the widget.

## [1.0.4] - 2026-09-04

Needs a Workavera server on 0.1.1 or newer: task start dates, public project
links, and subscription discovery are served by endpoints and fields that
release adds. Upgrade the server first.

### Added

- A Board task can carry an optional start date beside its due date, so a task
  reads as a span of work instead of a point in time. The detail sheet edits it
  from its own row, the card shows the span as "start – due", and a start set
  after the due date is refused before the server can reject it. Tasks with
  only a deadline, only a start, or neither behave exactly as before.
- A project you own carries a share button in Board's toolbar, publishing it to
  a public preview link anyone can open in a browser without an account, with
  no expiry or one 7 or 30 days out. Unlike a shared document the link pins
  nothing and always shows the project as it stands; revoking, expiring,
  archiving, or deleting takes it down, and the icon turns green while a link
  is live. An optional `?lang=zh` switch formats the page's dates in Chinese.
- Reading gains a Discover sheet: subscriptions you own, either an RSS/Atom
  feed or GitHub's trending board for one language over a day, week, or month,
  fetch candidates that are not in your list yet. A candidate can be summarized
  into English, 中文, or 日本語 first, and only the ones you keep become
  reading items, carrying the summary along. A subscription that fails to fetch
  reports its own error instead of emptying the panel.
- Tapping a notification opens a detail sheet with its full title and body —
  the list row keeps both truncated — and a model share is accepted or
  rejected from there.
- The share sheet of a published document can open its public link in the
  browser, so checking what a reader actually sees no longer means pasting the
  link somewhere first.
- A document you own carries a share button in its toolbar, publishing it to a
  link anyone can open in a browser without an account, with no expiry or one
  7 or 30 days out. The link serves the revision you publish and stays on it
  while you keep editing, so a draft is never exposed by accident; "Publish
  Latest" moves it forward and "Revoke Link" takes it out of service for good.
  Archived documents have no share button, because archiving already makes
  their link unavailable.

### Changed

- The application logo is now Workavera's arced W with a floating dot,
  replacing the previous robot mark across the app icon and in-app branding.
- A markdown document reads at the web reader's type scale: headings that open
  a section, blocks packed tight and carried by a generous line height, the
  editor's list indent, and quotes marked by a bar rather than italics.
  MarkdownUI's defaults are tuned for chat-sized messages, which left a
  document loose and its headings barely lifted off the text. Chat is
  unchanged. Headings 1 and 2 sit below the web scale on purpose: 3em and 2em
  are set for a wide column and leave a phone title a few characters to a line.
- A table in a document is a soft rounded block with light rules between rows,
  matching the web reader, instead of a full spreadsheet grid.

### Fixed

- An HTML document fills the screen and scrolls under the navigation bar the
  way a markdown one does. It was laid out inside the safe area, so it stopped
  at a seam under the bar, and the strip the bar left clear fell through to the
  app's background and read as a colour break above the document.

## [1.0.3] - 2026-08-04

### Added

- Board carries an archive button in its toolbar, opening the archived tasks
  of the project named in the panel's title. Each task lists the state it
  would return to and restores from there, so one archived by mistake is no
  longer out of reach on the phone.

### Fixed

- Chat approval cards show their approve and reject buttons while the current
  run is waiting for a decision. Cards now derive availability directly from
  the chat store instead of copying run state into the collection-view layer.
- Calendar shows unfinished Board task deadlines assigned to the signed-in
  user again, whether they own or participate in the project. The personal
  filter now matches assignee relation IDs and excludes completed states;
  comparing the multi-select relation itself silently returned no tasks.

## [1.0.2] - 2026-07-30

Needs a Workavera server on 0.0.10 or newer: task archiving reads a field that
release adds. Upgrade the server first.

### Fixed

- A document body now fills the screen and scrolls on its own. The metadata
  header above it is gone, for markdown as well, so a document with sticky
  elements of its own is no longer left scrolling inside a strip. Pull to
  refresh remains on markdown documents; an HTML document scrolls in its own
  web view and no longer offers it.
- A conversation list reordered after pinning or restoring now uses the same
  order as the server: pinned first, then by latest message, then by last
  edit. A locally reordered list no longer disagrees with the next refresh.
- Archived tasks no longer appear in Board pages, dashboard counts, or
  Calendar deadlines; Calendar also limits task deadlines to tasks assigned
  to the signed-in user.
- Tool cards now show their preparing or running state as soon as a tool call
  begins. Tool lifecycle events bypass the stream's 80 ms text refresh
  throttle, so a quiet execution period no longer makes Chat appear frozen
  until the result arrives.

## [1.0.1] - 2026-07-28

### Added

- Connect your own MCP servers from Settings and use their tools in Chat.
  Headers hold the credentials that reach the remote server and are
  write-only, so leaving a header field untouched keeps what is stored
  rather than clearing it. Tool definitions only arrive from a refresh
  against the server; review decides only whether a tool is enabled and
  whether its calls need approval, so an upstream server cannot silently
  redefine a tool that was already approved.
- Tool cards for folder creation and calendar event search. Both tools were
  reaching a card that could not parse their payload, so they rendered a
  header with nothing under it. The folder card distinguishes creating a
  folder from reusing one, and event rows carry their own date, marking a
  repeating event's start as "onwards" so it is not read as the only time it
  occurs.
- An approved action now reports what actually happened, from the outcome
  the server supplies, rather than leaving raw result JSON as the only
  account of it.
- A Support link in Settings.

### Changed

- A conversation opens at its newest message without measuring the whole
  history first. The list is a collection view, which places rows from an
  estimate and measures one only as it appears, so opening a long,
  tool-heavy conversation costs a screenful rather than the entire history.
  Assistant messages are also split into one row per part, since a single
  message can carry dozens of tool calls and was previously built and
  measured whole.
- A long message you sent collapses to twelve lines behind a toggle. Laying
  out a pasted log costs the same whether or not it is on screen, so the cap
  bounds the work as well as the height.

### Fixed

- Opening a conversation landed short of the end and visibly jumped as row
  heights arrived. Row heights are only known once measured, and measuring
  them moves the end, so the list now re-lands until the reader takes over
  rather than assuming a single jump arrives.
- Expanding a tool card no longer yanks the conversation to the end.
- An approval request no longer freezes its card on the previous state with
  no buttons. The stream coalesces chunks into at most one refresh per
  interval, which assumes another chunk will follow to carry a skipped
  render; an approval request breaks that assumption, because the server
  blocks on the answer, so it is exempt from the throttle.
- Approval tool cards stay expanded while a decision is pending.

[Unreleased]: https://github.com/xusenlin/workavera-ios/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/xusenlin/workavera-ios/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/xusenlin/workavera-ios/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/xusenlin/workavera-ios/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/xusenlin/workavera-ios/releases/tag/v1.0.1
