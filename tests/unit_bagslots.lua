-- Unit + property tests for util:BagSlots() (the shared bag-walk iterator) and the call sites that
-- adopted it: util:FindBagItemByLink, addon:PlayerHoldsItem (already covered in run.lua), and the
-- two Session scans addon:BuildBagSnapshot / addon:BuildTradeableEpicCounts.
--
-- The iterator's whole job is to reproduce the old nested loop exactly:
--     for bag = 0, NUM_BAG_SLOTS do for slot = 1, GetContainerNumSlots(bag) do ... end end
-- so the central guarantee is an ORACLE property test: over hundreds of random bag geometries the
-- iterator's (bag,slot) sequence must equal that nested loop's, in the same order. If that holds,
-- swapping the loop header at each call site (the body is unchanged) cannot change behavior.
--
-- The two Session scans were previously bypassed by the harness (bagLinkCounts shortcut). This suite
-- drives the REAL implementations (exposed as addon._realBuild* by the framework) against mocked bags
-- and the scan tooltip, closing that coverage gap.
--
-- Run from the addon dir:  luajit tests/unit_bagslots.lua

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("bag-walk iterator battery")

local makeWorld, putBag, linkFor = F.makeWorld, F.putBag, F.linkFor

-- the iterator's (bag,slot) sequence. Runs through the world's util closure, which reads the world
-- env's GetContainerNumSlots / NUM_BAG_SLOTS even though this test code runs in _G.
local function iterSeq(w)
    local out = {}
    for bag, slot in w.addon.util:BagSlots() do out[#out + 1] = bag .. ":" .. slot end
    return out
end

-- the reference nested loop, computed from the SAME env mocks the iterator reads.
local function refSeq(w)
    local out = {}
    local maxBag = w.env.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local n = w.env.GetContainerNumSlots(bag) or 0
        for slot = 1, n do out[#out + 1] = bag .. ":" .. slot end
    end
    return out
end

local function setBags(w, sizes, numBagSlots)
    w.env.NUM_BAG_SLOTS = numBagSlots
    w.env.__bags = {}
    for b, sz in pairs(sizes) do w.env.__bags[b] = { size = sz } end   -- unlisted bags read as absent (size 0)
end

local function eqSeq(a, b, msg)
    H.eq(table.concat(a, ","), table.concat(b, ","), msg)
end

-- ---------------------------------------------------------------------------
-- util:BagSlots() -- the iterator contract
-- ---------------------------------------------------------------------------
H.test("BagSlots: empty bags yield nothing", function()
    local w = makeWorld("Iter", true)
    setBags(w, { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 }, 4)
    H.eq(#iterSeq(w), 0, "no slots visited")
end)

H.test("BagSlots: ascending bag-then-slot order, zero-size bags skipped", function()
    local w = makeWorld("Iter", true)
    setBags(w, { [0] = 2, [1] = 0, [2] = 3 }, 4)
    eqSeq(iterSeq(w), { "0:1", "0:2", "2:1", "2:2", "2:3" }, "backpack then bag 2; empty bag 1 skipped")
end)

H.test("BagSlots: never visits a bag index past NUM_BAG_SLOTS", function()
    local w = makeWorld("Iter", true)
    setBags(w, { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1 }, 3)   -- bags 4,5 sized but out of range
    eqSeq(iterSeq(w), { "0:1", "1:1", "2:1", "3:1" }, "stops at NUM_BAG_SLOTS = 3")
end)

H.test("BagSlots: a caller break stops iteration cleanly (no over-run)", function()
    local w = makeWorld("Iter", true)
    setBags(w, { [0] = 5 }, 4)
    local seen = 0
    for _ in w.addon.util:BagSlots() do
        seen = seen + 1
        if seen == 2 then break end
    end
    H.eq(seen, 2, "break honored mid-walk")
end)

H.test("BagSlots: defaults NUM_BAG_SLOTS to 4 when the global is nil", function()
    local w = makeWorld("Iter", true)
    setBags(w, { [0] = 1, [4] = 1, [5] = 1 }, nil)   -- nil -> fallback 4; bag 5 must NOT be visited
    eqSeq(iterSeq(w), { "0:1", "4:1" }, "fallback range is 0..4")
end)

-- PROPERTY: the iterator is byte-for-byte the nested-loop oracle over random geometries.
H.test("BagSlots property: equals the nested-loop oracle over 600 random bag geometries", function()
    local w = makeWorld("Iter", true)
    math.randomseed(20260628)
    for _ = 1, 600 do
        local sizes = {}
        for b = 0, math.random(0, 8) do
            sizes[b] = (math.random(0, 1) == 0) and 0 or math.random(1, 24)
        end
        setBags(w, sizes, math.random(0, 6))
        eqSeq(iterSeq(w), refSeq(w), "iterator sequence == nested-loop sequence")
    end
end)

-- ---------------------------------------------------------------------------
-- util:FindBagItemByLink -- first matching (bag,slot), else nil
-- ---------------------------------------------------------------------------
H.test("FindBagItemByLink: nil/empty link returns nil", function()
    local w = makeWorld("Iter", true)
    H.eq(w.addon.util:FindBagItemByLink(nil), nil, "nil link -> nil")
    H.eq(w.addon.util:FindBagItemByLink(""), nil, "empty link -> nil")
end)

H.test("FindBagItemByLink property: returns the first match in walk order, nil when absent", function()
    local w = makeWorld("Iter", true)
    math.randomseed(424242)
    for _ = 1, 300 do
        w.env.__bags = {}
        for b = 0, 4 do w.env.__bags[b] = { size = 4 } end
        w.env.NUM_BAG_SLOTS = 4
        for b = 0, 4 do
            for s = 1, 4 do
                if math.random(0, 1) == 1 then
                    local id = math.random(1, 3)
                    w.env.__bags[b][s] = { id = id, count = 1, link = linkFor(id) }
                end
            end
        end
        for _, target in ipairs({ linkFor(1), linkFor(2), linkFor(3), linkFor(999) }) do
            local refB, refS
            for b = 0, 4 do
                for s = 1, 4 do
                    local it = w.env.__bags[b][s]
                    if it and it.link == target and not refB then refB, refS = b, s end
                end
            end
            local gotB, gotS = w.addon.util:FindBagItemByLink(target)
            H.eq((gotB or "nil") .. ":" .. (gotS or "nil"),
                 (refB or "nil") .. ":" .. (refS or "nil"), "first match for " .. target)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- addon:BuildBagSnapshot -- real scan (epic accumulation + quality gate + test mode)
-- ---------------------------------------------------------------------------
local GREEN_HEX = "|cff1eff00"
local function greenLink(id) return GREEN_HEX .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[Green" .. id .. "]|h|r" end
local BLUE_HEX = "|cff0070dd"
local function blueLink(id) return BLUE_HEX .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[Blue" .. id .. "]|h|r" end
local function emptyBags(w)
    w.env.__bags = {}
    for b = 0, 4 do w.env.__bags[b] = { size = 4 } end
    w.env.NUM_BAG_SLOTS = 4
end

H.test("BuildBagSnapshot (real scan): sums epic stacks across slots by link", function()
    local w = makeWorld("Iter", true)
    emptyBags(w)
    putBag(w, 0, 1, 40001, 1)
    putBag(w, 1, 2, 40001, 3)        -- same link, different bag/slot -> summed
    putBag(w, 2, 1, 40002, 1)
    local snap = w.addon:_realBuildBagSnapshot()
    H.eq(snap[linkFor(40001)], 4, "40001 summed across two slots")
    H.eq(snap[linkFor(40002)], 1, "40002 counted once")
end)

H.test("BuildBagSnapshot (real scan): sub-epic item excluded by the quality>=4 gate", function()
    local w = makeWorld("Iter", true)
    emptyBags(w)
    w.env.ITEM_QUALITY_COLORS[2] = { hex = GREEN_HEX }   -- so resolveQuality reads the green link as quality 2
    w.env.__bags[0][1] = { id = 50000, count = 5, link = greenLink(50000) }
    local snap = w.addon:_realBuildBagSnapshot()
    H.eq(snap[greenLink(50000)], nil, "green (quality 2) item not in the epic snapshot")
end)

-- Freya's chest hands the ML a rare-quality BoP container (Alchemist's Cache). The epic floor would
-- drop it, so addon.ROLL_ANY_QUALITY exempts listed ids; nothing else sub-epic may sneak through.
H.test("BuildBagSnapshot (real scan): an allowlisted rare is kept, an ordinary rare is not", function()
    local w = makeWorld("Iter", true)
    emptyBags(w)
    w.env.ITEM_QUALITY_COLORS[3] = { hex = BLUE_HEX }
    local listed = next(w.addon.ROLL_ANY_QUALITY)
    H.notNil(listed, "the allowlist ships at least one id")
    w.env.__bags[0][1] = { id = listed, count = 1, link = blueLink(listed) }
    w.env.__bags[0][2] = { id = 50001, count = 1, link = blueLink(50001) }
    local snap = w.addon:_realBuildBagSnapshot()
    H.eq(snap[blueLink(listed)], 1, "the allowlisted rare survives the epic floor")
    H.eq(snap[blueLink(50001)], nil, "an ordinary rare is still excluded")
end)

H.test("BuildTradeableEpicCounts (real scan): an allowlisted rare in its trade window is counted", function()
    local w = makeWorld("Iter", true)
    emptyBags(w)
    w.env.ITEM_QUALITY_COLORS[3] = { hex = BLUE_HEX }
    local listed = next(w.addon.ROLL_ANY_QUALITY)
    -- BoP with the 2h window, exactly as the cache arrives from the chest
    w.env.__bags[0][1] = { id = listed, count = 1, link = blueLink(listed), bound = true, win = 7200 }
    w.env.__bags[0][2] = { id = 50001, count = 1, link = blueLink(50001), bound = true, win = 7200 }
    local counts = w.addon:_realBuildTradeableEpicCounts()
    H.eq(counts[blueLink(listed)], 1, "the cache is eligible loot, so a lot can be minted for it")
    H.eq(counts[blueLink(50001)], nil, "an ordinary rare BoP is not eligible loot")
end)

H.test("BuildBagSnapshot (real scan): test mode (minQuality 0) includes sub-epic items", function()
    local w = makeWorld("Iter", true)
    w.addon.db.testMode = true
    emptyBags(w)
    w.env.ITEM_QUALITY_COLORS[2] = { hex = GREEN_HEX }
    w.env.__bags[0][1] = { id = 50000, count = 2, link = greenLink(50000) }
    local snap = w.addon:_realBuildBagSnapshot()
    H.eq(snap[greenLink(50000)], 2, "green item included under test mode")
end)

-- ---------------------------------------------------------------------------
-- addon:BuildTradeableEpicCounts -- real scan (drives the wired scan tooltip)
-- ---------------------------------------------------------------------------
H.test("BuildTradeableEpicCounts (real scan, test mode): counts tradeable, excludes bound, notes soonest window", function()
    local w = makeWorld("Iter", true)
    w.addon.db.testMode = true
    emptyBags(w)
    putBag(w, 0, 1, 40001, 1)                                  -- plain tradeable -> counted
    putBag(w, 0, 2, 40002, 1, { bound = true })               -- permanently soulbound -> excluded
    putBag(w, 1, 1, 40003, 1, { bound = true, win = 3600 })   -- soulbound but in trade window -> counted
    local counts = w.addon:_realBuildTradeableEpicCounts()
    H.eq(counts[linkFor(40001)], 1, "plain tradeable counted")
    H.eq(counts[linkFor(40002)], nil, "permanently soulbound excluded")
    H.eq(counts[linkFor(40003)], 1, "windowed soulbound counted")
    H.eq(w.addon._soonestLootExpiry, 3600, "soonest trade-window expiry recorded")
end)

F.endSuite()
