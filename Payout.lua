local addonName, addon = ...
addon = WeirdLoot

-- Payout bridge: connects WeirdLoot's loot results to the TradeDeliver-1.0 engine.
--
-- Upstream delivery was manual and one-at-a-time (target + whisper the winner, then
-- "Load Item" + "Trade Winner" by hand). This replaces that with the engine's
-- owed-ledger + partner-initiated auto-fill: every processed winner is "owed" their
-- item, then the loot master runs a single payout. Winners open a trade and their
-- items are filled automatically (the LM just clicks Trade to send -- AcceptTrade is
-- hardware-gated on 3.3.5a, so the final click can't be automated).
--
-- The engine owns its own trade/bag events, stack-correct splitting, throttled
-- whispers, and soonest-to-expire ordering for time-limited BoP loot.

function addon:InitializePayout()
    local TradeDeliver = LibStub and LibStub("TradeDeliver-1.0", true)
    if not TradeDeliver then
        self:Print("TradeDeliver-1.0 not found; auto-trade payout disabled.")
        return
    end

    WeirdLootDB.payout = WeirdLootDB.payout or {}
    self.payout = TradeDeliver:New({
        db     = WeirdLootDB.payout,                 -- owed ledger persists here
        name   = "WeirdLoot",
        prefix = "WeirdLootPay",                     -- distinct from the addon's comm prefix
        print  = function(text) addon:Print(text) end,
        debug  = function(text)
            if WeirdLootDB.payoutDebug then addon:Print("|cff888888[pay]|r " .. text) end
        end,
        -- a completed trade is the authoritative "where it went": record per-copy delivery.
        onDelivered = function(player, itemId)
            if addon.lootCore then addon.lootCore:MarkDeliveredFor(player, itemId, time()) end
        end,
    })

    -- Owes are derived from the core's per-copy awards. A resolve adds owes for that lot's
    -- non-ML winners (whispered once if payout is live); an unlock retracts them. The ML
    -- owns this; raiders never run payout.
    if self.lootCore and not self._payoutWired then
        self._payoutWired = true
        self.lootCore:On("lotResolved", function(lot) addon:OnLotResolvedPayout(lot) end)
        self.lootCore:On("lotUnlocked", function(lot, winners) addon:OnLotUnlockedPayout(lot, winners) end)
    end
end

function addon:OnLotResolvedPayout(lot)
    if not self.payout or not self:IsAuthorizedLootMaster() then return end
    local selfKey = addon.util:NormalizeKey(addon.util:GetPlayerName("player") or "")
    local _, link = addon.util:ItemRender(lot.itemId)
    for _, award in ipairs(lot.awards or {}) do
        local winner = award.state == addon.lootCore.AWARD.OWED and award.winner or nil
        if winner and addon.util:NormalizeKey(winner) ~= selfKey then
            self.payout:Owe(winner, lot.itemId, 1, link)
        end
    end
end

function addon:OnLotUnlockedPayout(lot, winners)
    if not self.payout or not self:IsAuthorizedLootMaster() then return end
    for _, winner in ipairs(winners or {}) do
        self.payout:Forgive(winner, lot.itemId)
    end
end

local function refreshMaster(self)
    if self.ui and self.ui.masterPanel then self:RefreshMasterTab() end
end

-- Loot master: whisper everyone still owed and turn on auto-fill.
function addon:StartPayout()
    if not self.payout then
        self:Print("Payout engine unavailable.")
        return
    end
    if not self:IsAuthorizedLootMaster() then
        self:Print("Only the loot master can run payouts.")
        return
    end
    -- Pure toggle: turn payout mode on even with nothing owed yet. New winners auto-whisper
    -- as they're added, and trades auto-fill on TRADE_SHOW.
    local sent = self.payout:StartPayout()
    if sent > 0 then
        self:Print("Payout ON: whispered " .. sent .. " winner(s). They open a trade; items auto-fill -- click Trade to send.")
    else
        self:Print("Payout ON. No one owed yet; winners will be whispered as they're decided.")
    end
    refreshMaster(self)
end

-- Pause: stop auto-fill but KEEP the owed list, so Start resumes where it left off.
function addon:StopPayout()
    if self.payout then
        self.payout:StopPayout()
        self:Print("Payout paused. Owed list kept; Start Payout again to resume.")
        refreshMaster(self)
    end
end

-- Turn payout mode on whenever a session is active (fresh start OR restored at login).
-- payoutActive is runtime-only and resets every login, so a restored session would
-- otherwise sit with owes that never whisper or auto-fill. Re-whispers anyone still
-- owed so they know to open a trade.
function addon:ResumePayoutMode()
    if not self.payout then return end
    if not (self.session and self.session.active) then return end
    if not self:IsAuthorizedLootMaster() then return end   -- only the real ML re-arms/whispers
    local sent = self.payout:StartPayout()
    if sent and sent > 0 then
        self:Print("Payout mode ON: re-whispered " .. sent .. " owed winner(s).")
    end
    if self.ui and self.ui.masterPanel then self:RefreshMasterTab() end
end

function addon:TogglePayout()
    if self.payout and self.payout:IsPayoutActive() then
        self:StopPayout()
    else
        self:StartPayout()
    end
end

-- Fill the currently-open trade from the loot ledger via the engine -- the manual
-- delivery path, using the same filler as auto-payout (no hand-placing items, so the
-- two can't conflict). Owing happens at Process Loot, so this works whether or not
-- payout mode is on.
function addon:FillOpenTrade()
    if not self.payout then
        self:Print("Payout engine unavailable.")
        return
    end
    local ok, reason = self.payout:FillOpenTrade()
    if not ok then
        self:Print(reason or "Could not fill the trade.")
    end
end
