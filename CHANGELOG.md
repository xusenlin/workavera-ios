# Changelog

All notable changes to Workavera for iOS are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

Server-side changes are recorded separately, in the
[Workavera changelog](https://github.com/xusenlin/workavera/blob/main/CHANGELOG.md).

## [Unreleased]

### Fixed

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

[Unreleased]: https://github.com/xusenlin/workavera-ios/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/xusenlin/workavera-ios/releases/tag/v1.0.1
