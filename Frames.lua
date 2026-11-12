local _, ns = ...
local issecret = ns.issecret

local BW, BH, GAP, HANDLE = 88, 40, 2, 14
local MAX_BUFFS, MAX_DEBUFFS = 3, 3
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

---------------------------------------------------------------------------
-- Skins: Voreinstellungen aus Größe, Balkentextur und Farbschema
---------------------------------------------------------------------------
ns.TEXTURES = {
    { value = "Standard", text = "Standard", file = BAR },
    { value = "Glatt", text = "Glatt", file = "Interface\\Buttons\\WHITE8x8" },
    { value = "Blizzard", text = "Blizzard", file = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { value = "Streifen", text = "Streifen", file = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}
ns.COLORS = {
    { value = "class", text = "Klassenfarbe" },
    { value = "green", text = "Grün" },
    { value = "dark", text = "Dunkel, Name in Klassenfarbe" },
}
ns.SKINS = {
    { value = "Kompakt", text = "Kompakt", width = 88, height = 40, texture = "Standard", colorMode = "class", percent = true },
    { value = "Dunkel", text = "Dunkel", width = 88, height = 40, texture = "Glatt", colorMode = "dark", percent = true },
    { value = "Breit", text = "Breit", width = 132, height = 28, texture = "Standard", colorMode = "class", percent = true },
    { value = "Minimal", text = "Minimal", width = 64, height = 32, texture = "Glatt", colorMode = "green", percent = false },
    { value = "Blizzard", text = "Blizzard", width = 88, height = 40, texture = "Blizzard", colorMode = "green", percent = true },
}
ns.SIZE = { minW = 56, maxW = 160, minH = 24, maxH = 60, step = 4 }

-- Im Kampf (und in Begegnungen/PvP) sind Buffs und Debuffs für Addons gesperrt.
-- Jeder direkte Zugriff wirft dann einen Fehler, also vorher fragen.
local function AurasSecret()
    return (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) and true or false
end
ns.AurasSecret = AurasSecret

local function IconSize()
    return BH < 36 and 11 or 13
end

local EnsureAuras -- weiter unten definiert

local function TextureFile()
    for _, t in ipairs(ns.TEXTURES) do
        if t.value == ns.db.texture then return t.file end
    end
    return BAR
end

local container, handle
local buttons, byUnit = {}, {}
ns.buttons = buttons
local readyCheck, readyRound = false, 0
local clicked, clickTime

---------------------------------------------------------------------------
-- Aktualisierung einzelner Elemente
---------------------------------------------------------------------------
local function UpdateName(b)
    local u = b.unit
    b.name:SetText(UnitName(u) or "")
    local _, class = UnitClass(u)
    local c = b.kind ~= "pet" and class and not issecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local mode = ns.db.colorMode
    if mode == "dark" then
        b.bar:SetStatusBarColor(0.2, 0.2, 0.23)
        if c then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(1, 1, 1) end
    else
        b.name:SetTextColor(1, 1, 1)
        if c and mode ~= "green" then
            b.bar:SetStatusBarColor(c.r, c.g, c.b)
        else
            b.bar:SetStatusBarColor(0.2, 0.7, 0.3)
        end
    end
end

-- Eingehende Heilung: zweiter Balken, der rechts an den Lebensbalken anschließt
local function UpdatePrediction(b, clear)
    if not UnitGetIncomingHeals then return end
    local dead = UnitIsDeadOrGhost(b.unit)
    if clear or (not issecret(dead) and dead) then
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
    -- Totstellen (Jäger) ist kein Tod
    if not issecret(dead) and dead and UnitIsFeignDeath then
        local feign = UnitIsFeignDeath(u)
        if not issecret(feign) and feign then dead = false end
    end
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

    if not ns.db.percent then
        b.status:SetText("")
    elseif not issecret(hp) and not issecret(max) then
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
    -- Im Zweifel "hat den Buff": lieber kein Icon als ein falsches
    if C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
        return not ok or aura ~= nil
    end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return true end
        if not aura then return false end
        if issecret(aura.name) or aura.name == name then return true end
    end
    return false
end

-- Fehlt der Einheit der eigene Klassenbuff? (nur außerhalb des Kampfes prüfbar)
local function NeedsBuff(b)
    local buff, u = ns.classBuff, b.unit
    if AurasSecret() then return false end
    if not (buff and b.kind ~= "pet" and C_UnitAuras and UnitExists(u) and UnitIsConnected(u)
        and not UnitIsDeadOrGhost(u) and UnitIsVisible(u)) then
        return false
    end
    -- Arkane Intelligenz bringt Klassen ohne Mana nichts
    if ns.class == "MAGE" then
        local _, class = UnitClass(u)
        if class == "WARRIOR" or class == "ROGUE" then return false end
    end
    for _, name in ipairs(buff.names) do
        if HasBuff(u, name) then return false end
    end
    return true
end

-- Fehlender Klassenbuff: anklickbares Icon, nur außerhalb des Kampfes
local function UpdateBuffButton(b)
    if InCombatLockdown() then return end
    local show = NeedsBuff(b)
    if show then
        local buff = ns.classBuff
        if b.buffBtn.spell ~= buff.cast then
            b.buffBtn.spell = buff.cast
            b.buffBtn:SetAttribute("spell", buff.cast)
            b.buffBtn.icon:SetTexture(buff.icon)
        end
    end
    b.buffBtn:SetShown(show)
end

-- Sammel-Knopf: jeder Klick bufft den Nächsten, dem der Klassenbuff fehlt.
-- Nach jedem Klick geht es beim Folgenden weiter, damit ein Fehlschlag
-- (Sichtlinie o. Ä.) die Runde nicht blockiert.
local buffAll
local buffAllIndex = 0

local function UpdateBuffAll()
    if not buffAll or InCombatLockdown() then return end
    local buff = ns.classBuff
    local count, pick, first = 0, nil, nil
    if buff then
        for i, b in ipairs(buttons) do
            if b:IsVisible() and b.buffBtn:IsShown() then
                count = count + 1
                local inRange, checked = UnitInRange(b.unit)
                local reachable = b.unit == "player" or issecret(inRange) or issecret(checked) or not checked or inRange
                if reachable then
                    first = first or i
                    if not pick and i > buffAllIndex then pick = i end
                end
            end
        end
    end
    pick = pick or first
    if not pick then
        buffAll.pick = nil
        buffAll:Hide()
        return
    end
    local unit = buttons[pick].unit
    if buffAll.unit ~= unit or buffAll.spell ~= buff.cast then
        buffAll.unit, buffAll.spell = unit, buff.cast
        buffAll:SetAttribute("unit", unit)
        buffAll:SetAttribute("spell", buff.cast)
        buffAll.icon:SetTexture(buff.icon)
    end
    buffAll.pick = pick
    buffAll.count:SetText(count)
    buffAll:Show()
end

local function CreateBuffAll(parent)
    buffAll = CreateFrame("Button", "HealbuddyBuffAll", parent, "SecureActionButtonTemplate")
    buffAll:SetSize(22, 22)
    buffAll:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 3, 0)
    buffAll:SetAttribute("type", "spell")
    buffAll:SetAttribute("useOnKeyDown", false)
    buffAll:RegisterForClicks("AnyUp")
    local edge = buffAll:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)
    buffAll.icon = buffAll:CreateTexture(nil, "ARTWORK")
    buffAll.icon:SetAllPoints()
    buffAll.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = buffAll:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.3)
    buffAll.count = buffAll:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    buffAll.count:SetPoint("BOTTOMRIGHT", 1, 0)
    buffAll:SetScript("PostClick", function(self)
        if self.pick then buffAllIndex = self.pick end
        ns.Safe(UpdateBuffAll)
    end)
    buffAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alle buffen")
        if self.unit then
            GameTooltip:AddLine((self.spell or "") .. " fehlt bei " .. self.count:GetText() .. " Spieler(n)", 1, 1, 1)
            GameTooltip:AddDoubleLine("Nächster Klick:", UnitName(self.unit) or "", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    buffAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buffAll:Hide()
end

-- Ersatzweg mit eigenen Icons. Wird nur benutzt, wenn der Blizzard-Baustein
-- (AuraContainer) fehlt, und funktioniert dann nur außerhalb des Kampfes.
local function UpdateManualAuras(b)
    local u = b.unit
    if AurasSecret() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        for i = 1, MAX_BUFFS do b.buffs[i]:Hide() end
        for i = 1, MAX_DEBUFFS do b.debuffs[i]:Hide() end
        b.dispelColor = nil
        UpdateBorder(b)
        return
    end
    local function get(unit, index, filter)
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        return ok and aura or nil
    end

    -- Eigene kurze Buffs (HoTs, Schilde)
    local shown = 0
    for i = 1, 40 do
        if shown >= b.maxIcons then break end
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
    for i = 1, b.maxIcons do
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
        for i = 1, b.maxIcons do
            local aura = get(u, i, "HARMFUL")
            if not aura then break end
            shown = shown + 1
            SetAuraIcon(b.debuffs[shown], u, aura)
        end
    end
    for i = shown + 1, MAX_DEBUFFS do b.debuffs[i]:Hide() end

    b.dispelColor = dispelColor
    UpdateBorder(b)
end

local function UpdateAuras(b)
    EnsureAuras(b)
    if b.manual then UpdateManualAuras(b) end
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
    b.col, b.row = col, row
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

local function PlaceManualIcons(b, size)
    for i = 1, MAX_BUFFS do
        local ic = b.buffs[i]
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        ic:SetPoint("BOTTOMLEFT", 2 + (i - 1) * (size + 1), 2)
    end
    for i = 1, MAX_DEBUFFS do
        local ic = b.debuffs[i]
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        ic:SetPoint("BOTTOMRIGHT", -2 - (i - 1) * (size + 1), 2)
    end
end

---------------------------------------------------------------------------
-- Buff-/Debuff-Icons über Blizzards AuraContainer
--
-- Der Client füllt diese Icons selbst, auch im Kampf, wenn Addons die Auren
-- nicht lesen dürfen. Wir legen nur fest, welche Auren (Filter) und wie sie
-- aussehen. Alles hier ist dem Forever-Quelltext (Blizzard_AuraContainer)
-- nachgebaut und läuft in pcall, weil es im Spiel noch nicht erprobt ist.
---------------------------------------------------------------------------
local AURA_TEMPLATE = "CustomAuraContainerTemplate"

-- Ein Icon mit Ablauf-Animation und Stapelzahl
local function InitAuraFrame(frame, size)
    frame:SetSize(size, size)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pcall(frame.SetIcon, frame, tex)

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    pcall(frame.SetDurationCooldown, frame, cd)

    local top = CreateFrame("Frame", nil, frame)
    top:SetAllPoints()
    top:SetFrameLevel(cd:GetFrameLevel() + 1)
    local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 2, -1)
    pcall(frame.SetApplicationCount, frame, count, {})
