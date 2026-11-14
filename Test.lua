local _, ns = ...
local L = ns.L
local issecret = ns.issecret

-- /hbu test: prüft, was der Client hergibt, und zeigt 5 Sekunden lang alle
-- Anzeigen am eigenen Frame. Geheime Werte werden nie ausgegeben (das würde
-- einen Fehler werfen), nur ob sie geheim sind.
local OK, WARN, BAD = "|cff55ff55OK|r", "|cffffcc33" .. L["LIMITED"] .. "|r", "|cffff5555" .. L["NOT WORKING"] .. "|r"
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
    Line(L["Health bar"], okBar and OK or BAD, not okBar and L["bar does not accept the values"] or nil)

    local state = Probe(UnitHealth, unit)
    if state == "ok" then
        Line(L["Health in percent"], OK)
    elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100
        and pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100) then
        Line(L["Health in percent"], OK, L["value is secret, shown via a client function"])
    else
        Line(L["Health in percent"], BAD, L["value is secret and there is no fallback function"])
    end

    state = Probe(UnitIsDeadOrGhost, unit)
    Line(L["Dead/offline detection"], state == "ok" and OK or BAD, state ~= "ok" and L["value: %s"]:format(state) or nil)

    if not UnitGetIncomingHeals then
        Line(L["Incoming heals"], BAD, L["function missing"])
    else
        local ok = pcall(function()
            local probe = CreateFrame("StatusBar")
            probe:SetMinMaxValues(0, UnitHealthMax(unit))
            probe:SetValue(UnitGetIncomingHeals(unit) or 0)
        end)
        Line(L["Incoming heals"], ok and OK or BAD)
    end
end

local function TestSpells()
    local total, ranked = 0, 0
    for _, s in ipairs(ns.spellList) do
        total = total + 1
        if #s.ranks > 1 then ranked = ranked + 1 end
    end
    if total == 0 then
        Line(L["Spellbook"], BAD, L["no spells found"])
    else
        Line(L["Spellbook"], OK, L["%d spells"]:format(total))
        Line(L["Ranks"], ranked > 0 and OK or WARN,
            ranked > 0 and L["%d spells with multiple ranks"]:format(ranked) or L["no spell with multiple ranks found (low level, or the client only reports the highest rank)"])
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
        Line(L["Class default bindings"], found > 0 and OK or WARN,
            (L["%d of %d spells known"]):format(found, found + missing))
    end

    local cost
    local first = ns.spellList[1]
    if first then cost = ns.ManaCost(first.ranks[1].id) end
    Line(L["Mana cost of ranks"], cost ~= nil and OK or WARN, cost == nil and L["not readable"] or nil)

    if ns.class == "PRIEST" or ns.class == "PALADIN" or ns.class == "SHAMAN" then
        Line(L["Resurrect via heal click"], ns.resName and OK or WARN,
            ns.resName or L["resurrection spell not learned or not detected"])
    end
    if ns.class == "PRIEST" or ns.class == "DRUID" or ns.class == "MAGE" then
        Line(L["Missing class buff"], ns.classBuff and OK or WARN,
            ns.classBuff and ns.classBuff.cast or L["buff not learned or not detected"])
    end
end

local function TestBindings(button)
    local count = 0
    for _, mod in ipairs(ns.MODS) do
        for n = 1, #ns.BUTTONS do
            if button:GetAttribute(mod.key .. "type" .. n) then count = count + 1 end
        end
    end
    Line(L["Click bindings"], count > 0 and OK or BAD,
        count > 0 and L["%d buttons set on the frame; please check yourself whether a click really casts"]:format(count) or L["no bindings arrived at the frame"])
end

local function TestAuras(button)
    if button.aurasReady then
        Line(L["Buff/debuff icons"], OK, L["via Blizzard components, also in combat"])
        Line(L["Border color for dispellable debuffs"], OK, L["via Blizzard component"])
    elseif button.manual then
        Line(L["Buff/debuff icons"], WARN, L["Blizzard component not available, icons only out of combat"]
            .. (ns.containerError and (" – " .. ns.containerError) or ""))
    else
        Line(L["Buff/debuff icons"], WARN, L["will be set up after combat"])
    end
    Line(L["Auras currently restricted"], OK, ns.AurasSecret() and L["yes"] or L["no"])
    if ns.classBuff then
        Line(L["Missing buff detection"], OK, L["only out of combat"])
    end
end

local function TestStatus(unit, other)
    local state = Probe(UnitThreatSituation, unit)
    Line(L["Aggro border"], state == "ok" and OK or BAD,
        state == "secret" and L["threat is secret"] or state == "missing" and L["function missing"] or nil)

    if other then
        state = Probe(UnitInRange, other)
        if state == "ok" then
            Line(L["Range"], OK)
        elseif state == "secret" then
            local alt = CreateFrame("Frame").SetAlphaFromBoolean ~= nil
            Line(L["Range"], alt and OK or BAD, alt and L["value is secret, shown via a client function"] or L["value is secret and there is no fallback function"])
        else
            Line(L["Range"], BAD, L["function missing or error"])
        end
    else
        Line(L["Range"], WARN, L["can only be checked in a group"])
    end

    state = Probe(GetRaidTargetIndex, unit)
    Line(L["Raid target icons"], (state == "ok") and OK or BAD, state ~= "ok" and L["value: %s"]:format(state) or nil)
    Line(L["Ready check"], GetReadyCheckStatus and OK or BAD)
    Line(L["Incoming resurrection"], UnitHasIncomingResurrection and OK or BAD)

    state = Probe(UnitPower, "player", ns.MANA)
    Line(L["Mana ticks"], state == "ok" and OK or WARN,
        state == "secret" and L["mana is secret: ticks are estimated from events, details with /hbu ticks"] or nil)
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
    ns.Print((L["Self-test – client %s (%s), interface %s, %s"]):format(
        tostring(version), tostring(build), tostring(interface),
        InCombatLockdown() and "|cffff5555" .. L["in combat"] .. "|r" or L["out of combat"]))

    local button
    for _, b in ipairs(ns.buttons or {}) do
        if b:IsVisible() and b.kind ~= "pet" then
            local me = b.unit == "player" or UnitIsUnit(b.unit, "player")
            if not issecret(me) and me then button = b break end
        end
    end
    if not button then
        return ns.Print(L["Own frame not visible – test aborted."])
    end
    local other
    for _, b in ipairs(ns.buttons) do
        if b:IsVisible() and b.kind ~= "pet" and b ~= button then other = b.unit break end
    end

    ns.Safe(TestHealth, button.unit, button.bar)
    ns.Safe(TestSpells)
    ns.Safe(TestBindings, button)
    ns.Safe(TestAuras, button)
    ns.Safe(TestStatus, button.unit, other)
    ns.Safe(Demo, button)

    if problems == 0 then
        ns.Print(L["Everything is fine. All indicators now run on your own frame for 5 seconds."])
    else
        ns.Print(L["%d item(s) limited or not working (see above). All indicators now run on your own frame for 5 seconds."]:format(problems))
    end
    if not InCombatLockdown() then
        ns.Print(L["Many values are only secret in combat – please repeat the test once in combat."])
    end
end
