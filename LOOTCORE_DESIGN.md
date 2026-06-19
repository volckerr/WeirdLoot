# WeirdLoot Loot Accounting Core: design sketch

## Why we're doing this
Loot accounting is currently smeared across `Session.lua`, `LiveRoll.lua`, `Comm.lua`, and
`Resolver.lua`, with **multiple representations of the same truth** and **multiple identity
schemes that disagree**. Every bug this session came from that:

- state in 4 places (`lockedItems`, `pendingIds`, `responses`, `copies`) that drifted out of sync.
- identity done 3 ways: positional ordinal ids (collided across re-drops), link matching
  (grabbed the wrong copy), and the seq ledger (correct, but other code bypassed it).
- the stale-roll bug: `LiveRollSessionItem` matched by **link**, so a resolve read a *different*
  copy's rolls.
- cross-drop bleed, won-copy-blocks-new, skip/pass re-roll: all "which copy is this, and whose
  state is it?" confusion.

The fix is not another patch. It's one module that **owns the loot model** (identity,
lifecycle, per-copy data, resolution) behind a small API. Everything else (bag scan, comm,
UI, popups, payout) becomes a *consumer*. This mirrors how TradeDeliver owns trade delivery as
a focused unit instead of being sprinkled through the addon.

## Boundary (what's in vs out)
**In the core (pure logic, no WoW globals beyond basic Lua):**
- the copy ledger + identity
- the per-copy state machine
- per-copy roll data + winner
- reconciliation (bag reality -> ledger)
- resolution (rolls -> winner)
- serialize / apply-remote for mirroring

**Out (consumers that call the core):**
- bag scanning / eligibility (feeds counts in)
- comm transport (serializes out / applies in; roll-lifecycle messages)
- UI + roll popups (read surfaceable copies, drive state via API)
- payout / TradeDeliver (consume the resolved winner)

The core never touches a frame, a `SendCommMessage`, or `GetContainerItemInfo`. Those are fed to
it. That separation is the whole point.

## Data model
```
LootCopy = {
  id,        -- "C:<seq>"  unique within a session, NEVER reused
  itemId,    -- numeric WoW item id (for payout/trade), NOT an identity key
  link, name, icon,
  state,     -- see state machine
  rolls = { [playerKey] = { tier = "ms"|..., roll = 73 } },  -- this copy's rolls ONLY
  winner,    -- playerKey or nil, set at resolve
  outcome,   -- nil until resolve, then "won" | "passed" (no winner). Set ONLY at resolve.
  recipient, -- set at MarkDelivered (who actually received it)
}
Ledger = { [id] = LootCopy }      -- the authoritative map
seq                                -- monotonic counter; ledger ids come from here
```
**Identity invariant:** a copy is identified by `id` and nothing else, ever. No consumer is
allowed to look a copy up by link. (This single rule kills the stale-roll class of bugs.)

## State machine
```
            mint(fresh)            mint(preexisting)
                 |                       |
                 v                       v
               [new] --------skip------> [skipped] ---surface--> [pending]
                 |  \                       ^                       |
              surface \---------------------/                   startRoll
                 |                                                  |
                 v                                                  v
              [pending] ---------startRoll-------------------->  [rolling]
                                                                    |
                                                                 resolve
                                                                    |
                                                                    v
                                                                [resolved]  (roll done;
              [idle] --surface--> [pending]                      enters disposition)
              (preexisting items, manual roll)
```
- **new**: fresh loot this session; auto-surfaced to the ML.
- **idle**: present but not fresh (session-start / late-eligible); listed, not auto-surfaced.
- **pending**: a Start Roll / Skip popup is up.
- **rolling**: broadcast to the raid, collecting rolls.
- **resolved**: roll finished (winner OR all-pass). Never auto-surfaced again, but NOT the end of
  the copy's life: it now enters a disposition substate (below).
- **skipped**: ML dismissed; **re-surfaces** on the next surface pass (not a decision).