end

-- Unsichtbarer "Slot" über dem ganzen Frame: erscheint nur bei einem Debuff,
-- den man selbst bannen kann, und färbt dann den Rahmen in der Debuff-Farbe.
local function InitDispelFrame(frame, anchor)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
    frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 1, -1)
    local style = Enum.CustomAuraButtonDispelTypeTextureStyle
    local options = style and { style = style.PreserveAsset, showWhenHarmful = true } or nil
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil },
    }
    for _, e in ipairs(edges) do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetPoint(e[1])
        tex:SetPoint(e[2])
        if e[3] then tex:SetWidth(e[3]) else tex:SetHeight(e[4]) end
        if options then pcall(frame.AddDispelTypeTexture, frame, tex, options) end
    end
end

local function CreateContainers(b)
    local size = IconSize()
    local function init(frame) ns.Safe(InitAuraFrame, frame, size) end
    local layout = { elementSpacing = 1 }

    local buffs = CreateFrame("AuraContainer", nil, b.over, AURA_TEMPLATE)
    buffs:SetPoint("BOTTOMLEFT", 2, 2)
    buffs:SetUnit(b.unit)
    -- Eigene kurze Buffs (HoTs, Schilde); maxDuration blendet Dauerbuffs aus
    buffs:AddAuraGroup("buffs", "HELPFUL|PLAYER", {
        maxFrameCount = b.maxIcons, initializeFrame = init, layout = layout,
        candidateFilters = { maxDuration = 120 },
    })

    local debuffs = CreateFrame("AuraContainer", nil, b.over, AURA_TEMPLATE)
    debuffs:SetPoint("BOTTOMRIGHT", -2, 2)
    debuffs:SetUnit(b.unit)
    debuffs:AddAuraGroup("debuffs", "HARMFUL", {
        maxFrameCount = b.maxIcons, initializeFrame = init, layout = layout,
    })

    local dispel = CreateFrame("AuraContainer", nil, b.vis, AURA_TEMPLATE)
    dispel:SetAllPoints(b.vis)
    dispel:SetFrameLevel(b.over:GetFrameLevel() + 1)
    dispel:SetUnit(b.unit)
    -- HARMFUL|RAID = Debuffs, die der Spieler selbst bannen kann
    dispel:AddAuraSlot("dispel", "HARMFUL|RAID", {
        initializeFrame = function(frame) ns.Safe(InitDispelFrame, frame, b.vis) end,
    })

    b.auraBuffs, b.auraDebuffs, b.auraDispel = buffs, debuffs, dispel
