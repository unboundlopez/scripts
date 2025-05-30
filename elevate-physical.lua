-- Elevate all the physical attributes of a unit

function ElevatePhysicalAttributes(value)
    local unit=dfhack.gui.getSelectedUnit()
    if unit==nil then
        print ("No unit under cursor!  Aborting with extreme prejudice.")
        return
    end
    --print name of dwarf
    print("Adjusting "..dfhack.df2console(dfhack.units.getReadableName(unit)))
    --walk through available attributes, adjust current to max
    if unit.body then
        for k,v in pairs(unit.body.physical_attrs) do
            if value ~= nil then
                print("Adjusting current value for "..tostring(k).." of "..v.value.." to the value of "..value)
                v.value=value
            else
                print("Adjusting current value for "..tostring(k).." of "..v.value.." to max value of "..v.max_value)
                v.value=v.max_value
                --below will reset values back to "normal"
                --v.value=v.max_value/2
            end
        end
    end
end
--script execution starts here
local opt = ...
opt = tonumber(opt) --luacheck: retype

if opt ~= nil then
    if opt >=0 and opt <=5000 then
        ElevatePhysicalAttributes(opt)
    end
    if opt <0 or opt >5000 then
        error('Invalid number!')
    end
end

if opt == nil then
    ElevatePhysicalAttributes()
end
