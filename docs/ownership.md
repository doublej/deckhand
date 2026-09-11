# Ownership

> Who has this Mac right now — the person, or Deckhand

## What this is

A proposal, not a thing that exists. JJ described it on 2026-09-10 as "a way to indicate full
screen by covering the entire screen … to indicate whether the system is owned by deckhand or
owned by me", and the sentence after it is the one that matters:

> That also answers the question whether I am active on the machine or active on phone, which
> answers the question how an agent should communicate with me.

So this is not a screen blocker with a sign on it. It is a **presence fact** that the Mac
currently does not have, and a **screen that declares it**. The screen is the visible half; the
fact is the useful half, and most of what follows is about the fact.

## Why it is load-bearing

`deliver.py` says it in its own first paragraph: on the keyboard route, **the daemon is holding
JJ's keyboard for him**. `it2 session run` types the words into the pane and presses return, and
they arrive as the person because they *are* the person's.

That is exactly right when the person is not at the keyboard, and wrong when they are. Two
things typing into one pane interleave, and neither knows the other happened. Today
`deliver(route="auto")` takes the keyboard whenever the session has a pane — a test of whether a
*window* exists, never of whether a *person* does. It is correct by luck.

Three questions collapse into this one fact:

- **May an agent use the keyboard route?** Only if nobody is holding the keyboard.
- **Where should something reach the person?** The pane when they are here, the phone when they
  are not. The Lock Screen card already exists for the second case and currently has no way to
  know it is the right one.
- **Is it safe to start something disruptive?** A rebuild that steals focus, a simulator launch,
  a window rearrangement.

## What the Mac can already know

Measured on this machine, not assumed:

| Signal | How | Costs |
|---|---|---|
| Seconds since the last keyboard or mouse event | `ioreg -c IOHIDSystem` → `HIDIdleTime`, nanoseconds | one `ioreg`, no permission, no entitlement |
| Screen locked | `CGSSessionScreenIsLocked` in `ioreg -n Root -d1 -a` | same call |
| The phone is here and awake | every authenticated request already arrives with the pairing token; nothing records when | free — the daemon simply does not look |

While this document was being written, `HIDIdleTime` read **695 seconds** while JJ was talking to
a session continuously from his phone. That is the whole feature in one number: eleven minutes
untouched at the Mac, and never more present. Nothing in this repo notices the difference.

## The three states

Ownership is not a boolean, and the third state is the one that makes it worth having.

- **The person has it.** Recent HID input. The keyboard route is unsafe, the cover is down, and
  anything wanting attention should use the screen in front of them rather than the phone.
- **Deckhand has it.** Idle at the Mac, and the phone has been heard from. The cover is up, the
  keyboard route is free, and the phone is where a person is reached.
- **Nobody has it.** Idle at the Mac and silent on the phone. The cover is up, work proceeds, and
  anything needing a person waits — it has nowhere better to go than the Lock Screen card, which
  will be read whenever the phone is next picked up.

The transition that matters most is the one *back*: a key pressed or the mouse moved takes
ownership instantly, with no confirmation and no animation to sit through. Anything else teaches
the person to resent it.

## What the cover is, and what it is not

It is a sign. It says the Mac is working, what it is working on, and that touching it will
interrupt something. Someone walking up should be able to read it from standing distance and
decide whether to sit down. That is the whole job.

It is **not** a lock. It holds no secret, it guards nothing, and it must not pretend to. A cover
that can be dismissed by any key is honest about being a sign; one that asks for a password is
claiming to be a security boundary it has no right to be, and it would be the first thing to
strand JJ in front of his own machine.

What it must never do, each for its own reason:

- **Never cover the real lock screen or a system alert.** The system's own surfaces outrank it.
- **Never survive its own daemon.** If the daemon dies the cover must come down, or a crash locks
  the person out of the machine with a sign about work that is no longer happening. This is the
  same failure that took `openLog` down with the daemon it was reporting on — the button that
  only matters when the process is dead cannot be served *by* that process.
- **Never take keyboard focus.** It must not swallow the keystroke that dismisses it, and a pane
  being typed into by the daemon must keep receiving those keystrokes underneath.
- **Never appear while the person is present.** The cost of a false positive here is high and
  immediate.

## Where it lives

Not in Deckhand. Deckhand's Mac half is a headless Python daemon with no UI surface at all, and
the root CLAUDE.md is explicit that the menu bar app was deleted because utt's plugin page
replaced every reason it existed. Reviving a second Mac app to draw one window is the thing that
packet was written to prevent.

So the cover belongs in **utt**, driven by Deckhand — the same relationship as `daemon.log`,
where the extension names a thing and utt does it, precisely so it keeps working when the
extension's own process is not. That precedent is two commits old and it argues for itself: the
cover must come down when the daemon dies, so the daemon cannot be what draws it.

The presence *fact* is the daemon's, because the daemon is what needs it: it picks the route, it
decides whether to raise a Lock Screen card, and it already polls once a second for other
reasons.

## What it would take

1. `presence.py` in the daemon: `HIDIdleTime`, the lock flag, and a last-heard-from timestamp for
   the phone written by the existing auth dependency. One `ioreg` per sweep on a loop that is
   already running.
2. An ownership state on `/health` and `/sessions`, so the phone can show it and the app can stop
   guessing.
3. `deliver(route="auto")` consults it: the keyboard route requires that nobody is at the
   keyboard, and falls back to the socket rather than interleaving. **This is the one change that
   fixes a real bug rather than adding a feature**, and it is worth doing whether or not the cover
   is ever drawn.
4. A manifest key in utt — the shape `daemon.log` already established — naming that this extension
   wants a cover, and a route or file the daemon uses to raise and lower it.
5. The cover itself in utt: a borderless window at a level above normal windows and below the
   system's, dismissed by any input, torn down when the extension's daemon stops reporting.

Steps 1–3 are worth doing alone. The cover is the visible reward for having done them, and the
order is not negotiable — a sign that declares an ownership nobody computed would be a lie drawn
at full screen.

## Open questions

- **How long is idle?** Thirty seconds is twitchy; five minutes is a person who has left the room
  and come back twice. It probably wants to be asymmetric — slow to claim the Mac, instant to
  give it back.
- **Does the phone being awake mean the person is?** A phone on a desk polls exactly like a phone
  in a hand. The honest version may be that the phone can only ever say "reachable", never
  "present".
- **One Mac or several?** `mac` is already on the wire for the Lock Screen card because a second
  machine must never be mistaken for the first. Ownership has the same problem and no answer yet.
- **Does the cover show the work, or only that there is work?** Showing it is more useful and is
  also a small screen-sized leak of what JJ is doing, in whatever room the Mac is in.
