-- Script author: Andrew Draper (paperpancake/paperpancake5)

local function pancake_out(msg)
    out("&&& paperpancake's Find Idle Units mod: "..msg);
end;

local bm = get_bm();

local pancake_is_multiplayer = false;

local is_marking_idle_units = false;
local idle_cache_has_entry = true;
local is_deployed = false;
local is_battle_complete = false;

local pancake_advisor_open = false;
local need_to_sync_highlights = false;

--In this script file, a "unit_key" is very important as a unique identifier for a unit
--unit_keys are used as an index for idle_flags and idle_mock_sus, among other things
--Currently, I'm using a unit's unique_ui_id as the unit_key, but I recommend doing
--CTRL+F for "local unit_key = " to see what property of a unit is used in case I forget to update this comment

local last_selected_idle = nil; --this stores the unit_key, not the unit or the su, of the last selected using this mod's hotkey

--idle_flags and idle_mock_sus are parallel arrays, indexed by unit_keys
--These tables may have entries for units no longer in the army's unit list (that's ok)
--for example: a unit is idle at some point in a battle, and then that unit withdraws from the battle
local idle_flags = {};
local idle_mock_sus = {}; --As an abbreviation for script_unit, I prefer su over sunit here because sunit and unit look similar in this code

local function pancake_show_ui_toggle(advice_str)
    effect.advice(advice_str);
    pancake_advisor_open = true;
    
    if not pancake_advisor_open then
        core:add_listener(
            "pancake_advice_listener",
            "ComponentLClickUp", 
            function(context) return context.string == __advisor_progress_button_name end,
            function(context) pancake_advisor_open = false; end, 
            false --listener should not persist after being triggered
        );
    end;

    
    local pancake_advisor_dismiss = function()
        if pancake_advisor_open then
            bm:close_advisor();
        end;
    end;
    
    bm:remove_process("pancake_advisor_dismiss");
    bm:callback(pancake_advisor_dismiss, 1700, "pancake_advisor_dismiss");
end;

local function pancake_fill_table(given_list, fill_value)
    for key in next, given_list do rawset(given_list, key, fill_value) end;
end;

local function pancake_esc_menu_is_visible()
    local retval = false;
    local uic_esc_menu = find_uicomponent(core:get_ui_root(), "panel_manager", "esc_menu_battle");
    if uic_esc_menu then
        if uic_esc_menu:Visible() then
            retval = true;
        end;
    end;
    
    return retval;
end;

--a slimmed down version of script_unit:new() (from lib_battle_script_unit)
--it should mimic a script unit except that a mock_su won't have a unit controller
--I'm not certain that it's necessary to mock script_units like this; I originally
--created to avoid an error I was getting from trying to create multiple unit controllers for multiplayer gifted Bretonnians in lance formation
local function pancake_create_mock_su(new_army, new_ref, pancake_unit_key) --pancake added parameter
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
        pancake_unit_key = nil --pancake added value. This is used by my code if I'm worried a reference might have become stale
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
    
    mock_su.pancake_unit_key = pancake_unit_key; --pancake added code
	
	return mock_su;
end;

-- modified from lib_battle_script_unit's highlight_unit_card
-- I'm also using this to filter for units that are under your control in multiplayer battles with gifted units
-- This is also one way that I'm checking to see if a unit is still alive (if it's dead, references we have to it might be stale)
local function pancake_find_unit_card(unit_key)
	local uim = bm:get_battle_ui_manager();
	
    -- TODO (low priority): I'm hoping this next check will help avoid conflicts with tutorials, but it
    -- deals with highlighting, not camera movement
    -- perhaps instead query battle_manager's enable_camera_movement(), but how to query instead of setting a value?
	if not uim:get_help_page_link_highlighting_permitted() then
		return;
	end;

	local uic_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY");
	local unique_ui_id = tostring(unit_key);
	
	if uic_parent then
		for i = 0, uic_parent:ChildCount() - 1 do
			local uic_card = uic_parent:Find(i);
			if uic_card then
                uic_card = UIComponent(uic_card);
                if uic_card:Id() == unique_ui_id then
                    return uic_card;
                end;
            end;
		end;
	end;
    
    return nil;
end;

--if no unit_key is provided, this will use mock_su.pancake_unit_key
local function pancake_safely_remove_pancake_pings(mock_su, unit_key)
    if not is_battle_complete then
        if mock_su then
            if mock_su.uic_ping_marker and is_uicomponent(mock_su.uic_ping_marker) then

                if not unit_key then
                    unit_key = mock_su.pancake_unit_key;
                end;

                if unit_key then
                    --IMPORTANT: You need some way to tell if the uic_ping_marker is broken or stale
                    --           That can happen when a summoned unit dies, for example
                    --           Right now, seeing if the unit has a unit card seems to work for this.
                    if pancake_find_unit_card(unit_key) then
                        mock_su:remove_ping_icon();
                    end;
                else
                    pancake_out("Warning: pancake_safely_remove_pancake_pings was called, but no unit_key or cached unit_key could be found.");
                end;
            end;
        else
            pancake_out("Warning: pancake_safely_remove_pancake_pings was called, but no mock_su was provided.");
        end;
    end;