end

-- Icon-Größe und -Anzahl an den Skin anpassen (nur außerhalb des Kampfes)
local function StyleContainers(b, size)
    local layout = { elementSpacing = 1, elementWidth = size, elementHeight = size }
    for key, c in pairs({ buffs = b.auraBuffs, debuffs = b.auraDebuffs }) do
        c:SetAuraGroupMaxFrameCount(key, b.maxIcons)
        c:SetAuraGroupLayout(key, layout)
        for i = 1, c:GetAuraGroupFrameCount(key) do
            c:GetAuraGroupFrame(key, i):SetSize(size, size)
        end
    end
end

-- Alles, was vom Skin abhängt (Größe, Textur, Farben, Platz für Icons).
-- Verändert geschützte Frames, darf also nur außerhalb des Kampfes laufen.
local function StyleButton(b)
    local file = TextureFile()
    local low = BH < 36
    local size = low and 11 or 13
    b.bar:SetStatusBarTexture(file)
    b.pred:SetStatusBarTexture(file)
    b.pred:SetWidth(BW - 2)
    if ns.db.colorMode == "dark" then
        b.bg:SetColorTexture(0.38, 0.07, 0.07, 1) -- fehlendes Leben fällt rot auf
    else
        b.bg:SetColorTexture(0.08, 0.08, 0.08, 1)
    end

    -- Niedrige Frames: Prozent neben den Namen statt in die Mitte
    b.name:ClearAllPoints()
    b.name:SetPoint("TOPLEFT", 3, -3)
    b.name:SetPoint("TOPRIGHT", (low and ns.db.percent) and -46 or -16, -3)
    b.status:ClearAllPoints()
    if low then
        b.status:SetPoint("TOPRIGHT", -16, -3)
    else
        b.status:SetPoint("CENTER", 0, -1)
    end

    -- Schmale Frames zeigen weniger Icons, damit sich Buffs und Debuffs nicht überlappen
    b.maxIcons = math.max(1, math.min(MAX_BUFFS, math.floor((BW - 6) / 2 / (size + 1))))
    if b.manual then PlaceManualIcons(b, size) end
    if b.aurasReady then pcall(StyleContainers, b, size) end

    b.buffBtn:SetSize(12, 12)
    b.buffBtn:ClearAllPoints()
    if low then
        b.buffBtn:SetPoint("CENTER", b, "CENTER", 0, 0)
    else
        b.buffBtn:SetPoint("RIGHT", b, "RIGHT", -3, 1)
    end