`resolved` ends the *roll*. `skipped` is a snooze. Cancel sends `rolling -> pending`.

### Disposition (end of life: where the copy actually went)
The bag scan can detect that a copy is gone, but never *which* one or *where* it went (no GUID, no
memory). So a copy's physical fate is a recorded transition, not something inferred from a count
drop. After `resolved`, a copy is in one of:
- **owed**: resolved to a winner who is not the ML, not yet delivered. Still in the ledger and in
  the ML's bags. (Self-win or all-pass copies skip this; the ML already holds them.)
- **delivered**: TradeDeliver completed the trade and called `core:MarkDelivered(id, recipient)`.
  Recipient and time are recorded. TERMINAL. This is the "where it went" audit record.
- **removed**: the copy left the ML's bags with NO delivery reported (vendored, banked, mailed,
  disenchanted, or a self-win/all-pass copy the ML offloaded). TERMINAL, disposition unrecorded.
  The core marks it honestly as `removed` rather than guessing it was delivered.

So the only truly terminal states are **delivered** and **removed**. A `resolved`/`owed` copy is
NOT silently dropped on a bag-count decrease; the decrease is reconciled into `delivered` (if a
report arrived) or `removed` (if not). Undecided copies (idle/new/skipped) that vanish go straight
to `removed`.

## Reconciliation (bag reality -> ledger)  [ML only]
Input each pass: `eligibleCounts` (link -> count of tradeable-epic copies, from the bag scanner)
and `freshLinks` (the bag-delta set of links that just increased).
"have" below counts only LIVE copies (not ones already `delivered`/`removed`).
```
for each link:
  want = eligibleCounts[link];  live = #live copies for link
  want > live -> mint (want-live) copies, id = "C:"..(++seq),
                 state = freshLinks[link] and "new" or "idle"
  want < live -> (want-live) copies left the bags. Transition that many OUT of the live set into
                 a terminal disposition, choosing the LEAST-committed first and NEVER a "rolling"
                 or (if avoidable) an "owed" copy. Order: idle > skipped > new > resolved-no-winner
                 > owed(last resort). For each chosen copy:
                   - delivery already reported for it  -> already "delivered" (skip; accounted)
                   - otherwise                         -> "removed" (left bags, disposition unknown)
links no longer eligible -> transition all live copies the same way
```
Terminal copies (`delivered`/`removed`) STAY in the ledger as the session's loot log. They are
never re-surfaced or re-resolved and ids are never reused, so their rolls cannot bleed into
anything. Explicit `MarkDelivered` reports remove won copies from the live set before/around the
time the bag scan sees the drop, which is what keeps the "which copy left" choice from mis-attributing.

**Invariants:** ids never reused; identity is driven by the (stable) eligible count, independent of
UI/comm timing; a copy's physical fate is a recorded transition, never inferred. The ML owns this;
raiders never run it (they mirror, see Sync).

## Resolution (delegates to the existing Resolver)
The core does NOT reimplement winner-picking. `Resolver.lua` already does the hard part
(bracket then named-rule then spec then status then roll). The core's only job at resolve time is
to hand the Resolver exactly ONE copy's rolls, keyed by stable id, and store what comes back:
```
core:Resolve(id):
  copy = ledger[id]                                  -- by id, ONLY
  record = addon:ResolveSessionItem(copy)            -- reads copy.rolls (== this id's rolls)
  copy.winner  = record.winner
  copy.outcome = record.winner and "won" or "passed" -- "passed" covers all-declined AND silence
  copy.state   = (record.winner and not isML(record.winner)) and "owed" or "resolved"
  return record                                      -- "owed" copies await MarkDelivered
```
The split: the **core** owns WHICH rolls belong to WHICH copy (the thing that broke); the
**Resolver** owns HOW to pick from a given set of rolls (already correct). An all-pass copy hands
over empty rolls, so the Resolver returns no winner. The old stale-roll bug was a link lookup
feeding the Resolver a different copy's rolls; routing every resolve through `ledger[id]` makes
that impossible by construction.

