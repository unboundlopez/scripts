--@module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local function to_search_text(text)
    return dfhack.toSearchNormalized((text or ''):lower())
end

local function safe_get(obj, key)
    local ok, val = pcall(function() return obj and obj[key] end)
    return ok and val or nil
end

local function set_first_existing_field(obj, fields, value)
    for _, field in ipairs(fields) do
        local ok = pcall(function() obj[field] = value end)
        if ok then return true end
    end
    return false
end

local function get_selected_index(vs)
    for _, field in ipairs{'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'} do
        local val = safe_get(vs, field)
        if type(val) == 'number' then
            return field, val
        end
    end
end

local function get_entries()
    local out = {}

    -- Steam DFHack source of truth: worldgen parameter labels are taken from worldgen_parms
    -- and are what users see in advanced worldgen tuning.
    local worldgen = safe_get(df.global.world, 'worldgen')
    local parms = safe_get(worldgen, 'worldgen_parms')
    if not parms then return out end

    for idx, parm in ipairs(parms) do
        local name = safe_get(parm, 'name')
        if name and #name > 0 then
            table.insert(out, {
                text=name,
                search_key=to_search_text(name),
                data={idx=idx-1}, -- C++ vectors are generally 0-indexed in UI state fields
            })
        end
    end

    return out
end

WorldGenDetailedModeSearchEngineOverlay = defclass(WorldGenDetailedModeSearchEngineOverlay, overlay.OverlayWidget)
WorldGenDetailedModeSearchEngineOverlay.ATTRS {
    desc='Adds an Alt+S search box for filtering advanced worldgen parameter names.',
    default_enabled=true,
    default_pos={x=2, y=2},
    frame={w=52, h=14},
    frame_style=gui.MEDIUM_FRAME,
    viewscreens='new_region/Advanced',
}

function WorldGenDetailedModeSearchEngineOverlay:init()
    self.entries = get_entries()

    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text='Detailed mode search',
            text_pen=COLOR_CYAN,
        },
        widgets.EditField{
            view_id='search',
            frame={t=1, l=0, r=0},
            key='CUSTOM_ALT_S',
            label_text='Search: ',
            on_change=self:callback('on_search_changed'),
        },
        widgets.FilteredList{
            view_id='list',
            frame={t=3, l=0, r=0, b=0},
            not_found_label='No matching worldgen parameters',
            on_submit=self:callback('jump_to_selected'),
            choices=self.entries,
        },
    }
end

function WorldGenDetailedModeSearchEngineOverlay:on_search_changed(text)
    self.subviews.list:setFilter(text)
end

function WorldGenDetailedModeSearchEngineOverlay:jump_to_selected(_, choice)
    if not choice then return end

    local vs = dfhack.gui.getViewscreenByType(df.viewscreen_new_regionst, 0)
    if not vs then return end

    local _, current_idx = get_selected_index(vs)
    local target_idx = choice.data.idx

    -- Try direct assignment first.
    if set_first_existing_field(vs,
            {'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'},
            target_idx) then
        return
    end

    -- Fallback: nudge via the common delta field if present.
    if type(current_idx) == 'number' then
        local delta = target_idx - current_idx
        set_first_existing_field(vs, {'scroll_delta', 'scroll_step'}, delta)
    end
end

OVERLAY_WIDGETS = {
    world_gen_detailed_mode_search_engine=WorldGenDetailedModeSearchEngineOverlay,
}

if dfhack_flags.module then
    return
end

print('world-gen-detailed-mode-search-engine loaded. Open new_region/Advanced and press Alt+S to focus search.')
