-------------------------------------------------------------------------------------------------------------------------------
--- @section Mock Script Units
--- @desc Mock script units don't have unit controllers, but have all the other
--        functionality of a script_unit
--        plus a few bookkeeping variables
--
--        Note: I'm not certain that it's necessary to mock script_units like this; I originally
--              created to avoid an error I was getting from trying to create multiple unit controllers
--              for multiplayer gifted Bretonnians in lance formation
-------------------------------------------------------------------------------------------------------------------------------

local bm = get_bm();

local function need_function(f)
    return not f or not is_function(f);
end;

if need_function(pancake_create_mock_script_unit) then

    --a slimmed down version of script_unit:new() (from lib_battle_script_unit)
    --it should mimic a script unit except that a mock_su won't have a unit controller
    function pancake_create_mock_script_unit(new_army, new_ref)
        local new_unit = new_army:units():item(new_ref);
        local unit_found = true;
            
        -- set up the script unit
        local mock_su = {
            bm = bm, --pancake edited value
            name = "",
            alliance = nil,
            alliance_num = -1,
            army = new_army, --pancake edited value
            army_num = -1,
            unit = nil,
            uc = nil,
            enemy_alliance_num = -1,
            start_position = nil,
            start_bearing = nil,
            start_width = nil,
            uic_ping_marker = false,
            has_pancake_toggle_mark = false, --pancake added code
        };
        setmetatable(mock_su, script_unit); --give this mock_su all the methods of script_unit
                                            --note: you should never directly or indirectly call a method that requires a unit controller,
                                            --since this mock_su won't have a unit controller
        
        script_unit.__index = script_unit;
        script_unit.__tostring = function() return TYPE_SCRIPT_UNIT end;
            
        -- work out which alliance and army this unit is in
        local alliances = bm:alliances();
        
        for i = 1, alliances:count() do
            local armies = alliances:item(i):armies();
            
            for j = 1, armies:count() do
                if contains_unit(armies:item(j), new_unit) then
                    mock_su.alliance = alliances:item(i);
                    mock_su.alliance_num = i;
                    mock_su.army_num = j;
                    break;
                end;
            end;
        end;
        
        mock_su.name = tostring(mock_su.alliance_num) .. ":" .. tostring(mock_su.army_num) .. ":" .. tostring(new_ref);
        
        if mock_su.alliance_num == 2 then
            mock_su.enemy_alliance_num = 1;
        else
            mock_su.enemy_alliance_num = 2;
        end;
        
        mock_su.unit = new_unit;
        --mock_su.uc = create_unitcontroller(new_army, new_unit); --removed to avoid errors from having multiple unit controllers
                
        mock_su.start_position = new_unit:ordered_position();
        mock_su.start_bearing = new_unit:bearing();
        mock_su.start_width = new_unit:ordered_width();
        
        return mock_su;
    end;
end;