`outcome` is `won` or `passed` (where `passed` covers both "everyone declined" and "nobody
responded"; they are equivalent for disposition). It is set only here, at resolve. It exists to
drive optional downstream actions without re-deriving anything: a `passed` copy is the signal to
offer a one-click re-roll (`Unlock(id)` takes it `resolved -> idle` to surface again) or to route
it to disenchant, and it reads cleanly in the loot log ("Mantle: no winner (passed)"). `cancel`
and `skip` are state transitions, not outcomes: cancel sends a live roll `rolling -> pending`,
skip sends a pending copy `pending -> skipped`. Neither writes `outcome` or any history.

## API surface (the seam)
```
-- mutation (ML)
core:Reconcile(eligibleCounts, freshLinks)
core:Surface(id)            -- new/skipped/idle -> pending
core:Skip(id)               -- pending -> skipped
core:StartRoll(id)          -- pending -> rolling; clears rolls
core:RecordRoll(id, player, tier, roll)
core:Resolve(id) -> result   -- winner(other) -> "owed"; self-win/all-pass stay resolved
core:Unlock(id) / core:UnlockAll()   -- resolved/owed -> idle (reroll; retracts the owe)
core:MarkDelivered(id, recipient)    -- owed -> delivered (called by TradeDeliver)

-- queries (UI / popups)
core:Get(id) / core:State(id) / core:IsResolved(id)
core:Surfaceable()          -- copies in {new, skipped} awaiting the ML
core:List()                 -- ordered projection for the UI/list (live copies)
core:Log()                  -- terminal copies (delivered/removed): the session loot history

-- sync
core:Serialize() -> snapshot           -- ML -> broadcast
core:ApplyRemote(snapshot)             -- raider mirror (authoritative-replace)

-- events (so consumers react instead of polling)
core.on.copyAdded / copyResolved / copyDelivered / copyUnlocked / ledgerChanged
```

## Invariants (the rules that prevent every bug we hit)
1. **`id` is the only identity.** No code matches loot by link. (kills stale-roll reuse)
2. **ids never reused.** (kills cross-drop / re-kill bleed)
3. **a live copy's rolls live with the copy; on resolve they are frozen onto the record.** (kills stale responses)
4. **`resolved` ends the roll; `skipped` resurfaces; `delivered`/`removed` are the only true terminals.** (matches the agreed UX)
5. **ML owns the live ledger and runs all mutation (reconcile/mint/resolve); raiders hold a read-only mirror with that machinery dormant.** (kills raider self-bag rebuild)
6. **identity is on the eligible count, not on UI/comm/popup timing.** (kills the won-copy cap)
7. **physical fate is a recorded transition (`MarkDelivered` or `removed`), never inferred from a count drop.** (gives a real "where it went" audit trail)

## Interaction model (how each system talks to the core, and why)

Every system reaches the loot model through ONE door. Nothing keeps its own copy of loot state.
The recurring bugs all came from the opposite: LiveRoll kept `pendingIds`, Session kept
`lockedItems`, responses were keyed inconsistently, and the ML and raiders each rebuilt `items`
their own way. Centralizing means a system can only read or change the truth through a query or a
command, so it cannot independently drift.

### System map
```
   AutoLoot ---routes loot to ML bags---> [ BAG_UPDATE ]      (loot only ever
   (never calls the core)                        |            enters via the bag)
                                                 v
   Session bag scan (ML) --eligibleCounts+freshLinks--> core:Reconcile()
                                                 |
        Surface/Skip/StartRoll   RecordRoll      |   Serialize / ApplyRemote
        (LiveRoll popups, ML)    (from RSP)      |   (Comm: ML out, raider mirror)
                  \                 |            /                |
                   v               v           v                 |
                 +================ LootCore ================+     |
                 |  ids  |  state machine  |  per-copy rolls |    |
                 +=========================================+      |
                   |              |                |   ^          |
        copyAdded /  copyResolved  ledgerChanged   |   | Resolve() delegates
        (open popup) (winner+itemId)  (refresh)    |   | pick from one copy's rolls
                   |              |                |   v          v
                   v              v                | Resolver     UI (List/State,
                 LiveRoll       Payout /           |              renders + reacts)
                 popups         TradeDeliver       |
```

### Per-system contracts

**Bag scanner (Session.lua, ML only).** Calls in: `core:Reconcile(eligibleCounts, freshLinks)` on
each bag delta. Reads: nothing. Why: the core needs ground truth of what is eligible in the ML's
bags to mint and retire copies, but the scan itself touches `GetContainerItemInfo`, `resolveQuality`,
and tooltip reads, all WoW-specific. Keeping those out of the core leaves the core a pure, testable
state machine that just consumes counts.

**AutoLoot (AutoLoot.lua).** Calls in: nothing. Why: AutoLoot routes master loot into the ML's
bags and stops there. The resulting `BAG_UPDATE` is what the scanner observes. The bag is the
integration point, on purpose. Upstream's hint hack broke this by letting AutoLoot feed the model
directly; that is exactly the coupling we are removing.

**Live-roll popups (LiveRoll.lua, ML only).** Reads: `core:Surfaceable()` to know which copies need
a Start Roll / Skip popup. Calls in: `core:Skip(id)`, `core:StartRoll(id)`. Listens: `copyAdded`
(pop a new pending), `copyResolved` (close or relabel a popup). Why: popups are pure presentation
plus user intent. They must not own state (the `pendingIds` drift). They ask the core what to show
and tell the core what the ML decided, by id.

**Roll transport (Comm.lua wire + LiveRoll DROP/RSP/WIN).** Flow: `core:StartRoll` triggers a DROP
broadcast (ALERT); a raider's pick comes back as RSP (ALERT) and the ML calls
`core:RecordRoll(id, player, tier, roll)`; on countdown or End Roll the ML calls `core:Resolve(id)`
and broadcasts WIN (ALERT). Why: the core is the single place a roll is recorded against a copy id.
RSP carries the roll id, which maps to one copy id, so the roll lands under that id and nowhere
else. No link matching anywhere. This is the stale-roll fix expressed at the model layer.

**Session sync (Comm.lua).** ML: `core:Serialize()` produces a snapshot that Comm broadcasts (BULK,
debounced). Raider: Comm receives and calls `core:ApplyRemote(snapshot)` to mirror, authoritative
replace. Why: the core owns the canonical snapshot shape so serialization is consistent and the
raider mirror cannot drift incrementally. Comm owns only the wire (chunking, priority). This
replaces today's per-ITEM and per-ITEM_LOCK message storm that floods the throttle.

**Resolver (Resolver.lua).** Called by the core during `core:Resolve` (see Resolution above). Why:
the winner-picking algorithm is complex and already correct; the core guarantees it is always
handed exactly one copy's rolls by stable id, never a stale or wrong set.

**Payout / TradeDeliver (Payout.lua, TradeDeliver.lua).** Listens: `copyResolved` carrying winner +
itemId; on a non-self win it queues an owe (Payout decides self-vs-other, the core does not). Calls
back ONCE: when TradeDeliver completes the trade to the winner it calls
`core:MarkDelivered(id, recipient)`, moving that copy `owed -> delivered`. This is the only
back-channel into the core, and it exists because the bag scan can see a copy vanish but never
where it went; the trade completion is the authoritative "delivered to X" fact, so it must be
recorded, not inferred. Payout works in terms of `(player, itemId, count)`, not the copy id
(duplicates are fungible at the trade window), so two won copies of one item produce two
`copyResolved` events and two owes. Why this split: Payout/TradeDeliver own "what is owed and
handing it over"; the core owns "who won what and where it ended up." The wire between them is the
resolved/unlocked events out, and the single delivery report back.

Identity note: Payout never reads the core's copy id, but TradeDeliver needs it for
`MarkDelivered`. The copy id rides along on the `copyResolved` event and on the owe record, so when
a trade closes TradeDeliver knows exactly which copy to mark. (If two copies of one item are owed
to the same player, marking is FIFO over that player's owed copies of that itemId.)

**UI (UI.lua).** Reads: `core:List()` for rows, `core:State(id)` / `core:Get(id)` for per-row state
(locked styling, count, winner). Listens: `ledgerChanged` to refresh. Why: UI is pure presentation
of the core's projection, with no UI-owned state.

**Roster (Roster.lua).** Not a core dependency. The Resolver uses roster to evaluate rules; the core
stays free of it.

### The core deliberately does NOT
- scan bags, read tooltips, or know item quality (Session feeds it counts)
- send or receive addon messages (Comm owns the wire)
- create or position frames (LiveRoll / UI own presentation)
- pick winners (Resolver owns the algorithm)
- execute trades or run payout (TradeDeliver/Payout own those; the core only RECORDS a delivery
  outcome reported to it via MarkDelivered)
- know about the roster

### Two walkthroughs

**A. A fresh token drops (and a duplicate of one already won and kept).**
1. AutoLoot routes both to the ML's bags. `BAG_UPDATE` fires.
2. Session scans, calls `core:Reconcile(eligibleCounts={token:2}, freshLinks={token})`.
3. Core sees one existing copy for that link (state `resolved`, the kept one). It mints ONE new
   copy with a fresh id, state `new`. It does NOT touch the resolved copy. Emits `copyAdded`.
4. LiveRoll's `copyAdded` handler shows ONE pending popup for the new id. The resolved copy stays
   hidden. No stale rolls, no re-roll, because the new copy has its own id and empty rolls.

**B. A roll runs and resolves with nobody rolling.**
1. ML hits Start Roll on the pending copy. `core:StartRoll(id)` flips it to `rolling` and clears
   that id's rolls. LiveRoll broadcasts DROP.
2. Nobody picks anything, so no RSP arrives, so `core:RecordRoll` is never called for this id.
3. Countdown expires. `core:Resolve(id)` reads `ledger[id].rolls` (empty), hands it to the
   Resolver, which returns no winner. Copy goes `resolved`, `outcome = "passed"`, no winner.
   Emits `copyResolved`.
4. Result popup shows no winner. No previously-won copy's rolls can leak in, because resolve only
   ever reads `ledger[id]`. Because `outcome` is `passed`, the UI can offer a one-click re-roll
   (`Unlock(id)` to surface it again) or send it to disenchant.

## What it replaces (migration)
`session.copies` + `responses` + (already-removed) `lockedItems`/`pendingIds` + every by-link
lookup collapse into the core. `Session.lua` keeps only the bag-scan glue + ownership; `LiveRoll`
drives the core via API; `Comm` serializes the core; `Resolver` calls `core:Resolve`. The
`Lock/Unlock/IsItemLocked` wrappers stay as compatibility shims over `state` during migration,
then callers move to `core:` directly.

## Decisions
1. **Form: separate library.** `LootCore.lua`, own namespace `WeirdLoot.lootCore`, loaded early in
   the `.toc`. No frames / comm / bag API inside it; that boundary is the point. (DECIDED)

## Defaults (override any of these)
2. **Name:** `LootCore` (`WeirdLoot.lootCore`).
3. **Comm:** core owns the snapshot *shape* (`Serialize`/`ApplyRemote`); `Comm.lua` owns the wire
   (chunking, priority, distribution) and just calls those.
4. **Persistence:** ledger lives under a dedicated `WeirdLootSessionDB[...].lootCore` sub-table the
   core owns, not loose fields on the session.
5. **Scope:** incremental. Land `LootCore.lua` (ledger + identity + state machine + reconcile +
   resolve + serialize) first with unit-style self-checks, then migrate consumers one at a time
   behind the existing `Lock/Unlock/IsItemLocked` compat shims, deleting the old scattered state
   as each consumer moves over.
```
