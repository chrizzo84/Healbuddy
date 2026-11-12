local _, ns = ...
local issecret = ns.issecret

local BW, BH, GAP, HANDLE = 88, 40, 2, 14
local MAX_BUFFS, MAX_DEBUFFS = 3, 3
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local container, handle
local buttons, byUnit = {}, {}
ns.buttons = buttons
local readyCheck = false
local clicked, clickTime

---------------------------------------------------------------------------
-- Aktualisierung einzelner Elemente
---------------------------------------------------------------------------
local function UpdateName(b)
    local u = b.unit
    b.name:SetText(UnitName(u) or "")
    local _, class = UnitClass(u)
    local c = b.kind ~= "pet" and class and not issecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        b.bar:SetStatusBarColor(c.r, c.g, c.b)
    else
        b.bar:SetStatusBarColor(0.2, 0.7, 0.3)
    end
end

-- Eingehende Heilung: zweiter Balken, der rechts an den Lebensbalken anschließt
local function UpdatePrediction(b, clear)
    if not UnitGetIncomingHeals then return end
    if clear then
        b.pred:SetValue(0)
        return
    end
    b.pred:SetMinMaxValues(0, UnitHealthMax(b.unit))
    b.pred:SetValue(UnitGetIncomingHeals(b.unit) or 0)
end

local function UpdateHealth(b)
    local u = b.unit
    local connected = UnitIsConnected(u)
    local dead = UnitIsDeadOrGhost(u)
    if not issecret(connected) and not connected then
        b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0)
        b.status:SetText("Offline")
        UpdatePrediction(b, true)
        return
    elseif not issecret(dead) and dead then
        b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0)
        b.status:SetText("|cffff5555Tot|r")
        UpdatePrediction(b, true)
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
    UpdatePrediction(b)
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

-- Rahmen: bannbarer Debuff (Farbe des Typs) vor Aggro (rot) vor normal (schwarz)
local function UpdateBorder(b)
    local c = b.dispelColor
    if c then
        b.border:SetColorTexture(c.r, c.g, c.b, 1)
    elseif b.hasAggro then
        b.border:SetColorTexture(1, 0.1, 0.1, 1)
    else
        b.border:SetColorTexture(0, 0, 0, 1)
    end
end

local function HasBuff(unit, name)
    if C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL") ~= nil
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then return false end
        if issecret(aura.name) or aura.name == name then return true end
    end
    return false
end

-- Fehlender Klassenbuff: anklickbares Icon, nur außerhalb des Kampfes
local function UpdateBuffButton(b)
    if InCombatLockdown() then return end
    local buff, u = ns.classBuff, b.unit
    local show = false
    if buff and b.kind ~= "pet" and C_UnitAuras and UnitExists(u) and UnitIsConnected(u)
        and not UnitIsDeadOrGhost(u) and UnitIsVisible(u) then
        show = true
        for _, name in ipairs(buff.names) do
            if HasBuff(u, name) then show = false break end
        end
    end
    if show then
        if b.buffBtn.spell ~= buff.cast then
            b.buffBtn.spell = buff.cast
            b.buffBtn:SetAttribute("spell", buff.cast)
            b.buffBtn.icon:SetTexture(buff.icon)
        end
    end
    b.buffBtn:SetShown(show)
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

    b.dispelColor = dispelColor
    UpdateBorder(b)

    UpdateBuffButton(b)
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
    b.hasAggro = s ~= nil and not issecret(s) and s >= 2
    b.aggro:SetShown(b.hasAggro)
    UpdateBorder(b)
end

local READY_TEX = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

-- Mitte des Frames: Bereitschaftscheck oder eingehende Wiederbelebung
local function UpdateCenter(b)
    local tex
    if readyCheck and GetReadyCheckStatus then
        local s = GetReadyCheckStatus(b.unit)
        tex = s and not issecret(s) and READY_TEX[s]
    end
    if not tex and UnitHasIncomingResurrection then
        local res = UnitHasIncomingResurrection(b.unit)
        if not issecret(res) and res then tex = "Interface\\RaidFrame\\Raid-Icon-Rez" end
    end
    if tex then
        b.center:SetTexture(tex)
        b.center:Show()
        b.status:SetAlpha(0)
    else
        b.center:Hide()
        b.status:SetAlpha(1)
    end
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
    ns.Safe(UpdateCenter, b)
    ns.Safe(UpdateRange, b)
end

ns.UpdateAll = UpdateAll

local function ForVisible(func)
    for _, b in ipairs(buttons) do
        if b:IsVisible() then ns.Safe(func, b) end
    end
end

