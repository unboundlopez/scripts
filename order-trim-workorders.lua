-- Trim and save work orders stored in JSON files.
--
--[====[

order-trim-workorders
=====================
Run an interactive UI to select a work order JSON file, filter the
orders it contains, and remove selected entries. You can save changes
back to the original file or use "Save As" to write to a new file.

The script expects files under dfhack-config/orders/.

Usage:
    order-trim-workorders

]====]

local gui = require('gui')
local dialogs = require('gui.dialogs')
local json = require('json')
local utils = require('utils')
local widgets = require('gui.widgets')

local BASE_DIR = 'dfhack-config/orders'

local function get_base_dir()
    return dfhack.getDFPath() .. '/' .. BASE_DIR
end

local function resolve_enum(enum, value)
    if value == nil then
        return nil
    end
    if type(value) == 'number' then
        return enum[value] or tostring(value)
    end
    if type(value) == 'string' then
        local num = tonumber(value)
        if num and enum[num] then
            return enum[num]
        end
        if enum[value] then
            return value
        end
        return value
    end
    return tostring(value)
end

local function format_amount(amount)
    if amount == nil then
        return 'amount=?'
    end
    if amount == 0 then
        return 'amount=∞'
    end
    return 'amount=' .. tostring(amount)
end

local function describe_order(order)
    local job = resolve_enum(df.job_type, order.job or order.job_type) or 'unknown job'
    local amount = format_amount(order.amount_total or order.amount)
    local details = {}

    if order.item_type ~= nil then
        local item = resolve_enum(df.item_type, order.item_type)
        if order.item_subtype ~= nil then
            item = string.format('%s/%s', item or tostring(order.item_type), tostring(order.item_subtype))
        end
        table.insert(details, 'item=' .. tostring(item))
    end

    if order.reaction_name and order.reaction_name ~= '' then
        table.insert(details, 'reaction=' .. order.reaction_name)
    end

    if order.mat_type ~= nil or order.mat_index ~= nil then
        table.insert(details, string.format('mat=%s:%s', tostring(order.mat_type), tostring(order.mat_index)))
    end

    if order.frequency then
        table.insert(details, 'freq=' .. tostring(order.frequency))
    end

    if order.order_conditions then
        table.insert(details, 'conditions=' .. tostring(#order.order_conditions))
    end

    return job, amount, table.concat(details, ', ')
end


local function sanitize_json_text(text)
    text = text:gsub('^\239\187\191', '')
    local lines = {}
    for line in text:gmatch('[^\r\n]+') do
        local trimmed = line:match('^%s*(.*)') or ''
        if not trimmed:match('^//') and not trimmed:match('^#') then
            table.insert(lines, line)
        end
    end
    text = table.concat(lines, '\n')
    text = text:gsub(',%s*([}%]])', '%1')
    return text
end

local function make_temp_path(original_path)
    local dir = original_path:match('(.+)/[^/]+$') or '.'
    local base = original_path:match('([^/]+)$') or 'workorders.json'
    base = base:gsub('%.[^%.]+$', '')
    return dir .. '/' .. base .. '.txt'
end

local function resolve_path(original_path)
    if original_path:match('^%a:[\\/]') or original_path:startswith('/') then
        return original_path
    end
    return dfhack.getDFPath() .. '/' .. original_path
end

local function write_temp_copy(original_path)
    local resolved_path = resolve_path(original_path)
    local file = io.open(resolved_path, 'rb')
    if not file then
        return nil, 'Could not open file.'
    end
    local content = file:read('*a')
    file:close()

    local temp_path = make_temp_path(resolved_path)
    local temp = io.open(temp_path, 'wb')
    if not temp then
        return nil, 'Could not create temp file.'
    end
    temp:write(content)
    temp:close()

    return temp_path
end

local function delete_temp_file(path)
    if path and dfhack.filesystem.exists(path) then
        dfhack.filesystem.remove(path)
    end
end

local function load_json(path)
    local temp_path, err = write_temp_copy(path)
    if not temp_path then
        return false, err
    end

    local file = io.open(temp_path, 'rb')
    if not file then
        delete_temp_file(temp_path)
        return false, 'Could not open temp file.'
    end
    local content = file:read('*a')
    file:close()

    content = sanitize_json_text(content or '')
    local ok2, data2 = pcall(json.decode, content)
    if ok2 then
        return true, data2, temp_path
    end

    delete_temp_file(temp_path)
    return false, data2
end

local function list_json_files()
    local root = get_base_dir()
    if not dfhack.filesystem.isdir(root) then
        return {}
    end

    local entries = dfhack.filesystem.listdir_recursive(root, nil, false) or {}
    local files = {}
    for _, entry in ipairs(entries) do
        if not entry.isdir then
            local lower = string.lower(entry.path)
            if lower:match('%.json$') then
                local rel = entry.path
                if rel:startswith(root .. '/') then
                    rel = rel:sub(#root + 2)
                elseif rel:startswith(root) then
                    rel = rel:sub(#root + 1)
                end
                table.insert(files, {
                    text = rel,
                    rel = rel,
                    path = entry.path,
                    search_key = rel:lower(),
                })
            end
        end
    end

    table.sort(files, function(a, b) return a.rel < b.rel end)
    return files
end

local function sanitize_relative_path(name)
    local normalized = utils.normalizePath(name):gsub('^/+', '')
    if normalized == '' then
        return nil, 'File name cannot be empty.'
    end
    if normalized:find('..', 1, true) then
        return nil, 'File name cannot contain "..".'
    end
    return normalized
end

OrderTrimScreen = defclass(OrderTrimScreen, gui.FramedScreen)
OrderTrimScreen.ATTRS{
    frame_title = 'Select Work Order JSON',
    focus_path = 'order-trim-workorders',
}

function OrderTrimScreen:init()
    self.files = {}
    self.data = nil
    self.orders = {}
    self.marked = {}
    self.current_file = nil
    self.current_path = nil
    self.temp_path = nil
    self.using_temp = false

    local select_panel = widgets.Panel{
        view_id = 'select_panel',
        frame = {t = 0, l = 0, b = 2},
        subviews = {
            widgets.FilteredList{
                view_id = 'file_list',
                frame = {t = 0, l = 0, b = 2},
                edit_key = 'CUSTOM_F',
                on_submit = self:callback('onFileSelected'),
            },
            widgets.Label{
                frame = {b = 0, l = 0},
                text = {
                    {key = 'CUSTOM_F', text = ': Filter, '},
                    {key = 'SELECT', text = ': Load, '},
                    {key = 'LEAVESCREEN', text = ': Exit'},
                },
            },
        },
    }

    local orders_panel = widgets.Panel{
        view_id = 'orders_panel',
        frame = {t = 0, l = 0, b = 4},
        subviews = {
            widgets.Label{
                view_id = 'file_label',
                frame = {t = 0, l = 0},
                text_to_wrap = self:callback('getFileLabel'),
            },
            widgets.FilteredList{
                view_id = 'order_list',
                frame = {t = 2, l = 0, b = 2},
                row_height = 2,
                edit_key = 'CUSTOM_F',
                on_submit = self:callback('toggleMarked'),
            },
            widgets.Label{
                frame = {b = 0, l = 0},
                text = {
                    {key = 'CUSTOM_F', text = ': Filter, '},
                    {key = 'CUSTOM_X', text = ': Clear filter, '},
                    {key = 'SELECT', text = ': Toggle mark, '},
                    NEWLINE,
                    {key = 'CUSTOM_D', text = ': Delete marked, '},
                    {key = 'CUSTOM_S', text = ': Save, '},
                    {key = 'CUSTOM_A', text = ': Save As, '},
                    {key = 'LEAVESCREEN', text = ': Back'},
                },
            },
        },
    }

    self:addviews{
        widgets.Pages{
            view_id = 'pages',
            subviews = {
                select_panel,
                orders_panel,
            },
        },
    }

    self:refresh_file_list()
    self.subviews.pages:setSelected('select_panel')
end

function OrderTrimScreen:getFileLabel()
    if not self.current_file then
        return 'No file loaded.'
    end
    return 'Editing: ' .. self.current_file
end

function OrderTrimScreen:refresh_file_list()
    self.files = list_json_files()
    self.subviews.file_list:setChoices(self.files)
end

function OrderTrimScreen:resolve_orders(data)
    if type(data) ~= 'table' then
        return nil
    end
    if type(data.orders) == 'table' then
        return data.orders
    end
    return data
end

function OrderTrimScreen:make_order_choices()
    local choices = {}
    for i, order in ipairs(self.orders) do
        local job, amount, detail = describe_order(order)
        local marked = self.marked[i]
        local prefix = marked and '[x]' or '[ ]'
        local line = string.format('%s %s (%s)', prefix, job, amount)
        local text
        if detail ~= '' then
            text = {line, NEWLINE, '  ' .. detail}
        else
            text = line
        end
        table.insert(choices, {
            text = text,
            order_index = i,
            search_key = string.lower(string.format('%s %s %s', job, amount, detail or '')),
        })
    end
    return choices
end

function OrderTrimScreen:refresh_order_list()
    local list = self.subviews.order_list
    local filter = list:getFilter()
    local selected = list:getSelected()
    list:setChoices(self:make_order_choices())
    if filter and filter ~= '' then
        list:setFilter(filter, selected)
    end
end

function OrderTrimScreen:onFileSelected(_, choice)
    if not choice then
        return
    end

    local ok, data, temp_path = load_json(choice.path)
    if not ok then
        dialogs.showMessage('Failed to load JSON', tostring(data), COLOR_LIGHTRED)
        return
    end
    if type(data) ~= 'table' then
        dialogs.showMessage('Invalid JSON', 'Expected an array of work orders.', COLOR_LIGHTRED)
        return
    end

    local orders = self:resolve_orders(data)
    if not orders then
        dialogs.showMessage('Invalid JSON', 'No work orders found in the file.', COLOR_LIGHTRED)
        return
    end

    self.data = data
    self.orders = orders
    self.marked = {}
    self.current_file = choice.rel
    self.current_path = choice.path
    self.temp_path = temp_path
    self.using_temp = temp_path ~= nil
    self.frame_title = 'Trim Work Orders'

    self:refresh_order_list()
    self.subviews.pages:setSelected('orders_panel')
end

function OrderTrimScreen:toggleMarked(_, choice)
    if not choice then
        return
    end
    local index = choice.order_index
    if not index then
        return
    end
    self.marked[index] = not self.marked[index]
    self:refresh_order_list()
end

function OrderTrimScreen:clearOrderFilter()
    local list = self.subviews.order_list
    list:setFilter('')
end

function OrderTrimScreen:discardTempFile()
    if self.using_temp then
        delete_temp_file(self.temp_path)
        self.temp_path = nil
        self.using_temp = false
    end
end

function OrderTrimScreen:deleteMarked()
    local indices = {}
    for index, marked in pairs(self.marked) do
        if marked then
            table.insert(indices, index)
        end
    end

    if #indices == 0 then
        dialogs.showMessage('Nothing selected', 'No orders are marked for deletion.', COLOR_YELLOW)
        return
    end

    dialogs.showYesNoPrompt(
        'Delete marked orders',
        string.format('Delete %d marked work orders?', #indices),
        COLOR_YELLOW,
        function()
            table.sort(indices, function(a, b) return a > b end)
            for _, index in ipairs(indices) do
                table.remove(self.orders, index)
            end
            self.marked = {}
            self:refresh_order_list()
        end
    )
end

function OrderTrimScreen:saveFile(path)
    local ok, err = pcall(json.encode_file, self.data, path, {pretty = true})
    if not ok then
        dialogs.showMessage('Save failed', tostring(err), COLOR_LIGHTRED)
        return false
    end
    return true
end

function OrderTrimScreen:saveCurrent()
    if not self.current_path then
        dialogs.showMessage('No file loaded', 'Select a JSON file first.', COLOR_YELLOW)
        return
    end
    if self:saveFile(self.current_path) then
        if self.using_temp then
            delete_temp_file(self.temp_path)
            self.temp_path = nil
            self.using_temp = false
        end
        dialogs.showMessage('Saved', 'Work orders saved to ' .. self.current_file .. '.', COLOR_GREEN)
    end
end

function OrderTrimScreen:saveAs()
    dialogs.showInputPrompt(
        'Save As',
        'Enter a JSON filename under ' .. BASE_DIR,
        COLOR_WHITE,
        self.current_file or 'workorders.json',
        function(name)
            local relative, err = sanitize_relative_path(name)
            if not relative then
                dialogs.showMessage('Invalid name', err, COLOR_LIGHTRED)
                return
            end
            if not relative:lower():match('%.json$') then
                relative = relative .. '.json'
            end

            local base_dir = get_base_dir()
            if not dfhack.filesystem.isdir(base_dir) then
                dfhack.filesystem.mkdir_recursive(base_dir)
            end

            local full_path = base_dir .. '/' .. relative
            local dir = full_path:match('(.+)/[^/]+$')
            if dir and not dfhack.filesystem.isdir(dir) then
                dfhack.filesystem.mkdir_recursive(dir)
            end

            if self:saveFile(full_path) then
                if self.using_temp then
                    delete_temp_file(self.temp_path)
                    self.temp_path = nil
                    self.using_temp = false
                end
                self.current_file = relative
                self.current_path = full_path
                self.frame_title = 'Trim Work Orders'
                dialogs.showMessage('Saved', 'Work orders saved to ' .. relative .. '.', COLOR_GREEN)
                self:refresh_file_list()
            end
        end
    )
end

function OrderTrimScreen:onInput(keys)
    if keys.CUSTOM_D then
        if self.subviews.pages:getSelected() == 'orders_panel' then
            self:deleteMarked()
            return true
        end
    elseif keys.CUSTOM_S then
        if self.subviews.pages:getSelected() == 'orders_panel' then
            self:saveCurrent()
            return true
        end
    elseif keys.CUSTOM_A then
        if self.subviews.pages:getSelected() == 'orders_panel' then
            self:saveAs()
            return true
        end
    elseif keys.CUSTOM_X then
        if self.subviews.pages:getSelected() == 'orders_panel' then
            self:clearOrderFilter()
            return true
        end
    elseif keys.LEAVESCREEN or keys._MOUSE_R then
        if self.subviews.pages:getSelected() == 'orders_panel' then
            if self.using_temp then
                dialogs.showYesNoPrompt(
                    'Save changes?',
                    'Save changes back to the JSON file?\nIf you select No, the temporary file will be deleted.',
                    COLOR_YELLOW,
                    function()
                        self:saveCurrent()
                        self.subviews.pages:setSelected('select_panel')
                        self.frame_title = 'Select Work Order JSON'
                    end,
                    function()
                        self:discardTempFile()
                        self.subviews.pages:setSelected('select_panel')
                        self.frame_title = 'Select Work Order JSON'
                    end
                )
                return true
            end
            self.subviews.pages:setSelected('select_panel')
            self.frame_title = 'Select Work Order JSON'
            return true
        end
        self:dismiss()
        return true
    end

    return OrderTrimScreen.super.onInput(self, keys)
end

OrderTrimScreen{}:show()
