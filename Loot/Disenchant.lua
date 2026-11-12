-- Disenchant a drop nobody rolled for. Raiders whisper their Enchanting skill to the loot master; the ML's
-- "No one rolled" card offers the raiders whose skill can disenchant that item, and a pick hands the copy
-- to them through the loot-council award path (owed and traded like a win, or sent off the corpse). The
-- payout marks the copy as for disenchanting, so its come-trade whisper says so.

local addon = WeirdLoot
local util = addon.util

-- Enchanting a raider needs to be offered as a disenchanter: one baseline per quality, the skill that
-- disenchants any Northrend item of it (greens 350, blues 325, epics 375). Lower-level items need less,
-- but a raid's disenchanter is someone who can take everything that drops.
local DE_BASELINE = { [2] = 350, [3] = 325, [4] = 375 }
local GREEN_BASELINE = DE_BASELINE[2]

-- The baseline for itemId, or nil when it cannot be disenchanted (not armor or a weapon, below green,
-- above epic) or is not cached yet.
function addon:DisenchantSkillFor(itemId)
    local _, _, quality, _, _, itemType = GetItemInfo(itemId)
    local need = quality and DE_BASELINE[quality]
    if not need then return nil end
    local weapon, armor = GetAuctionItemClasses()
    if itemType ~= weapon and itemType ~= armor then return nil end
    return need
end

-- This character's Enchanting rank, 0 without it. The skill line name is localized; the Enchanting
-- spell (7411) carries the same localized name.
function addon:EnchantingSkill()
    local enchanting = GetSpellInfo(7411)
    for i = 1, (GetNumSkillLines() or 0) do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if not isHeader and name == enchanting then return rank or 0 end
    end
    return 0
end

-- Free general bag slots (bags 0-4). Profession bags are skipped: gear to disenchant cannot go in them.
function addon:FreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local n, bagType = GetContainerNumFreeSlots(bag)
        if (bagType or 0) == 0 then free = free + (n or 0) end
    end
    return free
end