end

local function MakeManual(b)
    b.buffs, b.debuffs = {}, {}
    for i = 1, MAX_BUFFS do b.buffs[i] = CreateAuraIcon(b.over, 13) end
    for i = 1, MAX_DEBUFFS do b.debuffs[i] = CreateAuraIcon(b.over, 13) end
    PlaceManualIcons(b, IconSize())
    b.manual = true
end

-- Legt die Aura-Anzeige eines Frames beim ersten Gebrauch an
function EnsureAuras(b)
    if b.aurasReady or b.manual then return end
    if not ns.noContainers then
        local ok, err = pcall(CreateContainers, b)
        if ok then
            b.aurasReady = true
            return
        end
        -- Halb angelegte Bausteine stilllegen
        for _, key in ipairs({ "auraBuffs", "auraDebuffs", "auraDispel" }) do
            if b[key] then pcall(b[key].Hide, b[key]) b[key] = nil end
        end
        if InCombatLockdown() or AurasSecret() then
            return -- im Kampf gescheitert: nach dem Kampf erneut versuchen
        end
        ns.noContainers, ns.containerError = true, tostring(err)
    end
    MakeManual(b)
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

    -- Der klickbare Button liegt über allem Sichtbaren. Sonst würden die
    -- Aura-Icons des Clients (eigene, mausempfindliche Buttons) Klicks abfangen.
    local base = container:GetFrameLevel()
    b:SetFrameLevel(base + 30)
    local vis = CreateFrame("Frame", nil, b)
    vis:SetAllPoints()
    vis:SetFrameLevel(base + 1)
    b.vis = vis

    b.border = vis:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetColorTexture(0, 0, 0, 1)

    local content = CreateFrame("Frame", nil, vis)
    content:SetPoint("TOPLEFT", 1, -1)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
    b.content = content

    b.bg = content:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()

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
    b.over = over

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
    bb:SetFrameLevel(b:GetFrameLevel() + 2)
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

    StyleButton(b)
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

