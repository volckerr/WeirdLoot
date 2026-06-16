local addon = WeirdLoot
local util = addon.util

local ROW_HEIGHT = 22
local TAB_KEYS = { "loot", "raiders", "results", "master" }
local TAB_LABELS = {
    loot = "Loot",
    raiders = "Raiders",
    results = "Results",
    master = "Loot Master",
}
local GROUP_LOOT_TEXTURES = {
    roll = {
        up = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
        down = "Interface\\Buttons\\UI-GroupLoot-Dice-Down",
        highlight = "Interface\\Buttons\\UI-GroupLoot-Dice-Highlight",
    },
    pass = {
        up = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        down = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
        highlight = "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight",
    },
}

local function isItemUsableForPlayer(itemLink)
    if not itemLink or itemLink == "" then
        return false
    end

    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemLink)
    local _, classToken = UnitClass("player")
    local normalizedType = util:NormalizeKey(itemType or "")
    local normalizedSubType = util:NormalizeKey(itemSubType or "")
    local normalizedEquipLoc = util:NormalizeKey(equipLoc or "")

    if not classToken then
        return false
    end

    local armorByClass = {
        DEATHKNIGHT = "plate",
        DRUID = "leather",
        HUNTER = "mail",
        MAGE = "cloth",
        PALADIN = "plate",
        PRIEST = "cloth",
        ROGUE = "leather",
        SHAMAN = "mail",
        WARLOCK = "cloth",
        WARRIOR = "plate",
    }

    local weaponByClass = {
        DEATHKNIGHT = { ["one-handed axes"] = true, ["two-handed axes"] = true, ["one-handed maces"] = true, ["two-handed maces"] = true, ["one-handed swords"] = true, ["two-handed swords"] = true, polearms = true, sigils = true },
        DRUID = { daggers = true, ["fist weapons"] = true, ["one-handed maces"] = true, ["two-handed maces"] = true, polearms = true, staves = true, idols = true },
        HUNTER = { ["one-handed axes"] = true, ["two-handed axes"] = true, daggers = true, ["fist weapons"] = true, polearms = true, staves = true, ["one-handed swords"] = true, ["two-handed swords"] = true, bows = true, guns = true, crossbows = true },
        MAGE = { daggers = true, ["one-handed swords"] = true, staves = true, wands = true },
        PALADIN = { ["one-handed axes"] = true, ["two-handed axes"] = true, ["one-handed maces"] = true, ["two-handed maces"] = true, polearms = true, ["one-handed swords"] = true, ["two-handed swords"] = true, shields = true, librams = true },
        PRIEST = { daggers = true, ["one-handed maces"] = true, staves = true, wands = true },
        ROGUE = { daggers = true, ["fist weapons"] = true, ["one-handed maces"] = true, ["one-handed swords"] = true, bows = true, guns = true, crossbows = true, thrown = true },
        SHAMAN = { ["one-handed axes"] = true, ["two-handed axes"] = true, daggers = true, ["fist weapons"] = true, ["one-handed maces"] = true, ["two-handed maces"] = true, staves = true, shields = true, totems = true },
        WARLOCK = { daggers = true, ["one-handed swords"] = true, staves = true, wands = true },
        WARRIOR = { ["one-handed axes"] = true, ["two-handed axes"] = true, daggers = true, ["fist weapons"] = true, ["one-handed maces"] = true, ["two-handed maces"] = true, polearms = true, ["one-handed swords"] = true, ["two-handed swords"] = true, bows = true, guns = true, crossbows = true, thrown = true, shields = true },
    }

    if normalizedType == "armor" then
        if normalizedSubType == "cloak"
            or normalizedSubType == "miscellaneous"
            or normalizedEquipLoc == "invtype_neck"
            or normalizedEquipLoc == "invtype_finger"
            or normalizedEquipLoc == "invtype_trinket"
            or normalizedEquipLoc == "invtype_holdable"
            or normalizedEquipLoc == "invtype_shield"
            or normalizedEquipLoc == "invtype_relic" then
            if normalizedEquipLoc == "invtype_shield" then
                return weaponByClass[classToken] and weaponByClass[classToken].shields or false
            end
            if normalizedEquipLoc == "invtype_relic" then
                if normalizedSubType == "idol" or normalizedSubType == "idols" then
                    return classToken == "DRUID"
                elseif normalizedSubType == "libram" or normalizedSubType == "librams" then
                    return classToken == "PALADIN"
                elseif normalizedSubType == "totem" or normalizedSubType == "totems" then
                    return classToken == "SHAMAN"
                elseif normalizedSubType == "sigil" or normalizedSubType == "sigils" then
                    return classToken == "DEATHKNIGHT"
                end
            end
            return true
        end

        return armorByClass[classToken] == normalizedSubType
    end

    if normalizedType == "weapon" then
        local allowed = weaponByClass[classToken]
        if not allowed then
            return false
        end

        return allowed[normalizedSubType] and true or false
    end

    if type(IsUsableItem) == "function" then
        local isUsable = IsUsableItem(itemLink)
        return isUsable and true or false
    end

    return false
end

