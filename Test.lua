local _, ns = ...
local issecret = ns.issecret

-- /hbu test: prüft, was der Client hergibt, und zeigt 5 Sekunden lang alle
-- Anzeigen am eigenen Frame. Geheime Werte werden nie ausgegeben (das würde
-- einen Fehler werfen), nur ob sie geheim sind.
local OK, WARN, BAD = "|cff55ff55OK|r", "|cffffcc33EINGESCHRÄNKT|r", "|cffff5555GEHT NICHT|r"
local problems

local function Line(label, state, detail)
    if state ~= OK then problems = problems + 1 end
    DEFAULT_CHAT_FRAME:AddMessage(("  %s: %s%s"):format(label, state, detail and (" – " .. detail) or ""))
end

-- "ok" (lesbar), "secret", "missing" (Funktion fehlt) oder "error"
local function Probe(func, ...)
    if type(func) ~= "function" then return "missing" end
    local ok, value = pcall(func, ...)
    if not ok then return "error", value end
    if issecret(value) then return "secret" end
    return "ok", value
end

local function Has(tbl, name)
    return type(tbl) == "table" and type(tbl[name]) == "function"
end

local function TestHealth(unit, bar)
    local okBar = pcall(function()
        local probe = CreateFrame("StatusBar")
        probe:SetMinMaxValues(0, UnitHealthMax(unit))
        probe:SetValue(UnitHealth(unit))
    end)
    Line("Lebensbalken", okBar and OK or BAD, not okBar and "Balken nimmt die Werte nicht an" or nil)

    local state = Probe(UnitHealth, unit)
    if state == "ok" then
        Line("Lebenspunkte in Prozent", OK)
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100
        and pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100) then
        Line("Lebenspunkte in Prozent", OK, "Wert geheim, Anzeige über Client-Funktion")
    else
        Line("Lebenspunkte in Prozent", BAD, "Wert geheim und keine Ersatzfunktion")
    end

    state = Probe(UnitIsDeadOrGhost, unit)
    Line("Tot/Offline-Erkennung", state == "ok" and OK or BAD, state ~= "ok" and "Wert " .. state or nil)

    if not UnitGetIncomingHeals then
        Line("Eingehende Heilung", BAD, "Funktion fehlt")
    else
        local ok = pcall(function()
            local probe = CreateFrame("StatusBar")
            probe:SetMinMaxValues(0, UnitHealthMax(unit))
            probe:SetValue(UnitGetIncomingHeals(unit) or 0)
        end)
        Line("Eingehende Heilung", ok and OK or BAD)
    end
end

local function TestSpells()
    local total, ranked = 0, 0
    for _, s in ipairs(ns.spellList) do
        total = total + 1
        if #s.ranks > 1 then ranked = ranked + 1 end
    end
    if total == 0 then
        Line("Zauberbuch", BAD, "keine Zauber gefunden")
    else
        Line("Zauberbuch", OK, total .. " Zauber")
        Line("Ränge", ranked > 0 and OK or WARN,
            ranked > 0 and (ranked .. " Zauber mit mehreren Rängen") or "kein Zauber mit mehreren Rängen gefunden (niedrige Stufe oder Client liefert nur den höchsten Rang)")
    end

    local def = ns.CLASS_DEFAULTS[ns.class]
    if def then
        local found, missing = 0, 0
        for _, d in ipairs(def) do
            local hit = false
            for i = 3, #d do
                local name = ns.SpellName(d[i])
                if name and ns.spells[name] then hit = true end
            end
            if hit then found = found + 1 else missing = missing + 1 end
        end
        Line("Startbelegung der Klasse", found > 0 and OK or WARN,
            ("%d von %d Zaubern bekannt"):format(found, found + missing))
    end

    local cost
    local first = ns.spellList[1]
    if first then cost = ns.ManaCost(first.ranks[1].id) end
    Line("Manakosten der Ränge", cost ~= nil and OK or WARN, cost == nil and "nicht auslesbar" or nil)

    if ns.class == "PRIEST" or ns.class == "PALADIN" or ns.class == "SHAMAN" then
        Line("Wiederbeleben per Heil-Klick", ns.resName and OK or WARN,
            ns.resName or "Wiederbelebungszauber nicht gelernt oder nicht erkannt")
    end
    if ns.class == "PRIEST" or ns.class == "DRUID" or ns.class == "MAGE" then
        Line("Fehlender Klassenbuff", ns.classBuff and OK or WARN,
            ns.classBuff and ns.classBuff.cast or "Buff nicht gelernt oder nicht erkannt")
    end
end

local function TestBindings(button)
    local count = 0
    for _, mod in ipairs(ns.MODS) do
        for n = 1, #ns.BUTTONS do
            if button:GetAttribute(mod.key .. "type" .. n) then count = count + 1 end
        end
    end
    Line("Klick-Belegung", count > 0 and OK or BAD,
        count > 0 and (count .. " Tasten am Frame gesetzt; ob der Klick wirklich zaubert, bitte selbst prüfen") or "keine Belegung am Frame angekommen")
end

