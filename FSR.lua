local _, ns = ...
local issecret = ns.issecret

-- 5-Sekunden-Regel: Nach jedem Zauber, der Mana kostet, setzt die
-- Willenskraft-Regeneration 5 Sekunden lang aus. Der Balken läuft diese
-- 5 Sekunden ab; ist er weg, regeneriert man wieder voll.
local DURATION = 5
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local bar, endTime

-- true = kostet Mana, false = kostet sicher kein Mana, nil = unbekannt
local function CostsMana(spellID)
    if not spellID or issecret(spellID) then return nil end
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if not costs then return nil end
    for _, c in ipairs(costs) do
        if issecret(c.type) or issecret(c.cost) then return nil end
        if c.type == MANA and c.cost > 0 then return true end
    end
    return false
end

local function Start()
    endTime = GetTime() + DURATION
    bar:Show()
end

local function OnUpdate(self)
    local left = endTime - GetTime()
    if left <= 0 then
        self:Hide()
        return
    end
    self:SetValue(left)
    self.spark:SetPoint("CENTER", self, "LEFT", self:GetWidth() * left / DURATION, 0)
    self.text:SetFormattedText("%.1f", left)
end

function ns.CreateFSR(anchor)
    local _, class = UnitClass("player")
    if class == "WARRIOR" or class == "ROGUE" then return end

    bar = CreateFrame("StatusBar", nil, anchor)
    bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    bar:SetHeight(10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.25, 0.55, 1)
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
        if not ns.db.fsr then return end
        -- Bei unbekannten Kosten lieber anzeigen als verschweigen
        local ok, costs = pcall(CostsMana, spellID)
        if not ok or costs ~= false then Start() end
    end)
end

function ns.UpdateFSR()
    if bar and not ns.db.fsr then bar:Hide() end
end