---------------------------------------------------------------------------
-- Click-Casting
---------------------------------------------------------------------------
local function DoApplyBindings()
    local res = ns.db.context and ns.resName
    for _, b in ipairs(buttons) do
        for _, mod in ipairs(ns.MODS) do
            local p = mod.key
            for n = 1, #ns.BUTTONS do
                local bind = ns.cdb.bindings[p][n]
                local kind = bind and bind.kind
                local type, spell, macro
                if kind == "spell" and bind.spell then
                    if res and bind.spell ~= res then
                        -- Kontext-Klick: tote Spieler außerhalb des Kampfes wiederbeleben
                        type = "macro"
                        macro = ("/cast [@mouseover,help,dead,nocombat] %s; [@mouseover] %s"):format(res, ns.MacroSpell(bind))
                    else
                        type, spell = "spell", ns.ResolveSpell(bind)
                    end
                elseif kind == "target" then
                    type = "target"
                elseif kind == "menu" then
                    type = "togglemenu"
                end
                b:SetAttribute(p .. "type" .. n, type)
                b:SetAttribute(p .. "spell" .. n, spell)
                b:SetAttribute(p .. "macrotext" .. n, macro)
            end
        end
    end
end

function ns.ApplyBindings()
    if container then ns.AfterCombat(DoApplyBindings) end
end

