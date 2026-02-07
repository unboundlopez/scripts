-- Spawn units in fortress mode with a custom prompt-driven interface.
-- Does not use modtools/create-unit.lua.

local dialogs = require('gui.dialogs')
local gui = require('gui')
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

local SpawnRelayScreen = defclass(SpawnRelayScreen, gui.ZScreen)
SpawnRelayScreen.ATTRS {focus_path='spawn-unit/relay'}
function SpawnRelayScreen:onRenderBody() end

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

local function get_creature_raw_and_idx_by_id(creature_id)
    for idx, creature in ipairs(df.global.world.raws.creatures.all) do
        if creature.creature_id == creature_id then
            return creature, idx
        end
    end
    qerror('Invalid race: ' .. tostring(creature_id))
end

local function get_caste_idx_by_id(creature, caste_id)
    for idx, caste in ipairs(creature.caste) do
        if caste.caste_id == caste_id then
            return idx
        end
    end
    qerror(('Invalid caste for %s: %s'):format(creature.creature_id, tostring(caste_id)))
end

local function set_unit_nickname(unit, nick)
    if nick and nick ~= '' then
        dfhack.units.setNickname(unit, nick)
    end
end

local function set_unit_domesticated(unit)
    unit.flags1.tame = true
end

local function init_arena_creature_lists()
    local arena = df.global.world.arena
    local arena_unit = df.global.game.main_interface.arena_unit

    arena.race:resize(0)
    arena.caste:resize(0)
    arena.creature_cnt:resize(0)
    arena.last_race = -1
    arena.last_caste = -1

    arena_unit.race = 0
    arena_unit.caste = 0
    arena_unit.races_filtered:resize(0)
    arena_unit.races_all:resize(0)
    arena_unit.castes_filtered:resize(0)
    arena_unit.castes_all:resize(0)
    arena_unit.editing_filter = false

    for race_idx, raw in ipairs(df.global.world.raws.creatures.all) do
        arena.creature_cnt:insert('#', 0)
        for caste_idx in ipairs(raw.caste) do
            arena.race:insert('#', race_idx)
            arena.caste:insert('#', caste_idx)
        end
    end
end

local function get_arena_entry_idx(race_idx, caste_idx)
    local arena = df.global.world.arena
    for idx = 0, #arena.race - 1 do
        if arena.race[idx] == race_idx and arena.caste[idx] == caste_idx then
            return idx
        end
    end
    return nil
end

local function save_state()
    local popups = {}
    for _, popup in pairs(df.global.world.status.popups) do
        table.insert(popups, popup)
    end
    return {
        gamemode=df.global.gamemode,
        gametype=df.global.gametype,
        mode=df.global.plotinfo.main.mode,
        cursor=copyall(df.global.cursor),
        view={x=df.global.window_x, y=df.global.window_y, z=df.global.window_z},
        popups=popups,
    }
end

local function restore_state(state)
    df.global.window_x = state.view.x
    df.global.window_y = state.view.y
    df.global.window_z = state.view.z
    df.global.cursor:assign(state.cursor)
    df.global.gamemode = state.gamemode
    df.global.gametype = state.gametype
    df.global.plotinfo.main.mode = state.mode
    df.global.world.status.popups:resize(0)
    for _, popup in ipairs(state.popups) do
        df.global.world.status.popups:insert('#', popup)
    end
end

local function spawn_one(relay, entry_idx, race_idx, caste_idx, pos)
    local mi = df.global.game.main_interface
    local arena = df.global.world.arena

    df.global.cursor.x = pos.x
    df.global.cursor.y = pos.y
    df.global.cursor.z = pos.z

    arena.last_race = race_idx
    arena.last_caste = caste_idx
    mi.arena_unit.race = entry_idx
    mi.arena_unit.caste = 0
    mi.arena_unit.open = false
    mi.bottom_mode_selected = -1

    local before = df.global.unit_next_id

    relay:sendInputToParent{ARENA_CREATE_CREATURE=true}

    if not mi.arena_unit.open and mi.bottom_mode_selected == -1 then
        return nil, 'arena spawn panel did not open'
    end

    relay:sendInputToParent{SELECT=true}

    if df.global.unit_next_id <= before then
        -- fallback key route
        local scr = dfhack.gui.getDFViewscreen(true)
        pcall(function() gui.simulateInput(scr, 'SELECT') end)
    end

    if mi.arena_unit.open then
        relay:sendInputToParent{LEAVESCREEN=true}
    end

    if df.global.unit_next_id <= before then
        return nil, 'unit_next_id did not increase after SELECT'
    end

    return df.unit.find(df.global.unit_next_id - 1), nil
end

local function do_spawn(opts)
    require_fortress_mode()
    local pos = get_cursor_pos()
    local count = parse_positive_int('count', opts.count or 1)

    local creature, race_idx = get_creature_raw_and_idx_by_id(opts.race)
    local caste_idx = get_caste_idx_by_id(creature, opts.caste)

    local state = save_state()
    local relay = SpawnRelayScreen{}:show()

    local ok, err = pcall(function()
        df.global.world.status.popups:resize(0)
        df.global.gamemode = df.game_mode.DWARF
        df.global.gametype = df.game_type.DWARF_ARENA
        df.global.plotinfo.main.mode = df.ui_sidebar_mode.LookAround

        init_arena_creature_lists()
        local entry_idx = get_arena_entry_idx(race_idx, caste_idx)
        if not entry_idx then
            error('Could not map race/caste to arena entry index')
        end

        local failed = 0
        local first_error
        local created = {}

        for _ = 1, count do
            local unit, unit_err = spawn_one(relay, entry_idx, race_idx, caste_idx, pos)
            if not unit then
                failed = failed + 1
                first_error = first_error or unit_err
            else
                if opts.domesticate then set_unit_domesticated(unit) end
                set_unit_nickname(unit, opts.nick)
                table.insert(created, unit)
            end
        end

        if failed > 0 then
            error(('Spawn failed for %d unit(s): %s'):format(failed, tostring(first_error)))
        end

        print(string.format('Spawned %d %s/%s unit(s) at (%d, %d, %d).',
            #created, opts.race, opts.caste, pos.x, pos.y, pos.z))
    end)

    relay:dismiss()
    restore_state(state)

    if not ok then
        qerror(table.concat({
            ('Spawn failed for %s/%s at (%d, %d, %d).'):format(opts.race, opts.caste, pos.x, pos.y, pos.z),
            tostring(err),
            'This script does not use modtools/create-unit.lua.'
        }, '\n'))
    end
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
