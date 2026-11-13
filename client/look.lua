-- The look (2.0.1), two parts:
--   * whippy_look on the *extra* slot, full strength, rewritten once a second from client/look_data.lua: the tuned
--     grade, shadow-side ambient colour and haze keyed by game hour, as much of it as the current weather's group
--     allows (clear weathers get all of it; fog, rain, snow and Halloween keep their own character), plus the
--     sun-shadow box. Absolute values, so it never dips at dawn or dusk.
--   * whippy_day / whippy_night on the *main* slot, cross-faded by strength by game clock (night 21:00-05:00, day
--     07:00-19:00, passing through stock at 06:00 and 20:00). Strength lets GTA blend them with its own value for
--     wherever the player is, city or countryside, so they can't pop. The main slot is shared: when another script
--     puts its own modifier there (a camera filter, an editor) this steps aside until the slot is free again; when
--     something just clears it (a camera filter switched off), it's put back within a quarter second. In Halloween weather the
--     night uses whippy_night_plain (no moonlight colour / exposure change), so the green moon stays.
-- /ledambient toggles the whole look.

local LOOK, DAY, NIGHT, NIGHT_PLAIN = 'whippy_look', 'whippy_day', 'whippy_night', 'whippy_night_plain'
local TICK_MS = 1000
local D = LookData

local enabled = true
local applied = {}          -- var -> value written to whippy_look
local visualOrig = {}
-- visual settings (restored on stop / /ledambient off): softer highlights, and slightly bigger, brighter light halos
-- (stock 0.5 / 0.75; shot-tested with the night glow)
local VISUAL = {
    ['Tonemapping.bright.filmic.A'] = 0.20, ['Tonemapping.bright.filmic.W'] = 5.0,
    ['misc.coronas.intensityScaleGlobal'] = 0.9, ['misc.coronas.sizeScaleGlobal'] = 1.1,
}

local weatherByHash = {}
for name in pairs(D.weatherGroup) do weatherByHash[GetHashKey(name)] = name end

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(t) t = math.max(0.0, math.min(1.0, t)) return t * t * (3.0 - 2.0 * t) end

local function hourNow() return GetClockHours() + GetClockMinutes() / 60.0 + GetClockSeconds() / 3600.0 end

-- 1 = full night, 0 = full day
local function nightness(h)
    if h >= 19.0 and h < 21.0 then return smooth((h - 19.0) / 2.0) end
    if h >= 5.0 and h < 7.0 then return 1.0 - smooth((h - 5.0) / 2.0) end
    if h >= 7.0 and h < 19.0 then return 0.0 end
    return 1.0
end

-- the two keys around hour h, and how far between them (wraps at 24)
local function around(list, h)
    local n = #list
    local a, b = list[n], list[1]
    for i = 1, n do
        if list[i].h > h then
            b = list[i]
            a = list[i - 1] or list[n]
            break
        end
    end
    local span = (b.h - a.h) % 24.0
    if span == 0 then return a, b, 0.0 end
    return a, b, ((h - a.h) % 24.0) / span
end

local function currentGroupName()
    local weather = weatherByHash[GetNextWeatherTypeHashName()] or 'EXTRASUNNY'
    return D.weatherGroup[weather] or 'grey'
end

-- extra slot ------------------------------------------------------------------------------------------------------
local function lookValues(h)
    local group = D.groups[currentGroupName()] or D.groups.grey
    local want = { [D.box.var] = D.box.value }
    local a, b, t = around(D.look, h)
    local function keyed(var) return lerp(a.v[var], b.v[var], t) end
    if group.grade > 0 then
        for _, var in ipairs(D.families.grade) do
            local v = keyed(var)
            if not var:find('cutoff', 1, true) then v = 1.0 + (v - 1.0) * group.grade end
            want[var] = v
        end
    end
    if group.amb then for _, var in ipairs(D.families.amb) do want[var] = keyed(var) end end
    if group.fog then for _, var in ipairs(D.families.fog) do want[var] = keyed(var) end end
    if group.glow then for _, var in ipairs(D.families.glow) do want[var] = keyed(var) end end
    return want
end

local function writeLook(want)
    for var, v in pairs(want) do
        local old = applied[var]
        if old == nil or math.abs(old - v) > 1e-4 then
            SetTimecycleModifierVar(LOOK, var, v + 0.0, v + 0.0)
            applied[var] = v
        end
    end
    for var in pairs(applied) do
        if want[var] == nil then
            RemoveTimecycleModifierVar(LOOK, var)
            applied[var] = nil
        end
    end