-- Raider: whisper the ML our Enchanting and free bag slots once per session, when we first sync it (a
-- join, a late sync or a reload all land here). Professions do not change mid-raid, so nothing listens
-- for skill changes; non-enchanters send 0 with their bags. again: our free slots changed while we are a watched
-- disenchanter, so re-send them (only once this session's report has gone out).
function addon:ReportEnchanting(again)
    if self:IsAuthorizedLootMaster() then return end
    local ml = self:GetLootMasterName()
    local session = self:GetCurrentSession()
    if not ml or ml == "" or not session.active then return end
    if (session.id == self._enchSentEpoch) ~= (again and true or false) then return end
    self._enchSentEpoch = session.id
    -- everyone reports: the free slots let the ML hand greens to a holder when nobody can disenchant
    self._bagsSent = self:FreeBagSlots()
    self:SendLargeMessage("ENCH", { self:EnchantingSkill(), self._bagsSent }, "WHISPER", ml)
end

-- Raider: while the ML has us down as a disenchanter (greens, or the flyout's remembered pick), re-send our
-- free slots once the bags settle after any change: trades, corpse sends, trash loot, vendoring alike.
-- Unchanged counts send nothing.
local BAGS_SETTLE = 5
local bagsTimer = CreateFrame("Frame")
bagsTimer:Hide()
bagsTimer:SetScript("OnUpdate", function()
    if not addon._bagsReportAt or GetTime() < addon._bagsReportAt then return end
    addon._bagsReportAt = nil
    bagsTimer:Hide()
    if addon:FreeBagSlots() ~= addon._bagsSent then addon:ReportEnchanting(true) end
end)

function addon:IsWatchedDisenchanter()
    local w = self._deWatch
    return w and w.id == self:GetCurrentSession().id and w.names[util:NormalizeKey(util:GetPlayerName("player") or "")] or false
end

-- BAG_UPDATE (Core.lua): a trailing 5 s deadline, pushed back by every further change.
function addon:DEBagsChanged()
    if not self._enchSentEpoch or not self:IsWatchedDisenchanter() then return end
    self._bagsReportAt = GetTime() + BAGS_SETTLE
    bagsTimer:Show()
end

-- Raider: the ML's current disenchanters for this session (fields: session id, then names).
function addon:OnDEWatch(sender, fields)
    if util:NormalizeKey(sender or "") ~= util:NormalizeKey(self:GetLootMasterName() or "") then return end
    local names = {}
    for i = 2, #fields do if fields[i] ~= "" then names[util:NormalizeKey(fields[i])] = true end end
    self._deWatch = { id = fields[1], names = names }
end

-- ML: tell the raid who watches their bags (the greens disenchanter and the flyout's remembered pick), when
-- that changes; to = one raider (whispered, e.g. a late joiner's first report).
function addon:SendDEWatch(to)
    if not self:IsAuthorizedLootMaster() then return end
    local session = self:GetCurrentSession()
    local a, b = session.deer or "", session.deDefault or ""
    local key = tostring(session.id) .. "|" .. a .. "|" .. b
    if not to and key == self._deWatchSent then return end
    if not to then self._deWatchSent = key end
    self:SendLargeMessage("DEWATCH", { session.id, a, b }, to and "WHISPER" or "RAID", to)
end

-- ML: a raider's report. Kept in the session (survives an ML reload); a new session gets fresh reports.
-- free: their free bag slots (nil from an older WeirdLoot).
function addon:OnEnchantingReport(sender, rank, free)
    if not self:IsAuthorizedLootMaster() then return end
    local session = self:GetCurrentSession()
    local key = util:NormalizeKey(sender)
    session.enchanting = session.enchanting or {}
    session.enchanting[key] = tonumber(rank) or 0
    session.deBags = session.deBags or {}
    session.deBags[key] = tonumber(free)
    if util:NormalizeKey(session.deer or "") == key or util:NormalizeKey(session.deDefault or "") == key then
        self:SendDEWatch(sender)   -- they may have joined or reloaded after the raid-wide one
    end
    -- the greens prompt is open: a late report can add a name, or a new bag count, to it
    local f = self._greensPrompt
    if f and f:IsShown() then self:PromptGreensDisenchanter(f.itemId, f.link, f.gone) end
end

-- ML: who's free bag slots, as last reported (the ML's own read directly), or nil if never reported.
function addon:DisenchanterFreeSlots(who)
    local key = util:NormalizeKey(who or "")
    if key == util:NormalizeKey(util:GetPlayerName("player") or "") then return self:FreeBagSlots() end
    local bags = self:GetCurrentSession().deBags
    return bags and bags[key]
end

-- "22 free" coloured by how soon they fill: red under 5, yellow under 10, mild green otherwise; "-" unknown.
function addon:FreeSlotsText(who)
    local n = self:DisenchanterFreeSlots(who)
    if not n then return "|cff9a9a9a-|r" end
    local c = (n < 5 and "ff4040") or (n < 10 and "ffd200") or "80cc80"
    return "|cff" .. c .. n .. " free|r"
end

-- The raider a lot went to for disenchanting, or nil.
function addon:DisenchantTarget(lotId)
    local lots = self:GetCurrentSession().deLots
    return lots and lots[lotId]
end

-- ML: the last raider picked to disenchant, when they can disenchant this item too (else nil).
function addon:DisenchantDefault(candidates)
    local session = self:GetCurrentSession()
    -- the last flyout pick; before any, the greens disenchanter as a starting suggestion
    local who = session.deDefault or session.deer
    if not who then return nil end
    for _, c in ipairs(candidates or {}) do
        if util:NormalizeKey(c.name) == util:NormalizeKey(who) then return c.name end
    end
end

-- ML: raid members who can disenchant itemId, highest skill first, as flyout rows { name, class, roll }
-- (roll = their skill). The ML's own skill is read directly. Returns the rows and the skill needed.
function addon:DisenchantCandidates(itemId)
    return self:DisenchantCandidatesAt(self:DisenchantSkillFor(itemId))
end

-- Raid members with at least `need` Enchanting (rows as above), and `need`. nil need: nobody.
function addon:DisenchantCandidatesAt(need)
    if not need then return {}, nil end
    local reports = self:GetCurrentSession().enchanting or {}
    local me = util:NormalizeKey(util:GetPlayerName("player") or "")
    local list = {}
    for i = 1, (GetNumRaidMembers() or 0) do
        local name, _, _, _, className, _, _, online = GetRaidRosterInfo(i)
        if name and online then   -- an offline raider cannot take loot
            local key = util:NormalizeKey(name)
            local rank = (key == me) and self:EnchantingSkill() or reports[key] or 0
            if rank >= need then list[#list + 1] = { name = name, class = className, roll = rank } end
        end
    end
    table.sort(list, function(a, b)
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.name < b.name
    end)
    return list, need
end

-- ML, when nobody can disenchant greens: online raiders (not us: Keep covers that) who reported room to hold
-- them, most free first, the top HOLDERS_MAX with at least HOLDER_MIN free (fewer would fill almost at once).
local HOLDERS_MAX, HOLDER_MIN = 5, 5
function addon:GreensHolderCandidates()
    local bags = self:GetCurrentSession().deBags or {}
    local me = util:NormalizeKey(util:GetPlayerName("player") or "")
    local list = {}
    for i = 1, (GetNumRaidMembers() or 0) do
        local name, _, _, _, className, _, _, online = GetRaidRosterInfo(i)
        local key = name and util:NormalizeKey(name)
        local free = key and bags[key]
        if online and key ~= me and free and free >= HOLDER_MIN then
            list[#list + 1] = { name = name, class = className, free = free }
        end
    end
    table.sort(list, function(a, b)
        if a.free ~= b.free then return a.free > b.free end
        return a.name < b.name
    end)
    for i = #list, HOLDERS_MAX + 1, -1 do list[i] = nil end
    return list
end

-- Can `who` disenchant greens (the Loot Master tab says "Disenchanter" or "Greens to")?
function addon:CanDisenchantGreens(who)
    local key = util:NormalizeKey(who or "")
    local rank = (key == util:NormalizeKey(util:GetPlayerName("player") or "")) and self:EnchantingSkill()
        or (self:GetCurrentSession().enchanting or {})[key] or 0
    return rank >= GREEN_BASELINE
end

-- ML: send a no-winner copy to `who` to disenchant. The loot-council award does the work (owe and trade,
-- or the corpse send for a copy still on the corpse); the flag marks the owe as for disenchanting.
function addon:SendForDisenchant(lotId, who)
    if not self:IsAuthorizedLootMaster() then return end
    local lot = self.lootCore:Get(lotId)
    if not lot then return end
    local session = self:GetCurrentSession()
    session.deDefault = who   -- the next card offers them first (greens keep their own disenchanter)
    -- which lots went out to disenchant: the corpse send, its delivery and raiders' cards read it
    session.deLots = session.deLots or {}
    session.deLots[lotId] = who
    self:SendDEWatch()
    self._awardForDE = true
    self:AwardLootCouncilCopy(lotId, who, true)
    self._awardForDE = nil
    local name = util:ItemRender(lot.itemId)
    self:Print(string.format("%s -> %s (disenchant).", name or "item", who))
end

-- The session's greens disenchanter: greens that bind on equip go straight off the corpse to them. Separate
-- from the Disenchant flyout's remembered pick (epics can go to someone else). nil clears it (greens wait
-- for the prompt again). quiet: no chat.
function addon:SetGreensDisenchanter(who, quiet)
    local session = self:GetCurrentSession()
    session.deer = who
    session.deerSelf = nil
    if self._greensPrompt then self._greensPrompt:Hide() end
    self:SendDEWatch()
    if not quiet then
        self:Print(who and ("Greens go to " .. who .. (self:CanDisenchantGreens(who) and " to disenchant" or "")
            .. " this session.") or "Disenchanter cleared.")
    end
    if self.ui and self.ui.masterPanel and self.RefreshMasterTab then self:RefreshMasterTab() end
end

-- "Keep greens myself": greens go to the ML for the rest of the session, and the prompt stops.
function addon:KeepGreensMyself()
    local session = self:GetCurrentSession()
    session.deer, session.deerSelf = nil, true
    if self._greensPrompt then self._greensPrompt:Hide() end
    self:SendDEWatch()
    self:Print("Greens go to you this session.")
    if self.ui and self.ui.masterPanel and self.RefreshMasterTab then self:RefreshMasterTab() end
end

local PROMPT_W, ROW_H = 230, 22

-- Where Blizzard's own popups open (StaticPopup1, top centre), like the fresh-session prompt; when popups
-- are up, below the lowest of them, so a fresh-session prompt and this one can both be read.
local function placeGreensPrompt(f)
    local below
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local p = _G["StaticPopup" .. i]
        if p and p:IsShown() then below = p end
    end
    f:ClearAllPoints()
    if below then
        f:SetPoint("TOP", below, "BOTTOM", 0, -8)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -135)
    end
end

local function buildGreensPrompt(self)
    local f = CreateFrame("Frame", "WeirdLootGreensPrompt", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(PROMPT_W)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:EnableMouse(true)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -14)
    f.title:SetText("Who disenchants greens?")
    f.item = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.item:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    f.item:SetWidth(PROMPT_W - 20)   -- a long item name wraps rather than widening the box
    f.rows = {}
    f.keep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.keep:SetWidth(130); f.keep:SetHeight(20)
    f.keep:SetText("Keep greens myself")
    f.keep:SetScript("OnClick", function() self:KeepGreensMyself(); self:RouteLootSlots() end)
    -- the ML's own free slots, in line with the names' column
    f.keep.free = f.keep:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.keep.free:SetPoint("LEFT", f.keep, "RIGHT", 6, 0)
    -- a popup opening or closing while we are up: move to stay clear of it
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local p = _G["StaticPopup" .. i]
        if p and p.HookScript then
            p:HookScript("OnShow", function() if f:IsShown() then placeGreensPrompt(f) end end)
            p:HookScript("OnHide", function() if f:IsShown() then placeGreensPrompt(f) end end)
        end
    end
    f:Hide()
    return f
end

-- ML: the session's first green that binds on equip, with no disenchanter set: ask who takes greens.
-- The green waits in the loot window; a pick (or Keep) routes it at once if the window is still open.
-- gone: why the previous greens disenchanter cannot take them, a full sentence shown in red on the box.
function addon:PromptGreensDisenchanter(itemId, link, gone)
    if not self:IsAuthorizedLootMaster() then
        -- the fresh-session prompt holds authority after a reload: ask once it is answered
        if self._mlPromptPending then self._greensAskPending = { itemId, link, gone } end
        return
    end
    self._greensAskPending = nil
    local f = self._greensPrompt or buildGreensPrompt(self)
    self._greensPrompt = f
    -- always the green baseline: this picks who takes every green, not just the one that dropped
    local cands = self:DisenchantCandidatesAt(GREEN_BASELINE)
    local lines = {}
    if gone then lines[#lines + 1] = "|cffff8080" .. gone .. "|r" end
    local noDE = #cands == 0
    if noDE then
        -- nobody can disenchant: offer whoever has room to hold the greens instead
        cands = self:GreensHolderCandidates()
        if #cands == 0 and self:FreeBagSlots() == 0 then
            -- no one, us included, has room: nothing to choose, so no box; the greens stay in the corpse
            f:Hide()
            local session = self:GetCurrentSession()
            if self._allFullSaid ~= session.id then
                self._allFullSaid = session.id
                self:Print("Everyone's bags are full: greens stay in the corpse.")
            end
            return
        end
        lines[#lines + 1] = "No one can disenchant greens."
        if #cands > 0 then lines[#lines + 1] = "Send greens to:" end
    end
    -- with nobody to disenchant, the choice is only who holds them
    f.title:SetText(noDE and "Who gets greens?" or "Who disenchants greens?")
    local top, gap = f.title, -6
    if #lines > 0 then
        f.item:SetText(table.concat(lines, "\n"))
        f.item:Show()
        top = f.item
    else
        f.item:Hide()
    end
    for i, c in ipairs(cands) do
        local b = f.rows[i]
        if not b then
            b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetWidth(130); b:SetHeight(ROW_H - 2)
            b.free = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.free:SetPoint("LEFT", b, "RIGHT", 6, 0)
            f.rows[i] = b
        end
        b:ClearAllPoints()
        -- no skill shown: everyone listed can take greens
        b:SetPoint("TOP", top, "BOTTOM", -24, gap - (i - 1) * ROW_H)
        b.free:SetText(self:FreeSlotsText(c.name))
        b:SetText(c.name)
        b.name = c.name
        b:SetScript("OnClick", function(btn) self:SetGreensDisenchanter(btn.name); self:RouteLootSlots() end)
        b:Show()
    end
    for i = #cands + 1, #f.rows do f.rows[i]:Hide() end
    f.keep:ClearAllPoints()
    f.keep:SetPoint("TOP", top, "BOTTOM", -24, gap - 4 - #cands * ROW_H)
    local h = 68 + #cands * ROW_H + (#lines > 0 and ((tonumber(f.item:GetStringHeight()) or 12 * #lines) + 6) or 0)
    f.keep.free:SetText(self:FreeSlotsText(util:GetPlayerName("player")))
    f:SetHeight(h)   -- includes padding under Keep, clear of the border
    f.itemId, f.link, f.gone = itemId, link, gone
    placeGreensPrompt(f)
    f:Show()
end

-- The server refused a green we just handed the disenchanter: their bags are full. The greens stay in the
-- corpse, so say so and ask who takes greens instead (they may clear space and be picked again).
function addon:UI_ERROR_MESSAGE(msg)
    if msg ~= ERR_LOOT_MASTER_INV_FULL or not self._deerSentAt then return end
    if GetTime() - self._deerSentAt > 2 then return end
    local who = self._deerSentTo
    self._deerSentAt = nil
    if self._greensPrompt and self._greensPrompt:IsShown() then return end   -- one ask per refused batch
    self:Print((who or "The disenchanter") .. "'s bags are full: the greens stay in the corpse. Choose who takes greens.")
    local session = self:GetCurrentSession()
    session.deer, session.deerSelf = nil, nil   -- greens wait in the corpse for a new choice (Keep included)
    self:SendDEWatch()
    if who then
        session.deBags = session.deBags or {}
        session.deBags[util:NormalizeKey(who)] = 0
    end
    self:PromptGreensDisenchanter(nil, nil, who and (who .. "'s bags are full.") or nil)
end
