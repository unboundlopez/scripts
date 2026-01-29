-- Get status and location of a historical figure
local function get_status_and_location(hfid)
    local status, location = "(Free)", "Outside Fort"

    for _, p in ipairs(df.global.plotinfo.punishments or {}) do
        if p.prison_counter > 0 then
            local u = df.unit.find(p.criminal)
            if u and u.hist_figure_id == hfid then
                status = "(Convicted)"
                break
            end
        end
    end

    for _, u in ipairs(df.global.world.units.active or {}) do
        if u.hist_figure_id == hfid then
            location = "Inside Fort"
            break
        end
    end

    return status, location
end

-- Print who is working together by group, split by location
local function print_working_together(entries)
    print("\n==========================================")
    print("Working Together")
    print("==========================================\n")

    for group_num, org_entry in pairs(entries) do
        local org_name = org_entry.list_name or "<Unnamed>"
        -- collect members by location
        local members_by_location = {
            ["Outside Fort"] = {},
            ["Inside Fort"]  = {},
        }

        for _, node in ipairs(org_entry.node or {}) do
            local hf = node.actor_entry and node.actor_entry.hf
            if hf then
                -- get status and location
                local status, location = get_status_and_location(hf.id)
                -- translate name
                local raw = dfhack.translation.translateName(hf.name, false)
                local trl = dfhack.translation.translateName(hf.name, true)
                local first = raw:match("^(%S+)")
                local raw_last = raw:match(" ([^ ]+)$") or "<unknown>"
                local trl_last = trl:match(" ([^ ]+)$") or "<unknown>"
                -- update profession on the unit
                for _, u in ipairs(df.global.world.units.active) do
                    if u.hist_figure_id == hf.id then
                        u.custom_profession = string.format(
                            "Justice %s %s %s",
                            first, raw_last, trl_last
                        )
                        break
                    end
                end
                -- build display label (name || status)
                local name = string.format("%s %s %s", first, raw_last, trl_last)
                local label = string.format("%s || %s", name, status)
                -- insert under correct heading
                table.insert(members_by_location[location], label)
            end
        end

        -- print the group header
        print(string.format("Group %s || Organization: %s", tostring(group_num), org_name))

        -- Outside Fort block
        print("Outside Fort")
        for _, label in ipairs(members_by_location["Outside Fort"]) do
            print("    - " .. label .. "  ")
        end
        print("")

        -- Inside Fort block
        print("Inside Fort")
        for _, label in ipairs(members_by_location["Inside Fort"]) do
            print("    - " .. label .. "  ")
        end
            print("==========================================")

    end

    print("==========================================")
end

-- Main function
local function printJusticeMenuOffenders()
    print("========== Justice Menu Offenders ==========")
    print("Format: name || status || location\n")
    print("Units custom_profession(nickname) has been updated accordingly to view in gui/sitemap")
    print("Modified names begin with Justice\n")
    print_working_together(df.global.game.main_interface.info.justice.base_organization_entry)
end

-- Execute only if Justice Menu is open
local info = df.global.game.main_interface.info
if info and info.open and info.current_mode == 7 then
    printJusticeMenuOffenders()
else
    print("Please open the Justice Menu before running this script.")
end
