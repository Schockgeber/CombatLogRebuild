-- CombatLogRebuild v0.1
-- Restores broken combat damage log on Turtle WoW (DE client)
-- Rebuilds melee via UNIT_COMBAT, forwards spell damage, feeds ShaguDPS

local frame = CreateFrame("Frame")

-- Always print to Combat Log tab
local CHAT_FRAME_NAME = "ChatFrame2"

local function out()
  return _G[CHAT_FRAME_NAME] or DEFAULT_CHAT_FRAME
end

-- Print with Blizzard combat log colors
local function printLine(text, chatType)
  local f = out()
  if not (f and f.AddMessage) then return end

  if chatType and ChatTypeInfo and ChatTypeInfo[chatType] then
    local c = ChatTypeInfo[chatType]
    f:AddMessage(text, c.r, c.g, c.b)
  else
    f:AddMessage(text)
  end
end

local function printEvent(text, eventName)
  if not eventName then
    printLine(text)
    return
  end
  local chatType = string.gsub(eventName, "^CHAT_MSG_", "")
  printLine(text, chatType)
end

-- ---- ShaguDPS feed ----
local function feedShagu(eventName, text)
  if not ShaguDPS or not ShaguDPS.parser then return end
  local handler = ShaguDPS.parser:GetScript("OnEvent")
  if not handler then return end

  local old_event, old_arg1 = event, arg1
  event, arg1 = eventName, text
  handler()
  event, arg1 = old_event, old_arg1
end

-- Vanilla-safe formatter (no varargs)
local function safeFormat(fmt, a, b, c)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local ok, res = pcall(string.format, fmt, a, b, c)
  if ok then return res end
  return nil
end

-- ---- Emitters using localized GlobalStrings ----
local function emitYouHit(target, dmg, crit)
  local fmt = crit and COMBATHITCRITSELFOTHER or COMBATHITSELFOTHER
  local line = safeFormat(fmt, target, dmg, nil)
  if not line then return end
  printEvent(line, "CHAT_MSG_COMBAT_SELF_HITS")
  feedShagu("CHAT_MSG_COMBAT_SELF_HITS", line)
end

local function emitMobHitsYou(source, dmg, crit)
  local fmt = crit and COMBATHITCRITOTHERSELF or COMBATHITOTHERSELF
  local line = safeFormat(fmt, source, dmg, nil)
  if not line then return end
  printEvent(line, "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
  feedShagu("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", line)
end

local function emitPetHit(petName, target, dmg, crit)
  local fmt = crit and COMBATHITCRITOTHEROTHER or COMBATHITOTHEROTHER
  local line = safeFormat(fmt, petName, target, dmg)
  if not line then return end
  printEvent(line, "CHAT_MSG_COMBAT_PET_HITS")
  feedShagu("CHAT_MSG_COMBAT_PET_HITS", line)
end

-- ---- Forward ONLY damage-related spell events (NO healing/buffs) ----
local FORWARD_EVENTS = {
  -- spell damage
  "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PET_DAMAGE",
  "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF",
  "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",

  -- periodic damage
  "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
}

local MIRROR_FORWARDED = true

-- ---- UNIT_COMBAT handling ----
-- unit == "player" -> incoming damage
-- unit == "target" -> outgoing damage
local function handleUnitCombat(unit, action, descriptor, value)
  local dmg = tonumber(value)
  if not dmg or dmg <= 0 then return end

  local isCrit = (descriptor == "CRITICAL" or descriptor == "CRIT" or action == "CRITICAL")
  local targetName = UnitExists("target") and UnitName("target") or nil
  local petName = (UnitExists("pet") and UnitName("pet")) or "Pet"

  -- Incoming damage (mob -> you)
  if unit == "player" and targetName then
    emitMobHitsYou(targetName, dmg, isCrit)
    return
  end

  -- Outgoing damage (you -> mob)
  if unit == "target" and targetName and UnitCanAttack("player", "target") then
    emitYouHit(targetName, dmg, isCrit)
    return
  end

  -- Pet outgoing (best effort)
  if unit == "pet" and targetName and UnitCanAttack("player", "target") then
    emitPetHit(petName, targetName, dmg, isCrit)
    return
  end
end

-- ---- Register events ----
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_COMBAT")
for _, e in ipairs(FORWARD_EVENTS) do
  frame:RegisterEvent(e)
end

frame:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" then
    printLine("|cff00ff00CombatLogRebuild v0.1|r enabled (damage only, ShaguDPS compatible)")
    return
  end

  -- Forward damage-related spell events
  if string.sub(event, 1, 9) == "CHAT_MSG_" and arg1 then
    feedShagu(event, arg1)
    if MIRROR_FORWARDED then
      printEvent(arg1, event)
    end
    return
  end

  if event == "UNIT_COMBAT" then
    handleUnitCombat(arg1, arg2, arg3, arg4)
  end
end)
