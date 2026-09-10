-- Unit tests for addon.config.* (Config.lua) -- parsers, normalizers, lookup helpers.
-- The full world-builder is overkill here; these functions are pure-ish (some need a few
-- rosterside helpers). We build the minimal env the parsers touch.
--
-- Run from the addon dir:  luajit tests/unit_config.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("config unit battery")

-- Minimal env for Config. The real harness loads everything; here we mimic just enough.
local env = setmetatable({}, { __index = _G })
env._G = env
env.WeirdLoot = env.WeirdLoot or {}
env.LibStub = setmetatable({}, { __call = function(_, _) return nil end, __index = function() return nil end })
-- Core.lua line 31: addon.events = CreateFrame("Frame")
env.CreateFrame = function()
    local f = { __scripts = {} }
    local mt = { __index = function(t, k)
        if k == "RegisterEvent" then return function() end end
        if k == "Hide" then return function() end end
        if k == "Show" then return function() end end
        if k == "SetScript" then return function(_, _, fn) end end
        if k == "GetScript" then return function() return nil end end
        return function() return t end
    end }
    return setmetatable(f, mt)
end
env.GetTime = function() return 0 end
env.UnitGUID = function() return "Player-0-00000001" end
env.UnitClass = function() return "Warrior", "WARRIOR" end
env.UnitName = function() return "Tester" end
env.GetRealmName = function() return "TestRealm" end
env.time = function() return 0 end
env.randomseed = function() end
env.math = setmetatable({}, { __index = math })
env.StaticPopupDialogs = {}
env.DEFAULT_CHAT_FRAME = setmetatable({ AddMessage = function() end }, { __index = function() return function() end end })
env.SlashCmdList = {}
-- Core.lua's StaticPopup blocks call .Hide / .SetText / .SetFocus / :Click() / :GetText() etc. on
-- the edit box returned by StaticPopup_Show (when called). We never trigger those in unit_config,
-- but Core.lua line ~3800 references them at load time during a "save as preset" dialog stub.
env.StaticPopup_Show = function()
    local box = {
        SetText = function() end, SetFocus = function() end, HighlightText = function() end,
        GetText = function() return "" end,
    }
    return {
        button1 = { Click = function() end },
        editBox = box,
        GetParent = function() return { Hide = function() end } end,
        Hide = function() end,
        SetOwner = function() end, ClearAllPoints = function() end, SetPoint = function() end,
        SetHyperlink = function() end, Show = function() end,
    }
end
local private = {}

-- Config requires Core+Util+LootPrios loaded ahead of it (defaultItemInfo lives in Core).
for _, file in ipairs({ "Core.lua", "Data/LootPrios.lua", "Core/Util.lua", "Core/Config.lua" }) do
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)
    chunk("WeirdLoot", private)
end

local addon = env.WeirdLoot
local util = addon.util

-- Config functions need a config table to operate on; install a minimal one.
addon.config = {
    rosterEntries = {},
    roster = {},
    rosterImportText = "",
    lootPriorityText = "",
    namedItemsText = "",
    lootRules = {},
    namedRules = {},
}
addon.defaultRosterEntries = addon.defaultRosterEntries or {}

------------------------------------------------------------------------
-- NormalizeStatus
------------------------------------------------------------------------
H.test("NormalizeStatus: maps alt forms to designatedalt", function()
    H.eq(addon:NormalizeStatus("main"),       "main",          "main stays main")
    H.eq(addon:NormalizeStatus("MAIN"),       "main",          "case-insensitive")
    H.eq(addon:NormalizeStatus("designatedalt"), "designatedalt", "canonical form")
    H.eq(addon:NormalizeStatus("Designated Alt"), "designatedalt", "two-word form")
    H.eq(addon:NormalizeStatus("alt"),        "designatedalt", "alt short form")
    H.eq(addon:NormalizeStatus(""),           "nil",           "empty is nil")
    H.eq(addon:NormalizeStatus("garbage"),    "nil",           "unknown is nil")
    H.eq(addon:NormalizeStatus(nil),          "nil",           "nil input is nil")
end)

------------------------------------------------------------------------
-- NormalizeClassName
------------------------------------------------------------------------
H.test("NormalizeClassName: resolves known aliases", function()
    -- configClassAliases maps 'dk' / 'deathknight' / 'death knight' -> 'death knight'
    H.eq(addon:NormalizeClassName("dk"), "death knight", "dk -> death knight")
    H.eq(addon:NormalizeClassName("DK"), "death knight", "case-insensitive")
    H.eq(addon:NormalizeClassName("warrior"), "warrior", "warrior passes through")
    H.eq(addon:NormalizeClassName("not a class"), "not a class", "unknown stays")
end)

