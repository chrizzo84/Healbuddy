local _, ns = ...
local L = ns.L

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
        { value = "none", text = "|cff888888" .. L["– nothing –"] .. "|r" },
        { value = "target", text = L["Target"], icon = ns.ICONS.target },
        { value = "menu", text = L["Menu"], icon = ns.ICONS.menu },
        { value = "pin", text = L["Pin heal target"], icon = ns.ICONS.pin },
    }
    if ns.combo then
        table.insert(items, { value = "combo", text = L["Emergency heal"], icon = ns.combo.icon })
    end
    for _, s in ipairs(ns.spellList) do
        table.insert(items, { value = "spell:" .. s.name, text = s.name, icon = s.icon })
    end
    -- Schadenszauber: wirken auf das Ziel des angeklickten Spielers
    for _, s in ipairs(ns.harmList) do
        table.insert(items, { value = "assist:" .. s.name, text = L["Attack: %s"]:format(s.name), icon = s.icon })
    end
    return items
end

local function RefreshRow(row)
    local bind = ns.GetBinding(currentMod, row.index)
    local isSpell = bind.kind == "spell" and bind.spell
    local missing = " |cffff5555" .. L["(not learned)"] .. "|r"
    if isSpell then
        row.action:Set("spell:" .. bind.spell, bind.spell .. missing)
    elseif bind.kind == "assist" and bind.spell then
        row.action:Set("assist:" .. bind.spell, bind.spell .. missing)
    elseif bind.kind == "combo" then
        row.action:Set("combo", L["Emergency heal"] .. missing)
    else
        row.action:Set(bind.kind)
    end

    local spell = isSpell and ns.spells[bind.spell]
    local hasRanks = spell and #spell.ranks > 1
    row.max:SetShown(isSpell and true or false)
    row.maxLabel:SetShown(isSpell and true or false)
    row.rank:SetShown(isSpell and true or false)
    row.ladder:SetShown(hasRanks and true or false)
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

local currentPage = "bind"
local pages, pageTabs, look
local cdButtons, cdEmpty = {}, nil

local function PreviewItems()
    local items = { { value = 0, text = L["Off"] } }
    for _, count in ipairs({ 5, 10, 25, 40 }) do
        table.insert(items, { value = count, text = L["%d players"]:format(count) })
    end
    return items
end

