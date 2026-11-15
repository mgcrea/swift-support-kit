# SupportKitDriving: pointer events an app can read

Written 2026-11-15. Olivier approved the design in a Maquette session the same day ("ok sounds
great"), as the first of three small cycles that make a check by eye of our own Mac apps run
through the driving channel instead of the session's cursor: this one in swift-support-kit, then
Maquette linking the channel, then Cupertino naming a running copy by pid.

## Why

Maquette's checks by eye (G7, the view cube, G8) lost most of their time to synthetic input the
app does not read, and to driving the Mac the person was using. The channel already solves the
second: a command goes into the app's own windows, which never come to the front. But it cannot
drive Maquette's 3D viewport, for three reasons in `EventSynthesis.swift`:

1. Every pointer event is made by `NSEvent.mouseEvent(with:…)`, whose `deltaX` and `deltaY` are 0.
   The viewport turns and pans by `event.deltaX/Y` (`ViewportView.swift:583`, `:625`), as most
   canvases, maps and 3D views do, so a drag through the channel moves nothing.
2. A drag is the left button with no modifier. Maquette pans with Option-drag or the middle button.
3. A drag's steps are all queued before its down, so the drag takes no time. That is right for a
   control that tracks the mouse inside its down (a slider), and wrong for a view that animates
   or throttles between events.

A scroll is `.line` units only; a trackpad's pixel scroll (`hasPreciseScrollingDeltas`), which
the viewport also reads, cannot be sent.

## What changes

- **Deltas.** Every pointer event the channel makes carries `deltaX`/`deltaY`: a drag step the
  movement from the step before it (the down's point for the first), in points, y down as
  AppKit's deltas are; a hover's moves the same along its path; a click and an up zero. Made by
  building the event as today, then setting `mouseEventDeltaX/Y` on its `CGEvent` and making the
  `NSEvent` again from it (`NSEvent(cgEvent:)`), so its window and location stay as they were.
  The builder is a static function, testable without a window.
- **A drag's button and modifiers.** `drag` takes `button` (`left`, the default, or `other`, the
  middle button) and `modifiers` (as `key` takes them), carried on the down, every step and the
  up. `right` stays refused, as it is for a click, and for the same reason: a right-press can open
  a context menu the channel could never close.
- **A paced drag.** `drag` takes `paced: true`: its steps are sent over `durationMs` in real time,
  each after the one before is handled, instead of queued at once. The default stays queued, so
  every caller today gets what it got.
- **A hover's path.** `hover` takes an optional `from`: the moves run from it to `point`, so the
  deltas say which way the pointer went; without it, as today, every move is at `point` with a
  zero delta.
- **Pixel scrolls.** `scroll` takes `units`: `line` (the default, as today) or `pixel`, a precise
  scroll as a trackpad sends.
- **The protocol's version.** The `ready` event says `"version": 2`, so Cupertino can tell which
  verbs an app's channel takes; version 1 apps refuse the new fields as unknown, so Cupertino
  sends them only to version 2.

## Not here

- Measuring whether a `mouseMoved` sent this way fires a tracking area or `onContinuousHover`, and
  whether Maquette's viewport orbits: that is Maquette's cycle, which links the channel.
- Cupertino passing the new fields from `apple_desktop_drag`, `hover` and `scroll`: Cupertino's
  cycle.
- The channel's known gaps on Cupertino's side (`O_APPEND`, the `seq` base, re-reading
  `events.jsonl`): Cupertino's.
- A right-button drag.

## Tests

`DrivingCommandTests` pins each new field from its literal line, its default and its refusal (an
unknown button, `right` on a drag, an unknown unit). A new `PointerEventTests` builds events with
the static builder and checks `deltaX/Y`, `modifierFlags`, the event type for each button
(`otherMouseDragged` for `other`), `clickCount`, and a pixel scroll's
`hasPreciseScrollingDeltas` and `scrollingDeltaY`. A paced drag is checked in a hosted window
where `SupportKitTestHostTests` already opens one, if it can be without taking the screen;
otherwise by a scratch app, reported.

## Release

A minor version (the wire stays compatible: every new field is optional). Tagging it is
Olivier's call, as every release is; Maquette's cycle needs it.
