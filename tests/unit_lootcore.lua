-- Unit tests for the LootCore. Wraps the addon's LootCore.RunSelfChecks (the in-file self-test
-- battery the core author wrote) plus a few extra property-style assertions targeted at the
-- contract callers depend on (id monotonicity, no reuse, Resolve route is single-door).
--
-- Run from the addon dir:  luajit tests/unit_lootcore.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("lootcore unit battery")

H.test("core self-checks (in-harness)", function()
    local w = H.makeWorld("Masterlooter", true)
    H.check(w.addon.LootCore.RunSelfChecks(false), "all core self-checks pass")
end)

-- ---------------------------------------------------------------------------
-- Property-style: LootCore behaves correctly under repeated Reconcile cycles.
-- ---------------------------------------------------------------------------
H.test("LootCore: ids are strictly monotonic and never reused across resets", function()
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    -- Mint three distinct lots
    c:Reconcile({ [100] = 1 }, { [100] = true })
    c:Reconcile({ [101] = 1 }, { [101] = true })
    c:Reconcile({ [102] = 1 }, { [102] = true })
    local first = c:All()        -- All() returns every lot (List filters to live)
    H.eq(#first, 3, "three lots minted")
    local ids = { first[1].id, first[2].id, first[3].id }
    H.check(ids[1] ~= ids[2] and ids[2] ~= ids[3] and ids[1] ~= ids[3], "all three ids distinct")

    -- Drop one, re-mint: id must NOT be reused. Retired lots stay in the map with removed=true;
    -- the new live lot for [100] must carry a different id.
    c:Reconcile({ [100] = 0 }, {})
    c:Reconcile({ [100] = 1 }, { [100] = true })
    local newLot = c:openLotForItem(100)
    H.notNil(newLot, "a new live lot exists for [100]")
    H.check(newLot.id ~= ids[1], "new [100] lot id != the retired one (no id reuse)")
    -- The retired lot is still in the ledger (audit log) but no longer live.
    H.check(c:Get(ids[1]).removed == true, "retired lot flagged removed")
end)

H.test("LootCore: STATE constants are exactly the documented set", function()
    local w = H.makeWorld("Masterlooter", true)
    local S = w.addon.LootCore.STATE
    H.eq(S.NEW,      "new",      "NEW")
    H.eq(S.IDLE,     "idle",     "IDLE")
    H.eq(S.PENDING,  "pending",  "PENDING")
    H.eq(S.ROLLING,  "rolling",  "ROLLING")
    H.eq(S.RESOLVED, "resolved", "RESOLVED")
    H.eq(S.SKIPPED,  "skipped",  "SKIPPED")
end)

H.test("LootCore: AWARD constants are exactly the documented set", function()
    local w = H.makeWorld("Masterlooter", true)
    local A = w.addon.LootCore.AWARD
    H.eq(A.OWED,      "owed",      "OWED")
    H.eq(A.RESOLVED,  "resolved",  "RESOLVED")
    H.eq(A.DELIVERED, "delivered", "DELIVERED")
    H.eq(A.REMOVED,   "removed",   "REMOVED")
end)

H.test("LootCore: ledgerChanged event fires after Reset", function()
    -- Catches a regression where Reset forgets to emit the change notification, breaking UI sync.
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    local fired = 0
    c:On("ledgerChanged", function() fired = fired + 1 end)
    c:Reconcile({ [1] = 1 }, { [1] = true })
    c:Reset()
    H.check(fired >= 1, "ledgerChanged fired at least once (mints + reset)")
end)

-- ---------------------------------------------------------------------------
-- An item the ML already carries (idle) dropping again: the fresh copy gets its own lot, and copies
-- leaving the bags drain the open lots before any award is touched.
-- ---------------------------------------------------------------------------
local function lotsByState(c, itemId)
    local out = {}
    for _, l in ipairs(c:lotsForItem(itemId)) do
        if not l.removed then out[l.state] = (out[l.state] or 0) + (l.count or 0) end
    end
    return out
end

H.test("LootCore: a fresh drop of an item held idle mints its own new lot; idle copies stay idle", function()
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    local S = c.STATE
    c:Reconcile({ [500] = 2 }, {})                        -- carried into the session
    H.eq(lotsByState(c, 500)[S.IDLE], 2, "baseline: 2 idle")
    c:Reconcile({ [500] = 3 }, { [500] = true })           -- a new drop
    local st = lotsByState(c, 500)
    H.eq(st[S.IDLE], 2, "the idle lot did not grow")
    H.eq(st[S.NEW], 1, "the drop is its own new lot")
    c:Reconcile({ [500] = 4 }, { [500] = true })           -- another drop
    st = lotsByState(c, 500)
    H.eq(st[S.NEW], 2, "a second drop joins the new lot, not the idle one")
    H.eq(#c:lotsForItem(500), 2, "still two lots")
    c:Reconcile({ [500] = 5 }, {})                         -- not fresh (e.g. a re-read): old behaviour
    H.eq(lotsByState(c, 500)[S.IDLE], 3, "a non-fresh rise grows the first open lot")
end)

H.test("LootCore: copies leaving drain idle first, then the new lot, and only then awards", function()
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    local S, A = c.STATE, c.AWARD
    c:SetML("Masterlooter")
    c:Reconcile({ [600] = 2 }, {})                         -- idle 2
    c:Reconcile({ [600] = 3 }, { [600] = true })            -- new 1
    c:Reconcile({ [600] = 3, [601] = 1 }, { [601] = true }) -- an unrelated drop, untouched below
    c:Reconcile({ [600] = 2, [601] = 1 }, {})              -- one copy leaves
    local st = lotsByState(c, 600)
    H.eq(st[S.IDLE], 1, "idle shrinks first")
    H.eq(st[S.NEW], 1, "the fresh drop is kept for its roll")
    c:Reconcile({ [601] = 1 }, {})                         -- both remaining copies leave
    st = lotsByState(c, 600)
    H.eq(st[S.IDLE], nil, "idle lot gone")
    H.eq(st[S.NEW], nil, "the new lot drains too, past the first open lot")
    H.eq(c:liveCountForItem(600), 0, "nothing left counted")
    H.eq(c:liveCountForItem(601), 1, "the unrelated item kept its copy")
end)

H.test("LootCore: with an idle lot, a new lot and an owed award, a bag drop takes open copies before the award", function()
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    local S, A = c.STATE, c.AWARD
    c:SetML("Masterlooter")
    c:SetResolver(function() return { winners = { "Alice" } } end)
    c:Reconcile({ [700] = 1 }, { [700] = true })            -- a drop, rolled and owed to Alice
    local won = c:openLotForItem(700).id
    c:StartRoll(won); c:Resolve(won)
    H.eq(c:Get(won).awards[1].state, A.OWED, "owed to Alice")
    c:Reconcile({ [700] = 2 }, {})                         -- an idle copy (e.g. carried / unlocked)
    c:Reconcile({ [700] = 3 }, { [700] = true })            -- and a fresh drop
    H.eq(lotsByState(c, 700)[S.NEW], 1, "fresh drop has its own new lot")
    c:Reconcile({ [700] = 1 }, {})                         -- two copies leave
    H.eq(c:Get(won).awards[1].state, A.OWED, "Alice's owed copy is untouched")
    H.eq(lotsByState(c, 700)[S.IDLE], nil, "the idle copy went first")
    H.eq(lotsByState(c, 700)[S.NEW], nil, "then the new one")
end)

F.endSuite()