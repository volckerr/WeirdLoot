-- Unit tests for the quest-starter roll block (Loot/LiveRoll.lua QUEST_STARTER): the server hides a
-- quest-starting drop from anyone whose start quest is in their log or turned in, so rolling on it
-- must be blocked in both states, for raiders and for the ML's own invisible phantom.
--
-- Run from the addon dir:  luajit tests/unit_queststarter.lua

local F = dofile("tests/_framework.lua").get()
F.beginSuite("Quest-starter roll block battery")
local makeWorld, eq, check, test = F.makeWorld, F.eq, F.check, F.test

-- quest log mock: entries = { {questId}, {header = true}, ... }; hidden = quests under collapsed headers
local function questLog(w, entries, hidden)
    w.env.GetNumQuestLogEntries = function()
        local quests = hidden or 0
        for _, e in ipairs(entries) do if not e.header then quests = quests + 1 end end
        return #entries, quests
    end
    w.env.GetQuestLogTitle = function(i)
        local e = entries[i]
        if not e then return nil end
        return "q", 80, nil, 0, e.header and 1 or nil, nil, nil, nil, (not e.header) and e[1] or nil
    end
end

local function queryMock(w, done)
    w.queries = 0
    w.env.QueryQuestsCompleted = function() w.queries = w.queries + 1 end
    w.env.GetQuestsCompleted = function() return done end
end

test("quest starter: start quest in the log blocks the drop, leaving it with the log in full view unblocks", function()
    local w = makeWorld("Saelinen", false)
    queryMock(w, {})
    questLog(w, { { header = true }, { 13604 } })
    w.addon:QUEST_LOG_UPDATE()
    eq(w.addon:RollSelfBlockReason(45506), "quest", "on the disc quest, no disc held: blocked")
    eq(w.addon:RollSelfBlockReason(45857), nil, "the 25-man disc has its own quest")
    eq(w.queries, 0, "accepting a quest asks the server nothing")
    questLog(w, { { header = true } })
    w.addon:QUEST_LOG_UPDATE()
    eq(w.queries, 1, "the quest leaving the log asks for the turned-in list")
    eq(w.addon:RollSelfBlockReason(45506), nil, "gone from the log and not turned in (abandoned): open")
end)

test("quest starter: a collapsed header keeps a quest seen earlier", function()
    local w = makeWorld("Saelinen", false)
    queryMock(w, {})
    questLog(w, { { header = true }, { 13372 } })     -- Focusing Iris key quest: the key is used up on accepting
    w.addon:QUEST_LOG_UPDATE()
    eq(w.addon:RollSelfBlockReason(44569), "quest", "on the Iris quest with no key held: blocked")
    questLog(w, { { header = true } }, 1)            -- header collapsed: one quest not listed
    w.addon:QUEST_LOG_UPDATE()
    eq(w.addon:RollSelfBlockReason(44569), "quest", "still blocked while its header is collapsed")
    eq(w.queries, 0, "a collapse is not a turn-in")
end)

test("quest starter: the turned-in list blocks the drop and re-checks an open card", function()
    local w = makeWorld("Saelinen", false)
    local done = {}
    queryMock(w, done)
    questLog(w, {})
    local pushed = {}
    w.addon.SetRollBannerCardDisabled = function(_, key, disabled) pushed[key] = disabled end
    w.addon.live.rolls["L:7"] = { id = "L:7", itemId = 45506, name = "Archivum Data Disc" }
    w.addon.live.rolls["L:8"] = { id = "L:8", itemId = 40064, name = "Thunderstorm Amulet" }
    w.addon:PLAYER_ENTERING_WORLD()
    check(w.queries >= 1, "zone-in asks for the turned-in list")
    eq(w.addon:RollSelfBlockReason(45506), nil, "before the answer: open")
    done[13604] = true
    w.addon:QUEST_QUERY_COMPLETE()
    eq(w.addon:RollSelfBlockReason(45506), "quest", "disc quest turned in: blocked")
    check(pushed["L:7"] and pushed["L:7"].MS, "the open disc card got MS disabled")
    check(not (pushed["L:7"] and pushed["L:7"].Pass), "Pass stays live")
    eq(pushed["L:8"], nil, "an unrelated card is left alone")
end)

test("quest starter: the ML's own invisible phantom is blocked once the ML is on or past the quest", function()
    local w = makeWorld("Kuyra", true)
    queryMock(w, { [13631] = true })
    questLog(w, {})
    w.addon:QUEST_QUERY_COMPLETE()
    eq(w.addon:RollSelfBlockReason(46052, true), "quest", "Reply-Code quest turned in: the ML cannot win the phantom")
    eq(w.addon:RollSelfBlockReason(46053, true), nil, "the 25-man code is a different quest")
end)

F.endSuite()
