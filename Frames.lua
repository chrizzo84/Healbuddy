local _, ns = ...
local issecret = ns.issecret

local BW, BH, GAP, HANDLE = 88, 40, 2, 14
local MAX_BUFFS, MAX_DEBUFFS = 3, 3
local TEX = "Interface\\Buttons\\WHITE8x8"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local container, handle
local buttons, byUnit = {}, {}
local pendingApply, pendingScale

---------------------------------------------------------------------------
-- Aktualisierung einzelner Elemente
---------------------------------------------------------------------------
local function UpdateName(b)
    local u = b.unit
    b.name:SetText(UnitName(u) or "")
    local _, class = UnitClass(u)
    local c = class and not issecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        b.bar:SetStatusBarColor(c.r, c.g, c.b)
    else
        b.bar:SetStatusBarColor(0.2, 0.8, 0.3)
    end
end

local function UpdateHealth(b)
    local u = b.unit
    local connected = UnitIsConnected(u)
    local dead = UnitIsDeadOrGhost(u)
    if not issecret(connected) and not connected then
        b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0)
        b.status:SetText("Offline")
        return
    elseif not issecret(dead) and dead then
        b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0)
        b.status:SetText("|cffff5555Tot|r")
        return
    end

    -- StatusBar akzeptiert Secret Values direkt; rechnen dürfen wir damit nicht
    local hp, max = UnitHealth(u), UnitHealthMax(u)
    b.bar:SetMinMaxValues(0, max)
    b.bar:SetValue(hp)

    if not issecret(hp) and not issecret(max) then
        if max > 0 then
            b.status:SetFormattedText("%.0f%%", hp / max * 100)
        else
            b.status:SetText("")
        end
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitHealthPercent, u, true, CurveConstants.ScaleTo100)
        if ok and pct ~= nil then
            b.status:SetFormattedText("%.0f%%", pct)
        else
            b.status:SetText("")
        end
    else
        b.status:SetText("")
    end
end

local function SetAuraIcon(ic, unit, aura)
    ic.tex:SetTexture(aura.icon)

    local id = aura.auraInstanceID
    if C_UnitAuras.GetAuraDuration and ic.cd.SetCooldownFromDurationObject then
        local dur = C_UnitAuras.GetAuraDuration(unit, id)
        if dur then ic.cd:SetCooldownFromDurationObject(dur) else ic.cd:Clear() end
    elseif not issecret(aura.duration) and not issecret(aura.expirationTime) and aura.duration and aura.duration > 0 then
        ic.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
    else
        ic.cd:Clear()
    end

    if C_UnitAuras.GetAuraApplicationDisplayCount then
        ic.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, 2, 99))
    elseif not issecret(aura.applications) and aura.applications and aura.applications > 1 then
        ic.count:SetText(aura.applications)
    else
        ic.count:SetText("")
    end
    ic:Show()
end

local function UpdateAuras(b)
    local u = b.unit
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local get = C_UnitAuras.GetAuraDataByIndex

    -- Eigene kurze Buffs (HoTs, Schilde)
    local shown = 0
    for i = 1, 40 do
        if shown >= MAX_BUFFS then break end
        local aura = get(u, i, "HELPFUL|PLAYER")
        if not aura then break end
        local d = aura.duration
        if issecret(d) or (d and d > 0 and d <= 120) then
            shown = shown + 1
            SetAuraIcon(b.buffs[shown], u, aura)
        end
    end
    for i = shown + 1, MAX_BUFFS do b.buffs[i]:Hide() end

    -- Debuffs: bannbare zuerst, sonst die ersten schädlichen
    shown = 0
    local dispelColor
    for i = 1, MAX_DEBUFFS do
        local aura = get(u, i, "HARMFUL|RAID")
        if not aura then break end
        shown = shown + 1
        SetAuraIcon(b.debuffs[shown], u, aura)
        if not dispelColor then
            local t = aura.dispelName
            dispelColor = (t and not issecret(t) and DebuffTypeColor and DebuffTypeColor[t]) or { r = 1, g = 0.2, b = 1 }
        end
    end
    if shown == 0 then
        for i = 1, MAX_DEBUFFS do
            local aura = get(u, i, "HARMFUL")
            if not aura then break end
            shown = shown + 1
            SetAuraIcon(b.debuffs[shown], u, aura)
        end
    end
    for i = shown + 1, MAX_DEBUFFS do b.debuffs[i]:Hide() end

    if dispelColor then
        b.border:SetColorTexture(dispelColor.r, dispelColor.g, dispelColor.b, 1)
    else
        b.border:SetColorTexture(0, 0, 0, 1)
    end