local function getLootItemColumns(itemLink)
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemLink or "")
    local normalizedType = util:NormalizeKey(itemType or "")
    local normalizedSubType = util:NormalizeKey(itemSubType or "")
    local normalizedEquipLoc = util:NormalizeKey(equipLoc or "")

    local slotByEquipLoc = {
        invtype_head = "Head",
        invtype_neck = "Neck",
        invtype_shoulder = "Shoulder",
        invtype_body = "Shirt",
        invtype_chest = "Chest",
        invtype_robe = "Chest",
        invtype_waist = "Waist",
        invtype_legs = "Legs",
        invtype_feet = "Feet",
        invtype_wrist = "Wrist",
        invtype_hand = "Hands",
        invtype_finger = "Finger",
        invtype_trinket = "Trinket",
        invtype_cloak = "Back",
        invtype_weapon = "Weapon",
        invtype_2hweapon = "Two-Hand",
        invtype_weaponmainhand = "Main Hand",
        invtype_weaponoffhand = "Off Hand",
        invtype_holdable = "Off Hand",
        invtype_shield = "Shield",
        invtype_ranged = "Ranged",
        invtype_rangedright = "Ranged",
        invtype_thrown = "Thrown",
        invtype_relic = "Relic",
        invtype_tabard = "Tabard",
    }

    local slotText = slotByEquipLoc[normalizedEquipLoc] or util:TitleCaseWords(normalizedSubType ~= "" and normalizedSubType or normalizedType)
    if normalizedEquipLoc == "invtype_relic" then
        slotText = util:TitleCaseWords(normalizedSubType ~= "" and normalizedSubType or "Relic")
    end

    local typeText = ""
    if normalizedType == "armor" then
        typeText = util:TitleCaseWords(normalizedSubType ~= "" and normalizedSubType or "Armor")
    elseif normalizedType == "weapon" then
        typeText = util:TitleCaseWords(normalizedSubType ~= "" and normalizedSubType or "Weapon")
    else
        typeText = util:TitleCaseWords(normalizedSubType ~= "" and normalizedSubType or normalizedType)
    end

    return typeText, slotText
end

local function getLootItemLookupName(item)
    if not item then
        return ""
    end

    local resolvedName = item.link and GetItemInfo(item.link)
    if resolvedName and resolvedName ~= "" then
        return resolvedName
    end

    if item.link and item.link ~= "" then
        local linkedName = string.match(item.link, "%[(.+)%]")
        if linkedName and linkedName ~= "" then
            return linkedName
        end
    end

    return item.name or ""
end

local function getLootItemInfoText(item)
    local lookupName = getLootItemLookupName(item)
    local entry = addon.defaultItemInfo and addon.defaultItemInfo[util:NormalizeKey(lookupName)]
    if not entry then
        return ""
    end

    local note = string.trim(entry.note or "")
    local role = string.trim(entry.role or "")
    if note ~= "" and role ~= "" then
        return string.format("%s, %s", note, role)
    end

    return note ~= "" and note or role
end

local function createLabel(parent, text, anchor, relativeTo, relativePoint, offsetX, offsetY)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint(anchor, relativeTo, relativePoint, offsetX, offsetY)
    fontString:SetJustifyH("LEFT")
    fontString:SetText(text)
    return fontString
end

local function createButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

local function createLootChoiceButton(parent, textures)
    local button = CreateFrame("CheckButton", nil, parent)
    button:SetWidth(24)
    button:SetHeight(24)
    button:SetNormalTexture(textures.up)
    button:SetPushedTexture(textures.down)
    button:SetHighlightTexture(textures.highlight, "ADD")
    button:SetCheckedTexture(textures.down)
    return button
end

local function setLootChoiceButtonState(button, shouldRoll)
    local textures = shouldRoll and GROUP_LOOT_TEXTURES.roll or GROUP_LOOT_TEXTURES.pass
    button:SetNormalTexture(textures.up)
    button:SetPushedTexture(textures.down)
    button:SetHighlightTexture(textures.highlight, "ADD")
    button:SetCheckedTexture(textures.down)
    button:SetChecked(shouldRoll and true or false)
end

