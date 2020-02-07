-- Script author: Andrew Draper (paperpancake/paperpancake5)

require("pancake_config_loader");
require("pancake_battle_ui_handler");
require("pancake_mock_script_unit");

-------------------------------------------------------------------------------------------------------------------------------
--- @section declarations
-------------------------------------------------------------------------------------------------------------------------------

--In this script file, a "unit_key" is very important as a unique identifier for a unit
--unit_keys are used as an index for idle_flags and idle_mock_sus, among other things
--Currently, I'm using a unit's unique_ui_id as the unit_key, but I recommend doing
--CTRL+F for "local unit_key = " to see what property of a unit is used in case I forget to update this comment
--We can't use current_unit:name() as a unique identifier if we want this to work with generated battles
--That's because in lib_battle_manager, it says:
--  "we are currently using the scriptunit name to determine the
--  army script name - this might change in future"
--So all the units can have names like "1:1:player_army", which confuses script_unit:new(...),
--since units:item() can find a unit based on the name

local bm = get_bm();
local config;
local config_log_msg;

local pancake = {
    is_marking_idle_units = false,
    is_deployed = false,
    is_battle_complete = false,
    need_to_sync_highlights = false,
    toggle_was_toggled = false, --this should change to true after the first use of the toggle
    last_selected_idle = nil, --this stores the unit_key, not the unit or the su, of the last selected using this mod's hotkey
    needs_update_after_command = false;

    --idle_flags and idle_mock_sus are parallel arrays, indexed by unit_keys
    --These tables may have entries for units no longer in the army's unit list (that's ok)
    --for example: a unit is idle at some point in a battle, and then that unit withdraws from the battle
    idle_flags = {},
    idle_mock_sus = {}, --As an abbreviation for script_unit, I prefer su over sunit here because sunit and unit look similar in this code

    --battle commands that don't affect a unit's idle status in this mod
    --the command name is stored as a key, with the value set to true, for faster lookup
    --see https://stackoverflow.com/a/2282547/1019330
    irrelevant_commands = {};
};

pancake.irrelevant_commands["Group Created"] = true;
pancake.irrelevant_commands["Group Destroyed"] = true;
pancake.irrelevant_commands["Change Speed"] = true;
pancake.irrelevant_commands["Double Click"] = true;
pancake.irrelevant_commands["Entity Hit"] = true;
pancake.irrelevant_commands["Double Click Unit Card"] = true;
pancake.irrelevant_commands["Unit Left Battlefield"] = true;
pancake.irrelevant_commands["Battle Results"] = true;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Static Methods
-------------------------------------------------------------------------------------------------------------------------------
function pancake.out(msg)
    out("&&& paperpancake's Find Idle Units mod: "..msg);
end

function pancake.fill_table(given_list, fill_value)
    for key in next, given_list do rawset(given_list, key, fill_value) end;
end;

function pancake.is_paused()
    local is_paused = false;
    --the next line for finding the pause button is taken from battle_ui_manager:highlight_time_controls
    local uic_pause = find_uicomponent(core:get_ui_root(), "radar_holder", "speed_buttons", "pause");
    
    if not uic_pause then
        --Looking in the layout pause button in another place
        uic_pause = find_uicomponent(core:get_ui_root(), "layout", "radar_holder", "speed_buttons", "pause");
    end;
    
    if uic_pause then
        local pause_button_state = tostring(uic_pause:CurrentState());
        is_paused = pause_button_state:lower():find("selected");
    else
        --pancake.out("Couldn't find pause button. Assuming it's not paused.");
    end;
    
    return is_paused;
end;

--TODO: is this function still needed? Now that we're using SimulateDblLClick() instead of a custom pan, we might be able to remove this
function pancake.esc_menu_is_visible()
    local retval = false;
    local uic_esc_menu = find_uicomponent(core:get_ui_root(), "panel_manager", "esc_menu_battle");
    if uic_esc_menu then
        if uic_esc_menu:Visible() then
            retval = true;
        end;
    end;
    
    return retval;
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Extend the battle_manager's functionality
--- @desc This will allow me to more easily listen for any battle command
-------------------------------------------------------------------------------------------------------------------------------