end

local function UpdateRaidTarget(b)
    local idx = GetRaidTargetIndex(b.unit)
    if idx and not issecret(idx) then
        SetRaidTargetIconTexture(b.raidIcon, idx)
        b.raidIcon:Show()
    else
        b.raidIcon:Hide()
    end
end

local function UpdateThreat(b)
    local s = UnitThreatSituation and UnitThreatSituation(b.unit)
    b.aggro:SetShown(s ~= nil and not issecret(s) and s >= 2)
end

local function UpdateRange(b)
    local u = b.unit
    if u == "player" then return end
    local inRange, checked = UnitInRange(u)
    if issecret(inRange) or issecret(checked) then
        if b.content.SetAlphaFromBoolean then
            b.content:SetAlphaFromBoolean(inRange, 1, 0.4)
        end
    else
        b.content:SetAlpha((checked and not inRange) and 0.4 or 1)
    end
end

local function UpdateAll(b)
    ns.Safe(UpdateName, b)
    ns.Safe(UpdateHealth, b)
    ns.Safe(UpdateAuras, b)
    ns.Safe(UpdateRaidTarget, b)
    ns.Safe(UpdateThreat, b)
    ns.Safe(UpdateRange, b)
end

---------------------------------------------------------------------------
-- Click-Casting
---------------------------------------------------------------------------
function ns.ApplyBindings()
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = nil
    for _, b in ipairs(buttons) do
        for _, mod in ipairs(ns.MODS) do
            local p = mod.key
            for n = 1, #ns.BUTTONS do
                local bind = ns.cdb.bindings[p][n]
                local kind = bind and bind.kind
                local type, spell
                if kind == "spell" and bind.spell then
                    type, spell = "spell", ns.ResolveSpell(bind)
                elseif kind == "target" then
                    type = "target"
                elseif kind == "menu" then
                    type = "togglemenu"
                end
                b:SetAttribute(p .. "type" .. n, type)
                b:SetAttribute(p .. "spell" .. n, spell)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------
local function CreateAuraIcon(parent, size)
    local ic = CreateFrame("Frame", nil, parent)
    ic:SetSize(size, size)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints()
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
    ic.cd:SetAllPoints()
    ic.cd:SetReverse(true)
    if ic.cd.SetHideCountdownNumbers then ic.cd:SetHideCountdownNumbers(true) end
    ic.cd:EnableMouse(false)
    local top = CreateFrame("Frame", nil, ic)
    top:SetAllPoints()
    top:SetFrameLevel(ic.cd:GetFrameLevel() + 1)
    ic.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    ic.count:SetPoint("BOTTOMRIGHT", 2, -1)
    ic:EnableMouse(false)
    ic:Hide()
    return ic
end

local function CreateUnitButton(unit, col, row, driver)
    local index = #buttons + 1
    local b = CreateFrame("Button", "HealbuddyUnit" .. index, container, "SecureUnitButtonTemplate")
    b.unit = unit
    b:SetSize(BW, BH)
    b:SetPoint("TOPLEFT", container, "TOPLEFT", col * (BW + GAP), -(HANDLE + GAP) - row * (BH + GAP))
    b:SetAttribute("unit", unit)
    b:RegisterForClicks("AnyUp")

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0, 0, 0, 1)

    local content = CreateFrame("Frame", nil, b)
    content:SetPoint("TOPLEFT", 1, -1)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    b.content = content

    local bg = content:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 1)

    b.bar = CreateFrame("StatusBar", nil, content)
    b.bar:SetAllPoints()
    b.bar:SetStatusBarTexture(BAR)
    b.bar:SetMinMaxValues(0, 1)
    b.bar:SetValue(1)

    local over = CreateFrame("Frame", nil, content)
    over:SetAllPoints()
    over:SetFrameLevel(b.bar:GetFrameLevel() + 2)

    b.name = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT", 3, -3)
    b.name:SetPoint("TOPRIGHT", -16, -3)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)

    b.status = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetPoint("CENTER", 0, -1)

    b.raidIcon = over:CreateTexture(nil, "OVERLAY")
    b.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    b.raidIcon:SetSize(12, 12)
    b.raidIcon:SetPoint("TOPRIGHT", -2, -2)
    b.raidIcon:Hide()

    b.aggro = over:CreateTexture(nil, "OVERLAY")
    b.aggro:SetColorTexture(1, 0.1, 0.1, 1)
    b.aggro:SetSize(6, 6)
    b.aggro:SetPoint("BOTTOMLEFT", over, "LEFT", 2, -3)
    b.aggro:Hide()

    b.buffs, b.debuffs = {}, {}
    for i = 1, MAX_BUFFS do
        local ic = CreateAuraIcon(over, 13)
        ic:SetPoint("BOTTOMLEFT", 2 + (i - 1) * 14, 2)
        b.buffs[i] = ic
    end
    for i = 1, MAX_DEBUFFS do
        local ic = CreateAuraIcon(over, 13)
        ic:SetPoint("BOTTOMRIGHT", -2 - (i - 1) * 14, 2)
        b.debuffs[i] = ic
    end

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b:SetScript("OnShow", UpdateAll)
    RegisterStateDriver(b, "visibility", driver)

    buttons[index] = b
    byUnit[unit] = b
    return b
