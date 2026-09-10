local addon = WeirdLoot
local util = addon.util

-- LootObserver: what the ML's loot window ACTUALLY contained, and what left it. Two drops can
-- silently never reach the raid under master loot:
--   * a pure-Unique the ML already holds: the slot is visible but the self-assign no-ops, so the
--     item despawns with the corpse (TODO item 30);
--   * a quest-gated drop the ML cannot SEE (quest completed): the server filters the slot out of
--     the ML's loot entirely (TODO item 29).
-- The observer snapshots every slot at LOOT_OPENED (with the source named from the dead target),
-- ticks slots off on LOOT_SLOT_CLEARED, and knows at LOOT_CLOSED exactly what stayed behind. On
-- top of that it warns the ML firmly in both cases, mints a PHANTOM lot for a blocked unique so
-- the raid rolls it normally (LootCore:MintPhantom), and master-loots the copy straight to the
-- winner when the ML re-opens the corpse (the pending-send registry, fed by LiveRoll at resolve).
-- ML-only by construction: every entry point is called under AutoLoot's session + IsMasterLooter
-- gate or checks it itself.

-- Quest-gated GUARANTEED drops, keyed by the SOURCE NAME as this client sees it: a dead target's
-- unit name for a corpse, the world tooltip's first line for a chest (a chest is not a unit, so no
-- token or GUID names it on 3.3.5a; the tooltip line is still the object's name when LOOT_OPENED
-- fires, verified in-game on the Cache of Living Stone). Names, not npc ids: a corpse GUID carries
-- the creature's BASE entry whatever the raid size (the server swaps the 25-man template
-- server-side only), so an id table needs every size folded under the base id and silently skips
-- the warning when it is not; this check runs on the ML's own client, and the name is what that
-- client has. Only 100%-chance items belong here: the "absent from the ML's loot = the ML cannot
-- see it" inference does not hold for chance drops. items is keyed by GetInstanceDifficulty
-- (1=10, 2=25). Source: chromiecraft creature_loot_template / gameobject_loot_template (Chance=100).
-- Assumes an English client (ChromieCraft is enUS), as the item-type checks already do.
addon.QUEST_GATED_DROPS = {
    ["Sapphiron"]            = { label = "the Key to the Focusing Iris", items = { [1] = 44569, [2] = 44577 } },
    -- Assembly of Iron: Steelbreaker and Runemaster Molgeim both carry the disc at 100%, so
    -- whichever of them died last is the looted corpse.
    ["Steelbreaker"]         = { label = "the Archivum Data Disc", items = { [1] = 45506, [2] = 45857 } },
    ["Runemaster Molgeim"]   = { label = "the Archivum Data Disc", items = { [1] = 45506, [2] = 45857 } },
    ["Gift of the Observer"] = { label = "Reply-Code Alpha", items = { [1] = 46052, [2] = 46053 } },   -- Algalon's chest
}

-- Firm, local alert: red chat line + the raid-warning sound. The persistent signal lives on the
-- banner cards themselves (the "On Corpse" side tag), so no center-screen text.
function addon:LootAlert(text)
    self:Print("|cffff4040" .. text .. "|r")
    if PlaySound then PlaySound("RaidWarning") end
end

local function whisperChat(target, text)
    util:WhisperChat(target, text)
end

-- ---------------------------------------------------------------------------
-- snapshot lifecycle
-- ---------------------------------------------------------------------------

