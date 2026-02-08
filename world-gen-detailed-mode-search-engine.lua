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

local function get_container_size(container)
    if not container then return 0 end

    local ok_len, len = pcall(function() return #container end)
    if ok_len and type(len) == 'number' then return len end

    local ok_size = pcall(function() return container.size end)
    if ok_size then
        local ok_call, sz = pcall(function() return container:size() end)
        if ok_call and type(sz) == 'number' then return sz end
    end

    local n = 0
    while true do
        local ok_idx, val = pcall(function() return container[n] end)
        if not ok_idx or val == nil then break end
        n = n + 1
    end
    return n
end

local function get_at(container, idx)
    local ok, val = pcall(function() return container[idx] end)
    if ok then return val end
end

local function clear_container(container)
    if not container then return end

    local ok_resize = pcall(function() return container.resize end)
    if ok_resize and pcall(function() container:resize(0) end) then
        return
    end

    local ok_erase = pcall(function() return container.erase end)
    if ok_erase then
        local sz = get_container_size(container)
        for i = sz - 1, 0, -1 do
            if not pcall(function() container:erase(i) end) then break end
        end
        return
    end

    local sz = get_container_size(container)
    for i = sz, 1, -1 do
        table.remove(container, i)
    end
end

local function append_container(container, value)
    if not container then return end

    local ok_insert = pcall(function() return container.insert end)
    if ok_insert then
        if pcall(function() container:insert('#', value) end) then return end
        local sz = get_container_size(container)
        if pcall(function() container:insert(sz, value) end) then return end
    end

    table.insert(container, value)
end

local function get_entry_name(entry)
    if type(entry) == 'string' then return entry end
    local name = safe_get(entry, 'name')
    if type(name) == 'string' and #name > 0 then return name end
    local caption = safe_get(entry, 'caption')
    if type(caption) == 'string' and #caption > 0 then return caption end
end

local function iter_named_entries(container)
    local out = {}
    local sz = get_container_size(container)
    if sz <= 0 then return out end

    local had_zero = false
    local zero = get_at(container, 0)
    if zero ~= nil then had_zero = true end

    if had_zero then
        for i = 0, sz - 1 do
            local entry = get_at(container, i)
            local name = get_entry_name(entry)
            if name then table.insert(out, {entry=entry, name=name}) end
        end
    else
        for i = 1, sz do
            local entry = get_at(container, i)
            local name = get_entry_name(entry)
            if name then table.insert(out, {entry=entry, name=name}) end
        end
    end

    return out
end

local function get_selected_index(vs)
    for _, field in ipairs{'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'} do
        local val = safe_get(vs, field)
        if type(val) == 'number' then return val end
    end
end

local function set_selected_index(vs, value)
    for _, field in ipairs{'sel_idx', 'sel_detail', 'sel_detail_idx', 'cursor', 'cursor_idx'} do
        if pcall(function() vs[field] = value end) then return true end
    end
    return false
end

local function get_worldgen_names()
    local names = {}
    local worldgen = safe_get(df.global.world, 'worldgen')
    local parms = safe_get(worldgen, 'worldgen_parms')
    if not parms then return names end

    for _, rec in ipairs(iter_named_entries(parms)) do
        names[rec.name] = true
    end
    return names
end

local function discover_target_containers(vs)
    local wg_names = get_worldgen_names()
    local candidates = {}

    for field, value in pairs(vs) do
        local t = type(value)
        if t == 'table' or t == 'userdata' then
            local named = iter_named_entries(value)
            local n = #named
            if n > 0 then
                local overlap = 0
                for _, rec in ipairs(named) do
                    if wg_names[rec.name] then overlap = overlap + 1 end
                end
                if overlap > 0 then
                    local ratio = overlap / n
                    if overlap >= 3 or ratio >= 0.20 then
                        table.insert(candidates, {
                            field=field,
                            container=value,
                            original=named,
                            overlap=overlap,
                            total=n,
                            ratio=ratio,
                        })
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.overlap ~= b.overlap then return a.overlap > b.overlap end
        if a.ratio ~= b.ratio then return a.ratio > b.ratio end
        return a.total > b.total
    end)

    return candidates