do
    local bm = get_bm();
    --register a dummy function so that the battle_manager registers its listener and keeps it registered
    bm:register_command_handler_callback("Pancake_Dummy_Command", function() --[[Do nothing]] end, "Pancake_Dummy_Command");

    --both the callback_key (string) and the callback (function) are required
    --the order that the listeners will be called in is not guaranteed
    function bm:pancake_set_listener_for_battle_commands(callback_key, callback)

        if not (callback_key and is_string(callback_key) and callback and is_function(callback)) then
            pancake.out("Bad arguments provided to bm:pancake_add_listener_for_battle_commands");
            return;
        end;

        if not self.pancake_listeners_for_battle_commands then
            self.pancake_listeners_for_battle_commands = {};
        end;
        
        self.pancake_listeners_for_battle_commands[callback_key] = callback;
    end;

    function bm:pancake_clear_listeners_for_battle_commands()
        self.pancake_listeners_for_battle_commands = nil;
    end;

    --overrides the old, global function
    local original_battle_manager_command_handler = battle_manager_command_handler;
    battle_manager_command_handler = function(command_context)

        --note that this is a function, not a method; you can't use the self variable here

        if bm.pancake_listeners_for_battle_commands then
            for k, pancake_callback in next, bm.pancake_listeners_for_battle_commands do
                pancake_callback(command_context);
            end;
        end;

        original_battle_manager_command_handler(command_context);
    end;
end;


-------------------------------------------------------------------------------------------------------------------------------
--- @section Optional Configuration
--- @desc The user can provide a text file containing variable assignments
-------------------------------------------------------------------------------------------------------------------------------

do
    local success, file_found, msg;

    --set default values before loading the config file
    config = {};
    config.popup_msg_duration = 1.3;

    success, file_found, msg, config = pancake_config_loader.load_file("./mod_config/find_idle_units_config.txt", config);

    if not file_found then
        --This might be the most common use case, so don't provide a visual dialog
        pancake.out("No config file found; using default values.");
    else
        if not success then
            config_log_msg = "The config file could not be completely read. There might be an error in it.\n"
                        .."Loaded as much as could be read up to the error, which was:\n"
                        ..msg;
            pancake.out(config_log_msg);
            --config_log_msg is also used further below
        else
            pancake.out("Config was loaded.");
        end;
    end;

    config.toggle_on_automatically_after = pancake_config_loader.convert_to_ms(config.toggle_on_automatically_after, false);
    if config.toggle_on_automatically_after == 0 then
        local pancake_object = pancake;
        pancake_object.is_marking_idle_units = true;
    end;

    config.popup_msg_duration = pancake_config_loader.convert_to_ms(config.popup_msg_duration, true);
    if config.popup_msg_duration == 0 then
        config.popup_msg_duration = false;
    end;

    --pancake.out("Config is: ");
    --for k, v in next, config do
    --    pancake.out(tostring(k).." = "..tostring(v));
    --end;

end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Pancake Methods
--- @desc Some of these methods could be static, too, but then some would use ":" and some "." Consistency is better for now.
-------------------------------------------------------------------------------------------------------------------------------

-- modified from lib_battle_script_unit's highlight_unit_card
-- I'm also using this to filter for units that are under your control in multiplayer battles with gifted units
-- This is also one way that I'm checking to see if a unit is still alive (if it's dead, references we have to it might be stale)
function pancake:find_unit_card(unit_key)

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

function pancake:highlight_unit_card_if_ok(mock_su, ...)
    if not config.no_card_pulsing_for_toggle then
        return mock_su:highlight_unit_card(...);
    end;
end;