local function ShowTooltip(b)
    if InCombatLockdown() then return end
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(UnitName(b.unit) or "")
    for _, mod in ipairs(ns.MODS) do
        for n = 1, #ns.BUTTONS do
            local bind = ns.cdb.bindings[mod.key][n]
            local text
            if bind and bind.kind == "spell" and bind.spell then
                text = bind.max and bind.spell or ns.MacroSpell(bind)
            elseif bind and bind.kind == "target" then
                text = "Anvisieren"
            elseif bind and bind.kind == "menu" then
                text = "Menü"
            end
            if text then
                local key = (mod.key ~= "" and (mod.label .. " + ") or "") .. ns.BUTTONS[n]
                GameTooltip:AddDoubleLine(key, text, 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Anordnung
---------------------------------------------------------------------------
local function SetPos(b, col, row)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", container, "TOPLEFT", col * (BW + GAP), -(HANDLE + GAP) - row * (BH + GAP))
end

-- Schlachtzug: eine Spalte pro (nicht leerer) Gruppe
local function DoLayout()
    local members = {}
    for i = 1, 40 do
        local name, _, sub = GetRaidRosterInfo(i)
        if name and sub then
            members[sub] = members[sub] or {}
            table.insert(members[sub], i)
        end
    end
    local col = 0
    for group = 1, 8 do
        if members[group] then
            for row, i in ipairs(members[group]) do
                SetPos(byUnit["raid" .. i], col, row - 1)
            end
            col = col + 1
        end
    end
end

local function DoPetDrivers()
    for _, b in ipairs(buttons) do
        if b.kind == "pet" then
            RegisterStateDriver(b, "visibility", ns.db.pets and b.driver or "hide")
        end
    end
end

function ns.UpdatePets()
    ns.AfterCombat(DoPetDrivers)
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

local function CreateUnitButton(unit, kind, col, row, driver)
    local index = #buttons + 1
    local b = CreateFrame("Button", "HealbuddyUnit" .. index, container, "SecureUnitButtonTemplate")
    b.unit, b.kind, b.driver = unit, kind, driver
    b:SetSize(BW, BH)
    SetPos(b, col, row)
    b:SetAttribute("unit", unit)
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForClicks("AnyUp")

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 1)

    local content = CreateFrame("Frame", nil, b)
    content:SetPoint("TOPLEFT", 1, -1)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    b.content = content

    local bg = content:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 1)

    b.bar = CreateFrame("StatusBar", nil, content)
    b.bar:SetAllPoints()
    b.bar:SetStatusBarTexture(BAR)
    b.bar:SetMinMaxValues(0, 1)
    b.bar:SetValue(1)

    b.pred = CreateFrame("StatusBar", nil, content)
    b.pred:SetPoint("TOPLEFT", b.bar:GetStatusBarTexture(), "TOPRIGHT")
    b.pred:SetPoint("BOTTOMLEFT", b.bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    b.pred:SetWidth(BW - 2)
    b.pred:SetStatusBarTexture(BAR)
    b.pred:SetStatusBarColor(0.5, 1, 0.6, 0.55)
    b.pred:SetMinMaxValues(0, 1)
    b.pred:SetValue(0)

    local over = CreateFrame("Frame", nil, content)
    over:SetAllPoints()
    over:SetFrameLevel(b.bar:GetFrameLevel() + 3)

    b.name = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT", 3, -3)
    b.name:SetPoint("TOPRIGHT", -16, -3)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)

    b.status = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetPoint("CENTER", 0, -1)

    b.center = over:CreateTexture(nil, "OVERLAY")
    b.center:SetSize(16, 16)
    b.center:SetPoint("CENTER", 0, -1)
    b.center:Hide()

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

    -- Rotes Aufblinken, wenn ein Klick nichts bewirken konnte
    local flash = over:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints()
    flash:SetColorTexture(1, 0, 0, 1)
    flash:SetAlpha(0)
    b.flash = flash:CreateAnimationGroup()
    local fade = b.flash:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.65)
    fade:SetToAlpha(0)
    fade:SetDuration(0.45)

    -- Fehlender Klassenbuff (eigener sicherer Button, damit der Klick bufft)
    local bb = CreateFrame("Button", nil, b, "SecureActionButtonTemplate")
    bb:SetSize(14, 14)
    bb:SetPoint("RIGHT", b, "RIGHT", -3, -1)
    bb:SetFrameLevel(over:GetFrameLevel() + 2)
    bb:SetAttribute("type", "spell")
    bb:SetAttribute("unit", unit)
    bb:SetAttribute("useOnKeyDown", false)
    bb:RegisterForClicks("AnyUp")
    bb.icon = bb:CreateTexture(nil, "ARTWORK")
    bb.icon:SetAllPoints()
    bb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bb.icon:SetDesaturated(true)
    bb.icon:SetVertexColor(1, 0.6, 0.6)
    local bhl = bb:CreateTexture(nil, "HIGHLIGHT")
    bhl:SetAllPoints()
    bhl:SetColorTexture(1, 1, 1, 0.3)
    bb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((self.spell or "Buff") .. " fehlt")
        GameTooltip:AddLine("Klicken zum Buffen", 1, 1, 1)
        GameTooltip:Show()
    end)
    bb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bb:Hide()
    b.buffBtn = bb

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b:SetScript("OnShow", UpdateAll)
    b:SetScript("PreClick", function(self)
        clicked, clickTime = self, GetTime()
    end)
    b:HookScript("OnEnter", function(self) ns.Safe(ShowTooltip, self) end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    RegisterStateDriver(b, "visibility", (kind ~= "pet" or ns.db.pets) and driver or "hide")

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

local function DoScale()
    container:SetScale(ns.db.scale)
end

function ns.ApplyScale()
    ns.AfterCombat(DoScale)
end

local unitEvents = {
    UNIT_HEALTH = UpdateHealth,
    UNIT_MAXHEALTH = UpdateHealth,
    UNIT_CONNECTION = UpdateHealth,
    UNIT_HEAL_PREDICTION = UpdatePrediction,
    UNIT_AURA = UpdateAuras,
    UNIT_NAME_UPDATE = UpdateName,
    UNIT_THREAT_SITUATION_UPDATE = UpdateThreat,
}

local otherEvents = {
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_PET", "RAID_TARGET_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UI_ERROR_MESSAGE",
    "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED", "INCOMING_RESURRECT_CHANGED",
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

    -- Gruppe: Spieler + party1-4 untereinander, Begleiter in der Spalte daneben
    CreateUnitButton("player", "player", 0, 0, "[group:raid] hide; show")
    CreateUnitButton("pet", "pet", 1, 0, "[group:raid] hide; [@pet,exists] show; hide")
    for i = 1, 4 do
        CreateUnitButton("party" .. i, "party", 0, i, ("[group:raid] hide; [@party%d,exists] show; hide"):format(i))
        CreateUnitButton("partypet" .. i, "pet", 1, i, ("[group:raid] hide; [@partypet%d,exists] show; hide"):format(i))
    end
    -- Schlachtzug: Spalten nach Gruppen (siehe DoLayout)
    for i = 1, 40 do
        CreateUnitButton("raid" .. i, "raid", math.floor((i - 1) / 5), (i - 1) % 5, ("[@raid%d,exists] show; hide"):format(i))
    end
    ns.ApplyBindings()
    ns.AfterCombat(DoLayout)
    ns.Safe(ns.CreateFSR, container)

    local ev = CreateFrame("Frame")
    -- Nicht jeder Client kennt jedes Event; unbekannte einfach auslassen
    for event in pairs(unitEvents) do pcall(ev.RegisterEvent, ev, event) end
    for _, event in ipairs(otherEvents) do pcall(ev.RegisterEvent, ev, event) end
    ev:SetScript("OnEvent", function(_, event, unit)
        local handler = unitEvents[event]
        if handler then
            local b = byUnit[unit]
            if b and b:IsVisible() then ns.Safe(handler, b) end
        elseif event == "RAID_TARGET_UPDATE" then
            ForVisible(UpdateRaidTarget)
        elseif event == "UI_ERROR_MESSAGE" then
            if clicked and GetTime() - clickTime < 0.3 then
                clicked.flash:Stop()
                clicked.flash:Play()
                clicked = nil
            end
        elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
            readyCheck = true
            ForVisible(UpdateCenter)
        elseif event == "READY_CHECK_FINISHED" then
            C_Timer.After(6, function()
                readyCheck = false
                ForVisible(UpdateCenter)
            end)
        elseif event == "INCOMING_RESURRECT_CHANGED" then
            ForVisible(UpdateCenter)
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Letzte Gelegenheit vor der Kampfsperre
            for _, b in ipairs(buttons) do b.buffBtn:Hide() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            ForVisible(UpdateBuffButton)
        else
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                ns.AfterCombat(DoLayout)
            end
            for _, b in ipairs(buttons) do
                if b:IsVisible() then UpdateAll(b) end
            end
        end
    end)

    C_Timer.NewTicker(0.3, function() ForVisible(UpdateRange) end)
end