end

WorldGenDetailedModeSearchEngineOverlay = defclass(WorldGenDetailedModeSearchEngineOverlay, overlay.OverlayWidget)
WorldGenDetailedModeSearchEngineOverlay.ATTRS {
    desc='Adds an Alt+S filter box that filters advanced worldgen entries.',
    default_enabled=true,
    default_pos={x=2, y=2},
    frame={w=64, h=3},
    frame_style=gui.MEDIUM_FRAME,
    viewscreens='new_region/Advanced',
}

function WorldGenDetailedModeSearchEngineOverlay:init()
    self.updating_filter = false
    self.target_containers = nil
    self.status_text = ''

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
            text={{text=function() return self.status_text end, pen=COLOR_CYAN}},
        },
    }

    self:on_filter_changed('')
end

function WorldGenDetailedModeSearchEngineOverlay:ensure_targets()
    if self.target_containers then return true end

    local vs = dfhack.gui.getViewscreenByType(df.viewscreen_new_regionst, 0)
    if not vs then return false end

    local found = discover_target_containers(vs)
    if #found == 0 then
        self.status_text = 'Could not locate vanilla parameter containers'
        return false
    end

    self.target_containers = found
    self.status_text = ('Hooked %d container(s); best=%s'):format(#found, tostring(found[1].field))
    return true
end

function WorldGenDetailedModeSearchEngineOverlay:get_filtered_entries(original, text)
    if not text or #text == 0 then return original end

    local search = to_search_text(text)
    local out = {}
    for _, rec in ipairs(original) do
        if to_search_text(rec.name):find(search, 1, true) then
            table.insert(out, rec)
        end
    end
    return out
end

function WorldGenDetailedModeSearchEngineOverlay:apply_entries(container, entries)
    clear_container(container)
    for _, rec in ipairs(entries) do
        append_container(container, rec.entry)
    end
end

function WorldGenDetailedModeSearchEngineOverlay:on_filter_changed(text)
    if self.updating_filter then return end
    self.updating_filter = true

    local ok, err = xpcall(function()
        if not self:ensure_targets() then return end

        local vs = dfhack.gui.getViewscreenByType(df.viewscreen_new_regionst, 0)
        if not vs then return end

        local selected = get_selected_index(vs)

        local shown, total = 0, 0
        for _, target in ipairs(self.target_containers) do
            local filtered = self:get_filtered_entries(target.original, text)
            self:apply_entries(target.container, filtered)
            shown = math.max(shown, #filtered)
            total = math.max(total, #target.original)
        end

        self.status_text = ('Showing %d/%d parameters'):format(shown, total)

        if shown == 0 then
            set_selected_index(vs, 0)
        elseif type(selected) == 'number' then
            set_selected_index(vs, math.min(selected, shown-1))
        end
    end, debug.traceback)

    self.updating_filter = false
    if not ok then dfhack.printerr(err) end
end

function WorldGenDetailedModeSearchEngineOverlay:restore_original_entries()
    if not self.target_containers then return end
    for _, target in ipairs(self.target_containers) do
        self:apply_entries(target.container, target.original)
    end
end

function WorldGenDetailedModeSearchEngineOverlay:onDestroy()
    self:restore_original_entries()
end

OVERLAY_WIDGETS = {
    world_gen_detailed_mode_search_engine=WorldGenDetailedModeSearchEngineOverlay,
}

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc ~= SC_VIEWSCREEN_CHANGED then return end
    -- restoration is handled by overlay onDestroy when screen changes
end

if dfhack_flags.module then
    return
end

print('world-gen-detailed-mode-search-engine loaded. Open new_region/Advanced and press Alt+S.')
