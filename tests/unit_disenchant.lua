-- Disenchant from the no-winner card (Loot/Disenchant.lua): the skill rule, raiders' Enchanting reports
-- to the ML, the candidate list, the send (owed as a win, flagged for disenchanting) with its own
-- 10 s whisper, and the card's Disenchant button + flyout on the real banner.
--
-- Run from the addon dir:  luajit tests/unit_disenchant.lua

local F = dofile("tests/_framework.lua").get()
F.beginSuite("disenchant battery")
local test, eq, check = F.test, F.eq, F.check

local function roster(w, members)   -- members = { { name, class } }, index 1 = ML
    w.env.GetNumRaidMembers = function() return #members end
    w.env.GetRaidRosterInfo = function(i)
        local m = members[i]
        if not m then return nil end
        return m[1], (i == 1) and 2 or 0, 1, 80, m[2], nil, nil, m[3] ~= false and 1 or nil   -- m[3] false: offline
    end
end

local function itemAs(w, quality, itemLevel, itemType)
    local orig = w.env.GetItemInfo
    w.env.GetItemInfo = function(id)
        local name, link = orig(id)
        return name, link, quality, itemLevel, 80, itemType or "Armor", "Cloth", 1, "INVTYPE_SHOULDER", "x", 0
    end
end

local function noWinnerLot(w, itemId)
    F.setBag(w, itemId, 1); F.bagUpdate(w)
    local lot = F.openLot(w, itemId)
    w.addon:StartLiveRoll(lot.id)
    w.addon:ResolveLiveRoll(lot.id)
    return lot
end

