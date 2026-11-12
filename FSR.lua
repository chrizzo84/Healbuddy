local _, ns = ...
local issecret = ns.issecret

-- 5-Sekunden-Regel: Nach jedem Zauber, der Mana kostet, setzt die
-- Willenskraft-Regeneration 5 Sekunden lang aus (blauer Balken).
-- Danach zeigt der Balken grün die 2-Sekunden-Ticks der Regeneration:
-- wer direkt nach einem Tick castet, verschenkt am wenigsten Mana.
local DURATION, TICK = 5, 2

local bar, endTime
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

local function OnMana()
    local cur, max = UnitPower("player", ns.MANA), UnitPowerMax("player", ns.MANA)
    secret = issecret(cur) or issecret(max)
    if secret then
        lastMana, lastTick = nil, nil
        return
    end
    local now = GetTime()
    if lastMana and cur > lastMana then
        lastInterval = lastGain and (now - lastGain) or nil
        gains = gains + 1
        -- Zuwächse in schneller Folge = fließende Regeneration, keine Ticks
        if lastInterval and lastInterval < 1 then smooth = smooth + 1 else smooth = 0 end
        lastGain, lastTick = now, now
    end
    lastMana = cur
    full = cur >= max
    if ns.db.fsr and lastTick and not full and not bar:IsShown() then bar:Show() end
end

function ns.FSRDebug()
    if not bar then return ns.Print("Tickanzeige: für diese Klasse nicht aktiv.") end
    if secret then
        return ns.Print("Tickanzeige: Mana ist ein geheimer Wert – der Client lässt das Auslesen nicht zu.")
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

function ns.CreateFSR(anchor)
    if ns.class == "WARRIOR" or ns.class == "ROGUE" then return end

    bar = CreateFrame("StatusBar", nil, anchor)
    bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
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
    ev:SetScript("OnEvent", function(_, _, _, _, spellID)
        if ns.db.fsr then OnCast(spellID) end
    end)
    C_Timer.NewTicker(0.1, function() ns.Safe(OnMana) end)
end

function ns.UpdateFSR()
    if bar and not ns.db.fsr then bar:Hide() end
end
