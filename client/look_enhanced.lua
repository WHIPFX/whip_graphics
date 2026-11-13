-- The look (Enhanced build of 2.0.3), two parts, as in the Legacy pack:
--   * on the *extra* slot, full strength: the tuned look (grade, shadow-side ambient colour, haze, glow) plus the
--     sun-shadow box. On Enhanced it comes baked into snapshot modifiers through the day per weather group
--     (data/whippy_led_look_snapshots.xml, listed in client/look_snap.lua); this script puts the one for the current game
--     hour and weather on the slot. Only GTA's own natives are needed (FiveM's timecycle-editing natives that the
--     Legacy pack uses are unconfirmed on FiveM Enhanced). Each switch moves values by at most 5% of their range.
--   * whippy_day / whippy_night on the *main* slot, cross-faded by strength by game clock (night 21:00-05:00, day
--     07:00-19:00, passing through stock at 06:00 and 20:00), so GTA blends them with its own value for wherever the
--     player is. It steps aside while another script's modifier is on the main slot and comes back within a quarter second of it being
--     free. In Halloween weather the night uses whippy_night_plain, so the green moon stays.
-- Visual settings (softer highlights, bigger light halos) are applied only if this FiveM build has the natives.
-- /ledambient toggles the whole look.
--
-- 2.1.0: one pack for both games. This is Enhanced's look; client/look_legacy.lua is Legacy's. whip's whip_platform
-- convar says which game (setr whip_platform enhanced in an Enhanced server.cfg; unset is Legacy, as whip_core reads it).
if string.lower(GetConvar('whip_platform', 'legacy')) ~= 'enhanced' then return end

local DAY, NIGHT, NIGHT_PLAIN = 'whippy_day', 'whippy_night', 'whippy_night_plain'
local TICK_MS = 1000
local S = LookSnap

local enabled = true
local visualOrig = {}
local VISUAL = {
    ['Tonemapping.bright.filmic.A'] = 0.20, ['Tonemapping.bright.filmic.W'] = 5.0,
    ['misc.coronas.intensityScaleGlobal'] = 0.9, ['misc.coronas.sizeScaleGlobal'] = 1.1,
}
local canVisual = type(SetVisualSettingFloat) == 'function' and type(GetVisualSettingFloat) == 'function'

local weatherByHash = {}
for name in pairs(S.weatherGroup) do weatherByHash[GetHashKey(name)] = name end

local function smooth(t) t = math.max(0.0, math.min(1.0, t)) return t * t * (3.0 - 2.0 * t) end
local function hourNow() return GetClockHours() + GetClockMinutes() / 60.0 + GetClockSeconds() / 3600.0 end

local function currentGroupName()
    local weather = weatherByHash[GetNextWeatherTypeHashName()] or 'EXTRASUNNY'
    return S.weatherGroup[weather] or 'grey'
end

-- 1 = full night, 0 = full day
local function nightness(h)
    if h >= 19.0 and h < 21.0 then return smooth((h - 19.0) / 2.0) end
    if h >= 5.0 and h < 7.0 then return 1.0 - smooth((h - 5.0) / 2.0) end
    if h >= 7.0 and h < 19.0 then return 0.0 end
    return 1.0
end

-- the snapshot covering hour h: the last one starting at or before it
local function snapshotFor(group, h)
    local list = S.groups[group] or S.groups.grey
    local pick = list[#list]
    for _, s in ipairs(list) do
        if s.h <= h then pick = s else break end
    end
    return pick.name
end

-- extra slot ------------------------------------------------------------------------------------------------------
local extra = { name = nil, index = nil }

local function applyExtra(name)
    if extra.name ~= name or GetExtraTimecycleModifierIndex() ~= extra.index then
        SetExtraTimecycleModifier(name)
        extra.name, extra.index = name, GetExtraTimecycleModifierIndex()
    end
    SetExtraTimecycleModifierStrength(1.0)
end

local function clearExtra()
    if extra.index and GetExtraTimecycleModifierIndex() == extra.index then ClearExtraTimecycleModifier() end
    extra.name, extra.index = nil, nil
end

-- main slot -------------------------------------------------------------------------------------------------------
local dayNight = { mod = nil, strength = 0.0 }
local mainIndex, ours = {}, {}         -- learnt when we put a modifier on the main slot

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
    if mainIndex[want] == nil or cur ~= mainIndex[want] then
        SetTimecycleModifier(want)
        shownStrength = nil
        local idx = GetTimecycleModifierIndex()
        if idx ~= -1 then mainIndex[want], ours[idx] = idx, true end
    end
    if shownStrength ~= dayNight.strength then
        SetTimecycleModifierStrength(dayNight.strength)
        shownStrength = dayNight.strength
    end
end

local function setVisual(on)
    if not canVisual then return end
    for name, v in pairs(VISUAL) do
        if on then
            if visualOrig[name] == nil then
                local ok, cur = pcall(GetVisualSettingFloat, name)
                if ok then visualOrig[name] = cur end
            end
            pcall(SetVisualSettingFloat, name, v)
        elseif visualOrig[name] ~= nil then
            pcall(SetVisualSettingFloat, name, visualOrig[name])
            visualOrig[name] = nil
        end
    end
end

CreateThread(function()
    setVisual(true)
    while true do
        if enabled then
            local h = hourNow()
            applyExtra(snapshotFor(currentGroupName(), h))
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
    while true do
        enforceMain()
        Wait(MAIN_CHECK_MS)
    end
end)

-- /ledambient : toggle the whole look (both slots and the visual settings) for before/after comparison
RegisterCommand('ledambient', function()
    enabled = not enabled
    if not enabled then
        clearExtra()
        if ours[GetTimecycleModifierIndex()] then ClearTimecycleModifier() end
    end
    setVisual(enabled)
    print(('[whip_graphics_enhanced] look %s'):format(enabled and 'ON' or 'OFF'))
end, false)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    setVisual(false)
    clearExtra()
    if ours[GetTimecycleModifierIndex()] then ClearTimecycleModifier() end
end)