local function DoSkin()
    BW, BH = ns.db.width, ns.db.height
    container:SetSize(BW, HANDLE)
    for _, b in ipairs(buttons) do
        b:SetSize(BW, BH)
        SetPos(b, b.col, b.row)
        StyleButton(b)
    end
    DoLayout()
    for _, b in ipairs(buttons) do
        if b:IsVisible() then UpdateAll(b) end
    end
end

function ns.ApplySkin()
    if container then ns.AfterCombat(DoSkin) end
end

-- Voreinstellung übernehmen
function ns.SetSkin(value)
    for _, skin in ipairs(ns.SKINS) do
        if skin.value == value then
            local db = ns.db
            db.preset = value
            db.width, db.height = skin.width, skin.height
            db.texture, db.colorMode, db.percent = skin.texture, skin.colorMode, skin.percent
            ns.ApplySkin()
            return
        end
    end
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
    BW, BH = ns.db.width, ns.db.height
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
    CreateBuffAll(container)

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
            if event == "READY_CHECK" then readyRound = readyRound + 1 end
            readyCheck = true
            ForVisible(UpdateCenter)
        elseif event == "READY_CHECK_FINISHED" then
            -- Ergebnis noch kurz stehen lassen, außer es läuft schon der nächste Check
            local round = readyRound
            C_Timer.After(6, function()
                if round ~= readyRound then return end
                readyCheck = false
                ForVisible(UpdateCenter)
            end)
        elseif event == "INCOMING_RESURRECT_CHANGED" then
            ForVisible(UpdateCenter)
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Letzte Gelegenheit vor der Kampfsperre
            for _, b in ipairs(buttons) do b.buffBtn:Hide() end
            buffAll:Hide()
        elseif event == "PLAYER_REGEN_ENABLED" then
            ForVisible(UpdateAuras)
        else
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                ns.AfterCombat(DoLayout)
            end
            for _, b in ipairs(buttons) do
                if b:IsVisible() then UpdateAll(b) end
            end
        end
    end)

    C_Timer.NewTicker(0.3, function()
        ForVisible(UpdateRange)
        ns.Safe(UpdateBuffAll)
    end)
end