local function createBackdropFrame(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    return frame
end

local function createScrollList(parent, name, rowCount, initializer)
    local frame = createBackdropFrame(name, parent)
    frame.scroll = CreateFrame("ScrollFrame", name .. "Scroll", frame, "FauxScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 0, -4)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    frame.rows = {}
    for index = 1, rowCount do
        local row = CreateFrame("Button", name .. "Row" .. index, frame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", 6, 0)
        row:SetPoint("RIGHT", -6, 0)
        if index == 1 then
            row:SetPoint("TOP", frame, "TOP", 0, -8)
        else
            row:SetPoint("TOP", frame.rows[index - 1], "BOTTOM", 0, -2)
        end
        initializer(row, index)
        frame.rows[index] = row
    end

    frame.update = function(totalCount, updater)
        frame.totalCount = totalCount
        frame.rowUpdater = updater
        local offset = FauxScrollFrame_GetOffset(frame.scroll)
        FauxScrollFrame_Update(frame.scroll, totalCount, rowCount, ROW_HEIGHT)
        for index, row in ipairs(frame.rows) do
            local dataIndex = index + offset
            updater(row, dataIndex)
        end
    end

    frame.scroll:SetScript("OnVerticalScroll", function(scrollFrame, offset)
        FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, ROW_HEIGHT, function()
            if frame.rowUpdater then
                frame.update(frame.totalCount or 0, frame.rowUpdater)
            end
        end)
    end)

    return frame
end

function addon:InitializeUI()
    self.ui = self.ui or {}

    local frame = createBackdropFrame("WeirdLootFrame", UIParent)
    frame:SetWidth(980)
    frame:SetHeight(640)
    frame:SetPoint("CENTER", UIParent, "CENTER", self.db.ui.frame.x or 0, self.db.ui.frame.y or 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local _, _, _, x, y = selfFrame:GetPoint()
        addon.db.ui.frame.x = x
        addon.db.ui.frame.y = y
    end)
    frame:Hide()

    local title = createLabel(frame, "WeirdLoot", "TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetFontObject(GameFontHighlightLarge)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local status = createLabel(frame, "", "TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    status:SetWidth(720)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 44)

    self.ui.frame = frame
    self.ui.status = status
    self.ui.content = content
    self.ui.tabs = {}
    self.ui.panels = {}
    self.ui.selectedTab = self.db.ui.selectedTab or "loot"

    self:BuildLootTab()
    self:BuildRaidersTab()
    self:BuildResultsTab()
    self:BuildMasterTab()
    self:BuildBottomTabs()

    self:RegisterCallback("STATE_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("CONFIG_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("ROSTER_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("AUTHORITY_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("SESSION_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("RESULTS_UPDATED", function()
        addon:RefreshUI()
    end)

    self:SelectTab(self.ui.selectedTab)
    self:RefreshUI()
end

function addon:BuildBottomTabs()
    local previous
    for _, key in ipairs(TAB_KEYS) do
        local tab = createButton(self.ui.frame, TAB_LABELS[key], 120, 24)
        if not previous then
            tab:SetPoint("BOTTOMLEFT", self.ui.frame, "BOTTOMLEFT", 16, 12)
        else
            tab:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        end
        tab:SetScript("OnClick", function()
            addon:SelectTab(key)
        end)
        self.ui.tabs[key] = tab
        previous = tab
    end
end

function addon:SelectTab(tabKey)
    self.ui.selectedTab = tabKey
    self.db.ui.selectedTab = tabKey

    for key, panel in pairs(self.ui.panels) do
        if key == tabKey then
            panel:Show()
        else
            panel:Hide()
        end
    end

    self:RefreshUI()
end

function addon:ToggleMainFrame()
    if not self.ui or not self.ui.frame then
        self:Print("UI is not initialized yet. If this keeps happening, reload the UI and check script errors.")
        return
    end

    if self.ui.frame:IsShown() then
        self.ui.frame:Hide()
    else
        self.ui.frame:Show()
        self:RefreshUI()
    end
end

function addon:TradeSelectedWinner()
    local result = self.ui and self.ui.selectedResult
    local winner = result and result.winner
    if not result or not winner or winner == "" or winner == "No winner" then
        self:Print("No winner is selected for trade.")
        return
    end

    if UnitExists("target") and util:NormalizeKey(util:GetPlayerName("target") or "") == util:NormalizeKey(winner) then
        InitiateTrade("target")
    else
        self:Print("Click Target Winner first, then click Trade Winner.")
    end
end

function addon:LoadSelectedItemForTrade()
    local result = self.ui and self.ui.selectedResult
    if not result or not result.itemLink or result.itemLink == "" then
        self:Print("No item is selected to load.")
        return
    end

    local bag, slot = util:FindBagItemByLink(result.itemLink)
    if not bag or not slot then
        self:Print("Could not find that item in your bags.")
        return
    end

    if CursorHasItem() then
        ClearCursor()
    end

    PickupContainerItem(bag, slot)
    self:Print(string.format("Picked up %s from bag %d slot %d. Click the trade slot to place it.", result.itemName or "item", bag, slot))
end

function addon:BuildLootTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.loot = panel

    local header = createLabel(panel, "Session items", "TOPLEFT", panel, "TOPLEFT", 4, -4)
    header:SetFontObject(GameFontHighlight)

    local syncButton = createButton(panel, "Request Sync", 110, 22)
    syncButton:SetPoint("LEFT", header, "RIGHT", 12, 0)
    syncButton:SetScript("OnClick", function()
        addon:RequestSessionSync()
    end)
    panel.syncButton = syncButton

    local usabilityButton = createButton(panel, "Usable: Off", 110, 22)
    usabilityButton:SetPoint("LEFT", syncButton, "RIGHT", 8, 0)
    usabilityButton:SetScript("OnClick", function()
        addon:ToggleLootUsabilitySort()
    end)
    panel.usabilityButton = usabilityButton

    local headerName = createButton(panel, "Name", 80, 18)
    headerName:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 24, -12)
    headerName:SetScript("OnClick", function()
        addon:SetLootSortMode("name")
    end)
    panel.headerName = headerName

    local headerChoice = createButton(panel, "Roll", 56, 18)
    headerChoice:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 336, -12)
    headerChoice:SetScript("OnClick", function() end)
    panel.headerChoice = headerChoice

    local headerType = createButton(panel, "Type", 70, 18)
    headerType:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 422, -12)
    headerType:SetScript("OnClick", function()
        addon:SetLootSortMode("type")
    end)
    panel.headerType = headerType

    local headerSlot = createButton(panel, "Slot", 62, 18)
    headerSlot:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 500, -12)
    headerSlot:SetScript("OnClick", function()
        addon:SetLootSortMode("slot")
    end)
    panel.headerSlot = headerSlot

    local headerInfo = createButton(panel, "Info", 78, 18)
    headerInfo:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 570, -12)
    headerInfo:SetScript("OnClick", function()
        addon:SetLootSortMode("info")
    end)
    panel.headerInfo = headerInfo

    local headerRollers = createButton(panel, "Rollers", 80, 18)
    headerRollers:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 828, -12)
    headerRollers:SetScript("OnClick", function() end)
    panel.headerRollers = headerRollers

    local list = createScrollList(panel, "WeirdLootLootList", 20, function(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(18)
        row.icon:SetHeight(18)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.name = createLabel(row, "", "LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(292)

        row.choice = createLootChoiceButton(row, GROUP_LOOT_TEXTURES.pass)
        row.choice:SetPoint("LEFT", row, "LEFT", 344, 0)
        row.choice:SetScript("OnClick", function(button)
            if not row.item then
                return
            end

            local playerName = util:GetPlayerName("player")
            local shouldRoll = not addon:GetPlayerResponse(row.item.id, playerName)
            addon:SetPlayerResponse(row.item.id, playerName, shouldRoll)
            addon:BroadcastSelectionState(row.item.id, playerName, shouldRoll)
            addon:SendSelection(row.item.id, shouldRoll)
            setLootChoiceButtonState(button, shouldRoll)
        end)

        row.itemType = createLabel(row, "", "LEFT", row, "LEFT", 422, 0)
        row.itemType:SetWidth(72)

        row.itemSlot = createLabel(row, "", "LEFT", row, "LEFT", 500, 0)
        row.itemSlot:SetWidth(64)

        row.info = createLabel(row, "", "LEFT", row, "LEFT", 570, 0)
        row.info:SetWidth(222)

        row.state = createLabel(row, "", "LEFT", row, "LEFT", 836, 0)
        row.state:SetWidth(72)
        row.state:SetJustifyH("LEFT")
        row.stateHitbox = CreateFrame("Frame", nil, row)
        row.stateHitbox:SetPoint("TOPLEFT", row.state, "TOPLEFT", -4, 4)
        row.stateHitbox:SetPoint("BOTTOMRIGHT", row.state, "BOTTOMRIGHT", 4, -4)
        row.stateHitbox:EnableMouse(true)
        row.stateHitbox:SetScript("OnEnter", function()
            if not row.item then
                return
            end

            local rollers = {}
            for playerKey, shouldRoll in pairs(addon.session.responses[row.item.id] or {}) do
                if shouldRoll then
                    local attendee = addon:GetAttendee(playerKey) or addon:GetRosterProfile(playerKey)
                    rollers[#rollers + 1] = {
                        name = attendee and attendee.name or playerKey,
                        className = attendee and attendee.className or "",
                        specName = attendee and attendee.specName or "",
                    }
                end
            end

            table.sort(rollers, function(left, right)
                return string.lower(left.name or "") < string.lower(right.name or "")
            end)

            GameTooltip:SetOwner(row.stateHitbox, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", row.stateHitbox, "BOTTOMLEFT", 0, -4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Players Rolling", 1, 0.82, 0)

            if #rollers == 0 then
                GameTooltip:AddLine("No active rollers", 1, 1, 1)
            else
                for _, roller in ipairs(rollers) do
                    local classSpec = string.trim((roller.className or "") .. " " .. (roller.specName or ""))
                    local colorCode = util:GetClassColorCode(roller.className)
                    local line = colorCode .. (roller.name or "") .. "|r"
                    if classSpec ~= "" then
                        line = line .. " " .. colorCode .. "- " .. classSpec .. "|r"
                    end
                    GameTooltip:AddLine(line, 1, 1, 1)
                end
            end

            GameTooltip:Show()
        end)
        row.stateHitbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnEnter", function(selfRow)
            if not selfRow.item or not selfRow.item.link or selfRow.item.link == "" then
                return
            end

            GameTooltip:SetOwner(selfRow, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPRIGHT", selfRow, "TOPLEFT", -8, 0)
            GameTooltip:SetHyperlink(selfRow.item.link)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnClick", function(selfRow, button)
            if button ~= "LeftButton" or not selfRow.item or not selfRow.item.link or selfRow.item.link == "" then
                return
            end

            if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(selfRow.item.link)
                return
            end

            if DressUpItemLink then
                DressUpItemLink(selfRow.item.link)
            else
                GameTooltip:SetOwner(selfRow, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("TOPRIGHT", selfRow, "TOPLEFT", -8, 0)
                GameTooltip:SetHyperlink(selfRow.item.link)
                GameTooltip:Show()
            end
        end)
    end)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -28)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    self.ui.lootList = list
end

function addon:ToggleLootSortMode()
    self.db.ui.lootSortMode = self.db.ui.lootSortMode == "gear" and "name" or "gear"
    self:RefreshLootTab()
end

function addon:SetLootSortMode(sortMode)
    self.db.ui.lootSortMode = sortMode or "name"
    self:RefreshLootTab()
end

function addon:ToggleLootUsabilitySort()
    self.db.ui.lootUsabilitySort = not self.db.ui.lootUsabilitySort
    self:RefreshLootTab()
end

function addon:GetSortedLootItems()
    local items = {}
    for _, item in ipairs(self.session.items or {}) do
        items[#items + 1] = item
    end

    local sortMode = self.db.ui.lootSortMode or "name"
    if sortMode == "gear" then
        table.sort(items, function(left, right)
            if self.db.ui.lootUsabilitySort then
                local leftUsable = isItemUsableForPlayer(left.link)
                local rightUsable = isItemUsableForPlayer(right.link)
                if leftUsable ~= rightUsable then
                    return leftUsable
                end
            end

            local leftInfo = util:GetLootSortInfo(left.link)
            local rightInfo = util:GetLootSortInfo(right.link)

            if leftInfo.order ~= rightInfo.order then
                return leftInfo.order < rightInfo.order
            end
            if leftInfo.subtype ~= rightInfo.subtype then
                return leftInfo.subtype < rightInfo.subtype
            end
            return util:NormalizeKey(left.name or "") < util:NormalizeKey(right.name or "")
        end)
    elseif sortMode == "type" then
        table.sort(items, function(left, right)
            if self.db.ui.lootUsabilitySort then
                local leftUsable = isItemUsableForPlayer(left.link)
                local rightUsable = isItemUsableForPlayer(right.link)
                if leftUsable ~= rightUsable then
                    return leftUsable
                end
            end

            local leftType = util:NormalizeKey(select(1, getLootItemColumns(left.link)))
            local rightType = util:NormalizeKey(select(1, getLootItemColumns(right.link)))
            if leftType ~= rightType then
                return leftType < rightType
            end
            return util:NormalizeKey(left.name or "") < util:NormalizeKey(right.name or "")
        end)
    elseif sortMode == "slot" then
        table.sort(items, function(left, right)
            if self.db.ui.lootUsabilitySort then
                local leftUsable = isItemUsableForPlayer(left.link)
                local rightUsable = isItemUsableForPlayer(right.link)
                if leftUsable ~= rightUsable then
                    return leftUsable
                end
            end

            local leftSlot = util:NormalizeKey(select(2, getLootItemColumns(left.link)))
            local rightSlot = util:NormalizeKey(select(2, getLootItemColumns(right.link)))
            if leftSlot ~= rightSlot then
                return leftSlot < rightSlot
            end
            return util:NormalizeKey(left.name or "") < util:NormalizeKey(right.name or "")
        end)
    elseif sortMode == "info" then
        table.sort(items, function(left, right)
            if self.db.ui.lootUsabilitySort then
                local leftUsable = isItemUsableForPlayer(left.link)
                local rightUsable = isItemUsableForPlayer(right.link)
                if leftUsable ~= rightUsable then
                    return leftUsable
                end
            end

            local leftInfo = util:NormalizeKey(getLootItemInfoText(left))
            local rightInfo = util:NormalizeKey(getLootItemInfoText(right))
            if leftInfo ~= rightInfo then
                return leftInfo < rightInfo
            end
            return util:NormalizeKey(left.name or "") < util:NormalizeKey(right.name or "")
        end)
    else
        table.sort(items, function(left, right)
            if self.db.ui.lootUsabilitySort then
                local leftUsable = isItemUsableForPlayer(left.link)
                local rightUsable = isItemUsableForPlayer(right.link)
                if leftUsable ~= rightUsable then
                    return leftUsable
                end
            end

            return util:NormalizeKey(left.name or "") < util:NormalizeKey(right.name or "")
        end)
    end

    return items
end

function addon:BuildRaidersTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.raiders = panel

    local summary = createLabel(panel, "", "TOPLEFT", panel, "TOPLEFT", 8, -6)
    summary:SetWidth(760)
    summary:SetTextColor(0.9, 0.82, 0.5)

    local rosterFrame = createBackdropFrame("WeirdLootRaidersFrame", panel)
    rosterFrame:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
    rosterFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 0)

    local headerPresence = createLabel(rosterFrame, "Raid", "TOPLEFT", rosterFrame, "TOPLEFT", 8, -8)
    headerPresence:SetWidth(48)
    headerPresence:SetTextColor(0.8, 0.8, 0.8)

    local headerName = createLabel(panel, "Name", "LEFT", headerPresence, "RIGHT", 14, 0)
    headerName:SetWidth(132)
    headerName:SetTextColor(0.8, 0.8, 0.8)

    local headerClassSpec = createLabel(panel, "Class / Spec", "LEFT", headerName, "RIGHT", 4, 0)
    headerClassSpec:SetWidth(200)
    headerClassSpec:SetTextColor(0.8, 0.8, 0.8)

    local headerStatus = createLabel(panel, "Status", "LEFT", headerClassSpec, "RIGHT", 12, 0)
    headerStatus:SetWidth(110)
    headerStatus:SetTextColor(0.8, 0.8, 0.8)

    local headerSource = createLabel(panel, "Source", "LEFT", headerStatus, "RIGHT", 12, 0)
    headerSource:SetWidth(80)
    headerSource:SetTextColor(0.8, 0.8, 0.8)

    local list = createScrollList(rosterFrame, "WeirdLootRaidersList", 18, function(row)
        row.present = createLabel(row, "", "LEFT", row, "LEFT", 8, 0)
        row.present:SetWidth(48)
        row.name = createLabel(row, "", "LEFT", row.present, "RIGHT", 14, 0)
        row.name:SetWidth(132)
        row.classSpec = createLabel(row, "", "LEFT", row.name, "RIGHT", 4, 0)
        row.classSpec:SetWidth(200)
        row.status = createLabel(row, "", "LEFT", row.classSpec, "RIGHT", 12, 0)
        row.status:SetWidth(110)
        row.source = createLabel(row, "", "LEFT", row.status, "RIGHT", 12, 0)
        row.source:SetWidth(80)
    end)
    list:SetPoint("TOPLEFT", headerPresence, "BOTTOMLEFT", 0, -8)
    list:SetPoint("BOTTOMRIGHT", rosterFrame, "BOTTOMRIGHT", -6, 6)
    self.ui.raidersList = list
    self.ui.raidersSummary = summary
end

function addon:BuildResultsTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.results = panel

    local list = createScrollList(panel, "WeirdLootResultsList", 16, function(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(18)
        row.icon:SetHeight(18)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.name = createLabel(row, "", "LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(290)
        row.winner = createLabel(row, "", "LEFT", row.name, "RIGHT", 12, 0)
        row.winner:SetWidth(200)

        row:SetScript("OnEnter", function(selfRow)
            local result = selfRow.result
            if not result or not result.itemLink or result.itemLink == "" then
                return
            end

            GameTooltip:SetOwner(selfRow, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPRIGHT", selfRow, "TOPLEFT", -8, 0)
            GameTooltip:SetHyperlink(result.itemLink)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnClick", function()
            if row.result then
                addon.ui.selectedResult = row.result
                addon:RefreshUI()
            end

            if not row.result or not row.result.itemLink or row.result.itemLink == "" then
                return
            end

            if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(row.result.itemLink)
                return
            end

            if DressUpItemLink then
                DressUpItemLink(row.result.itemLink)
            else
                GameTooltip:SetOwner(row, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
                GameTooltip:SetHyperlink(row.result.itemLink)
                GameTooltip:Show()
            end
        end)
    end)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    list:SetWidth(520)

    local detailFrame = createBackdropFrame("WeirdLootResultDetail", panel)
    detailFrame:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    detailFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local itemHeader = CreateFrame("Button", nil, detailFrame)
    itemHeader:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 8, -8)
    itemHeader:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -30, -8)
    itemHeader:SetHeight(20)
    itemHeader.text = itemHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemHeader.text:SetPoint("LEFT", itemHeader, "LEFT", 0, 0)
    itemHeader.text:SetJustifyH("LEFT")
    itemHeader.text:SetWidth(360)
    itemHeader:SetScript("OnEnter", function()
        local result = addon.ui and addon.ui.selectedResult
        if not result or not result.itemLink or result.itemLink == "" then
            return
        end

        GameTooltip:SetOwner(itemHeader, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", itemHeader, "BOTTOMLEFT", 0, -4)
        GameTooltip:SetHyperlink(result.itemLink)
        GameTooltip:Show()
    end)
    itemHeader:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    itemHeader:SetScript("OnClick", function()
        local result = addon.ui and addon.ui.selectedResult
        if not result or not result.itemLink or result.itemLink == "" then
            return
        end

        if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then
            ChatEdit_InsertLink(result.itemLink)
            return
        end

        if DressUpItemLink then
            DressUpItemLink(result.itemLink)
        end
    end)

    local scroll = CreateFrame("ScrollFrame", "WeirdLootResultDetailScroll", detailFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", itemHeader, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)

    local editBox = CreateFrame("EditBox", "WeirdLootResultDetailText", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(380)
    editBox:SetHeight(1120)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    local targetButton = CreateFrame("Button", "WeirdLootResultTargetButton", detailFrame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    targetButton:SetWidth(110)
    targetButton:SetHeight(22)
    targetButton:SetPoint("BOTTOMLEFT", detailFrame, "BOTTOMLEFT", 8, 8)
    targetButton:SetText("Target + Whisper")
    targetButton:SetAttribute("type", "macro")

    local tradeButton = createButton(detailFrame, "Trade Winner", 110, 22)
    tradeButton:SetPoint("LEFT", targetButton, "RIGHT", 8, 0)
    tradeButton:SetScript("OnClick", function()
        addon:TradeSelectedWinner()
    end)

    local loadItemButton = createButton(detailFrame, "Load Item", 100, 22)
    loadItemButton:SetPoint("LEFT", tradeButton, "RIGHT", 8, 0)
    loadItemButton:SetScript("OnClick", function()
        addon:LoadSelectedItemForTrade()
    end)

    local tradeHelp = createLabel(detailFrame, "", "BOTTOMLEFT", targetButton, "TOPLEFT", 0, 10)
    tradeHelp:SetWidth(420)
    tradeHelp:SetTextColor(0.85, 0.85, 0.85)

    self.ui.resultsList = list
    self.ui.resultItemHeader = itemHeader
    self.ui.resultDetail = editBox
    self.ui.resultTargetButton = targetButton
    self.ui.resultTradeButton = tradeButton
    self.ui.resultLoadItemButton = loadItemButton
    self.ui.resultTradeHelp = tradeHelp
end

function addon:BuildMasterTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.master = panel

    panel.warning = createLabel(panel, "", "TOPLEFT", panel, "TOPLEFT", 8, -8)
    panel.warning:SetTextColor(1, 0.2, 0.2)

    local startButton = createButton(panel, "Start Session", 120, 24)
    startButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    startButton:SetScript("OnClick", function()
        addon:StartLootSession()
    end)

    local scanButton = createButton(panel, "Scan Bags", 120, 24)
    scanButton:SetPoint("LEFT", startButton, "RIGHT", 8, 0)
    scanButton:SetScript("OnClick", function()
        addon:RefreshSessionItems(true)
    end)

    local broadcastButton = createButton(panel, "Broadcast", 120, 24)
    broadcastButton:SetPoint("LEFT", scanButton, "RIGHT", 8, 0)
    broadcastButton:SetScript("OnClick", function()
        addon:BroadcastSession()
    end)

    local processButton = createButton(panel, "Process Loot", 120, 24)
    processButton:SetPoint("LEFT", broadcastButton, "RIGHT", 8, 0)
    processButton:SetScript("OnClick", function()
        addon:ProcessLoot()
    end)

    panel.startButton = startButton
    panel.scanButton = scanButton
    panel.broadcastButton = broadcastButton
    panel.processButton = processButton

    panel.summary = createLabel(panel, "", "TOPLEFT", startButton, "BOTTOMLEFT", 0, -24)
    panel.summary:SetWidth(900)
    panel.summary:SetJustifyV("TOP")

    self.ui.masterPanel = panel
end

function addon:RefreshUI()
    if not self.ui or not self.ui.frame then
        return
    end

    local session = self:GetCurrentSession()
    local lootMasterName = self:GetLootMasterName() or "Unknown"
    local authority = self:IsAuthorizedLootMaster() and "Yes" or "No"
    local sessionState = session.active and ("Active session " .. (session.id or "")) or "No active session"
    self.ui.status:SetText(string.format("Loot master: %s | Authorized: %s | %s", lootMasterName, authority, sessionState))

    self:RefreshLootTab()
    self:RefreshRaidersTab()
    self:RefreshResultsTab()
    self:RefreshMasterTab()
end

function addon:RefreshLootTab()
    local items = self:GetSortedLootItems()
    local playerName = util:GetPlayerName("player")
    if self.ui.panels and self.ui.panels.loot and self.ui.panels.loot.syncButton then
        local label = self:IsAuthorizedLootMaster() and "Rebroadcast" or "Request Sync"
        self.ui.panels.loot.syncButton:SetText(label)
    end
    if self.ui.panels and self.ui.panels.loot and self.ui.panels.loot.usabilityButton then
        local usabilityLabel = self.db.ui.lootUsabilitySort and "Usable: On" or "Usable: Off"
        self.ui.panels.loot.usabilityButton:SetText(usabilityLabel)
    end
    self.ui.lootList.update(#items, function(row, index)
        local item = items[index]
        row.item = item
        if not item then
            row:Hide()
            return
        end

        row:Show()
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local itemText = item.link and item.link ~= "" and item.link or item.name or ""
        if (item.quantity or 1) > 1 then
            itemText = string.format("%s x%d", itemText, item.quantity)
        end
        row.name:SetText(itemText)

        local shouldRoll = self:GetPlayerResponse(item.id, playerName)
        setLootChoiceButtonState(row.choice, shouldRoll)
        local typeText, slotText = getLootItemColumns(item.link)
        row.itemType:SetText(typeText)
        row.itemSlot:SetText(slotText)
        row.info:SetText(getLootItemInfoText(item))

        local rollCount = 0
        for _, shouldPlayerRoll in pairs(self.session.responses[item.id] or {}) do
            if shouldPlayerRoll then
                rollCount = rollCount + 1
            end
        end
        row.state:SetText(string.format("%d roller(s)", rollCount))
    end)
end

function addon:RefreshRaidersTab()
    local rosterEntries = self:GetRosterDisplayList()
    local configuredCount = #self:GetRosterEntries()
    local attendeeCount = #self:GetAttendees()
    local matchedCount = 0
    local unconfiguredCount = 0

    for _, entry in ipairs(rosterEntries) do
        if entry.present and entry.source == "configured" then
            matchedCount = matchedCount + 1
        elseif entry.present and entry.source == "unconfigured" then
            unconfiguredCount = unconfiguredCount + 1
        end
    end

    if self.ui.raidersSummary then
        self.ui.raidersSummary:SetText(string.format(
            "Master roster: %d | In current raid: %d | Matched: %d | Unconfigured in raid: %d",
            configuredCount,
            attendeeCount,
            matchedCount,
            unconfiguredCount
        ))
    end

    self.ui.raidersList.update(#rosterEntries, function(row, index)
        local entry = rosterEntries[index]
        if not entry then
            row:Hide()
            return
        end
        row:Show()
        row.present:SetText(entry.present and "Yes" or "No")
        row.present:SetTextColor(entry.present and 0.3 or 0.7, entry.present and 0.9 or 0.3, 0.3)
        row.name:SetText((util:GetClassColorCode(entry.className) or "|cffffffff") .. util:TitleCaseWords(entry.name or "") .. "|r")
        row.classSpec:SetText((util:GetClassColorCode(entry.className) or "|cffffffff") .. util:TitleCaseWords(string.trim((entry.className or "") .. " " .. (entry.specName or ""))) .. "|r")
        row.status:SetText(util:PlayerDisplayStatus(entry.status))
        row.source:SetText(entry.source == "configured" and "Roster" or "Live")
        row.source:SetTextColor(entry.source == "configured" and 0.85 or 1, entry.source == "configured" and 0.85 or 0.45, entry.source == "configured" and 0.85 or 0.45)
    end)
end

function addon:RefreshResultsTab()
    local results = self.session.results or {}
    self.ui.resultsList.update(#results, function(row, index)
        local result = results[index]
        row.result = result
        if not result then
            row:Hide()
            return
        end
        row:Show()
        row.icon:SetTexture(result.itemIcon or result.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local itemText = (result.itemLink and result.itemLink ~= "" and result.itemLink) or result.itemName or ""
        if (result.quantity or 1) > 1 then
            itemText = string.format("%s x%d", itemText, result.quantity)
        end
        row.name:SetText(itemText)
        if result.winners and #result.winners > 0 and result.winnerDetails and #result.winnerDetails > 0 then
            local winnerParts = {}
            for winnerIndex, winnerName in ipairs(result.winners) do
                local detail = result.winnerDetails[winnerIndex] or {}
                local colorCode = util:GetClassColorCode(detail.className)
                winnerParts[#winnerParts + 1] = (colorCode or "|cffffffff") .. winnerName .. "|r"
            end
            row.winner:SetText(table.concat(winnerParts, ", "))
        else
            row.winner:SetText(result.winnersText or result.winner or "No winner")
        end
    end)

    local selected = self.ui.selectedResult
    if not selected and results[1] then
        selected = results[1]
        self.ui.selectedResult = selected
    end

    if self.ui.resultItemHeader and self.ui.resultItemHeader.text then
        local itemHeaderText = selected and (((selected.itemLink and selected.itemLink ~= "" and selected.itemLink) or selected.itemName or "")) or "No results yet."
        if selected and (selected.quantity or 1) > 1 then
            itemHeaderText = string.format("%s x%d", itemHeaderText, selected.quantity)
        end
        self.ui.resultItemHeader.text:SetText(itemHeaderText)
    end

    self.ui.resultDetail:SetText(selected and selected.detailText or "No results yet.")

    local canAct = self:IsAuthorizedLootMaster() and selected and selected.winner and selected.winner ~= "" and selected.winner ~= "No winner"
    if self.ui.resultTargetButton then
        if canAct then
            self.ui.resultTargetButton:Enable()
            local itemName = selected.itemLink or selected.itemName or "your item"
            local whisperName = selected.winner or ""
            local macroText = string.format("/target %s\n/w %s You won %s. Please run to the loot master for trade.", string.lower(whisperName), whisperName, itemName)
            self.ui.resultTargetButton:SetAttribute("macrotext", macroText)
            self.ui.resultTradeButton:Enable()
            self.ui.resultLoadItemButton:Enable()
            self.ui.resultTargetButton:Show()
            self.ui.resultTradeButton:Show()
            self.ui.resultLoadItemButton:Show()
            self.ui.resultTradeHelp:Show()
            self.ui.resultTradeHelp:SetText("Trade flow: click Target + Whisper, click Trade Winner, load item onto cursor, then click the trade slot.")
        else
            self.ui.resultTargetButton:Disable()
            self.ui.resultTradeButton:Disable()
            self.ui.resultLoadItemButton:Disable()
            if self:IsAuthorizedLootMaster() then
                self.ui.resultTargetButton:Show()
                self.ui.resultTradeButton:Show()
                self.ui.resultLoadItemButton:Show()
                self.ui.resultTradeHelp:Show()
                self.ui.resultTradeHelp:SetText("Select a result with a winner to use trade actions.")
            else
                self.ui.resultTargetButton:Hide()
                self.ui.resultTradeButton:Hide()
                self.ui.resultLoadItemButton:Hide()
                self.ui.resultTradeHelp:Hide()
            end
        end
    end
end

function addon:RefreshMasterTab()
    local panel = self.ui.masterPanel
    local authorized = self:IsAuthorizedLootMaster()
    panel.warning:SetText(authorized and "" or "Loot master controls are locked until you are the loot master or leadership fallback.")

    if authorized then
        panel.startButton:Enable()
        panel.scanButton:Enable()
        panel.broadcastButton:Enable()
        panel.processButton:Enable()
    else
        panel.startButton:Disable()
        panel.scanButton:Disable()
        panel.broadcastButton:Disable()
        panel.processButton:Disable()
    end

    local session = self:GetCurrentSession()
    local attendeeCount = #(self:GetAttendees() or {})
    local itemCount = #(session.items or {})
    local resultCount = #(session.results or {})
    panel.summary:SetText(string.format(
        "Controls:\nStart Session establishes the active loot session.\nScan Bags pulls current epic items from the loot master's bags.\nBroadcast syncs items and current roll state to the raid.\nProcess Loot resolves winners and records results.\n\nSession snapshot:\nConfig revision: %d\nRaid attendees: %d\nSession items: %d\nProcessed results: %d",
        self.config.revision or 0,
        attendeeCount,
        itemCount,
        resultCount
    ))
end