end;

--this relies on the idles cache from pancake_cache_idles()
local function pancake_mark_idles_now()
    local sync_highlights_now = need_to_sync_highlights;
    need_to_sync_highlights = false;
    
    for unit_key, is_idle in next, idle_flags do
        local current_mock_su = idle_mock_sus[unit_key];
        if current_mock_su then
            if pancake_find_unit_card(unit_key) then
                if is_idle then
                    if not current_mock_su.uic_ping_marker then
                        --TODO: if future config options opt out of pings, find another way to tell if the unit card is highlighted
                        current_mock_su:highlight_unit_card(true);
                        current_mock_su:add_ping_icon();
                        if not sync_highlights_now then
                            need_to_sync_highlights = true;
                        end;
                    elseif sync_highlights_now then
                        current_mock_su:highlight_unit_card(true);
                    end;
                else
                    current_mock_su:highlight_unit_card(false);
                    pancake_safely_remove_pancake_pings(current_mock_su, unit_key);
                end;
            end;
        end;
    end;
end;

--clears all idle marks except any that are from an idle hotkey ping
local function pancake_clear_idle_marks()
    for unit_key, is_idle in next, idle_flags do
        local current_mock_su = idle_mock_sus[unit_key];
        if current_mock_su then
            if pancake_find_unit_card(unit_key) then
                current_mock_su:highlight_unit_card(false); --this also handles the case where the unit no longer has a unit card
                pancake_safely_remove_pancake_pings(current_mock_su, unit_key);
            end;
        end;
    end;
end;

--this should only cache idle units for the indicated army if those units are controlled by the local player
local function pancake_cache_idles_for_army(army_to_cache)
    local army_units = army_to_cache:units();
    
    for i = 1, army_units:count() do
        local current_unit = army_units:item(i);
        if current_unit then
            local unit_key = current_unit:unique_ui_id();

            if pancake_find_unit_card(unit_key) then --this should filter out units controlled by other players (gifted in coop for example)
                if current_unit:is_idle() then
                    idle_flags[unit_key] = true;
                    if idle_mock_sus[unit_key] == nil then
                        --this handles all units, including reinforcements and summons

                        --We can't use current_unit:name() as the new_ref if we want this to work with generated battles
                        --That's because in lib_battle_manager, it says:
                        --  "we are currently using the scriptunit name to determine the
                        --  army script name - this might change in future"
                        --So all the units can have names like "1:1:player_army", which confuses script_unit:new(...),
                        --since it relies on units:item(new_ref) to find the right unit, and unite:item() can find
                        --things based on the name

                        --Note: script_unit:new() has been replaced by a mock script unit. See the comments for pancake_create_mock_su
                        idle_mock_sus[unit_key] = pancake_create_mock_su(army_to_cache, i, unit_key);
                    end;
                end;
            end;
        end;
    end;
end;

local function pancake_cache_idles()

    pancake_fill_table(idle_flags, false);

    local all_armies_in_alliance = bm:get_player_alliance():armies();

    for i = 1, all_armies_in_alliance:count() do
        pancake_cache_idles_for_army(all_armies_in_alliance:item(i));
    end;
    
    if is_marking_idle_units then
        pancake_mark_idles_now(); --this also clears idle marks for units that just started moving, so do this whether or not we found an idle now
    end;
end;

local function pancake_select_unit(uic_card, also_pan_camera)
    if uic_card then

        local was_visible = uic_card:Visible();

        if not was_visible then
            uic_card:SetVisible(true);
        end;
        if also_pan_camera then
            uic_card:SimulateDblLClick();
        else
            uic_card:SimulateLClick();
        end;
        if not was_visible then
            uic_card:SetVisible(false);
        end;
    end;
end;

local function pancake_get_ping_removal_name(unit_key, unit_name)
    return tostring(unit_key) .. "p" .. tostring(unit_name) .. "_remove_ping_icon";
end;

