-- Spawn units in fortress mode with a custom prompt-driven interface.
-- Delegates spawning to modtools/create-unit (Steam DFHack source of truth).

local create_unit = reqscript('modtools/create-unit')
local dialogs = require('gui.dialogs')
local guidm = require('gui.dwarfmode')
local utils = require('utils')

local validArgs = utils.invert({
    'race',
    'caste',
    'count',
    'nick',
    'domesticate',
    'help',
})

local function require_fortress_mode()
    if not dfhack.world.isFortressMode() then
        qerror('spawn-unit only works in fortress mode.')
    end
end

local function get_cursor_pos()
    local pos = guidm.getCursorPos()
    if not pos then
        qerror('This script requires an active keyboard cursor in fortress mode.')
    end
    return pos
end

local function parse_positive_int(label, value)
    local num = tonumber(value)
    if not num or num < 1 or math.floor(num) ~= num then
        qerror(string.format('%s must be a positive integer: %s', label, tostring(value)))
    end
    return num
end

local function get_creature_raw_by_id(creature_id)
    for _, creature in ipairs(df.global.world.raws.creatures.all) do
        if creature.creature_id == creature_id then
            return creature
        end
    end
    qerror('Invalid race: ' .. tostring(creature_id))
end

local function validate_race_and_caste(race_id, caste_id)
    local creature = get_creature_raw_by_id(race_id)
    for _, caste in ipairs(creature.caste) do
        if caste.caste_id == caste_id then
            return
        end
    end
    qerror(('Invalid caste for %s: %s'):format(race_id, tostring(caste_id)))
end

local function do_spawn(opts)
    require_fortress_mode()
    local pos = get_cursor_pos()

    local count = parse_positive_int('count', opts.count or 1)
    validate_race_and_caste(opts.race, opts.caste)

    local ok, units_or_err = pcall(function()
        return create_unit.createUnit(
            opts.race,
            opts.caste,
            pos,
            nil,
            nil,
            nil,
            opts.domesticate,
            nil,
            nil,
            nil,
            opts.nick,
            nil,
            count
        )
    end)

    if not ok then
        qerror(table.concat({
            ('Spawn failed for %s/%s at (%d, %d, %d).'):format(
                tostring(opts.race), tostring(opts.caste), pos.x, pos.y, pos.z),
            'Delegated to modtools/create-unit and it returned an error:',
            tostring(units_or_err),
            'If this references arena internals, your local Steam modtools/create-unit may be out of sync.'
        }, '\n'))
    end

    local units = units_or_err or {}
    print(string.format('Spawned %d %s/%s unit(s) at (%d, %d, %d).',
        #units, opts.race, opts.caste, pos.x, pos.y, pos.z))
    return units
end

local function get_creature_choices()
    local choices = {}
    for _, creature in ipairs(df.global.world.raws.creatures.alphabetic) do
        local display_name = creature.name[0] ~= '' and creature.name[0] or creature.creature_id
        table.insert(choices, {
            text=('%s (%s)'):format(creature.creature_id, display_name),
            data=creature,
        })
    end
    return choices
end

local function get_caste_choices(creature)
    local choices = {}
    for _, caste in ipairs(creature.caste) do
        local display_name = caste.caste_name[0]
        if display_name == '' then display_name = caste.caste_id end
        table.insert(choices, {
            text=('%s (%s)'):format(caste.caste_id, display_name),
            data=caste,
        })
    end
    return choices
end

local function run_prompt_flow()
    require_fortress_mode()
    get_cursor_pos()

    dialogs.showListPrompt(
        'spawn-unit',
        'Select creature race:',
        COLOR_LIGHTGREEN,
        get_creature_choices(),
        function(_, creature_choice)
            local creature = creature_choice.data
            dialogs.showListPrompt(
                'spawn-unit',
                'Select caste:',
                COLOR_LIGHTGREEN,
                get_caste_choices(creature),
                function(_, caste_choice)
                    dialogs.showInputPrompt(
                        'spawn-unit',
                        'How many units? (positive integer)',
                        COLOR_LIGHTGREEN,
                        '1',
                        function(count)
                            dialogs.showInputPrompt(
                                'spawn-unit',
                                'Optional nickname (blank for none):',
                                COLOR_LIGHTGREEN,
                                '',
                                function(nick)
                                    do_spawn{
                                        race=creature.creature_id,
                                        caste=caste_choice.data.caste_id,
                                        count=count,
                                        nick=nick,
                                    }
                                end
                            )
                        end
                    )
                end,
                nil,
                nil,
                true
            )
        end,
        nil,
        nil,
        true
    )
end

if dfhack_flags.module then
    return {do_spawn=do_spawn}
end

local args = utils.processArgs({...}, validArgs)
if args.help then
    print(dfhack.script_help())
    return
end

if args.race or args.caste or args.count or args.nick or args.domesticate then
    if not args.race or not args.caste then
        qerror('Both -race and -caste are required when using commandline arguments.')
    end
    do_spawn(args)
else
    run_prompt_flow()
end