-- Cooldown-Seite: ein Icon je Zauber, Klick schaltet die Anzeige um
local function RefreshCooldownPage()
    local list = ns.CooldownCandidates()
    for i, entry in ipairs(list) do
        local b = cdButtons[i]
        if not b then
            b = CreateFrame("Button", nil, pages.cd)
            b:SetSize(28, 28)
            b:SetPoint("TOPLEFT", 16 + ((i - 1) % 18) * 32, -66 - math.floor((i - 1) / 18) * 32)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.2)
            b:SetScript("OnClick", function(self)
                ns.ToggleCooldown(self.name)
                ns.RefreshOptions()
                if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.name)
                GameTooltip:AddLine(ns.CooldownShown(self.name) and L["shown"] or L["hidden"], 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cdButtons[i] = b
        end
        local on = ns.CooldownShown(entry.name)
        b.name = entry.name
        b.icon:SetTexture(entry.icon)
        b.icon:SetDesaturated(not on)
        b:SetAlpha(on and 1 or 0.4)
        b:Show()
    end
    for i = #list + 1, #cdButtons do cdButtons[i]:Hide() end
    cdEmpty:SetShown(#list == 0)
end

function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    for key, page in pairs(pages) do page:SetShown(key == currentPage) end
    for _, tab in ipairs(pageTabs) do
        tab.bg:SetColorTexture(0.2, 0.6, 0.9, tab.page == currentPage and 0.6 or 0.12)
    end
    for _, tab in ipairs(tabs) do
        tab.bg:SetColorTexture(0.2, 0.6, 0.9, tab.mod == currentMod and 0.6 or 0.12)
    end
    for _, row in ipairs(rows) do RefreshRow(row) end
    for _, check in ipairs(options.checks) do check:SetChecked(ns.db[check.key]) end
    local db = ns.db
    look.skin:Set(db.preset, L["Custom settings"])
    look.texture:Set(db.texture, db.texture)
    look.color:Set(db.colorMode, db.colorMode)
    look.width:SetText(db.width)
    look.height:SetText(db.height)
    look.scale:SetText(math.floor(db.scale * 100 + 0.5) .. "%")
    look.preview:Set(ns.GetPreview())
    if currentPage == "cd" then RefreshCooldownPage() end
end

local function Changed()
    ns.cdb.needSetup = nil
    ns.ApplyBindings()
    ns.RefreshOptions()
    if InCombatLockdown() then ns.Print(L["Change takes effect after combat."]) end
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

local function CreateRow(parent, index, y)
    local row = { index = index }
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 16, y - 5)
    label:SetText(ns.BUTTONS[index])

    row.action = CreateDropdown(parent, 190, ActionItems, function(value)
        local bind = ns.GetBinding(currentMod, index)
        local spell = value:match("^spell:(.+)$")
        local assist = value:match("^assist:(.+)$")
        if spell then
            if bind.spell ~= spell then bind.id = nil end
            bind.kind, bind.spell = "spell", spell
            if bind.max == nil or not bind.id then bind.max = true end
        elseif assist then
            bind.kind, bind.spell, bind.id, bind.max = "assist", assist, nil, true
            ns.Print(L["%s is cast on the target of the player you click."]:format(assist))
        else
            bind.kind = value
            if value == "combo" and ns.combo then
                ns.Print(L["Emergency heal: cancels the current cast, uses %s and casts %s."]:format(ns.combo.cd, ns.combo.heal))
            end
        end
        Changed()
    end)
    row.action:SetPoint("TOPLEFT", 100, y)

    row.max = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    row.max:SetSize(24, 24)
    row.max:SetPoint("LEFT", row.action, "RIGHT", 8, 0)
    row.maxLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.maxLabel:SetPoint("LEFT", row.max, "RIGHT", 0, 0)
    row.maxLabel:SetText(L["Highest rank"])
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

    row.ladder = SmallButton(parent, L["Ladder"], 50, function()
        local bind = ns.GetBinding(currentMod, index)
        if bind.kind == "spell" and bind.spell then
            ns.MakeLadder(index, bind.spell)
            ns.RefreshOptions()
            if InCombatLockdown() then ns.Print(L["Change takes effect after combat."]) end
        end
    end)
    row.ladder:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, y)
    row.ladder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Rank ladder"])
        GameTooltip:AddLine(L["Puts three ranks of this spell on this mouse button:"], 1, 1, 1)
        GameTooltip:AddLine(L["Click = economical, Shift = medium, Ctrl = highest rank"], 1, 1, 1)
        GameTooltip:AddLine(L["Overwrites the Shift and Ctrl bindings of this mouse button."], 1, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row.ladder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function Label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y - 5)
    fs:SetText(text)
    return fs
end

local function Check(parent, key, label, x, y, onChange)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check.key = key
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        onChange()
    end)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 0, 0)
    text:SetText(label)
    table.insert(options.checks, check)
end

-- Beschriftung, Wert und −/+ ; liefert den FontString für den Wert
local function Stepper(parent, label, x, y, onStep)
    Label(parent, label, x, y)
    local minus = SmallButton(parent, "–", 22, function() onStep(-1) end)
    minus:SetPoint("TOPLEFT", x + 84, y)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    value:SetWidth(44)
    local plus = SmallButton(parent, "+", 22, function() onStep(1) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 44, 0)
    return value
end

local function Clamp(value, low, high)
    return math.min(high, math.max(low, value))
end

local function CreateBindPage(page)
    Label(page, L["Modifier"], 16, -40)
    tabs = {}
    for i, mod in ipairs(ns.MODS) do
        local tab = SmallButton(page, mod.label, 70, function()
            currentMod = mod.key
            ns.RefreshOptions()
        end)
        tab.mod = mod.key
        tab:SetPoint("TOPLEFT", 100 + (i - 1) * 74, -40)
        tabs[i] = tab
    end

    local reset = SmallButton(page, L["Default bindings"], 120, function()
        ns.AutoSetup(true)
        ns.RefreshOptions()
    end)
    reset:SetPoint("TOPRIGHT", -14, -40)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Reset bindings to the class defaults"], 1, 1, 1)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows = {}
    for i = 1, #ns.BUTTONS do
        rows[i] = CreateRow(page, i, -74 - (i - 1) * 28)
    end

    Check(page, "context", L["Resurrect the dead with heal clicks"], 12, -220, function()
        if ns.db.context and not ns.resName and not ns.brezName then
            ns.Print(L["Your class has not learned a suitable resurrection spell."])
        end
        Changed()
    end)
end

