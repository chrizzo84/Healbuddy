local _, ns = ...

local options, rows, tabs
local currentMod = ""

---------------------------------------------------------------------------
-- Eigene, schlanke Combobox (mit Icons, scrollbar per Mausrad)
---------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 20, 14
local list, catcher

local function Flat(frame, r, g, b, a, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function RenderList()
    local items, owner = list.items, list.owner
    local visible = math.min(#items, MAX_ROWS)
    list:SetSize(owner:GetWidth(), visible * ROW_H + 4)
    for i = 1, math.max(visible, #list.rows) do
        local row = list.rows[i]
        if i > visible then
            row:Hide()
        else
            if not row then
                row = CreateFrame("Button", nil, list)
                row:SetHeight(ROW_H)
                row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * ROW_H)
                Flat(row, 1, 1, 1, 0.15, "HIGHLIGHT")
                row.sel = Flat(row, 0.2, 0.6, 0.9, 0.35)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", 2, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 22, 0)
                row.text:SetPoint("RIGHT", -2, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row:SetScript("OnClick", function(self)
                    local o, item = list.owner, self.item
                    list:Hide()
                    o.onSelect(item.value)
                end)
                list.rows[i] = row
            end
            local item = items[i + list.offset]
            row.item = item
            row.text:SetText(item.text)
            row.icon:SetTexture(item.icon)
            row.sel:SetShown(item.value == owner.value)
            row:Show()
        end
    end
end

local function OpenList(owner)
    if not list then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", function() list:Hide() end)

        list = CreateFrame("Frame", nil, UIParent)
        list:SetFrameStrata("TOOLTIP")
        list:EnableMouse(true)
        list:EnableMouseWheel(true)
        Flat(list, 0.05, 0.05, 0.07, 0.98)
        list.rows = {}
        list:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, #self.items - MAX_ROWS)
            self.offset = math.min(max, math.max(0, self.offset - delta * 2))
            RenderList()
        end)
        list:SetScript("OnShow", function() catcher:Show() end)
        list:SetScript("OnHide", function() catcher:Hide() end)
    end
    if list:IsShown() and list.owner == owner then
        list:Hide()
        return
    end
    list.owner = owner
    list.items = owner.getItems()
    list.offset = 0
    -- Liste so scrollen, dass die aktuelle Auswahl sichtbar ist
    for i, item in ipairs(list.items) do
        if item.value == owner.value then
            list.offset = math.max(0, math.min(i - 1, #list.items - MAX_ROWS))
            break
        end
    end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    RenderList()
    list:Show()
end

local function CreateDropdown(parent, width, getItems, onSelect)
    local dd = CreateFrame("Button", nil, parent)
    dd:SetSize(width, 22)
    Flat(dd, 0.12, 0.12, 0.15, 1)
    Flat(dd, 1, 1, 1, 0.08, "HIGHLIGHT")
    dd.icon = dd:CreateTexture(nil, "ARTWORK")
    dd.icon:SetSize(16, 16)
    dd.icon:SetPoint("LEFT", 3, 0)
    dd.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dd.text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.text:SetPoint("LEFT", 23, 0)
    dd.text:SetPoint("RIGHT", -16, 0)
    dd.text:SetJustifyH("LEFT")
    dd.text:SetWordWrap(false)
    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetRotation(-math.pi / 2)
    dd.getItems, dd.onSelect = getItems, onSelect
    dd:SetScript("OnClick", OpenList)
    dd:SetScript("OnHide", function() if list and list.owner == dd then list:Hide() end end)

    function dd:Set(value, fallbackText)
        self.value = value
        for _, item in ipairs(self.getItems()) do
            if item.value == value then
                self.text:SetText(item.text)
                self.icon:SetTexture(item.icon)
                return
            end
        end
        self.text:SetText(fallbackText or "")
        self.icon:SetTexture(nil)
    end

    function dd:SetActive(active)
        self:SetEnabled(active)
        self:SetAlpha(active and 1 or 0.35)
    end
    return dd
end

---------------------------------------------------------------------------
-- Einstellungsfenster
---------------------------------------------------------------------------
local function ActionItems()
    local items = {
        { value = "none", text = "|cff888888– nichts –|r" },
        { value = "target", text = "Anvisieren", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
        { value = "menu", text = "Menü", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    }
    for _, s in ipairs(ns.spellList) do
        table.insert(items, { value = "spell:" .. s.name, text = s.name, icon = s.icon })
    end
    return items
end

local function RefreshRow(row)
    local bind = ns.GetBinding(currentMod, row.index)
    local isSpell = bind.kind == "spell" and bind.spell
    row.action:Set(isSpell and ("spell:" .. bind.spell) or bind.kind, isSpell and (bind.spell .. " |cffff5555(nicht gelernt)|r") or nil)

    local spell = isSpell and ns.spells[bind.spell]
    local hasRanks = spell and #spell.ranks > 1
    row.max:SetShown(isSpell and true or false)
    row.maxLabel:SetShown(isSpell and true or false)
    row.rank:SetShown(isSpell and true or false)
    if isSpell then
        row.max:SetChecked(bind.max and true or false)
        row.rank:SetActive(hasRanks and not bind.max or false)
        if bind.max or not bind.id then
            local top = spell and spell.ranks[#spell.ranks]
            row.rank:Set(top and top.id, hasRanks and "" or "–")
            if not hasRanks then row.rank.text:SetText("–") end
        else
            row.rank:Set(bind.id, "?")
        end
    end
end

function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    for _, tab in ipairs(tabs) do
        tab.bg:SetColorTexture(0.2, 0.6, 0.9, tab.mod == currentMod and 0.6 or 0.12)
    end
    for _, row in ipairs(rows) do RefreshRow(row) end
    for _, check in ipairs(options.checks) do check:SetChecked(ns.db[check.key]) end
    options.scaleText:SetFormattedText("Größe: %d%%", ns.db.scale * 100 + 0.5)
end

local function Changed()
    ns.cdb.needSetup = nil
    ns.ApplyBindings()
    ns.RefreshOptions()
    if InCombatLockdown() then ns.Print("Änderung wird nach dem Kampf aktiv.") end
end

local function CreateRow(parent, index, y)
    local row = { index = index }
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 16, y - 5)
    label:SetText(ns.BUTTONS[index])

    row.action = CreateDropdown(parent, 190, ActionItems, function(value)
        local bind = ns.GetBinding(currentMod, index)
        local spell = value:match("^spell:(.+)$")
        if spell then
            if bind.spell ~= spell then bind.id = nil end
            bind.kind, bind.spell = "spell", spell
            if bind.max == nil or not bind.id then bind.max = true end
        else
            bind.kind = value
        end
        Changed()
    end)
    row.action:SetPoint("TOPLEFT", 100, y)

    row.max = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    row.max:SetSize(24, 24)
    row.max:SetPoint("LEFT", row.action, "RIGHT", 8, 0)
    row.maxLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.maxLabel:SetPoint("LEFT", row.max, "RIGHT", 0, 0)
    row.maxLabel:SetText("Höchster Rang")
    row.max:SetScript("OnClick", function(self)
        local bind = ns.GetBinding(currentMod, index)
        bind.max = self:GetChecked() and true or false
        if not bind.max and not bind.id then
            local spell = ns.spells[bind.spell]
            local top = spell and spell.ranks[#spell.ranks]
            bind.id = top and top.id
        end
        Changed()
    end)

    row.rank = CreateDropdown(parent, 110, function()
        local items = {}
        local bind = ns.GetBinding(currentMod, index)
        local spell = bind.spell and ns.spells[bind.spell]
        if spell then
            for _, r in ipairs(spell.ranks) do
                local cost = ns.ManaCost(r.id)
                local text = r.label
                if cost and cost > 0 then text = text .. "  |cff66aaff" .. cost .. "|r" end
                table.insert(items, { value = r.id, text = text, icon = spell.icon })
            end
        end
        return items
    end, function(id)
        ns.GetBinding(currentMod, index).id = id
        Changed()
    end)
    row.rank:SetPoint("LEFT", row.maxLabel, "RIGHT", 8, 0)
    return row
end

local function SmallButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    b.bg = Flat(b, 0.2, 0.6, 0.9, 0.12)
    Flat(b, 1, 1, 1, 0.1, "HIGHLIGHT")
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateOptions()
    options = CreateFrame("Frame", "HealbuddyOptions", UIParent)
    options:SetSize(560, 312)
    options:SetPoint("CENTER")
    options:SetFrameStrata("DIALOG")
    options:EnableMouse(true)
    options:SetMovable(true)
    options:SetClampedToScreen(true)
    options:RegisterForDrag("LeftButton")
    options:SetScript("OnDragStart", options.StartMoving)
    options:SetScript("OnDragStop", options.StopMovingOrSizing)
    Flat(options, 0.06, 0.07, 0.09, 0.96)
    table.insert(UISpecialFrames, "HealbuddyOptions")

    local header = options:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(28)
    header:SetColorTexture(0.1, 0.35, 0.5, 0.9)
    local title = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText("Healbuddy")
    local close = SmallButton(options, "X", 22, function() options:Hide() end)
    close:SetPoint("TOPRIGHT", -3, -3)

    -- Modifikator-Reiter
    local modLabel = options:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modLabel:SetPoint("TOPLEFT", 16, -45)
    modLabel:SetText("Modifikator")
    tabs = {}
    for i, mod in ipairs(ns.MODS) do
        local tab = SmallButton(options, mod.label, 70, function()
            currentMod = mod.key
            ns.RefreshOptions()
        end)
        tab.mod = mod.key
        tab:SetPoint("TOPLEFT", 100 + (i - 1) * 74, -40)
        tabs[i] = tab
    end

    local reset = SmallButton(options, "Standardbelegung", 120, function()
        ns.AutoSetup(true)
        ns.RefreshOptions()
    end)
    reset:SetPoint("TOPRIGHT", -14, -40)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Belegung auf den Klassen-Standard zurücksetzen", 1, 1, 1)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows = {}
    for i = 1, #ns.BUTTONS do
        rows[i] = CreateRow(options, i, -74 - (i - 1) * 28)
    end

    -- Fußzeile
    options.checks = {}
    local function Check(key, label, x, y, onChange)
        local check = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
        check.key = key
        check:SetSize(24, 24)
        check:SetPoint("BOTTOMLEFT", x, y)
        check:SetScript("OnClick", function(self)
            ns.db[key] = self:GetChecked() and true or false
            onChange()
        end)
        local text = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 0, 0)
        text:SetText(label)
        table.insert(options.checks, check)
    end
    Check("context", "Tote per Heil-Klick wiederbeleben (außerhalb des Kampfes)", 12, 58, function()
        if ns.db.context and not ns.resName then
            ns.Print("Deine Klasse hat keinen passenden Wiederbelebungszauber gelernt.")
        end
        Changed()
    end)
    Check("fsr", "5-Sekunden-Regel und Mana-Ticks anzeigen", 12, 34, ns.UpdateFSR)
    Check("pets", "Begleiter anzeigen (Gruppe)", 300, 34, ns.UpdatePets)
    Check("locked", "Position fixieren (Titelleiste ausblenden)", 12, 10, ns.UpdateLock)

    local function Scale(delta)
        ns.db.scale = math.min(2, math.max(0.5, math.floor((ns.db.scale + delta) * 10 + 0.5) / 10))
        ns.ApplyScale()
        ns.RefreshOptions()
    end
    local plus = SmallButton(options, "+", 22, function() Scale(0.1) end)
    plus:SetPoint("BOTTOMRIGHT", -14, 11)
    local minus = SmallButton(options, "–", 22, function() Scale(-0.1) end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    options.scaleText = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    options.scaleText:SetPoint("RIGHT", minus, "LEFT", -8, 0)

    options:SetScript("OnShow", ns.RefreshOptions)
end

function ns.ToggleOptions()
    if not options then
        CreateOptions()
        ns.RefreshOptions()
    else
        options:SetShown(not options:IsShown())
    end
end