------------------------------------------------------------------------
-- ParseClassSpecToken
------------------------------------------------------------------------
H.test("ParseClassSpecToken: 'rest' is a special token", function()
    local p = addon:ParseClassSpecToken("rest")
    H.eq(p.isRest, true, "rest flagged as isRest")
end)
H.test("ParseClassSpecToken: empty input is rest", function()
    H.eq(addon:ParseClassSpecToken("").isRest, true, "empty is rest")
end)
H.test("ParseClassSpecToken: 'class' alone has no specName", function()
    local p = addon:ParseClassSpecToken("warrior")
    H.eq(p.className, "warrior", "class recognized")
    H.eq(p.specName, "", "no spec")
    H.eq(p.matchKeys[1], "warrior", "match key 1: class alone")
end)
H.test("ParseClassSpecToken: 'class spec' parses both", function()
    local p = addon:ParseClassSpecToken("mage fire")
    H.eq(p.className, "mage", "class")
    H.eq(p.specName, "fire", "spec")
    H.eq(p.matchKeys[1], "mage fire", "match key 1: 'class spec'")
    H.eq(p.matchKeys[2], "fire mage", "match key 2: 'spec class'")
end)
H.test("ParseClassSpecToken: 'spec class' (suffix form)", function()
    -- "fury warrior" matches because of the suffix-suffix branch
    local p = addon:ParseClassSpecToken("fury warrior")
    H.eq(p.className, "warrior", "suffix class recognized")
    H.eq(p.specName, "fury", "spec is the prefix")
end)

