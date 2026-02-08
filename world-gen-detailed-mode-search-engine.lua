--@module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local GLOBAL_KEY = 'world-gen-detailed-mode-search-engine'

local function to_search_text(text)
    return dfhack.toSearchNormalized((text or ''):lower())
end

local function safe_get(obj, key)
    local ok, val = pcall(function() return obj and obj[key] end)
    return ok and val or nil
end

local function get_parms_vec()
    local worldgen = safe_get(df.global.world, 'worldgen')
    return safe_get(worldgen, 'worldgen_parms')
end

local function get_selected_index(vs)
    for _, field in ipairs{'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'} do
        local val = safe_get(vs, field)
        if type(val) == 'number' then
            return field, val
        end
    end
end

local function set_selected_index(vs, value)
    for _, field in ipairs{'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'} do
        local ok = pcall(function() vs[field] = value end)
        if ok then return true end
    end
    return false
end

local saved_original_parms = nil

local function ensure_saved_original_parms()
    if saved_original_parms then return true end
    local parms = get_parms_vec()
    if not parms then return false end

    saved_original_parms = {}
    for _, parm in ipairs(parms) do
        table.insert(saved_original_parms, parm)
    end
    return true
end

local function repopulate_parms(list)
    local parms = get_parms_vec()
    if not parms then return end

    parms:resize(0)
    for _, parm in ipairs(list) do
        parms:insert('#', parm)
    end
end

local function restore_original_parms()
    if not saved_original_parms then return end
    repopulate_parms(saved_original_parms)
end

local function get_filtered_parms(filter)
    if not ensure_saved_original_parms() then return {} end
    if not filter or #filter == 0 then
        return saved_original_parms
    end

    local out = {}
    local search = to_search_text(filter)
    for _, parm in ipairs(saved_original_parms) do
        local name = safe_get(parm, 'name') or ''
        if to_search_text(name):find(search, 1, true) then
            table.insert(out, parm)
        end
    end
    return out
end

WorldGenDetailedModeSearchEngineOverlay = defclass(WorldGenDetailedModeSearchEngineOverlay, overlay.OverlayWidget)
WorldGenDetailedModeSearchEngineOverlay.ATTRS {
    desc='Adds an Alt+S filter box that filters the native advanced worldgen parameter list.',
    default_enabled=true,
    default_pos={x=2, y=2},
    frame={w=56, h=3},
    frame_style=gui.MEDIUM_FRAME,
    viewscreens='new_region/Advanced',
}

function WorldGenDetailedModeSearchEngineOverlay:init()
    self:addviews{
        widgets.EditField{
            view_id='search',
            frame={t=0, l=0, r=0},
            key='CUSTOM_ALT_S',
            label_text='Filter vanilla list: ',
            on_change=self:callback('on_filter_changed'),
        },
        widgets.Label{
            view_id='status',
            frame={t=1, l=0, r=0},
            text={{text=function() return self.status_text or '' end, pen=COLOR_CYAN}},
        },
    }

    self:on_filter_changed('')
end

function WorldGenDetailedModeSearchEngineOverlay:on_filter_changed(text)
    local vs = dfhack.gui.getViewscreenByType(df.viewscreen_new_regionst, 0)
    if not vs then return end

    local _, selected = get_selected_index(vs)
    local filtered = get_filtered_parms(text)
    repopulate_parms(filtered)

    local count = #filtered
    local total = saved_original_parms and #saved_original_parms or count
    self.status_text = ('Showing %d/%d parameters'):format(count, total)

    if count == 0 then
        set_selected_index(vs, 0)
    elseif type(selected) == 'number' then
        set_selected_index(vs, math.min(selected, count-1))
    end
end

function WorldGenDetailedModeSearchEngineOverlay:onDestroy()
    restore_original_parms()
end

OVERLAY_WIDGETS = {
    world_gen_detailed_mode_search_engine=WorldGenDetailedModeSearchEngineOverlay,
}

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc ~= SC_VIEWSCREEN_CHANGED then return end
    local focus = dfhack.gui.getCurFocus(true) or ''
    if not tostring(focus):find('^new_region/Advanced') then
        restore_original_parms()
    end
end

if dfhack_flags.module then
    return
end

print('world-gen-detailed-mode-search-engine loaded. Open new_region/Advanced and press Alt+S.')
