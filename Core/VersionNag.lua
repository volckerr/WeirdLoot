local addon = WeirdLoot

-- ---------------------------------------------------------------------------
-- Version notifier (DBM's mechanism)
--
-- Peers announce their build on the addon channel; a client that hears one it is behind prints a
-- line telling the player to update. That is the whole job. Nothing else in the addon reads the
-- result, and no decision anywhere gates on it.
--
-- Deliberately standalone: its own message prefix and its own event frame, sharing nothing with
-- WeirdComm or WeirdSync. A fault here cannot disturb the session mirror or a live roll, and the
-- notifier keeps working even when sync is down (which is exactly when a stale client shows up).
--
-- Two numbers ride the wire, both read from the toc:
--   Version        the build the sender runs. Bumped freely, cosmetic releases included.
--   X-MinVersion   the build the sender says everyone needs. Bumped only when an update matters.
--
-- A receiver nags when its OWN version is below the sender's X-MinVersion. Hearing a newer Version
-- on its own says nothing. That split is the point: "there is a newer build" and "go and update"
-- become separate statements, so a UI-only release does not tell the raid to go and update while a
-- wire-format change still can. Raise X-MinVersion in the toc to turn the nag on for everyone below it.
-- ---------------------------------------------------------------------------

local PREFIX       = "WLVER"  -- distinct from addon.prefix ("WeirdLoot"), which WeirdComm owns
local SEND_DELAY   = 5        -- seconds after a trigger before announcing
local MIN_INTERVAL = 60       -- floor between announcements

-- SEND_DELAY does double duty. Roster events arrive in bursts as a raid forms, so it coalesces them
-- into one send; and at login the guild roster is not populated yet, so announcing immediately would
-- skip the GUILD channel.

addon.minVersion = (GetAddOnMetadata and GetAddOnMetadata(addon.name, "X-MinVersion")) or addon.version

-- warned: nag once per session. lastSend/pending/elapsed: the coalescing send timer below.
addon.versionNag = { warned = false, lastSend = nil, pending = false, elapsed = 0 }

-- "1.4.10" is NEWER than "1.4.9", which a plain string compare gets backwards, so compare the dotted
-- parts numerically. A missing trailing part counts as 0, making "1.4" equal to "1.4.0". A
-- non-numeric part (the "dev" fallback when metadata is absent) sorts below every real build, so a
-- dev client is never treated as up to date.
local function versionParts(value)
    local out = {}
    for piece in tostring(value or ""):gmatch("[^.]+") do
        out[#out + 1] = tonumber(piece) or -1
    end
    return out
end

-- -1 when a is older than b, 1 when newer, 0 when equal.
function addon:CompareVersions(a, b)
    local pa, pb = versionParts(a), versionParts(b)
    local n = math.max(#pa, #pb)
    for i = 1, n do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

-- Guild as well as raid, as DBM does: a raider finds out while they can still go and fix it, rather
-- than at the pull.
local function announceChannels()
    local out = {}
    if IsInGuild and IsInGuild() then
        out[#out + 1] = "GUILD"
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        out[#out + 1] = "RAID"
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        out[#out + 1] = "PARTY"
    end
    return out
end

function addon:BroadcastVersion()
    if not SendAddonMessage then return end
    -- Gated like every other send path: a character switched off produces no addon traffic.
    if self:IsDisabled() then return end

    local now = (GetTime and GetTime()) or 0
    if self.versionNag.lastSend and now - self.versionNag.lastSend < MIN_INTERVAL then return end

    local channels = announceChannels()
    if #channels == 0 then return end

    self.versionNag.lastSend = now
    local message = tostring(self.version) .. ":" .. tostring(self.minVersion)
    for _, distribution in ipairs(channels) do
        SendAddonMessage(PREFIX, message, distribution)
    end
end

function addon:OnVersionMessage(message, sender)
    if type(message) ~= "string" then return end
    if sender and self.util and self.util:IsSelfName(sender) then return end

    local _, theirMin = message:match("^([^:]*):([^:]*)$")
    if not theirMin or theirMin == "" then return end

    -- Once per session, like DBM. Every peer in a 25 man announces, and without this the player gets
    -- one line per announcement.
    if self.versionNag.warned then return end
    if self:CompareVersions(self.version, theirMin) >= 0 then return end

    self.versionNag.warned = true
    self:Print(string.format(
        "|cffff4040Your WeirdLoot is out of date.|r You are on %s; the raid needs %s or newer.",
        tostring(self.version), tostring(theirMin)))
end

local versionFrame = CreateFrame("Frame")
versionFrame:RegisterEvent("CHAT_MSG_ADDON")
versionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
versionFrame:RegisterEvent("RAID_ROSTER_UPDATE")
versionFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

versionFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "CHAT_MSG_ADDON" then
        if arg1 ~= PREFIX then return end
        addon:OnVersionMessage(arg2, arg4)
        return
    end
    addon.versionNag.pending = true
    addon.versionNag.elapsed = 0
end)

versionFrame:SetScript("OnUpdate", function(_, dt)
    local state = addon.versionNag
    if not state.pending then return end
    state.elapsed = state.elapsed + (dt or 0)
    if state.elapsed < SEND_DELAY then return end
    state.pending = false
    state.elapsed = 0
    addon:BroadcastVersion()
end)

addon.versionFrame = versionFrame