-- Called at the top of AutoLoot's LOOT_OPENED (already gated: session active + we are the WoW ML),
-- BEFORE any routing assigns, so the snapshot is the window's true pre-assign contents.
function addon:ObserveLootOpened()
    local corpseGuid, sourceName, isChest
    if UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target") then
        corpseGuid = UnitGUID and UnitGUID("target") or nil
        sourceName = UnitName and UnitName("target") or nil
    else
        -- ponytail: live tooltip read only; a cursor that left the chest before the window opened
        -- reads nil (no warning). Add a CURSOR_UPDATE capture if that is ever seen in practice.
        local fs = GameTooltipTextLeft1
        sourceName = fs and fs.GetText and fs:GetText() or nil
        isChest = sourceName ~= nil
    end
    local slots = {}
    for slot = 1, GetNumLootItems() do
        if LootSlotIsItem(slot) then
            local link = GetLootSlotLink(slot)
            local itemId = link and util:ItemIdFromLink(link)
            if itemId then
                local _, _, quantity, quality = GetLootSlotInfo(slot)
                slots[slot] = { itemId = itemId, quality = quality or 0, quantity = quantity or 1 }
            end
        end
    end
    self.lootObs = {
        corpseGuid = corpseGuid,           -- nil for chests (no dead target to read)
        sourceName = sourceName,           -- dead target's name, or the world-tooltip name for a chest
        isChest = isChest or nil,
        slots = slots,
        assigning = {},                    -- [slot] = pending-send info, set by TryPhantomSends
        open = true,
    }
    self._lootObsSeen = self._lootObsSeen or {}   -- corpse+item dedupe across re-opens

    -- Trace what the observer could see at open: the source it resolved (or failed to) and the
    -- slot contents, so a missed quest-drop warning can be diagnosed from the log.
    local ids = {}
    for _, s in pairs(slots) do ids[#ids + 1] = s.itemId end
    self:LogCoreEvent("loot-open", {
        guid = corpseGuid, source = sourceName, chest = isChest or false,
        tgt = UnitExists and UnitExists("target") and (UnitName and UnitName("target")) or nil,
        tgtDead = UnitIsDead and UnitIsDead("target") or false,
        diff = (GetInstanceDifficulty and GetInstanceDifficulty()) or nil,
        items = table.concat(ids, ","),
    })

    self:WarnMissingQuestDrops()
    self:TryPhantomSends()
end

function addon:LOOT_SLOT_CLEARED(slot)
    local obs = self.lootObs
    if not obs or not obs.open then return end
    local s = obs.slots[slot]
    if s then s.cleared = true end
    local send = obs.assigning[slot]
    if send then
        obs.assigning[slot] = nil
        self:OnPhantomSendCleared(send.lotId, send.target)
    end
end

function addon:LOOT_CLOSED()
    local obs = self.lootObs
    if not obs or not obs.open then return end
    obs.open = false
    -- Backstop visibility: anything tracked by a phantom lot that is still sitting on the corpse.
    for _, s in pairs(obs.slots) do
        if not s.cleared and self.lootCore then
            local lot = self.lootCore:openPhantomLotForItem(s.itemId)
            local sendPending = self.phantomSends and next(self.phantomSends) and self:PhantomSendForItem(s.itemId)
            if lot or sendPending then
                local _, link = util:ItemRender(s.itemId)
                self:Print((link or ("item " .. s.itemId)) .. " is still on the corpse. Re-open it once the roll finishes to send it out.")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- item 29: a guaranteed quest-gated drop did not appear in the ML's loot at all
-- ---------------------------------------------------------------------------

-- Absence is decided at OPEN (loot slots never populate late), which is also the earliest moment
-- the fix (another looter, before despawn) can start. Warn once per corpse; a chest has no GUID, so
-- once per chest NAME this play-session (a raid cache is looted once per lockout).
function addon:WarnMissingQuestDrops()
    local obs = self.lootObs
    if not obs then return end
    local entry = obs.sourceName and self.QUEST_GATED_DROPS[obs.sourceName]
    -- once per corpse (GUID) or, for a chest, once per name this play-session (a raid cache is
    -- looted once per lockout)
    local seenKey = (obs.corpseGuid or ("chest:" .. tostring(obs.sourceName))) .. ":quest"
    self:LogCoreEvent("quest-check", { key = seenKey, entry = entry and entry.label or nil,
        seen = self._lootObsSeen[seenKey] or false })
    if not entry then return end
    if self._lootObsSeen[seenKey] then return end

    local difficulty = (GetInstanceDifficulty and GetInstanceDifficulty()) or 1
    local expected = entry.items[difficulty]
    local present = false
    for _, s in pairs(obs.slots) do
        if expected and s.itemId == expected then present = true end
        -- unknown difficulty reading: treat any listed id as present
        if not expected then
            for _, id in pairs(entry.items) do
                if s.itemId == id then present = true end
            end
        end
    end
    self:LogCoreEvent("quest-missing", { expected = expected, present = present, diff = difficulty })
    if present then
        self._lootObsSeen[seenKey] = true
        return
    end

    local where = obs.isChest and "This chest" or "This kill"
    if not (expected and self.lootCore) then
        -- Nothing to mint for this difficulty reading: say so rather than promise a roll, and leave
        -- the source unseen so a re-open (after a /reload, say) gets another chance.
        self:LootAlert(where .. " always drops " .. entry.label .. ", but it is NOT in your loot and WeirdLoot cannot tell which size dropped. Have another looter pick it up.")
        return
    end
    self._lootObsSeen[seenKey] = true
    self:LootAlert(where .. " always drops " .. entry.label .. ", but it is NOT in your loot. You likely cannot see it (quest already done). It rolls now; the winner picks it up via a master-loot loan.")
    -- Roll the invisible drop as a phantom. invisibleToML routes its resolve to the LOAN flow
    -- (the ML can never assign a slot they cannot see, so the corpse-send path is useless here).
    -- Local-only field: the owner's client decides the flavor; raiders roll it like any drop.
    -- Flush at once: a mint alone emits no ledger change, and the roll must not wait for some
    -- later bag delta to project, persist and broadcast it.
    local lot = self.lootCore:MintPhantom(expected, 1)
    lot.invisibleToML = true
    self:LogCoreEvent("quest-phantom", { id = lot.id, item = expected, state = lot.state })
    self.lootCore:Flush()
end

-- ---------------------------------------------------------------------------
-- item 30: a pure-Unique the ML already holds is visible but cannot be picked up
-- ---------------------------------------------------------------------------

-- Would self-assigning this itemId silently no-op? Hold-check first (cheap), tooltip scan second.
function addon:LootSlotIsBlockedUnique(itemId)
    return self:PlayerHoldsItem(itemId) and self:IsItemPureUnique(itemId)
end

-- AutoLoot found a BoP slot it would have self-assigned, but the ML already holds this pure-Unique:
-- the assign is skipped there; here we warn once per corpse and put the copy up for rolling as a
-- phantom lot (it can never enter the ML's bags, so the normal bag-delta mint can never see it).
function addon:OnUniqueBlockedSlot(slot, itemId, link)
    local obs = self.lootObs
    local seenKey = ((obs and obs.corpseGuid) or "?") .. ":" .. itemId
    if self._lootObsSeen[seenKey] then return end
    self._lootObsSeen[seenKey] = true

    local shown = link or ("item " .. itemId)
    self:LootAlert(shown .. " is a Unique you already hold: it CANNOT enter your bags and stays on the corpse. It rolls now; re-open the corpse afterwards to send it to the winner.")
    if self.lootCore then
        self.lootCore:MintPhantom(itemId, 1)
        self.lootCore:Flush()   -- see WarnMissingQuestDrops: a bare mint is invisible until flushed
    end
end

-- ---------------------------------------------------------------------------
-- pending sends: resolved phantom copies waiting to be master-looted off the corpse
-- ---------------------------------------------------------------------------
-- Registry shape: addon.phantomSends[lotId] = { itemId = N, target = "name" }. LiveRoll registers
-- an entry when a phantom lot resolves with a winner; the ML (or the card's flyout) may retarget.

-- Any phantom copy the ML still needs to RE-LOOT: an unresolved VISIBLE phantom (its roll queued
-- or running) or a pending corpse send. Drives the "re-loot the corpse" header strip, so
-- INVISIBLE phantoms are deliberately excluded: the ML cannot see those in any loot window and
-- re-looting achieves nothing (the loan flow + the Quest Drop side tag carry that case).
-- ML only: phantom lots also exist on raider mirrors.
function addon:HasCorpseLootOutstanding()
    if not self:IsAuthorizedLootMaster() then return false end
    if self.phantomSends and next(self.phantomSends) then return true end
    local core = self.lootCore
    if not core then return false end
    for _, lot in ipairs(core:List()) do
        if lot.phantom and not lot.invisibleToML and lot.state ~= core.STATE.RESOLVED then return true end
    end
    return false
end

-- Mark the phantom lot's owed copy for `recipient` delivered (the one back-channel shared by the
-- corpse-send confirm and the loan fulfillment). Precise by lot id, never by bag inference.
function addon:MarkPhantomAwardDelivered(lotId, recipient)
    local core = self.lootCore
    local lot = core and core:Get(lotId)
    if not lot or not lot.awards then return false end
    for idx, a in ipairs(lot.awards) do
        if a.state == core.AWARD.OWED and a.winner == recipient then
            return core:MarkDelivered(lotId, idx, recipient)
        end
    end
    return false
end

function addon:PhantomSendForItem(itemId)
    for lotId, send in pairs(self.phantomSends or {}) do
        if send.itemId == itemId then return lotId, send end
    end
    return nil
end

-- The loot window just opened: assign any pending phantom copy visible in it to its target.
function addon:TryPhantomSends()
    local obs = self.lootObs
    if not obs or not next(self.phantomSends or {}) then return end
    for slot, s in pairs(obs.slots) do
        if not s.cleared and not obs.assigning[slot] then
            local lotId, send = self:PhantomSendForItem(s.itemId)
            if lotId then
                local idx = self:FindMasterLootCandidate(send.target)
                if idx then
                    obs.assigning[slot] = { lotId = lotId, target = send.target }
                    GiveMasterLoot(slot, idx)
                else
                    self:Print("Cannot send " .. (select(2, util:ItemRender(s.itemId)) or "the item") .. ": " ..
                        send.target .. " is not a loot candidate here (out of range?). Pick another recipient on the win card.")
                end
            end
        end
    end
end

-- The server confirmed our assign (the slot cleared): record the delivery, tell both sides.
function addon:OnPhantomSendCleared(lotId, target)
    local core = self.lootCore
    local lot = core and core:Get(lotId)
    self:MarkPhantomAwardDelivered(lotId, target)
    if self.phantomSends then self.phantomSends[lotId] = nil end

    local _, link = util:ItemRender(lot and lot.itemId)
    local shown = link or "your item"
    whisperChat(target, "You won " .. shown .. "! It was master-looted directly to you.")
    self:Print(shown .. " sent to " .. target .. " (master-looted from the corpse).")
    if self.ShowPhantomSendCard then self:ShowPhantomSendCard(lotId) end
    if self.RefreshRollsLeftBanner then self:RefreshRollsLeftBanner() end   -- on-corpse header may clear now
end

-- ML retargets a pending send from the win card's flyout; assigns immediately if the window is open.
function addon:SetPhantomSendTarget(lotId, target)
    local send = self.phantomSends and self.phantomSends[lotId]
    if not send or not target or target == "" then return end
    send.target = target
    if self.lootObs and self.lootObs.open then self:TryPhantomSends() end
    if self.ShowPhantomSendCard then self:ShowPhantomSendCard(lotId) end
end