local function CreateLookPage(page)
    look = {}
    -- Jede Einzeländerung macht aus der Voreinstellung "Eigene Einstellungen"
    local function Custom()
        ns.db.preset = "custom"
        ns.ApplySkin()
        ns.RefreshOptions()
        if InCombatLockdown() then ns.Print(L["Change takes effect after combat."]) end
    end

    Label(page, L["Skin"], 16, -44)
    look.skin = CreateDropdown(page, 170, function() return ns.SKINS end, function(value)
        ns.SetSkin(value)
        ns.RefreshOptions()
        if InCombatLockdown() then ns.Print(L["Change takes effect after combat."]) end
    end)
    look.skin:SetPoint("TOPLEFT", 100, -44)

    Label(page, L["Preview"], 290, -44)
    look.preview = CreateDropdown(page, 200, PreviewItems, function(value)
        ns.SetPreview(value)
        ns.RefreshOptions()
    end)
    look.preview:SetPoint("TOPLEFT", 340, -44)

    Label(page, L["Bar"], 16, -76)
    look.texture = CreateDropdown(page, 170, function() return ns.TEXTURES end, function(value)
        ns.db.texture = value
        Custom()
    end)
    look.texture:SetPoint("TOPLEFT", 100, -76)

    Label(page, L["Color"], 290, -76)
    look.color = CreateDropdown(page, 200, function() return ns.COLORS end, function(value)
        ns.db.colorMode = value
        Custom()
    end)
    look.color:SetPoint("TOPLEFT", 340, -76)

    local size = ns.SIZE
    look.width = Stepper(page, L["Width"], 16, -108, function(dir)
        ns.db.width = Clamp(ns.db.width + dir * size.step, size.minW, size.maxW)
        Custom()
    end)
    look.height = Stepper(page, L["Height"], 290, -108, function(dir)
        ns.db.height = Clamp(ns.db.height + dir * size.step, size.minH, size.maxH)
        Custom()
    end)
    look.scale = Stepper(page, L["Overall scale"], 16, -140, function(dir)
        ns.db.scale = Clamp(math.floor((ns.db.scale + dir * 0.1) * 10 + 0.5) / 10, 0.5, 2)
        ns.ApplyScale()
        ns.RefreshOptions()
    end)

    Check(page, "percent", L["Show health in percent"], 286, -139, Custom)
    Check(page, "fsr", L["Mana bar with 5-second rule and ticks"], 12, -172, ns.UpdateFSR)
    Check(page, "pets", L["Show pets (party)"], 286, -172, ns.UpdatePets)
    Check(page, "locked", L["Lock position (hide title bar)"], 12, -198, ns.UpdateLock)
    Check(page, "legend", L["Legend of the click bindings"], 286, -198, ns.UpdateLegend)
    Check(page, "legendEmpty", L["Legend: also show unbound buttons"], 286, -224, ns.UpdateLegend)
end

local function CreateCooldownPage(page)
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -42)
    hint:SetText(L["Click an icon to show or hide it below the mana bar."])
    cdEmpty = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cdEmpty:SetPoint("TOPLEFT", 16, -70)
    cdEmpty:SetText(L["No spells with a cooldown found."])
end

local function CreateOptions()
    options = CreateFrame("Frame", "HealbuddyOptions", UIParent)
    options:SetSize(610, 256)
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
    options.checks = {}

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

    -- Seiten: Belegung | Aussehen
    pages, pageTabs = {}, {}
    for i, def in ipairs({ { "bind", L["Bindings"] }, { "look", L["Appearance"] }, { "cd", L["Cooldowns"] } }) do
        local page = CreateFrame("Frame", nil, options)
        page:SetAllPoints()
        pages[def[1]] = page
        local tab = SmallButton(options, def[2], 80, function()
            currentPage = def[1]
            ns.RefreshOptions()
        end)
        tab.page = def[1]
        tab:SetPoint("TOPLEFT", 100 + (i - 1) * 84, -3)
        pageTabs[i] = tab
    end
    CreateBindPage(pages.bind)
    CreateLookPage(pages.look)
    CreateCooldownPage(pages.cd)

    options:SetScript("OnShow", ns.RefreshOptions)
    -- Die Vorschau gehört zum Einstellungsfenster
    options:SetScript("OnHide", function()
        if ns.GetPreview() > 0 and not InCombatLockdown() then ns.SetPreview(0) end
    end)
end

function ns.ToggleOptions()
    if not options then
        CreateOptions()
        ns.RefreshOptions()
    else
        options:SetShown(not options:IsShown())
    end
end