local function pancake_ping_unit_temporarily(unit_key)
    local mock_su_to_ping = idle_mock_sus[unit_key];
    local ping_duration = 600;
    local ping_removal_function = function()
        pancake_safely_remove_pancake_pings(mock_su_to_ping, unit_key);
    end;

    local ping_removal_name = pancake_get_ping_removal_name(unit_key, mock_su_to_ping.name);

    if not is_marking_idle_units then
        if not mock_su_to_ping.uic_ping_marker then
            --this doesn't use the optional ping duration from add_ping_icon because we need more control of repeated pings
            mock_su_to_ping:add_ping_icon();
            bm:callback(ping_removal_function, ping_duration, ping_removal_name);
        else
            bm:remove_process(ping_removal_name);
            bm:callback(ping_removal_function, ping_duration, ping_removal_name);
        end;
        
        --remove the previous selection ping (especially helpful if the game is paused)
        if last_selected_idle then
            local prev_mock_su = idle_mock_sus[last_selected_idle];
            if prev_mock_su.uic_ping_marker then
                bm:remove_process(pancake_get_ping_removal_name(last_selected_idle, prev_mock_su.name));
                pancake_safely_remove_pancake_pings(prev_mock_su, prev_mock_su.pancake_unit_key);
            end;
        end;
    end;
end;

--only acts if the unit has a unit card
--returns true if actions were performed for the unit, false otherwise
local function pancake_helper_for_next_idle(unit_key)
    local uic_card = pancake_find_unit_card(unit_key);
    if uic_card then
        pancake_select_unit(uic_card, true); --uic_card, not unit_key
        pancake_ping_unit_temporarily(unit_key);
        last_selected_idle = unit_key; --this needs to be set *after* (or at the end of) pancake_helper_for_next_idle()
        return true;
    else
        return false;
    end;
end;

local function pancake_select_next_idle()
    if not pancake_esc_menu_is_visible() then
    
        local found_idle = false;
        local loop_around_to_beginning = (last_selected_idle ~= nil);
        local start_looping_from = last_selected_idle;

        --iterate from the start of the list to end (unless one is found)
        for unit_key, is_idle in next, idle_flags, start_looping_from do

            if is_idle then
                found_idle = pancake_helper_for_next_idle(unit_key);
                if found_idle then
                    break;
                end;
            end;
        end;

        if not found_idle then
            if loop_around_to_beginning then
                --then, if nothing was found, iterate from the beginning to the last selected
                for unit_key, is_idle in next, idle_flags, nil do
                    if is_idle then
                        found_idle = pancake_helper_for_next_idle(unit_key);
                        if found_idle then
                            break;
                        end;
                    end;
                end;
            end;

            if not found_idle then
                last_selected_idle = nil;
            end;
        end;
    end;
end;

local function pancake_set_should_find_idle_units(bool_val)
    if not is_battle_complete then
        is_marking_idle_units = bool_val;
        local advice_str = "Find Idle Units is ";
        if bool_val then
            advice_str = advice_str .. "ON";
        else
            advice_str = advice_str .. "OFF";
        end;
        
        if is_deployed then
            
            if bool_val then
                pancake_mark_idles_now();
            else
                pancake_clear_idle_marks();
                --note: this deliberately does not stop the repeat_callback from running, so the idle_mock_sus table stays updated
            end;
        end;
        
        pancake_show_ui_toggle(advice_str);
    end;
end;

local function pancake_phase_deployed()
    
    bm:repeat_callback(pancake_cache_idles, 600, "pancake_cache_idles");
    
    is_deployed = true;
    
    --If you want the toggle idle unit cards to default to be on at the beginning
    --of the battle instead of off,
    --then delete the -- at the start of the next line
    --pancake_set_should_find_idle_units(true);
end;

local function pancake_phase_complete()
    is_deployed = false;
    is_battle_complete = true;
end;

core:add_listener(
    "pancake_idle_mark_listener",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_save9"; -- save9 appears in the game as Save10
    end,
    function()
        pancake_set_should_find_idle_units(not is_marking_idle_units);
    end,
    true
);

core:add_listener(
    "pancake_next_idle_listener",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_save10"; -- save10 appears in the game as Save11
    end,
    function()
        if not is_battle_complete then
            if is_deployed then
                pancake_select_next_idle();
            else
                pancake_show_ui_toggle("Next idle is not enabled until the battle has started.");
            end;
        end;
    end,
    true
);

core:add_listener(
    "pancake_battle_start_listener",
    "ComponentLClickUp",
    function(context)
        return context.string == "button_battle_start";
    end,
    function(context)
        local uic = UIComponent(context.component);
        local uic_path_str = uicomponent_to_str(uic)
        --search the path to see if it has deployment_end_sp or _end_mp. (It should be the parent of the button.)
        if uic_path_str:find("deployment_end_sp") then
            pancake_out("Is single-player");
            pancake_is_multiplayer = false;
        elseif uic_path_str:find("deployment_end_mp") then
            pancake_out("Is multi-player");
            pancake_is_multiplayer = true;
        end;
    end,
    false --this listener is not persistent; we don't need to keep listening once we've determined whether the button is sp or mp
);

bm:register_phase_change_callback("Deployed", pancake_phase_deployed);
bm:register_phase_change_callback("Complete", pancake_phase_complete);