local function captureWhispers(w)
    local out = {}
    w.env.ChatThrottleLib = nil
    w.env.SendChatMessage = function(msg, kind, _, target)
        if kind == "WHISPER" then out[#out + 1] = { msg = msg, target = target } end
    end
    return out
end

test("skill rule: one baseline per quality (Northrend); only armor and weapons", function()
    local w = F.makeWorld("Masterlooter", true)
    itemAs(w, 4, 226); eq(w.addon:DisenchantSkillFor(40005), 375, "an epic needs 375")
    itemAs(w, 4, 120); eq(w.addon:DisenchantSkillFor(40005), 375, "whatever its level")
    itemAs(w, 3, 187); eq(w.addon:DisenchantSkillFor(40005), 325, "a blue needs 325")
    itemAs(w, 2, 60); eq(w.addon:DisenchantSkillFor(40005), 350, "a green needs 350")
    itemAs(w, 4, 226, "Weapon"); eq(w.addon:DisenchantSkillFor(40005), 375, "weapons too")
    itemAs(w, 4, 226, "Consumable"); eq(w.addon:DisenchantSkillFor(40005), nil, "not a consumable")
    itemAs(w, 5, 245); eq(w.addon:DisenchantSkillFor(40005), nil, "not a legendary")
    itemAs(w, 1, 200); eq(w.addon:DisenchantSkillFor(40005), nil, "not a white item")
end)

test("skill read: the Enchanting line by its localized name, 0 without it", function()
    local w = F.makeWorld("Raidertwo", false)
    eq(w.addon:EnchantingSkill(), 0, "no professions: 0")
    w.env.__skills = { { "Professions", true }, { "Tailoring", false, 450 }, { "Enchanting", false, 440 } }
    eq(w.addon:EnchantingSkill(), 440, "reads the Enchanting rank")
end)

test("raider report: whispered to the ML once per session; the ML keeps it", function()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    raider.env.__skills = { { "Enchanting", false, 450 } }
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    local sent = 0
    for _, m in ipairs(F.WIRE) do if m.value and m.value[1] == "ENCH" then sent = sent + 1 end end
    eq(sent, 1, "one ENCH whisper on syncing the session")
    F.flushWireTo(ml)
    eq(ml.addon:GetCurrentSession().enchanting["raidertwo"], 450, "the ML stored it")
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    sent = 0
    for _, m in ipairs(F.WIRE) do if m.value and m.value[1] == "ENCH" then sent = sent + 1 end end
    eq(sent, 0, "a later snapshot of the same session sends nothing")
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    sent = 0
    for _, m in ipairs(F.WIRE) do if m.value and m.value[1] == "ENCH" then sent = sent + 1 end end
    eq(sent, 1, "a new session hears it again")
end)

test("a non-enchanter reports 0 with its free slots", function()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    raider.env.__bags = { [0] = { size = 16 } }
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    F.flushWireTo(ml)
    eq(ml.addon:GetCurrentSession().enchanting["raidertwo"], 0, "Enchanting 0")
    eq(ml.addon:DisenchanterFreeSlots("Raidertwo"), 16, "free slots known")
end)

test("candidates: raid members whose skill is enough, highest first, the ML read directly", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" }, { "Halricb", "Paladin" }, { "Seme", "Mage" }, { "Low", "Priest" } })
    w.env.__skills = { { "Enchanting", false, 380 } }
    w.addon:OnEnchantingReport("Halricb", "450")
    w.addon:OnEnchantingReport("Low", "300")
    w.addon:OnEnchantingReport("Gone", "450")             -- reported, but no longer in the raid
    local list, need = w.addon:DisenchantCandidates(40005)
    eq(need, 375, "an epic at 200 needs 375")
    eq(#list, 2, "Halricb and the ML; Low is short, Gone left, Seme never reported")
    eq(list[1].name, "Halricb", "highest skill first")
    eq(list[1].roll, 450, "with the skill shown")
    eq(list[2].name, "Masterlooter", "the ML's own skill counts")
end)

test("send: owed to the disenchanter, one whisper 10 s after the last send, worded for disenchanting", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    local whispers = captureWhispers(w)
    w.addon.payout.payoutActive = true
    local a, b = noWinnerLot(w, 40005), noWinnerLot(w, 40006)
    w.addon:SendForDisenchant(a.id, "Halricb")
    F.pump(w, 6)
    w.addon:SendForDisenchant(b.id, "Halricb")
    F.pump(w, 6)
    eq(#whispers, 0, "still waiting: the second send restarted the 10 s wait")
    F.pump(w, 5)
    eq(#whispers, 1, "one whisper once the sends stop")
    check(whispers[1].target == "Halricb" and whispers[1].msg:find("to disenchant", 1, true)
        and whispers[1].msg:find("Hitem:40005", 1, true) and whispers[1].msg:find("Hitem:40006", 1, true),
        "it lists both items for disenchanting: " .. tostring(whispers[1] and whispers[1].msg))
    eq(w.addon.lootCore:OwedCountFor("Halricb"), 2, "both owed in the ledger, traded like a win")
end)

test("send: a won item and a disenchant item for the same player share one whisper", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    local whispers = captureWhispers(w)
    w.addon.payout.payoutActive = true
    w.addon:SendForDisenchant(noWinnerLot(w, 40005).id, "Halricb")
    w.addon.payout:Owe("Halricb", 40007, 1, "[Won]")      -- a normal win inside the disenchant wait
    F.pump(w, 3)
    eq(#whispers, 0, "a pending disenchant send holds the whisper to 10 s")
    F.pump(w, 8)
    eq(#whispers, 1, "one whisper")
    check(whispers[1].msg:find("collect: [Won]. To disenchant: ", 1, true) ~= nil, "both parts: " .. tostring(whispers[1].msg))
end)

local function bannerML()
    local w = F.makeWorld("BannerML", true)
    F.loadBanner(w)
    w.addon.db.options.bannerInstant = true
    return w
end

local function shownCard(w, key)
    for _ = 1, 60 do
        F.pump(w, 0.001)
        for _, f in ipairs(w.env.WeirdLootAwardedBanner.LootFrames) do
            if f.alive and f.rowKey == key then return f end
        end
    end
end

local LINK = "|cffa335ee|Hitem:40005:0:0:0:0:0:0:0|h[Blade of Test]|h|r"

test("card: Disenchant sits right of Reroll; it opens the flyout and a row sends the copy", function()
    local w = bannerML()
    local sent
    w.addon:AddLootBannerItem({ key = "L:21", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deNeed = 375,
        deCandidates = { { name = "Halricb", class = "Paladin", roll = 450 } },
        onDisenchant = function(who) sent = who end })
    local f = shownCard(w, "L:21")
    check(f and f.DEButton:IsShown(), "the Disenchant button shows")
    check(f.DEButton:GetButtonState() ~= "DISABLED", "enabled with a candidate")
    check(not f.LCFlyout:IsShown(), "the flyout waits for the button")
    f.DEButton:GetScript("OnClick")(f.DEButton)
    check(f.LCFlyout:IsShown(), "the button opens the flyout")
    check((f.LCFlyoutHeader.__text or ""):find("Disenchant to:", 1, true) ~= nil, "headed Disenchant to:")
    f.LCRows[1]:GetScript("OnClick")(f.LCRows[1])
    eq(sent, "Halricb", "the row sends it to that raider")
end)

test("card: nobody can disenchant it -> greyed out, saying the skill needed", function()
    local w = bannerML()
    w.addon:AddLootBannerItem({ key = "L:22", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deNeed = 375, deCandidates = {}, onDisenchant = function() end })
    local f = shownCard(w, "L:22")
    check(f and f.DEButton:IsShown(), "still shown")
    eq(f.DEButton:GetButtonState(), "DISABLED", "but disabled")
    check((f.DEButton.reason or ""):find("needs Enchanting 375", 1, true) ~= nil, "the hover says why")
end)

test("card: not disenchantable -> no button; sent -> reads '<name> to disenchant'", function()
    local w = bannerML()
    w.addon:AddLootBannerItem({ key = "L:23", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deCandidates = {}, onDisenchant = function() end })
    local f = shownCard(w, "L:23")
    check(f and not f.DEButton:IsShown(), "no button for an item that cannot be disenchanted")
    w.addon:AddLootBannerItem({ key = "L:23", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deTo = "Halricb", deToClass = "Paladin" })
    check((f.PlayerName.__text or ""):find("to disenchant", 1, true) ~= nil, "the card says who: " .. tostring(f.PlayerName.__text))
end)

test("default: the last pick is remembered, offered only when they can disenchant this one too", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    w.addon:SendForDisenchant(noWinnerLot(w, 40005).id, "Halricb")
    eq(w.addon:GetCurrentSession().deDefault, "Halricb", "the pick is remembered for the session")
    eq(w.addon:DisenchantDefault({ { name = "Seme" }, { name = "Halricb" } }), "Halricb", "offered when listed")
    eq(w.addon:DisenchantDefault({ { name = "Seme" } }), nil, "not when they cannot take this item")
end)

test("card: a second Disenchant click sends to the remembered disenchanter", function()
    local w = bannerML()
    local sent
    w.addon:AddLootBannerItem({ key = "L:24", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deNeed = 375,
        deCandidates = { { name = "Seme", roll = 460 }, { name = "Halricb", roll = 450 } },
        getDEDefault = function() return "Halricb" end,
        onDisenchant = function(who) sent = who end })
    local f = shownCard(w, "L:24")
    f.DEButton:GetScript("OnClick")(f.DEButton)
    check(f.LCFlyout:IsShown() and sent == nil, "the first click only opens the flyout")
    f.DEButton:GetScript("OnClick")(f.DEButton)
    eq(sent, "Halricb", "the second click sends to the default")
    check(not f.LCFlyout:IsShown(), "and closes the flyout")
end)

test("card: with no default, a second click just closes the flyout", function()
    local w = bannerML()
    local sent
    w.addon:AddLootBannerItem({ key = "L:25", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deNeed = 375, deCandidates = { { name = "Seme", roll = 460 } },
        getDEDefault = function() return nil end, onDisenchant = function(who) sent = who end })
    local f = shownCard(w, "L:25")
    f.DEButton:GetScript("OnClick")(f.DEButton)
    f.DEButton:GetScript("OnClick")(f.DEButton)
    check(not f.LCFlyout:IsShown() and sent == nil, "closed, nothing sent")
end)

test("raiders get a 'to disenchant' card, not a win card", function()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    F.startSession(ml)
    local lot = noWinnerLot(ml, 40005)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    raider.addon._bannerItems = {}
    ml.addon:SendForDisenchant(lot.id, "Halricb")
    F.flushWireTo(raider)
    local card = raider.addon._bannerItems[#raider.addon._bannerItems]
    check(card and card.deTo == "Halricb" and card.noWinner, "the raider's card names the disenchanter")
    check(card and not card.winners, "and is not a win card")
end)

test("a reroll or a new session forgets the disenchant mark", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    local lot = noWinnerLot(w, 40005)
    w.addon:SendForDisenchant(lot.id, "Halricb")
    eq(w.addon:DisenchantTarget(lot.id), "Halricb", "marked")
    w.addon:UnlockSessionRoll(lot.id)
    eq(w.addon:DisenchantTarget(lot.id), nil, "a reroll clears it")
    w.addon:StartLiveRoll(lot.id); w.addon:ResolveLiveRoll(lot.id)
    w.addon:SendForDisenchant(lot.id, "Halricb")
    F.startSession(w)
    eq(w.addon:DisenchantTarget(lot.id), nil, "a new session clears it")
end)

test("a corpse copy sent to disenchant gets no 'You won' whisper on delivery", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    local whispers = captureWhispers(w)
    local lot = w.addon.lootCore:MintPhantom(40431, 1)
    w.addon:StartLiveRoll(lot.id); w.addon:ResolveLiveRoll(lot.id)
    w.addon:SendForDisenchant(lot.id, "Halricb")
    eq(#whispers, 1, "told at once that it is coming to disenchant")
    w.addon:OnPhantomSendCleared(lot.id, "Halricb")
    eq(#whispers, 1, "and no win whisper when it lands")
end)

test("greens prompt: one row per raider who can disenchant the green; a row sets the disenchanter", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" }, { "Halricb", "Paladin" }, { "Low", "Priest" } })
    itemAs(w, 2, 182, "Weapon")
    w.addon:OnEnchantingReport("Halricb", "460")
    w.addon:OnEnchantingReport("Low", "300")
    w.addon.RouteLootSlots = function() end
    w.addon:PromptGreensDisenchanter(36486, "[Ornate Pugio]")
    local f = w.addon._greensPrompt
    check(f and f:IsShown(), "the prompt opens")
    check(f.rows[1] and f.rows[1]:IsShown() and f.rows[1].name == "Halricb", "Halricb is offered")
    check(not (f.rows[2] and f.rows[2]:IsShown()), "Low (300) is not: the green needs 350")
    f.rows[1]:GetScript("OnClick")(f.rows[1])
    eq(w.addon:GetCurrentSession().deer, "Halricb", "the pick sets the disenchanter")
    check(not f:IsShown(), "and closes the prompt")
end)

test("greens prompt: nobody can disenchant it -> says so, Keep only", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" } })
    itemAs(w, 2, 182, "Weapon")
    w.addon.RouteLootSlots = function() end
    w.addon:PromptGreensDisenchanter(36486, "[Ornate Pugio]")
    local f = w.addon._greensPrompt
    eq(f.item.__text, "No one can disenchant greens.", "says so")
    eq(f.title.__text, "Who gets greens?", "the title asks who gets them")
    f.keep:GetScript("OnClick")(f.keep)
    check(w.addon:GetCurrentSession().deerSelf, "Keep: greens go to the ML")
end)

test("card: the remembered disenchanter is lit, with a hint for the second click", function()
    local w = bannerML()
    w.addon:AddLootBannerItem({ key = "L:26", link = LINK, icon = "x", quantity = 1, noWinner = true,
        onReroll = function() end, deNeed = 375,
        deCandidates = { { name = "Seme", roll = 460 }, { name = "Halricb", roll = 450 } },
        getDEDefault = function() return "Halricb" end, onDisenchant = function() end })
    local f = shownCard(w, "L:26")
    f.DEButton:GetScript("OnClick")(f.DEButton)
    check(f.LCHint:IsShown() and (f.LCHint.__text or ""):find("again for Halricb", 1, true) ~= nil, "hint names the default")
    check(f.LCRows[2].textY == 0, "the remembered row is lit, not sunk")
end)

test("greens prompt: a report arriving while it is open adds that raider", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" }, { "Halricb", "Paladin" }, { "Seme", "Mage" } })
    itemAs(w, 2, 182, "Weapon")
    w.addon:OnEnchantingReport("Halricb", "460")
    w.addon.RouteLootSlots = function() end
    w.addon:PromptGreensDisenchanter(36486, "[Ornate Pugio]")
    local f = w.addon._greensPrompt
    check(not (f.rows[2] and f.rows[2]:IsShown()), "one name at first")
    w.addon:OnEnchantingReport("Seme", "410")
    check(f.rows[2] and f.rows[2]:IsShown() and f.rows[2].name == "Seme", "Seme appears without reopening")
end)

test("reset settings: options back to defaults; lists and the on/off switch kept", function()
    local w = F.makeWorld("Masterlooter", true)
    local opt = w.addon.db.options
    opt.rollDuration = 1800; opt.bannerInstant = true; opt.whitelistText = "Item A"; opt.disabled = false
    w.addon.db.autoRoll = true
    w.addon:ResetOptions()
    eq(opt.rollDuration, w.addon.OPTION_DEFAULTS.rollDuration, "roll duration back to default")
    eq(opt.bannerInstant, false, "banner look back to default")
    eq(w.addon.db.autoRoll, false, "auto-open back off")
    eq(opt.whitelistText, "Item A", "the white list is kept")
end)

test("Choose disenchanter with no item lists raiders at the green baseline (350)", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" }, { "Halricb", "Paladin" }, { "Low", "Priest" } })
    w.addon:OnEnchantingReport("Halricb", "350")
    w.addon:OnEnchantingReport("Low", "349")
    w.addon.RouteLootSlots = function() end
    w.addon:PromptGreensDisenchanter()
    local f = w.addon._greensPrompt
    check(f.rows[1] and f.rows[1]:IsShown() and f.rows[1].name == "Halricb", "Halricb at 350")
    check(not (f.rows[2] and f.rows[2]:IsShown()), "not Low at 349")
end)

test("candidates: an offline raider is not offered", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    roster(w, { { "Masterlooter", "Warrior" }, { "Halricb", "Paladin", false } })
    w.addon:OnEnchantingReport("Halricb", "460")
    local list = w.addon:DisenchantCandidatesAt(350)
    eq(#list, 0, "Halricb is offline")
end)

-- free bag slots: sent with the report and again after an item comes from the ML
local function enchSends()
    local out = {}
    for _, m in ipairs(F.WIRE) do if m.value and m.value[1] == "ENCH" then out[#out + 1] = m end end
    return out
end

test("bags: the report carries free slots; the ML shows them coloured", function()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    raider.env.__skills = { { "Enchanting", false, 450 } }
    raider.env.__bags = { [0] = { size = 16 }, [1] = { size = 4, [1] = { id = 1 }, [2] = { id = 2 } } }
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    F.flushWireTo(ml)
    eq(ml.addon:DisenchanterFreeSlots("Raidertwo"), 18, "16 + 2 free")
    check(ml.addon:FreeSlotsText("Raidertwo"):find("80cc80", 1, true) and ml.addon:FreeSlotsText("Raidertwo"):find("18 free"), "mild green at 10 or more")
    ml.addon:GetCurrentSession().deBags["raidertwo"] = 7
    check(ml.addon:FreeSlotsText("Raidertwo"):find("ffd200"), "yellow under 10")
    ml.addon:GetCurrentSession().deBags["raidertwo"] = 2
    check(ml.addon:FreeSlotsText("Raidertwo"):find("ff4040"), "red under 5")
    check(ml.addon:FreeSlotsText("Nobody"):find("-"), "unreported shows -")
end)

local function watchWorld()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    raider.env.__skills = { { "Enchanting", false, 450 } }
    raider.env.__bags = { [0] = { size = 16 } }
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    F.flushWireTo(ml)
    F.clearWire()
    return ml, raider
end

local function bagChange(raider) raider.addon:BAG_UPDATE() end

test("bag watch: not picked -> bag changes send nothing", function()
    local ml, raider = watchWorld()
    raider.env.__bags[0][1] = { id = 9 }; bagChange(raider)
    F.advanceClock(6); F.pump(raider)
    eq(#enchSends(), 0, "nothing")
end)

test("bag watch: the greens disenchanter re-sends 5 s after the bags settle, once, only on a change", function()
    local ml, raider = watchWorld()
    ml.addon:SetGreensDisenchanter("Raidertwo", true)
    F.flushWireTo(raider)
    check(raider.addon:IsWatchedDisenchanter(), "told it is watched")
    F.clearWire()
    raider.env.__bags[0][1] = { id = 9 }; bagChange(raider)
    F.advanceClock(3); F.pump(raider)
    raider.env.__bags[0][2] = { id = 9 }; bagChange(raider)   -- a second change pushes the deadline back
    F.advanceClock(3); F.pump(raider)
    eq(#enchSends(), 0, "still settling")
    F.advanceClock(3); F.pump(raider)
    eq(#enchSends(), 1, "one report after the bags went quiet")
    F.flushWireTo(ml)
    eq(ml.addon:DisenchanterFreeSlots("Raidertwo"), 14, "the ML has the new count")
    F.clearWire()
    bagChange(raider)                                          -- a change event with the same count
    F.advanceClock(6); F.pump(raider)
    eq(#enchSends(), 0, "unchanged count: nothing sent")
end)

test("bag watch: the flyout's remembered pick is watched too; a new pick or session ends it", function()
    local ml, raider = watchWorld()
    ml.addon:GetCurrentSession().deDefault = "Raidertwo"
    ml.addon:SendDEWatch()
    F.flushWireTo(raider)
    check(raider.addon:IsWatchedDisenchanter(), "remembered epic pick: watched")
    F.clearWire()
    ml.addon:SetGreensDisenchanter("Someoneelse", true)        -- epic pick unchanged: still watched
    F.flushWireTo(raider)
    check(raider.addon:IsWatchedDisenchanter(), "still the epic pick")
    ml.addon:GetCurrentSession().deDefault = "Someoneelse"
    ml.addon:SendDEWatch()
    F.flushWireTo(raider)
    check(not raider.addon:IsWatchedDisenchanter(), "no longer picked")
    ml.addon:SetGreensDisenchanter("Raidertwo", true)
    F.flushWireTo(raider)
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    check(not raider.addon:IsWatchedDisenchanter(), "a new session drops the old watch")
end)

test("bag watch: a watched raider who reloaded is told again on its report", function()
    local ml, raider = watchWorld()
    ml.addon:SetGreensDisenchanter("Raidertwo", true)
    raider.addon._deWatch, raider.addon._enchSentEpoch = nil, nil   -- the reload
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    F.flushWireTo(ml)
    F.flushWireTo(raider)
    check(raider.addon:IsWatchedDisenchanter(), "watched again after the report")
end)

test("bag watch: a holder (no Enchanting) is watched like a disenchanter", function()
    F.clearWire()
    local ml = F.makeWorld("Masterlooter", true)
    local raider = F.makeWorld("Raidertwo", false)
    raider.env.__bags = { [0] = { size = 16 } }
    F.startSession(ml)
    F.clearWire(); ml.addon:BroadcastSession(); F.flushWireTo(raider)
    ml.addon:SetGreensDisenchanter("Raidertwo", true); F.flushWireTo(raider)
    F.clearWire()
    raider.env.__bags[0][1] = { id = 9 }; bagChange(raider)
    F.advanceClock(6); F.pump(raider)
    eq(#enchSends(), 1, "re-sent")
end)

local function holderRaid(w, bags)
    roster(w, { { "Masterlooter", "Warrior" }, { "Aa", "Mage" }, { "Bb", "Priest" }, { "Cc", "Rogue" },
        { "Dd", "Druid" }, { "Ee", "Shaman" }, { "Ff", "Hunter" }, { "Gg", "Paladin", false } })
    local s = w.addon:GetCurrentSession()
    s.enchanting, s.deBags = {}, bags
end

test("holders: nobody can disenchant -> the most free first, 5 or more free, online, top 5, not the ML", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    holderRaid(w, { aa = 10, bb = 40, cc = 4, dd = 20, ee = 30, ff = 50, gg = 99, masterlooter = 90 })
    local list = w.addon:GreensHolderCandidates()
    local names = {}
    for _, c in ipairs(list) do names[#names + 1] = c.name end
    eq(table.concat(names, ","), "Ff,Bb,Ee,Dd,Aa", "sorted by free; Cc under 5, Gg offline, ML left out")
end)

test("holders: the box lists them under 'Send greens to:'; a pick says 'Greens to' on the Master tab", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    holderRaid(w, { bb = 40 })
    w.addon:PromptGreensDisenchanter()
    local f = w.addon._greensPrompt
    check(f and f:IsShown(), "box shown")
    check(f.rows[1] and f.rows[1]:IsShown() and f.rows[1].name == "Bb", "Bb offered as holder")
    check(not w.addon:CanDisenchantGreens("Bb"), "Bb cannot disenchant")
end)

test("holders: nobody has room, the ML included -> no box, one chat line per session", function()
    local w = F.makeWorld("Masterlooter", true)
    F.startSession(w)
    holderRaid(w, { bb = 0 })
    w.env.__bags = { [0] = { size = 1, [1] = { id = 9 } } }
    local said = 0
    local orig = w.addon.Print
    w.addon.Print = function(self, msg) if tostring(msg):find("Everyone's bags are full", 1, true) then said = said + 1 end end
    w.addon:PromptGreensDisenchanter()
    w.addon:PromptGreensDisenchanter()
    w.addon.Print = orig
    check(not (w.addon._greensPrompt and w.addon._greensPrompt:IsShown()), "no box")
    eq(said, 1, "said once")
end)

F.endSuite()
