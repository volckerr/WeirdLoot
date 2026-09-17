-- Version notifier battery (Core/VersionNag.lua).
--
-- The notifier's whole contract is: nag when MY version is below the SENDER's X-MinVersion, and stay
-- quiet otherwise. The interesting cases are the ones a naive implementation gets wrong: a dotted
-- string compare puts 1.4.10 below 1.4.9, and a sender on a much newer build with an unchanged
-- X-MinVersion must NOT nag, which is the entire reason the two numbers are separate.

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("version notifier battery")

local function capture(w)
    local lines = {}
    w.addon.Print = function(_, message) lines[#lines + 1] = message end
    return lines
end

H.test("CompareVersions orders dotted parts numerically, not as strings", function()
    local w = H.makeWorld("Masterlooter", true)
    local cmp = function(a, b) return w.addon:CompareVersions(a, b) end
    H.eq(cmp("1.4.9", "1.4.10"), -1, "1.4.9 is older than 1.4.10 (string compare gets this backwards)")
    H.eq(cmp("1.4.10", "1.4.9"), 1, "1.4.10 is newer than 1.4.9")
    H.eq(cmp("1.4.2", "1.4.2"), 0, "equal versions compare equal")
    H.eq(cmp("1.4", "1.4.0"), 0, "a missing trailing part counts as zero")
    H.eq(cmp("1.5", "1.4.9"), 1, "a higher minor beats any patch below it")
    H.eq(cmp("dev", "1.0.0"), -1, "a non-numeric build sorts below every real version")
end)

H.test("nags when own version is below the sender's X-MinVersion", function()
    local w = H.makeWorld("Raider", false)
    w.addon.version = "1.4.1"
    local lines = capture(w)
    w.addon:OnVersionMessage("1.9.0:1.4.2", "Someoneelse")
    H.eq(#lines, 1, "one nag printed")
    H.check(lines[1]:find("out of date"), "the line says the client is out of date")
    H.check(lines[1]:find("1.4.2", 1, true), "the line names the required version")
end)

H.test("stays quiet when a newer build carries an unchanged X-MinVersion", function()
    -- The point of splitting the two numbers: a cosmetic release must not tell the raid to update.
    local w = H.makeWorld("Raider", false)
    w.addon.version = "1.4.2"
    local lines = capture(w)
    w.addon:OnVersionMessage("1.9.0:1.4.2", "Someoneelse")
    H.eq(#lines, 0, "no nag while at or above the sender's X-MinVersion")
end)

H.test("nags at most once per session", function()
    local w = H.makeWorld("Raider", false)
    w.addon.version = "1.0.0"
    local lines = capture(w)
    for _ = 1, 25 do w.addon:OnVersionMessage("1.9.0:1.4.2", "Someoneelse") end
    H.eq(#lines, 1, "25 announcements produce one line, not 25")
end)

H.test("ignores its own announcement and malformed payloads", function()
    local w = H.makeWorld("Raider", false)
    w.addon.version = "1.0.0"
    local lines = capture(w)
    w.addon:OnVersionMessage("1.9.0:1.4.2", "Raider")
    H.eq(#lines, 0, "a client does not nag itself")
    w.addon:OnVersionMessage("garbage", "Someoneelse")
    w.addon:OnVersionMessage("1.9.0:", "Someoneelse")
    w.addon:OnVersionMessage(nil, "Someoneelse")
    H.eq(#lines, 0, "malformed payloads are dropped")
end)

H.test("announces version and X-MinVersion, gated by the disable switch", function()
    local w = H.makeWorld("Raider", false)
    local sent = {}
    w.env.SendAddonMessage = function(prefix, message, distribution)
        sent[#sent + 1] = { prefix = prefix, message = message, distribution = distribution }
    end
    w.env.IsInGuild = function() return true end
    w.addon.version, w.addon.minVersion = "1.4.2", "1.4.2"

    w.addon:BroadcastVersion()
    H.check(#sent > 0, "an announcement went out")
    H.eq(sent[1].message, "1.4.2:1.4.2", "the payload carries version and X-MinVersion")
    H.check(sent[1].prefix ~= w.addon.prefix, "the notifier uses its own prefix, not WeirdComm's")

    local guild = false
    for _, m in ipairs(sent) do if m.distribution == "GUILD" then guild = true end end
    H.check(guild, "announces on guild, as DBM does")

    w.addon.versionNag.lastSend = nil
    w.addon.db.options.disabled = true
    local before = #sent
    w.addon:BroadcastVersion()
    H.eq(#sent, before, "a disabled character sends nothing")
end)

H.test("WeirdLoot.toc declares X-MinVersion and it is not ahead of Version", function()
    local fh = assert(io.open("WeirdLoot.toc", "r"))
    local version, minVersion
    for line in fh:lines() do
        version = version or line:match("^## Version:%s*(.-)%s*$")
        minVersion = minVersion or line:match("^## X%-MinVersion:%s*(.-)%s*$")
    end
    fh:close()
    H.check(minVersion and minVersion ~= "", "the toc declares a ## X-MinVersion:")
    local w = H.makeWorld("Masterlooter", true)
    H.eq(w.addon.minVersion, minVersion, "VersionNag reads X-MinVersion from the toc")
    H.check(w.addon:CompareVersions(minVersion, version) <= 0,
        "X-MinVersion must not exceed Version, or the shipped build nags itself")
end)

F.endSuite()