end

local function SavePosition()
    local point, _, _, x, y = container:GetPoint(1)
    ns.db.pos = { point, x, y }
end

local function ApplyPosition()
    container:ClearAllPoints()
    local pos = ns.db.pos
    if pos then
        container:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else
        container:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
    end
end

function ns.ResetPosition()
    if InCombatLockdown() then return ns.Print("Im Kampf nicht möglich.") end
    ns.db.pos = nil
    ApplyPosition()
end

function ns.UpdateLock()
    if handle then handle:SetShown(not ns.db.locked) end
end

function ns.ApplyScale()
    if InCombatLockdown() then
        pendingScale = true
        return
    end
    pendingScale = nil
    container:SetScale(ns.db.scale)
end

local unitEvents = {
    UNIT_HEALTH = UpdateHealth,
    UNIT_MAXHEALTH = UpdateHealth,
    UNIT_CONNECTION = UpdateHealth,
    UNIT_AURA = UpdateAuras,
    UNIT_NAME_UPDATE = UpdateName,
    UNIT_THREAT_SITUATION_UPDATE = UpdateThreat,
}

function ns.CreateFrames()
    container = CreateFrame("Frame", "HealbuddyFrame", UIParent)
    container:SetSize(BW, HANDLE)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    ApplyPosition()
    container:SetScale(ns.db.scale)

    handle = CreateFrame("Button", nil, container)
    handle:SetAllPoints()
    local hbg = handle:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.1, 0.35, 0.5, 0.9)
    local htxt = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    htxt:SetPoint("CENTER")
    htxt:SetText("Healbuddy")
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("AnyUp")
    handle:SetScript("OnDragStart", function()
        if not InCombatLockdown() then container:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePosition()
    end)
    handle:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.ToggleOptions() end
    end)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Healbuddy")
        GameTooltip:AddLine("Ziehen: verschieben", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Einstellungen", 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.UpdateLock()

    -- Gruppe: Spieler + party1-4 untereinander; Schlachtzug: 5er-Spalten
    CreateUnitButton("player", 0, 0, "[group:raid] hide; show")
    for i = 1, 4 do
        CreateUnitButton("party" .. i, 0, i, ("[group:raid] hide; [@party%d,exists] show; hide"):format(i))
    end
    for i = 1, 40 do
        CreateUnitButton("raid" .. i, math.floor((i - 1) / 5), (i - 1) % 5, ("[@raid%d,exists] show; hide"):format(i))
    end
    ns.ApplyBindings()
    ns.Safe(ns.CreateFSR, container)

    local ev = CreateFrame("Frame")
    for event in pairs(unitEvents) do ev:RegisterEvent(event) end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("RAID_TARGET_UPDATE")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event, unit)
        local handler = unitEvents[event]
        if handler then
            local b = byUnit[unit]
            if b and b:IsVisible() then ns.Safe(handler, b) end
        elseif event == "RAID_TARGET_UPDATE" then
            for _, b in ipairs(buttons) do
                if b:IsVisible() then ns.Safe(UpdateRaidTarget, b) end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if pendingApply then ns.ApplyBindings() end
            if pendingScale then ns.ApplyScale() end
        else
            for _, b in ipairs(buttons) do
                if b:IsVisible() then UpdateAll(b) end
            end
        end
    end)

    C_Timer.NewTicker(0.3, function()
        for _, b in ipairs(buttons) do
            if b:IsVisible() then ns.Safe(UpdateRange, b) end
        end
    end)
end
