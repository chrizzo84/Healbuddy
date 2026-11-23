local _, ns = ...
local L = ns.L

-- Legende der Klick-Belegung: fünf kleine Icons (Links-, Rechts-, Mittelklick,
-- Maustaste 4 und 5) zwischen Manabalken und Cooldowns. Beim Halten von
-- Shift, Strg oder Alt wechselt sie sofort auf die Zauber dieser Ebene.
local SLOTS, GAP = 5, 1
local LETTERS = { "L", "R", "M", "4", "5" }

local row, anchorFrame
local slots = {}

-- Dieselbe Regel wie beim Klick: genau ein Modifikator oder keiner
local function CurrentMod()
    local alt, ctrl, shift = IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()
    if (alt and 1 or 0) + (ctrl and 1 or 0) + (shift and 1 or 0) > 1 then return nil end
    return alt and "alt-" or ctrl and "ctrl-" or shift and "shift-" or ""
end

local function Refresh()
    for _, slot in ipairs(slots) do
        if slot.id then
            ns.Safe(ns.SetSpellCooldown, slot.cd, slot.id)
        else
            slot.cd:Clear()
        end
    end
end

local function CreateSlot(i)
    local slot = CreateFrame("Frame", nil, row)
    local bg = slot:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.7)
    slot.tex = slot:CreateTexture(nil, "ARTWORK")
    slot.tex:SetAllPoints()
    slot.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.cd:SetAllPoints()
    slot.cd:EnableMouse(false)
    if slot.cd.SetHideCountdownNumbers then slot.cd:SetHideCountdownNumbers(true) end
    local top = CreateFrame("Frame", nil, slot)
    top:SetAllPoints()
    top:SetFrameLevel(slot.cd:GetFrameLevel() + 1)
    slot.letter = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slot.letter:SetPoint("CENTER")
    slot.letter:SetText(LETTERS[i])
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.BUTTONS[i])
        GameTooltip:AddLine(self.text or ("|cff888888" .. L["– nothing –"] .. "|r"), 1, 1, 1)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = slot
    return slot
end

function ns.UpdateLegend()
    if not row then return end
    local on = ns.db.legend
    local below = ns.cdRow or anchorFrame
    row:ClearAllPoints()
    row:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, on and 2 or 0)
    row:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, on and 2 or 0)
    if not on then
        row:SetHeight(0.1)
        for _, slot in ipairs(slots) do slot:Hide() end
        return
    end

    -- Fünf Plätze über die Breite eines Frames; die Höhe bleibt gleich,
    -- damit beim Drücken eines Modifikators nichts springt
    local size = math.max(8, math.min(18, math.floor((ns.db.width - (SLOTS - 1) * GAP) / SLOTS)))
    row:SetHeight(size)
    local mod = CurrentMod()
    for i = 1, SLOTS do
        local slot = slots[i] or CreateSlot(i)
        slot:SetSize(size, size)
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * (size + GAP), 0)
        local bind = mod and ns.cdb.bindings[mod][i]
        local text, icon, id = ns.BindingInfo(bind)
        slot.text, slot.id = text, id
        slot.tex:SetTexture(icon)
        -- Ohne Icon bleibt der Buchstabe der Maustaste stehen
        slot.letter:SetShown(not icon)
        slot.letter:SetAlpha(text and 1 or 0.35)
        -- Unbelegte Plätze nur auf Wunsch; die Position bleibt fest, damit
        -- man die Maustaste weiter an der Stelle erkennt
        slot:SetShown(text ~= nil or ns.db.legendEmpty)
    end
    Refresh()
end

function ns.CreateLegend(anchor)
    anchorFrame = anchor
    row = CreateFrame("Frame", nil, anchor)
    row:SetHeight(0.1)
    ns.legendRow = row
    ns.UpdateLegend()

    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "MODIFIER_STATE_CHANGED")
    pcall(ev.RegisterEvent, ev, "SPELL_UPDATE_COOLDOWN")
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "MODIFIER_STATE_CHANGED" then
            ns.Safe(ns.UpdateLegend)
        else
            Refresh()
        end
    end)
end
