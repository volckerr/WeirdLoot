-- LootCore: the single owner of loot identity, lifecycle, per-copy rolls, and disposition.
-- See LOOTCORE_DESIGN.md for the full rationale. This module is intentionally pure: no
-- frames, no SendCommMessage, no GetContainerItemInfo. Consumers feed it counts and read
-- its projections by stable copy id. That boundary is the whole point.
--
-- Step 1 (this file): the standalone core plus self-checks. No consumer is wired in yet.
-- Winner-picking is delegated through an injected resolver so the core has zero dependency
-- on the rest of the addon and can be verified with a plain Lua interpreter.

local addonName, addon = ...
if type(addon) ~= "table" then addon = WeirdLoot or {} end

local LootCore = {}

-- States. Live = anything that is not a terminal disposition.
local STATE = {
    NEW       = "new",        -- fresh loot this session; auto-surfaced to the ML
    IDLE      = "idle",       -- present but not fresh; listed, not auto-surfaced
    PENDING   = "pending",    -- a Start Roll / Skip popup is up
    ROLLING   = "rolling",    -- broadcast to the raid, collecting rolls
    RESOLVED  = "resolved",   -- roll finished (winner held by ML, or all-pass)
    SKIPPED   = "skipped",    -- ML dismissed; resurfaces next pass (a snooze, not a decision)
    OWED      = "owed",       -- resolved to a non-ML winner, awaiting delivery
    DELIVERED = "delivered",  -- terminal: trade completed, recipient recorded
    REMOVED   = "removed",    -- terminal: left bags, disposition unknown
}
LootCore.STATE = STATE

local function isLive(copy)
    return copy.state ~= STATE.DELIVERED and copy.state ~= STATE.REMOVED
end

-- Retire ordering for reconciliation: least-committed copies leave the bags first. A nil
-- rank means "never retire this one" (a rolling copy is mid-decision).
local function retireRank(copy)
    local s = copy.state
    if s == STATE.IDLE then return 1 end
    if s == STATE.SKIPPED then return 2 end
    if s == STATE.NEW then return 3 end
    if s == STATE.PENDING then return 4 end
    if s == STATE.RESOLVED then return copy.outcome == "won" and 6 or 5 end
    if s == STATE.OWED then return 7 end
    return nil -- rolling, or already terminal
end

local function deepcopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepcopy(v) end
    return out
end

-- ---------------------------------------------------------------------------
-- construction
-- ---------------------------------------------------------------------------
function LootCore.New()
    local self = setmetatable({}, { __index = LootCore })
    self.ledger = {}     -- id -> LootCopy (the authoritative map)
    self.order = {}      -- array of ids in mint order (drives List/Log ordering)
    self.seq = 0         -- monotonic; ids come from here and are NEVER reused
    self.handlers = {}   -- event name -> array of callbacks
    self._resolver = nil -- injected: function(copy) -> { winner = playerKey or nil }
    self._mlKey = nil    -- normalized key of the master looter
    return self
end