function pancake:show_popup_msg_if_ok(popup_str)
    --this if statement is needed because false or nil in the config file means the popup shouldn't appear at all
    if config.popup_msg_duration then
        pancake_battle_ui_handler:show_popup_msg(popup_str, config.popup_msg_duration);
    end;
end;

function pancake:get_ping_removal_name(unit_key, unit_name)
    return tostring(unit_name) .. "_remove_ping_icon_p" .. tostring(unit_key); --unit_name might not be unique, so use unit_key as well
end;

function pancake:safely_remove_pancake_ping(mock_su)
    if not self.is_battle_complete then
        if mock_su then
            if mock_su.uic_ping_marker and is_uicomponent(mock_su.uic_ping_marker) then

                --IMPORTANT: You need some way to tell if the uic_ping_marker is broken or stale
                --           That can happen when a summoned unit dies, for example
                --           Don't use self:find_unit_card(unit_key), because that won't allow you
                --           to remove pings from gifted units
                if not is_routing_or_dead(mock_su, true) then
                    mock_su:remove_ping_icon();
                end;
            end;
        else
            pancake.out("Warning: pancake:safely_remove_pancake_ping was called, but no mock_su was provided.");
        end;
    end;
end;

--@p should_check_idle_first is an optional boolean. If true, then the ping will only be cleared if the unit is not idle
function pancake:clear_last_temporary_ping(should_check_idle_first)
    --remove the previous selection ping (especially helpful if the game is paused)
    if self.last_selected_idle and not config.no_ping_icon_for_next_unit then
        local prev_mock_su = self.idle_mock_sus[self.last_selected_idle];
        if prev_mock_su.uic_ping_marker then

            local should_clear = not should_check_idle_first;
            
            if should_check_idle_first then
                --make sure it's still safe to reference the is_idle() function
                if not is_routing_or_dead(prev_mock_su, true) then
                    should_clear = true;
                    if find_unit_card(self.last_selected_idle) then
                        should_clear = not prev_mock_su.unit:is_idle();
                    end;
                end;
            end;
                        
            if should_clear then
                bm:remove_process(self:get_ping_removal_name(self.last_selected_idle, prev_mock_su.name));
                self:safely_remove_pancake_ping(prev_mock_su);
            end;
        end;
    end;
end;

--this function does not check if check the config or the toggle is on. Doing that is the calling code's responsibility
function pancake:ping_one_unit_temporarily(unit_key)
    local mock_su_to_ping = self.idle_mock_sus[unit_key];
    if mock_su_to_ping then
        local ping_duration = 300;
        local ping_removal_function = function()
            self:safely_remove_pancake_ping(mock_su_to_ping);
        end;

        local ping_removal_name = self:get_ping_removal_name(unit_key, mock_su_to_ping.name);

        if not mock_su_to_ping.uic_ping_marker then
            --this doesn't use the optional ping duration from add_ping_icon because we need more control of repeated pings
            mock_su_to_ping:add_ping_icon();
            bm:callback(ping_removal_function, ping_duration, ping_removal_name);
        else
            bm:remove_process(ping_removal_name);
            bm:callback(ping_removal_function, ping_duration, ping_removal_name);
        end;
    end;

    --remove the previous selection ping (especially helpful if the game is paused)
    if self.last_selected_idle and self.last_selected_idle ~= unit_key then
        self:clear_last_temporary_ping();
    end;
end;