local function TestAuras(unit)
    if not Has(C_UnitAuras, "GetAuraDataByIndex") then
        return Line("Buff-/Debuff-Icons", BAD, "Aura-Funktionen fehlen")
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HELPFUL")
    if not ok then
        return Line("Buff-/Debuff-Icons", BAD, "Abfrage wirft einen Fehler")
    end
    if not aura then
        return Line("Buff-/Debuff-Icons", WARN, "kein Buff auf dir zum Prüfen – mit einem Buff erneut testen")
    end
    local secretDuration = issecret(aura.duration)
    local timer = not secretDuration or (Has(C_UnitAuras, "GetAuraDuration") and true)
    Line("Buff-/Debuff-Icons", OK)
    Line("Ablauf-Animation der Icons", timer and OK or BAD, not timer and "Dauer geheim und keine Ersatzfunktion" or nil)
    Line("Filter kurzer eigener Buffs", secretDuration and WARN or OK,
        secretDuration and "Dauer geheim: es werden auch lange eigene Buffs angezeigt" or nil)
    Line("Farbe bannbarer Debuffs", issecret(aura.dispelName) and WARN or OK,
        issecret(aura.dispelName) and "Typ geheim: Rahmen einheitlich pink" or nil)
    local nameSecret = issecret(aura.name)
    if ns.classBuff then
        Line("Erkennung fehlender Buffs", (nameSecret and not Has(C_UnitAuras, "GetAuraDataBySpellName")) and BAD or OK)
    end
end

local function TestStatus(unit, other)
    local state = Probe(UnitThreatSituation, unit)
    Line("Aggro-Rahmen", state == "ok" and OK or BAD,
        state == "secret" and "Bedrohung ist geheim" or state == "missing" and "Funktion fehlt" or nil)

    if other then
        state = Probe(UnitInRange, other)
        if state == "ok" then
            Line("Reichweite", OK)
        elseif state == "secret" then
            local alt = CreateFrame("Frame").SetAlphaFromBoolean ~= nil
            Line("Reichweite", alt and OK or BAD, alt and "Wert geheim, Anzeige über Client-Funktion" or "Wert geheim und keine Ersatzfunktion")
        else
            Line("Reichweite", BAD, "Funktion fehlt oder Fehler")
        end
    else
        Line("Reichweite", WARN, "nur in einer Gruppe prüfbar")
    end

    state = Probe(GetRaidTargetIndex, unit)
    Line("Schlachtzugsymbole", (state == "ok") and OK or BAD, state ~= "ok" and "Wert " .. state or nil)
    Line("Bereitschaftscheck", GetReadyCheckStatus and OK or BAD)
    Line("Eingehende Wiederbelebung", UnitHasIncomingResurrection and OK or BAD)

    state = Probe(UnitPower, "player", ns.MANA)
    Line("Mana-Ticks", state == "ok" and OK or WARN,
        state == "secret" and "Mana geheim: Ticks werden über Events geschätzt, Details mit /hbu ticks" or nil)
end

-- Zeigt alle Anzeigen kurz am Frame, damit man sie einmal gesehen hat
local function Demo(button)
    local b = button
    b.flash:Stop()
    b.flash:Play()
    b.hasAggro = true
    b.aggro:Show()
    b.border:SetColorTexture(1, 0.1, 0.1, 1)
    b.center:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.center:Show()
    b.status:SetAlpha(0)
    SetRaidTargetIconTexture(b.raidIcon, 1)
    b.raidIcon:Show()
    if ns.FSRDemo then ns.FSRDemo() end
    C_Timer.After(5, function()
        b.hasAggro = false
        ns.UpdateAll(b)
    end)
end

function ns.RunTest()
    problems = 0
    local version, build, _, interface = GetBuildInfo()
    ns.Print(("Selbsttest – Client %s (%s), Interface %s, %s"):format(
        tostring(version), tostring(build), tostring(interface),
        InCombatLockdown() and "|cffff5555im Kampf|r" or "außerhalb des Kampfes"))

    local button
    for _, b in ipairs(ns.buttons or {}) do
        if b:IsVisible() and b.kind ~= "pet" then
            local me = b.unit == "player" or UnitIsUnit(b.unit, "player")
            if not issecret(me) and me then button = b break end
        end
    end
    if not button then
        return ns.Print("Kein eigenes Frame sichtbar – Test abgebrochen.")
    end
    local other
    for _, b in ipairs(ns.buttons) do
        if b:IsVisible() and b.kind ~= "pet" and b ~= button then other = b.unit break end
    end

    ns.Safe(TestHealth, button.unit, button.bar)
    ns.Safe(TestSpells)
    ns.Safe(TestBindings, button)
    ns.Safe(TestAuras, button.unit)
    ns.Safe(TestStatus, button.unit, other)
    ns.Safe(Demo, button)

    if problems == 0 then
        ns.Print("Alles in Ordnung. Am eigenen Frame laufen jetzt 5 Sekunden lang alle Anzeigen.")
    else
        ns.Print(problems .. " Punkt(e) eingeschränkt oder nicht möglich (siehe oben). Am eigenen Frame laufen jetzt 5 Sekunden lang alle Anzeigen.")
    end
    if not InCombatLockdown() then
        ns.Print("Viele Werte sind nur im Kampf geheim – bitte den Test einmal im Kampf wiederholen.")
    end
end
