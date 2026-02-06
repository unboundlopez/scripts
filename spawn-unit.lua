-- Spawn one or more units, with optional interactive prompts.
--[====[

spawn-unit
==========

Creates units using ``modtools/create-unit``. You can provide creature and caste
on the commandline, or run with ``-gui`` to choose them from interactive lists,
similar to arena creature selection.

Examples::

    spawn-unit -gui
    spawn-unit -race DWARF -caste MALE
    spawn-unit -race HUMAN -caste FEMALE -amount 5 -nick Visitor

]====]

local script = require('gui.script')
local utils = require('utils')
local guidm = require('gui.dwarfmode')
local create_unit = reqscript('modtools/create-unit')

local validArgs = utils.invert({
    'help',
    'gui',
    'race',
    'caste',
    'amount',
    'nick',
    'x',
    'y',
    'z',
})

local args = utils.processArgs({...}, validArgs)


local function sorted_creature_defs()
    local defs = {}
    for _, creature in ipairs(df.global.world.raws.creatures.all) do
        table.insert(defs, creature)
    end
    table.sort(defs, function(a, b) return a.creature_id < b.creature_id end)
    return defs
end

local function choose_creature_and_caste()
    local creature_defs = sorted_creature_defs()
    local creature_tokens = {}
    for _, creature in ipairs(creature_defs) do
        table.insert(creature_tokens, creature.creature_id)
    end

    local ok_creature, creature_idx = script.showListPrompt(
        'spawn-unit',
        'Choose creature',
        COLOR_WHITE,
        creature_tokens,
        20,
        true)
    if not ok_creature then return end

    local creature = creature_defs[creature_idx]
    local caste_tokens = {}
    for _, caste in ipairs(creature.caste) do
        table.insert(caste_tokens, caste.caste_id)
    end

    local ok_caste, caste_idx = script.showListPrompt(
        'spawn-unit',
        ('Choose caste for %s'):format(creature.creature_id),
        COLOR_WHITE,
        caste_tokens,
        20,
        true)
    if not ok_caste then return end

    return creature.creature_id, caste_tokens[caste_idx]
end

local function normalize_race_and_caste(race, caste)
    local target_race = race and race:upper()
    local target_caste = caste and caste:upper()

    for _, creature in ipairs(df.global.world.raws.creatures.all) do
        if creature.creature_id:upper() == target_race then
            local resolved_race = creature.creature_id
            local resolved_caste = caste
            if caste then
                for _, caste_def in ipairs(creature.caste) do
                    if caste_def.caste_id:upper() == target_caste then
                        resolved_caste = caste_def.caste_id
                        break
                    end
                end
            end
            return resolved_race, resolved_caste
        end
    end

    return race, caste
end

local function get_location()
    if args.x and args.y and args.z then
        return tonumber(args.x), tonumber(args.y), tonumber(args.z)
    end
    local cursor = guidm.getCursorPos() or qerror('Set the map cursor, or pass -x/-y/-z.')
    return cursor.x, cursor.y, cursor.z
end

local function spawn(race, caste, amount, nick)
    race, caste = normalize_race_and_caste(race, caste)
    local x, y, z = get_location()
    amount = math.max(1, tonumber(amount) or 1)

    local pos = xyz2pos(x, y, z)
    create_unit.createUnit(race, caste, pos, nil, nil, nil, nil, nil, nil, nil, nick, nil, amount, nil, nil, nil, nil, nil, nil)

    print(('Spawned %d %s:%s at %d %d %d'):format(amount, race, caste, x, y, z))
end

if args.help then
    print(dfhack.script_help())
    return
end

if args.gui or not args.race or not args.caste then
    script.start(function()
        local race = args.race
        local caste = args.caste

        if not race or not caste then
            race, caste = choose_creature_and_caste()
            if not race or not caste then return end
        end

        local amount = args.amount
        if not amount then
            local ok_amount, amount_str = script.showInputPrompt(
                'spawn-unit',
                'How many units should be created?',
                COLOR_WHITE,
                '1')
            if not ok_amount then return end
            amount = amount_str
        end

        local nick = args.nick
        if not nick then
            local ok_nick, nick_str = script.showInputPrompt(
                'spawn-unit',
                'Optional nickname (leave blank for none):',
                COLOR_WHITE,
                '')
            if not ok_nick then return end
            nick = nick_str
        end

        spawn(race, caste, amount, nick)
    end)
else
    spawn(args.race, args.caste, args.amount, args.nick)
end