--@param is_for_toggle true if this ping is for the toggle (false if it's for the next idle unit hotkey)
function pancake:ping_unit_if_ok(unit_key, is_for_toggle)
    local mock_su_to_ping = self.idle_mock_sus[unit_key];

    if mock_su_to_ping then
        
        if is_for_toggle then
            if not config.no_ping_icon_for_toggle then

                --handle the case where there's a ping removal scheduled from a previous hotkey selection
                --note that script_unit:add_ping_icon() doesn't check to see if a ping is already there
                --if you call add_ping_icon when there is already one created, then you'll lose your reference to it
                --and have no way to destroy it
                if mock_su_to_ping.uic_ping_marker then
                    --this does nothing if the process isn't found, which is good
                    bm:remove_process(self:get_ping_removal_name(unit_key, mock_su_to_ping.name));
                else
                    mock_su_to_ping:add_ping_icon();
                end;

            end;
        else --is for next idle unit hotkey
            if not config.no_ping_icon_for_next_unit then
                --check to see if it's already getting pings from the toggle
                if config.no_ping_icon_for_toggle or not self.is_marking_idle_units then
                    pancake:ping_one_unit_temporarily(unit_key);
                end;
            end;
        end;
    end;
end;

--just a helper function to avoid duplicate code
function pancake:clear_toggle_mark_for_unit(current_mock_su)
    current_mock_su.has_pancake_toggle_mark = false;
    self:highlight_unit_card_if_ok(current_mock_su, false);
    self:safely_remove_pancake_ping(current_mock_su);
end;

--this relies on the idles cache from pancake:update_idles()
function pancake:mark_idles_ui()
    local sync_highlights_now = self.need_to_sync_highlights;
    self.need_to_sync_highlights = false;
    
    for unit_key, is_idle in next, self.idle_flags do
        local current_mock_su = self.idle_mock_sus[unit_key];
        if current_mock_su then
            if self:find_unit_card(unit_key) then
                if is_idle then
                    if not current_mock_su.has_pancake_toggle_mark then
                        current_mock_su.has_pancake_toggle_mark = true;
                        self:highlight_unit_card_if_ok(current_mock_su, true);
                        self:ping_unit_if_ok(unit_key, true);
                        if not sync_highlights_now then
                            self.need_to_sync_highlights = true;
                        end;
                    elseif sync_highlights_now then
                        --no need to set current_mock_su.has_pancake_toggle_mark here. It's already set
                        self:highlight_unit_card_if_ok(current_mock_su, true);
                    end;
                else
                    self:clear_toggle_mark_for_unit(current_mock_su);
                end;

            elseif not is_routing_or_dead(current_mock_su, true) then
                self:clear_toggle_mark_for_unit(current_mock_su);
            end;
        end;
    end;
end;

--clears all idle marks
function pancake:clear_idle_marks()
    for unit_key, is_idle in next, self.idle_flags do
        local current_mock_su = self.idle_mock_sus[unit_key];
        if current_mock_su then
            if self:find_unit_card(unit_key) then
                self:clear_toggle_mark_for_unit(current_mock_su);
            end;
        end;
    end;
end;

--this should only cache idle units for the indicated army if those units are controlled by the local player
--
--IMPORTANT:    this function won't work if called immediately from within a hotkey listener. To use this function
--              with a hotkey, you need to use a callback (it seems like callbacks can have a delay of 0 if needed, but
--              a 0-delay is not guaranteed to work immediately when paused if there's a time-intensive script running in the hotkey context
--              Maybe hotkey listeners are on a different thread than the callback loop? Idk.)
--              The reason for this is that units:count() and unit:is_idle() don't work when called from a hotkey listener for some reason
function pancake:update_idles_for_army(army_to_cache)
    local army_units = army_to_cache:units();
    
    for i = 1, army_units:count() do
        local current_unit = army_units:item(i);
        if current_unit then
            local unit_key = current_unit:unique_ui_id();

            if self:find_unit_card(unit_key) then --this should filter out units controlled by other players (gifted in coop for example)
                if current_unit:is_idle() then
                    self.idle_flags[unit_key] = true;
                    if self.idle_mock_sus[unit_key] == nil then
                        --this handles all units, including reinforcements and summons

                        --Note: script_unit:new() has been replaced by a mock script unit. See the comments for pancake_mock_script_unit.lua
                        self.idle_mock_sus[unit_key] = pancake_create_mock_script_unit(army_to_cache, i);
                    end;
                end;
            end;
        end;
    end;
end;

function pancake:update_idles()

    pancake.fill_table(self.idle_flags, false);

    local all_armies_in_alliance = bm:get_player_alliance():armies();

    for i = 1, all_armies_in_alliance:count() do
        self:update_idles_for_army(all_armies_in_alliance:item(i));
    end;

end;

function pancake:update_and_mark_all_idles()

    self:update_idles();
    if self.is_marking_idle_units then
        self:mark_idles_ui(); --this also clears idle marks for units that just started moving, so do this whether or not we found an idle now
    end;

    self.needs_update_after_command = false;

end;

function pancake:select_unit(uic_card)

    if uic_card then
        local also_pan_camera = not config.no_camera_pan_for_next_unit;

        local was_visible = uic_card:Visible();

        if not was_visible then
            uic_card:SetVisible(true);
        end;
        if also_pan_camera then
            uic_card:SimulateDblLClick();
        else
            uic_card:SimulateLClick();
        end;

        --uic_card:SimulateMouseOff() is needed for the case where SimulateDblLClick() pans to a unit and ends
        --with the mouse hovering over the selected unit when the battle is paused. Without SimulateMouseOff(), the tooltips
        --that appear on hover won't disappear correctly.
        uic_card:SimulateMouseOff();

        if not was_visible then
            uic_card:SetVisible(false);
        end;
    end;
end;

--only acts if the unit has a unit card
--returns true if actions were performed for the unit, false otherwise
function pancake:helper_for_next_idle(unit_key)
    local uic_card = self:find_unit_card(unit_key);
    if uic_card then
        self:select_unit(uic_card, true); --uic_card, not unit_key
        self:ping_unit_if_ok(unit_key, false);
        self.last_selected_idle = unit_key; --this needs to be set *after* (or at the end of) pancake:helper_for_next_idle()
        return true;
    else
        return false;
    end;
end;

--is_from_hotkey_context is an optional parameter that moves the execution to a callback context
function pancake:select_next_idle(is_from_hotkey_context)
    if not self.esc_menu_is_visible() then

        if is_from_hotkey_context then
            --calls this method again, but from within the callback loop, not the hotkey context
            bm:callback(function() self:select_next_idle() end, 0, "pancake:select_next_idle_once");
            return;
        end;

        self:update_idles();
    
        local found_idle = false;
        local loop_around_to_beginning = (self.last_selected_idle ~= nil);
        local start_looping_from = self.last_selected_idle;

        --start looking after self.last_selected_idle, not from the beginning of the list
        for unit_key, is_idle in next, self.idle_flags, start_looping_from do

            if is_idle then
                found_idle = self:helper_for_next_idle(unit_key);
                if found_idle then
                    break;
                end;
            end;
        end;

        if not found_idle then
            if loop_around_to_beginning then
                --then, if nothing was found, iterate from the beginning to the last selected
                for unit_key, is_idle in next, self.idle_flags, nil do
                    if is_idle then
                        found_idle = self:helper_for_next_idle(unit_key);
                        if found_idle then
                            break;
                        end;
                    end;
                end;
            end;

            if not found_idle then
                --clear the last temporary ping even if self.is_marking_idle_units, since that is a different kind of ping
                self:clear_last_temporary_ping();
                self.last_selected_idle = nil;
            end;
        end;
    end;
end;

--helper function
function pancake:remove_processes_for_toggle()
    bm:remove_process("pancake:update_and_mark_all_idles_once");
    bm:remove_process("pancake:update_and_mark_all_idles_repeating");
end;

--skip_popup is an optional parameter, and it's not needed if config.no_popup_msg is set
--it's primarily used for turning the toggle on automatically
function pancake:set_should_find_idle_units(should_find, skip_popup)
    
    self.toggle_was_toggled = true;

    if not self.is_battle_complete then
        self.is_marking_idle_units = should_find;
        
        if self.is_deployed then
            
            if should_find then
                bm:callback(function() self:update_and_mark_all_idles() end, 0, "pancake:update_and_mark_all_idles_once");
                bm:repeat_callback(function() self:update_and_mark_all_idles() end, 600, "pancake:update_and_mark_all_idles_repeating");
            else
                bm:callback(function() self:remove_processes_for_toggle(); end, 0, "pancake:remove_processes_for_toggle");
                bm:callback(function() self:clear_idle_marks(); end, 0, "pancake:clear_idle_marks");
            end;
        end;
        
        if not skip_popup then

            local popup_str = "Find Idle Units is ";
            if should_find then
                popup_str = popup_str .. "ON";
            else
                popup_str = popup_str .. "OFF";
            end;

            self:show_popup_msg_if_ok(popup_str);
        end;
    end;
end;

function pancake:phase_startup()
    if config_log_msg then
        --this provides some kind of visual indication of an error in the config file
        --it should appear whether or not config.no_popup_msg is set
        effect.advice(config_log_msg); --this should be ok even if the log msg is long, since the advisor can scroll
    end;
end;

function pancake:respond_to_relevant_battle_commands(command_context)

    if not self.is_battle_complete then
        local command_name = tostring(command_context:get_name());

        --don't respond to an irrelevant command
        if not self.irrelevant_commands[command_name] then

            if pancake.is_paused() and not self.needs_update_after_command then

                if self.is_marking_idle_units then
                    self.needs_update_after_command = true;
                    bm:callback(function() self:update_and_mark_all_idles(); end, 0, "pancake:respond_to_relevant_battle_commands_all");
                else
                    bm:callback(function() self:clear_last_temporary_ping(true); end, 0, "pancake:respond_to_relevant_battle_commands_one");
                end;

            end;
        end;
    end;
end;

function pancake:phase_deployed()
    
    self.is_deployed = true;

    if self.is_marking_idle_units then
        
        self:set_should_find_idle_units(true, true);

    elseif config.toggle_on_automatically_after then
        bm:callback(
            function()
                if not self.toggle_was_toggled and not self.is_battle_complete then
                    self:set_should_find_idle_units(true, true);
                end;
            end,
            config.toggle_on_automatically_after,
            "pancake:auto_start_toggle"
        );
    end;
    
    bm:pancake_set_listener_for_battle_commands(
        "pancake:respond_to_relevant_battle_commands",
        function(command_context)
            self:respond_to_relevant_battle_commands(command_context);
        end
    );

end;

function pancake:phase_complete()
    self.is_deployed = false;
    self.is_battle_complete = true;

    self:remove_processes_for_toggle();
    bm:remove_process("pancake:auto_start_toggle");

    bm:pancake_clear_listeners_for_battle_commands();
end;

core:add_listener(
    "pancake_idle_mark_listener",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_save9"; -- save9 appears in the game as Save10
    end,
    function()
        local pancake_object = pancake;
        pancake_object:set_should_find_idle_units(not pancake_object.is_marking_idle_units);
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
        local pancake_object = pancake;
        if not pancake_object.is_battle_complete then
            if pancake_object.is_deployed then
                pancake_object:select_next_idle(true);
            else
                pancake_object:show_popup_msg_if_ok("Next idle is not enabled until the battle has started.");
            end;
        end;
    end,
    true
);

--We shouldn't need a listener for gifted units, since all non-ui pings are removed in the update
--core:add_listener(
--    "pancake_units_gifted_listener",
--    "ComponentLClickUp",
--    function(context) return context.string == "button_gift_unit"; end,
--    function() end,
--    true
--);

bm:register_phase_change_callback("Startup", function() pancake:phase_startup() end);
bm:register_phase_change_callback("Deployed", function() pancake:phase_deployed() end);
bm:register_phase_change_callback("Complete", function() pancake:phase_complete() end);