-- ---------------------------------------------------------------------------
-- wiring set by consumers (kept out of the core's logic so it stays pure)
-- ---------------------------------------------------------------------------
function LootCore:SetResolver(fn) self._resolver = fn end
function LootCore:SetML(playerKey) self._mlKey = playerKey end
function LootCore:IsML(playerKey) return self._mlKey ~= nil and playerKey == self._mlKey end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
function LootCore:On(event, handler)
    local list = self.handlers[event]
    if not list then list = {}; self.handlers[event] = list end
    list[#list + 1] = handler
end

function LootCore:emit(event, ...)
    local list = self.handlers[event]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

-- ---------------------------------------------------------------------------
-- internal helpers
-- ---------------------------------------------------------------------------
local function readEligible(entry)
    -- An eligible entry is either a bare count or { count, itemId, name, icon, link }.
    if type(entry) == "number" then return entry, nil end
    if type(entry) == "table" then return entry.count or 0, entry end
    return 0, nil
end

function LootCore:mint(link, fresh, meta)
    self.seq = self.seq + 1
    local copy = {
        id = "C:" .. self.seq,
        link = link,
        itemId = meta and meta.itemId or nil,
        name = meta and meta.name or nil,
        icon = meta and meta.icon or nil,
        state = fresh and STATE.NEW or STATE.IDLE,
        rolls = {},
        winner = nil,
        outcome = nil,
        recipient = nil,
    }
    self.ledger[copy.id] = copy
    self.order[#self.order + 1] = copy.id
    self:emit("copyAdded", copy)
    return copy
end

function LootCore:liveCopiesForLink(link)
    local out = {}
    for i = 1, #self.order do
        local copy = self.ledger[self.order[i]]
        if copy and copy.link == link and isLive(copy) then out[#out + 1] = copy end
    end
    return out
end

local function retire(copy)
    -- A copy left the ML's bags with no delivery reported. Recorded honestly as removed
    -- rather than guessing it was delivered. (A delivered copy is already terminal and out
    -- of the live set, so it never reaches here.)
    copy.state = STATE.REMOVED
end

-- ---------------------------------------------------------------------------
-- reconciliation: bag reality -> ledger  [ML only]
--   eligible    : link -> count (or link -> {count, itemId, name, icon})
--   freshLinks  : set of links that just increased this bag delta (link -> true)
-- ---------------------------------------------------------------------------
function LootCore:Reconcile(eligible, freshLinks)
    eligible = eligible or {}
    freshLinks = freshLinks or {}
    local changed = false

    -- mint / retire per eligible link
    for link, entry in pairs(eligible) do
        local want, meta = readEligible(entry)
        local live = self:liveCopiesForLink(link)
        if want > #live then
            for _ = 1, want - #live do
                self:mint(link, freshLinks[link] and true or false, meta)
                changed = true
            end
        elseif want < #live then
            self:retireExcess(live, #live - want)
            changed = true
        end
    end

    -- links that are no longer eligible at all: retire every live copy for them
    local seenLinks = {}
    for i = 1, #self.order do
        local copy = self.ledger[self.order[i]]
        if copy and isLive(copy) and not seenLinks[copy.link] then
            seenLinks[copy.link] = true
            if eligible[copy.link] == nil then
                local live = self:liveCopiesForLink(copy.link)
                self:retireExcess(live, #live)
                changed = true
            end
        end
    end

    if changed then self:emit("ledgerChanged") end
end

-- Retire `n` copies from `live`, least-committed first, never a rolling copy.
function LootCore:retireExcess(live, n)
    local candidates = {}
    for i = 1, #live do
        if retireRank(live[i]) ~= nil then candidates[#candidates + 1] = live[i] end
    end
    table.sort(candidates, function(a, b) return retireRank(a) < retireRank(b) end)
    for i = 1, n do
        local copy = candidates[i]
        if not copy then break end -- not enough retireable (rest are rolling); next pass catches them
        retire(copy)
    end
end

-- ---------------------------------------------------------------------------
-- lifecycle commands (ML)
-- ---------------------------------------------------------------------------
function LootCore:Surface(id)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state == STATE.NEW or copy.state == STATE.SKIPPED or copy.state == STATE.IDLE then
        copy.state = STATE.PENDING
        self:emit("ledgerChanged")
        return true
    end
    return false
end

function LootCore:Skip(id)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state == STATE.PENDING then
        copy.state = STATE.SKIPPED
        self:emit("ledgerChanged")
        return true
    end
    return false
end

function LootCore:StartRoll(id)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state == STATE.PENDING then
        copy.state = STATE.ROLLING
        copy.rolls = {} -- a roll always starts from a clean slate for THIS copy
        self:emit("ledgerChanged")
        return true
    end
    return false
end

function LootCore:Cancel(id)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state == STATE.ROLLING then
        copy.state = STATE.PENDING
        self:emit("ledgerChanged")
        return true
    end
    return false
end

function LootCore:RecordRoll(id, player, tier, roll)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state ~= STATE.ROLLING then return false end
    copy.rolls[player] = { tier = tier, roll = roll }
    return true
end

-- Resolve delegates winner-picking to the injected resolver, handing it exactly THIS
-- copy's rolls by stable id. The core only stores what comes back.
function LootCore:Resolve(id)
    local copy = self.ledger[id]; if not copy then return nil end
    local record
    if self._resolver then record = self._resolver(copy) else record = { winner = nil } end
    copy.winner = record and record.winner or nil
    copy.outcome = copy.winner and "won" or "passed"
    if copy.winner and not self:IsML(copy.winner) then
        copy.state = STATE.OWED -- awaits MarkDelivered
    else
        copy.state = STATE.RESOLVED -- self-win or all-pass: ML already holds it
    end
    self:emit("copyResolved", copy)
    self:emit("ledgerChanged")
    return record
end

-- resolved/owed -> idle, retracting any owe so the copy can be re-rolled.
function LootCore:Unlock(id)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state == STATE.RESOLVED or copy.state == STATE.OWED then
        copy.state = STATE.IDLE
        copy.winner = nil
        copy.outcome = nil
        copy.recipient = nil
        copy.rolls = {}
        self:emit("copyUnlocked", copy)
        self:emit("ledgerChanged")
        return true
    end
    return false
end

function LootCore:UnlockAll()
    for i = 1, #self.order do
        local copy = self.ledger[self.order[i]]
        if copy and (copy.state == STATE.RESOLVED or copy.state == STATE.OWED) then
            self:Unlock(copy.id)
        end
    end
end

-- The authoritative "where it went" record. Called once by TradeDeliver on trade completion.
function LootCore:MarkDelivered(id, recipient, when)
    local copy = self.ledger[id]; if not copy then return false end
    if copy.state ~= STATE.OWED then return false end
    copy.state = STATE.DELIVERED
    copy.recipient = recipient
    copy.deliveredAt = when
    self:emit("copyDelivered", copy)
    self:emit("ledgerChanged")
    return true
end

-- ---------------------------------------------------------------------------
-- queries
-- ---------------------------------------------------------------------------
function LootCore:Get(id) return self.ledger[id] end
function LootCore:State(id) local c = self.ledger[id]; return c and c.state or nil end
function LootCore:IsResolved(id)
    local c = self.ledger[id]
    return c ~= nil and (c.state == STATE.RESOLVED or c.state == STATE.OWED)
end

function LootCore:Surfaceable()
    local out = {}
    for i = 1, #self.order do
        local c = self.ledger[self.order[i]]
        if c and (c.state == STATE.NEW or c.state == STATE.SKIPPED) then out[#out + 1] = c end
    end
    return out
end

function LootCore:List() -- live copies, mint order
    local out = {}
    for i = 1, #self.order do
        local c = self.ledger[self.order[i]]
        if c and isLive(c) then out[#out + 1] = c end
    end
    return out
end

function LootCore:Log() -- terminal copies: the session loot history
    local out = {}
    for i = 1, #self.order do
        local c = self.ledger[self.order[i]]
        if c and not isLive(c) then out[#out + 1] = c end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- sync (core owns the snapshot shape; Comm owns the wire)
-- ---------------------------------------------------------------------------
function LootCore:Serialize()
    local copies = {}
    for i = 1, #self.order do
        local c = self.ledger[self.order[i]]
        if c then copies[#copies + 1] = deepcopy(c) end
    end
    return { seq = self.seq, copies = copies }
end

function LootCore:ApplyRemote(snapshot)
    self.ledger = {}
    self.order = {}
    self.seq = snapshot and snapshot.seq or 0
    if snapshot and snapshot.copies then
        for i = 1, #snapshot.copies do
            local c = deepcopy(snapshot.copies[i])
            self.ledger[c.id] = c
            self.order[#self.order + 1] = c.id
        end
    end
    self:emit("ledgerChanged")
end

-- ---------------------------------------------------------------------------
-- self-checks: exercise the design doc's walkthroughs and invariants with a plain
-- interpreter (luajit, 5.1 semantics). Run from the addon dir with:
--   luajit -e "local f=loadfile('LootCore.lua'); f('WeirdLoot', {}); WeirdLoot.LootCore.RunSelfChecks(true)"
-- ---------------------------------------------------------------------------
function LootCore.RunSelfChecks(verbose)
    local pass, fail = 0, 0
    local function ok(cond, label)
        if cond then pass = pass + 1; if verbose then print("  PASS " .. label) end
        else fail = fail + 1; print("  FAIL " .. label) end
    end
    -- a fake resolver: highest roll wins, no rolls -> no winner
    local function highestRoll(copy)
        local best, who
        for player, r in pairs(copy.rolls) do
            if not best or r.roll > best then best = r.roll; who = player end
        end
        return { winner = who }
    end

    -- 1. mint: fresh -> new, preexisting -> idle
    do
        local c = LootCore.New()
        c:Reconcile({ ["L1"] = 1 }, {}) -- not fresh
        c:Reconcile({ ["L1"] = 1, ["L2"] = 1 }, { ["L2"] = true }) -- L2 fresh
        local l1 = c:liveCopiesForLink("L1")[1]
        local l2 = c:liveCopiesForLink("L2")[1]
        ok(l1 and l1.state == STATE.IDLE, "mint preexisting -> idle")
        ok(l2 and l2.state == STATE.NEW, "mint fresh -> new")
    end

    -- 2. walkthrough A: a resolved copy is kept, a duplicate drops -> mint ONE new, don't touch the resolved one
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["T"] = 1 }, { ["T"] = true })
        local first = c:liveCopiesForLink("T")[1]
        c:Surface(first.id); c:StartRoll(first.id)
        c:RecordRoll(first.id, "ML", "ms", 50)
        c:Resolve(first.id) -- self-win, stays resolved, ML keeps it
        ok(c:State(first.id) == STATE.RESOLVED, "self-win stays resolved")
        c:Reconcile({ ["T"] = 2 }, { ["T"] = true }) -- duplicate drops alongside the kept one
        local live = c:liveCopiesForLink("T")
        ok(#live == 2, "duplicate mints exactly one new copy")
        local newOne
        for _, cp in ipairs(live) do if cp.id ~= first.id then newOne = cp end end
        ok(newOne and newOne.state == STATE.NEW, "new copy is fresh, own id")
        ok(c:State(first.id) == STATE.RESOLVED, "resolved copy untouched by re-drop")
        ok(next(newOne.rolls) == nil, "new copy has empty rolls (no bleed)")
    end

    -- 3. happy path to a non-ML winner -> owed -> delivered (terminal, in Log not List)
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["A"] = 1 }, { ["A"] = true })
        local id = c:liveCopiesForLink("A")[1].id
        c:Surface(id); c:StartRoll(id)
        c:RecordRoll(id, "Bob", "ms", 80)
        c:RecordRoll(id, "Amy", "os", 30)
        c:Resolve(id)
        ok(c:State(id) == STATE.OWED, "non-ML winner -> owed")
        ok(c:Get(id).winner == "Bob", "winner recorded")
        c:MarkDelivered(id, "Bob", 123)
        ok(c:State(id) == STATE.DELIVERED, "owed -> delivered")
        ok(c:Get(id).recipient == "Bob", "recipient recorded")
        ok(#c:List() == 0, "delivered copy leaves the live list")
        ok(#c:Log() == 1, "delivered copy is in the log")
    end

    -- 4. resolve with nobody rolling -> passed, no winner (walkthrough B)
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["B"] = 1 }, { ["B"] = true })
        local id = c:liveCopiesForLink("B")[1].id
        c:Surface(id); c:StartRoll(id); c:Resolve(id)
        ok(c:State(id) == STATE.RESOLVED, "all-pass stays resolved")
        ok(c:Get(id).outcome == "passed", "all-pass outcome is passed")
        ok(c:Get(id).winner == nil, "all-pass has no winner")
    end

    -- 5. stale-roll guard: two copies same link, rolls on copy1 never leak into copy2's resolve
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["D"] = 2 }, { ["D"] = true })
        local live = c:liveCopiesForLink("D")
        local one, two = live[1], live[2]
        c:Surface(one.id); c:StartRoll(one.id); c:RecordRoll(one.id, "Bob", "ms", 99)
        c:Surface(two.id); c:StartRoll(two.id) -- two has its own empty rolls
        c:Resolve(two.id)
        ok(c:State(two.id) == STATE.RESOLVED and c:Get(two.id).winner == nil, "copy2 resolves on its OWN (empty) rolls")
        ok(c:State(one.id) == STATE.ROLLING, "copy1 roll untouched by copy2 resolve")
        ok(c:Get(one.id).rolls["Bob"].roll == 99, "copy1 rolls intact")
    end

    -- 6. reconcile retire: drop count retires least-committed first, never a rolling copy
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["E"] = 3 }, { ["E"] = true })
        local live = c:liveCopiesForLink("E")
        local a, b, cc = live[1], live[2], live[3]
        c:Surface(a.id); c:StartRoll(a.id)              -- a = rolling (protected)
        c:Surface(b.id)                                  -- b = pending
        -- cc stays new (least committed)
        c:Reconcile({ ["E"] = 2 }, {})                   -- one copy left the bags
        ok(c:State(cc.id) == STATE.REMOVED, "least-committed (new) retired first")
        ok(c:State(a.id) == STATE.ROLLING, "rolling copy never retired")
        ok(c:State(b.id) == STATE.PENDING, "more-committed copy kept")
    end

    -- 7. ids never reused, even after a full retire-and-redrop cycle
    do
        local c = LootCore.New()
        c:Reconcile({ ["F"] = 1 }, { ["F"] = true })
        local id1 = c:liveCopiesForLink("F")[1].id
        c:Reconcile({}, {})                              -- F no longer eligible -> removed
        ok(c:State(id1) == STATE.REMOVED, "vanished undecided copy -> removed")
        c:Reconcile({ ["F"] = 1 }, { ["F"] = true })     -- re-drops
        local id2 = c:liveCopiesForLink("F")[1].id
        ok(id1 ~= id2, "re-dropped copy gets a brand new id (no reuse)")
    end

    -- 8. serialize / applyRemote round-trip mirrors state exactly
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["G"] = 1, ["H"] = 1 }, { ["G"] = true, ["H"] = true })
        local gid = c:liveCopiesForLink("G")[1].id
        c:Surface(gid); c:StartRoll(gid); c:RecordRoll(gid, "Bob", "ms", 70); c:Resolve(gid)
        local snap = c:Serialize()
        local mirror = LootCore.New()
        mirror:ApplyRemote(snap)
        ok(mirror.seq == c.seq, "seq mirrored")
        ok(mirror:State(gid) == STATE.OWED, "state mirrored")
        ok(mirror:Get(gid).winner == "Bob", "winner mirrored")
        ok(#mirror:List() == #c:List(), "live list count mirrored")
    end

    -- 9. unlock retracts an owe back to idle for re-roll
    do
        local c = LootCore.New(); c:SetResolver(highestRoll); c:SetML("ML")
        c:Reconcile({ ["I"] = 1 }, { ["I"] = true })
        local id = c:liveCopiesForLink("I")[1].id
        c:Surface(id); c:StartRoll(id); c:RecordRoll(id, "Bob", "ms", 60); c:Resolve(id)
        ok(c:State(id) == STATE.OWED, "owed before unlock")
        c:Unlock(id)
        ok(c:State(id) == STATE.IDLE, "unlock -> idle")
        ok(c:Get(id).winner == nil and next(c:Get(id).rolls) == nil, "unlock clears winner + rolls")
    end

    print(string.format("LootCore self-checks: %d passed, %d failed", pass, fail))
    return fail == 0
end

-- register the live instance on the addon namespace
addon.lootCore = LootCore.New()
addon.LootCore = LootCore -- the prototype/factory, for tests and New()
if not WeirdLoot then WeirdLoot = addon end
WeirdLoot.lootCore = addon.lootCore
WeirdLoot.LootCore = LootCore

return LootCore
