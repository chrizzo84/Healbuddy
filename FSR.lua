local _, ns = ...
local issecret = ns.issecret

-- 5-Sekunden-Regel: Nach jedem Zauber, der Mana kostet, setzt die
-- Willenskraft-Regeneration 5 Sekunden lang aus (blauer Balken).
-- Danach zeigt der Balken grün die 2-Sekunden-Ticks der Regeneration:
-- wer direkt nach einem Tick castet, verschenkt am wenigsten Mana.
local DURATION, TICK = 5, 2

local bar, mana, endTime
local lastMana, lastTick, lastGain, full
local smooth = 0 -- zählt Mana-Zuwächse in kurzer Folge (= keine Ticks, sondern fließende Regeneration)

local function SetSpark(self, fraction)
    self.spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * fraction, 0)
end

local function OnUpdate(self)
    local now = GetTime()
    if endTime and now < endTime then
        local left = endTime - now
        self:SetStatusBarColor(0.25, 0.55, 1)
        self:SetMinMaxValues(0, DURATION)
        self:SetValue(left)
        SetSpark(self, left / DURATION)
        self.text:SetFormattedText("%.1f", left)
    elseif lastTick and not full and smooth < 3 and now - lastTick < 3 * TICK then
        local phase = (now - lastTick) % TICK
        self:SetStatusBarColor(0.3, 0.85, 0.45)
        self:SetMinMaxValues(0, TICK)
        self:SetValue(phase)
        SetSpark(self, phase / TICK)
        self.text:SetText("")
    else
        self:Hide()
    end
end

-- Wird alle 0,1 s abgefragt (nicht per Event: je nach Client feuert
-- UNIT_POWER_UPDATE bei reiner Regeneration nicht zuverlässig)
local gains, lastInterval, secret = 0, nil, false
local lastCast, prevGain, prevTick

local function Gain(now)
    prevGain, prevTick = lastGain, lastTick
    lastInterval = lastGain and (now - lastGain) or nil
    gains = gains + 1
    -- Zuwächse in schneller Folge = fließende Regeneration, keine Ticks
    if lastInterval and lastInterval < 1 then smooth = smooth + 1 else smooth = 0 end
    lastGain, lastTick = now, now
    if ns.db.fsr and not full and not bar:IsShown() then bar:Show() end
end

-- Der Manabalken darf auch geheime Werte anzeigen (StatusBar nimmt sie direkt)
local function UpdateManaBar(cur, max)
    mana:SetMinMaxValues(0, max)
    mana:SetValue(cur)
    if not issecret(cur) and not issecret(max) then
        if max > 0 then mana.text:SetFormattedText("%.0f%%", cur / max * 100) else mana.text:SetText("") end
    elseif UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitPowerPercent, "player", ns.MANA, false, CurveConstants.ScaleTo100)
        if ok and pct ~= nil then mana.text:SetFormattedText("%.0f%%", pct) else mana.text:SetText("") end
    else
        mana.text:SetText("")
    end
end

local function OnMana()
    local cur, max = UnitPower("player", ns.MANA), UnitPowerMax("player", ns.MANA)
    if mana:IsShown() then ns.Safe(UpdateManaBar, cur, max) end
    secret = issecret(cur) or issecret(max)
    if secret then
        -- Wert nicht lesbar: die Ticks kommen dann über OnPowerEvent
        lastMana, full = nil, false
        return
    end
    local gained = lastMana and cur > lastMana
    lastMana = cur
    full = cur >= max
    if gained then Gain(GetTime()) end
end

-- Ist das Mana geheim, verrät immer noch der Zeitpunkt des Events den Tick:
-- jede Mana-Änderung, die nicht direkt auf einen eigenen Zauber folgt, zählt.
-- Bei vollem Mana kommen keine Events mehr, der Balken blendet sich dann aus.
local function OnPowerEvent(powerType)
    if not secret then return end
    if powerType and not issecret(powerType) and powerType ~= "MANA" then return end
    local now = GetTime()
    if lastCast and now - lastCast < 0.5 then return end
    Gain(now)
end

function ns.FSRDebug()
    if not bar then return ns.Print("Tickanzeige: für diese Klasse nicht aktiv.") end
    if secret then
        return ns.Print(("Tickanzeige: Mana ist geheim, Ticks werden über Events geschätzt. Events erkannt: %d, letzter Abstand: %s s, fließend-Zähler: %d, Option an: %s"):format(
            gains, lastInterval and ("%.2f"):format(lastInterval) or "-", smooth, tostring(ns.db.fsr)))
    end
    ns.Print(("Tickanzeige: Mana %s/%s, Zuwächse erkannt: %d, letzter Abstand: %s s, fließend-Zähler: %d, voll: %s, Option an: %s"):format(
        tostring(lastMana), tostring(UnitPowerMax("player", ns.MANA)), gains,
        lastInterval and ("%.2f"):format(lastInterval) or "-", smooth, tostring(full), tostring(ns.db.fsr)))
end

local function OnCast(spellID)
    -- Bei unbekannten Kosten lieber anzeigen als verschweigen
    local ok, cost = pcall(ns.ManaCost, spellID)
    if ok and cost == 0 then return end
    endTime = GetTime() + DURATION
    bar:Show()
end

local function OnEvent(_, event, _, arg2, spellID)
    if event == "UNIT_POWER_UPDATE" then
        ns.Safe(OnPowerEvent, arg2)
    else
        lastCast = GetTime()
        -- Der Manaabzug kann knapp vor diesem Event eintreffen: dann war es kein Tick
        if secret and lastGain and lastCast - lastGain < 0.3 then
            lastGain, lastTick = prevGain, prevTick
        end
        if ns.db.fsr then OnCast(spellID) end
    end
end

function ns.CreateFSR(anchor)
    if ns.class == "WARRIOR" or ns.class == "ROGUE" then return end

    mana = CreateFrame("StatusBar", nil, anchor)
    mana:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    mana:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    mana:SetHeight(10)
    mana:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    mana:SetStatusBarColor(0.15, 0.35, 0.9)
    local mbg = mana:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0, 0, 0, 0.7)
    mana.text = mana:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mana.text:SetPoint("CENTER")
    mana:SetShown(ns.db.fsr)

    bar = CreateFrame("StatusBar", nil, anchor)
    bar:SetPoint("BOTTOMLEFT", mana, "TOPLEFT", 0, 1)
    bar:SetPoint("BOTTOMRIGHT", mana, "TOPRIGHT", 0, 1)
    bar:SetHeight(10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, DURATION)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetSize(12, 22)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar:SetScript("OnUpdate", OnUpdate)
    bar:Hide()

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ev:SetScript("OnEvent", OnEvent)
    C_Timer.NewTicker(0.1, function() ns.Safe(OnMana) end)
end

function ns.FSRDemo()
    if not bar then return end
    endTime = GetTime() + DURATION
    bar:Show()
end

function ns.UpdateFSR()
    if not bar then return end
    mana:SetShown(ns.db.fsr)
    if not ns.db.fsr then bar:Hide() end
end