------------------------------------------------------------------------
-- ParseRosterImport
------------------------------------------------------------------------
H.test("ParseRosterImport: parses a CSV roster with name, descriptor, status", function()
    local text = "alice, warrior fury, main\nbob, mage fire, designatedalt\n"
    local entries = addon:ParseRosterImport(text)
    H.eq(#entries, 2, "two entries")
    H.eq(entries[1].name, "alice", "alice")
    H.eq(entries[1].className, "warrior", "alice class")
    H.eq(entries[1].specName, "fury", "alice spec")
    H.eq(entries[1].status, "main", "alice status")
    H.eq(entries[2].status, "designatedalt", "bob alt")
end)

H.test("ParseRosterImport: skips blank-name lines", function()
    local entries = addon:ParseRosterImport(", , \nalice, warrior fury, main\n, , \n")
    H.eq(#entries, 1, "blank lines ignored")
    H.eq(entries[1].name, "alice", "only alice kept")
end)

H.test("ParseRosterImport: missing status defaults to nil", function()
    local entries = addon:ParseRosterImport("alice, warrior fury")
    H.eq(entries[1].status, "nil", "missing status -> nil")
end)

------------------------------------------------------------------------
-- NormalizeRosterEntries
------------------------------------------------------------------------
H.test("NormalizeRosterEntries: dedupes by lowercase name, sorted", function()
    local out = addon:NormalizeRosterEntries({
        { name = "Bob",   className = "warrior", specName = "fury", status = "main" },
        { name = "alice", className = "mage",    specName = "fire", status = "main" },
        { name = "BOB",   className = "warrior", specName = "arms", status = "main" },
    })
    H.eq(#out, 2, "Bob deduped with BOB")
    H.eq(out[1].name, "alice", "alphabetical: alice first")
    H.eq(out[2].name, "Bob",   "alphabetical: bob second")
end)

H.test("NormalizeRosterEntries: normalizes status via NormalizeStatus", function()
    local out = addon:NormalizeRosterEntries({
        { name = "x", className = "", specName = "", status = "alt" },
    })
    H.eq(out[1].status, "designatedalt", "alt -> designatedalt")
end)

------------------------------------------------------------------------
-- ParseTieredRuleText (via ParseNamedToken for the named-items case)
------------------------------------------------------------------------
H.test("ParseTieredRuleText: parses named rules with LC/loot-council markers", function()
    local text = "Shadowmourne, alice / bob > carol > LC\nAmanitar, dave > eve\n"
    local rules = addon:ParseTieredRuleText(text, addon.ParseNamedToken)
    H.notNil(rules["shadowmourne"], "Shadowmourne rule parsed")
    H.notNil(rules["amanitar"], "Amanitar rule parsed")
end)

H.test("ParseTieredRuleText: an item name containing a comma keeps its whole name and its rule", function()
    local text = "Voldrethar, Dark Blade of Oblivion, styrza > fury\n"
    local rules = addon:ParseTieredRuleText(text, addon.ParseNamedToken)
    H.eq(rules["voldrethar"], nil, "the name is not truncated at the first comma")
    local rule = rules["voldrethar, dark blade of oblivion"]
    H.notNil(rule, "the full item name keys the rule")
    H.eq(#rule.tiers, 2, "both tiers survive")
    H.eq(rule.tiers[1].entries[1].playerKey, "styrza", "first tier is the real prio, not the item name tail")
end)

H.test("ParseTieredRuleText: a trailing comma does not swallow the rule", function()
    local rules = addon:ParseTieredRuleText("Amanitar, dave > eve,\n", addon.ParseNamedToken)
    H.notNil(rules["amanitar"], "rule still parsed")
end)

H.test("ParseTieredRuleText: returns empty map for empty input", function()
    local rules = addon:ParseTieredRuleText("", addon.ParseNamedToken)
    -- a rule map is a table; size 0 is acceptable
    local count = 0; for _ in pairs(rules) do count = count + 1 end
    H.eq(count, 0, "no rules from empty text")
end)

------------------------------------------------------------------------
-- ItemHasPriority / GetLootRule / GetNamedRule
------------------------------------------------------------------------
H.test("ItemHasPriority: false when item has no rules", function()
    addon.config.lootRules = {}
    addon.config.namedRules = {}
    H.check(not addon:ItemHasPriority("Random Item"), "unknown item has no priority")
    H.check(not addon:ItemHasPriority(""), "empty name has no priority")
end)
H.test("ItemHasPriority: true when item is in the lootRules map", function()
    addon.config.lootRules = { ["shadowmourne"] = { tiered = true } }
    addon.config.namedRules = {}
    H.truthy(addon:ItemHasPriority("Shadowmourne"), "Shadowmourne has a loot rule")
    H.truthy(addon:ItemHasPriority("SHADOWMOURNE"), "case-insensitive lookup")
end)
H.test("ItemHasPriority: true when item is in the namedRules map", function()
    addon.config.lootRules = {}
    addon.config.namedRules = { ["amanitar"] = { isLootCouncil = true } }
    H.truthy(addon:ItemHasPriority("Amanitar"), "Amanitar has a named rule")
end)

-- ---------------------------------------------------------------------------
-- The SHIPPED default lists (Data/LootPrios.lua). These are generated from the guild sheet by
-- tools/sheet_named_items.py, so a shorthand the translator does not know would otherwise sail
-- through as a rule that silently matches nobody, which is the bug these tests exist to stop.
-- ---------------------------------------------------------------------------
H.test("shipped spec list: every entry resolves to a real class", function()
    local rules = addon:ParseTieredRuleText(addon.defaultLootPriorityText or "", addon.ParseClassSpecToken)
    local count, bad = 0, {}
    for itemName, rule in pairs(rules) do
        for _, tier in ipairs(rule.tiers or {}) do
            for _, entry in ipairs(tier.entries or {}) do
                count = count + 1
                if not entry.isRest and (entry.className or "") == "" then
                    bad[#bad + 1] = itemName .. " -> " .. tostring(entry.raw)
                end
            end
        end
    end
    H.check(count > 0, "the shipped spec list is not empty")
    H.eq(#bad, 0, "unparsed spec tokens: " .. table.concat(bad, ", "))
end)

H.test("shipped named list: no class or spec word is filed as a player", function()
    local rules = addon:ParseTieredRuleText(addon.defaultNamedItemsText or "", addon.ParseNamedToken)
    -- A name that parses as a class/spec is a routing mistake in the extractor, not a raider.
    local bad = {}
    for itemName, rule in pairs(rules) do
        for _, tier in ipairs(rule.tiers or {}) do
            for _, entry in ipairs(tier.entries or {}) do
                if entry.playerKey and entry.playerKey ~= "" then
                    local parsed = addon:ParseClassSpecToken(entry.playerKey)
                    if parsed and (parsed.className or "") ~= "" then
                        bad[#bad + 1] = itemName .. " -> " .. entry.playerKey
                    end
                end
            end
        end
    end
    H.eq(#bad, 0, "class text filed as raider names: " .. table.concat(bad, ", "))
end)

H.test("shipped spec list: the generated-region markers are ignored, not read as items", function()
    local rules = addon:ParseTieredRuleText(addon.defaultLootPriorityText or "", addon.ParseClassSpecToken)
    for itemName in pairs(rules) do
        H.check(not string.find(itemName, "###", 1, true), "marker leaked in as an item: " .. itemName)
    end
end)


F.endSuite()