end

-- main slot -------------------------------------------------------------------------------------------------------
local dayNight = { mod = nil, strength = 0.0 }      -- what the main slot should hold now (nil = nothing of ours)
local ours = {}

-- Halloween nights keep their own green moon: Whippy's night values without the look's moonlight and exposure
local function dayNightTarget(h)
    local n = nightness(h)
    if n >= 0.5 then return (currentGroupName() == 'halloween') and NIGHT_PLAIN or NIGHT, (n - 0.5) * 2.0 end
    return DAY, (0.5 - n) * 2.0
end

-- 2.0.5 (CPU): the strength is set only when it changed or right after the modifier is put (back) on the slot; it
-- changes at most once a second (TICK_MS), and this runs every frame. Another script changing the strength of our
-- modifier without changing the modifier now stays until our next strength change (none in whip does that).
local shownStrength = nil            -- what the main slot was last given (nil: give it again)

local function enforceMain()
    local cur = GetTimecycleModifierIndex()
    local mine = ours[cur]
    if cur ~= -1 and not mine then shownStrength = nil; return end   -- another script's modifier: step aside
    local want = enabled and dayNight.strength > 0.001 and dayNight.mod or nil
    if want == nil then
        if mine then ClearTimecycleModifier() end
        shownStrength = nil
        return
    end
    if cur ~= ours.index[want] then SetTimecycleModifier(want); shownStrength = nil end
    if shownStrength ~= dayNight.strength then
        SetTimecycleModifierStrength(dayNight.strength)
        shownStrength = dayNight.strength
    end
end

local function setVisual(on)
    for name, v in pairs(VISUAL) do
        if on then
            if visualOrig[name] == nil then visualOrig[name] = GetVisualSettingFloat(name) end
            SetVisualSettingFloat(name, v)
        elseif visualOrig[name] ~= nil then
            SetVisualSettingFloat(name, visualOrig[name])
            visualOrig[name] = nil
        end
    end
end

CreateThread(function()
    local lookIndex = GetTimecycleModifierIndexByName(LOOK)
    ours.index = { [DAY] = GetTimecycleModifierIndexByName(DAY), [NIGHT] = GetTimecycleModifierIndexByName(NIGHT),
                   [NIGHT_PLAIN] = GetTimecycleModifierIndexByName(NIGHT_PLAIN) }
    for _, i in pairs(ours.index) do if i >= 0 then ours[i] = true end end
    setVisual(true)
    while true do
        if enabled then
            local h = hourNow()
            writeLook(lookValues(h))
            if GetExtraTimecycleModifierIndex() ~= lookIndex then SetExtraTimecycleModifier(LOOK) end
            SetExtraTimecycleModifierStrength(1.0)
            dayNight.mod, dayNight.strength = dayNightTarget(h)
        end
        Wait(TICK_MS)
    end
end)

-- the main slot is checked 4 times a second: a script clearing it shows the stock look for at most MAIN_CHECK_MS.
-- (Every frame cost more than the rest of the pack together; whip's inventory no longer clears the slot, so what
-- clears it now is a camera filter or a dev tool being switched off.)
local MAIN_CHECK_MS = 250
CreateThread(function()
    while ours.index == nil do Wait(100) end
    while true do
        enforceMain()
        Wait(MAIN_CHECK_MS)
    end
end)

-- /ledambient : toggle the whole look (both slots and the visual settings) for before/after comparison
RegisterCommand('ledambient', function()
    enabled = not enabled
    if not enabled then
        if GetExtraTimecycleModifierIndex() == GetTimecycleModifierIndexByName(LOOK) then ClearExtraTimecycleModifier() end
        if ours[GetTimecycleModifierIndex()] then ClearTimecycleModifier() end
    end
    setVisual(enabled)
    print(('[whip_graphics] look %s'):format(enabled and 'ON' or 'OFF'))
end, false)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    setVisual(false)
    if GetExtraTimecycleModifierIndex() == GetTimecycleModifierIndexByName(LOOK) then ClearExtraTimecycleModifier() end
    if ours[GetTimecycleModifierIndex()] then ClearTimecycleModifier() end
end)
