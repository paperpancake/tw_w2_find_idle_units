-- Script author: Andrew Draper (paperpancake/paperpancake5)

-------------------------------------------------------------------------------------------------------------------------------
--- @section declarations
-------------------------------------------------------------------------------------------------------------------------------

--In this script file, a "unit_key" is very important as a unique identifier for a unit
--unit_keys are used as an index for idle_timestamps and map_key_to_mock_sus, among other things
--Currently, I'm using a unit's unique_ui_id as the unit_key, but I recommend doing
--CTRL+F for "local unit_key = " to see what property of a unit is used in case I forget to update this comment
--We can't use current_unit:name() as a unique identifier if we want this to work with generated battles
--That's because in lib_battle_manager, it says:
--  "we are currently using the scriptunit name to determine the
--  army script name - this might change in future"
--So all the units can have names like "1:1:player_army", which confuses script_unit:new(...),
--since units:item() can find a unit based on the name

local this_mod_key = "pancake_find_idle";

local bm = get_bm();

--Since The Warden & The Paunch update, these require calls need to be below get_bm() for some reason
require("pancake_mock_script_unit");
require("pancake_battle_ui_handler");
require("script/pancake_lib/pancake_config_loader");
--there could be another require() below depending on the configuration
    --require("battlemod_button_ext");

if not is_function(toboolean) then
    --defined for readability
    function toboolean(arg)
        return not not arg;
    end;
end;

local pancake = {
    is_marking_idle_units = false,
    is_deployed = false,
    is_battle_complete = false,
    need_to_sync_highlights = false,
    toggle_was_toggled = false, --this should change to true after the first use of the toggle
    last_selected_idle = nil, --this stores the unit_key, not the unit or the su, of the last selected using this mod's hotkey
    needs_update_after_command = false; --was there a command given to units that requires idles be updated? (Used when the game is paused)

    --idle_timestamps and map_key_to_mock_sus are indexed by unit_keys
    --These tables may have entries for units no longer in the army's unit list (that's ok)
    --for example: a unit is idle at some point in a battle, and then that unit withdraws from the battle
    --idle_timestamps[unit_key] == timestamp_tick when it the unit was first marked as idle (and not in the exclusion_map), or false otherwise (not nil, since we need to know whether to clear existing marks)
    idle_timestamps = {},
    map_key_to_mock_sus = {}, --map_key_to_mock_sus[unit_key] == the mock_su for the unit that has the given unit key
                              --As an abbreviation for script_unit, I prefer su over sunit here because sunit and unit look similar in this code

    --if a unit should be excluded, then the exclusion_map should have an entry
    --of exclusion_map[unit_key] = pancake_exclusion_condition,
    --where pancake_exclusion_condition is an object from that class
    --note, this is a key, value mapping, so you can't use # or ipairs
    --the contents will likely change during the battle
    exclusion_map = {},

    --battle commands that don't affect a unit's idle status in this mod
    --the command name is stored as a key, with the value set to true, for faster lookup
    --see https://stackoverflow.com/a/2282547/1019330
    irrelevant_commands = {},

    --to have the Next Idle hotkey work while respecting config.seconds_idle_before_marked
    --we need the mod to keep checking idle status even when it isn't marking the idles
    --this variable might be changed to false if config.seconds_idle_before_marked is 0 or false 
    keep_checking_in_background = true,
    has_callback_for_updating_idles = false,

    listen_for_destroyed_gates = false,

    is_debug = false;
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
--- @Class pancake_exclusion_condition
-------------------------------------------------------------------------------------------------------------------------------
local pancake_exclusion_condition = {
    num_spells_when_excluded = nil; --only used for spellcasters; can't be set using UI scraping until the Deployed phase
};

function pancake_exclusion_condition:new()
    local new_obj = {};
    setmetatable(new_obj, self);
    self.__index = self;
    self.__tostring = function() return "pancake_exclusion_condition" end;

    return new_obj;
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Static Methods
--- (plus pancake:debug(), because I need it defined early)
-------------------------------------------------------------------------------------------------------------------------------
function pancake.out(msg)
    out("&&& paperpancake's Find Idle Units mod: "..msg);
end;

function pancake:debug(msg)
    if self.is_debug then
        pancake.out(msg);
    end;
end;

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
--- @section Optional Configuration
--- @desc The user can provide a text file containing variable assignments
-------------------------------------------------------------------------------------------------------------------------------

local config = nil;
local already_loaded_config = false;
local mct_local_reference = false;

core:add_listener(
    "find_idle_mct_init_listener",
    "MctInitialized",
    true,
    function(context)

        mct_local_reference = context:mct();

        if already_loaded_config then

            local mct_order_warning = "Warning: Please let the author of Find Idle Units know you received the following warning: MCT settings weren't available until after configuration was needed. We're ignoring them for this battle.";

            pancake.out(mct_order_warning);

            --if we already have loaded configuration from the file and weren't supposed to,
            --provide some kind of visual indication of that the MCT settings are being ignored
            --it should appear whether or not the config file asks for no popup messages
            local mct = mct_local_reference;
            if mct then
                local mct_for_find_idle = mct:get_mod_by_key(this_mod_key);
        
                if mct_for_find_idle then
        
                    local option_which_config = mct_for_find_idle:get_option_by_key("option_which_config");
                    config_type = option_which_config:get_finalized_setting(); --"mct", "file", or "original" (shouldn't be nil here, but theoretically could be)
        
                    if config_type ~= "file" then
                        bm:callback(function() effect.advice(mct_order_warning) end, 3000, this_mod_key.."_mct_order_warning_dialog");
                    end;
                end;
            end;
        end;
    end,
    true
);

--returns the MCT (or nil if it's not found)
local function try_to_get_MCT()
    
    local mct = nil;

    if is_function(get_mct) then
        mct = get_mct();
    end;
    
    return mct;
end;

local function create_config_table_with_defaults()
    local config = {
        
        hotkey_for_toggle_find_all_idle = true,
        hotkey_for_next_idle_unit = true,

        popup_msg_duration = 1.3,
        no_ping_icon_for_next_unit = true, --changed to true in 05/2020 update
        seconds_idle_before_marked = 1.8,
        seconds_between_idle_checks = 0.6,

        --This should save some users that might forget to put quotation marks around some strings like "script_F2"
        script_F2 = "script_F2",
        script_F3 = "script_F3",
        script_F4 = "script_F4",
        script_shift_F2 = "script_shift_F2",
        script_shift_F3 = "script_shift_F3",
        script_shift_F4 = "script_shift_F4",
        script_ctrl_F2 = "script_ctrl_F2",
        script_ctrl_F3 = "script_ctrl_F3",
        script_ctrl_F4 = "script_ctrl_F4",
    };

    return config;
end;

local function process_config_time_settings(config)
    config.toggle_on_automatically_after = pancake_config_loader.convert_to_ms(config.toggle_on_automatically_after, false);
    if config.toggle_on_automatically_after == 0 then
        local pancake_object = pancake;
        pancake_object.is_marking_idle_units = true;
    end;

    config.popup_msg_duration = pancake_config_loader.convert_to_ms(config.popup_msg_duration, true);
    if config.popup_msg_duration == 0 then
        config.popup_msg_duration = false;
    end;

    config.seconds_between_idle_checks = pancake_config_loader.convert_to_ms(config.seconds_between_idle_checks, false);
    if not config.seconds_between_idle_checks then
        config.seconds_between_idle_checks = 600; --we do need some positive value here
        config.seconds_idle_before_marked = 0; --they probably meant that they didn't want the overhead of waiting between idle checks?
    elseif config.seconds_between_idle_checks <= 0 then
        config.seconds_between_idle_checks = 600; --we do need some positive value here
    end;

    config.seconds_idle_before_marked = pancake_config_loader.convert_to_ms(config.seconds_idle_before_marked, false);
    if not config.seconds_idle_before_marked then
        config.seconds_idle_before_marked = 0;
    end;

    pancake.keep_checking_in_background = config.seconds_idle_before_marked and (config.seconds_idle_before_marked > 0);
end;

local function unpack_config_from_mct(mct, my_mod)

    local config, config_log_msg = nil, nil;

    config = create_config_table_with_defaults();

    local all_options = my_mod:get_options();
    for k, v in next, all_options do
        config[k] = v:get_finalized_setting();
    end;

    --handle any options that don't just directly transfer from MCT to file settings

    if config.use_hotkey_to_exclude_unit == "no" then
        config.use_hotkey_to_exclude_unit = false;
    end;

    if config.hotkey_for_toggle_find_all_idle == "no" then
        config.hotkey_for_toggle_find_all_idle = false;
    end;

    if config.hotkey_for_next_idle_unit == "no" then
        config.hotkey_for_next_idle_unit = false;
    end;

    config.no_card_pulsing_for_toggle = not config.pulse_toggle;
    config.no_ping_icon_for_toggle = not config.ping_toggle;
    config.no_ping_icon_for_next_unit = not config.ping_next;
    config.no_camera_pan_for_next_unit = not config.camera_pan_next;

    return config, config_log_msg;
end;

local function try_loading_config_from_mct()

    local config, config_type, config_log_msg = nil, nil, nil;

    local mct = try_to_get_MCT();

    if mct then
        local my_mod = mct:get_mod_by_key(this_mod_key);

        if my_mod then

            local option_which_config = my_mod:get_option_by_key("option_which_config");
            config_type = option_which_config:get_finalized_setting(); --"mct", "file", or "original" (shouldn't be nil here, but theoretically could be)

            if config_type == "mct" then
                config, config_log_msg = unpack_config_from_mct(mct, my_mod);
            end;

        else
            --config_type = nil;
        end;
    else
        --config_type = nil;
    end;

    return config, config_type, config_log_msg;

end;

local function try_loading_config_from_file()

    local success, file_found, msg;

    local config, config_log_msg;

    config = create_config_table_with_defaults();

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

    return config, config_log_msg;
end;

--config_type is "mct", "file", or "original", or nil
--TODO: test this with and without the mct, and with and without the file
local function pancake_idle_load_config()

    local config, config_type, config_log_msg;

    config, config_type, config_log_msg = try_loading_config_from_mct();

    --pancake:debug('config_type after looking for mct is: '..tostring(config_type));

    if config_type == "file" or config_type == nil then
        if config_type == nil then
            config_type = "file";
        end;
        config, config_log_msg = try_loading_config_from_file();

    elseif config_type == "original" then
        config = create_config_table_with_defaults();
    elseif config_type == "mct" then
        --config should already be set
    end;

    process_config_time_settings(config);
    already_loaded_config = true;

    if pancake.is_debug then
        pancake.out("Config is: ");
        for k, v in next, config do
            pancake.out(tostring(k).." = "..tostring(v));
        end;
    end;

    return config, config_log_msg;
end;


-------------------------------------------------------------------------------------------------------------------------------
--- @section Extend the battle_manager's functionality
--- @desc This will allow me to more easily listen for any battle commands or selection changes
-------------------------------------------------------------------------------------------------------------------------------

do
    local bm = get_bm();

    ----------------------------------------------------
    -- Extend listener for commands
    ----------------------------------------------------

    --register a dummy function so that the battle_manager registers its listener and keeps it registered
    bm:register_command_handler_callback("Pancake_Dummy_Command", function() --[[Do nothing]] end, "Pancake_Dummy_Command");

    --both the callback_key (string) and the callback (function) are required
    --the order that the listeners will be called in is not guaranteed
    function bm:pancake_set_listener_for_battle_commands(callback_key, callback)

        if not (callback_key and is_string(callback_key) and callback and is_function(callback)) then
            pancake.out("Bad arguments provided to bm:pancake_set_listener_for_battle_commands");
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

    ----------------------------------------------------
    -- Extend listener for selections
    ----------------------------------------------------

    --register a dummy listener so that the battle_manager registers its listener and keeps it registered
    --bm:register_unit_selection_callback(&&& needs a dummy unit &&&, function() --[[Do nothing]] end, "Pancake_Dummy_Selection");
    do
        local dummy_callback = {
            unit = nil,
            callback = function() --[[do nothing]] end;
        };
        
        if #bm.unit_selection_callback_list == 0 then
            bm:register_unit_selection_handler("battle_manager_unit_selection_handler");
        end;
        
        table.insert(bm.unit_selection_callback_list, dummy_callback);
    end;

    --both the callback_key (string) and the callback (function) are required
    --the order that the listeners will be called in is not guaranteed
    function bm:pancake_idle_set_listener_for_selections(callback_key, callback)
        if not (callback_key and is_string(callback_key) and callback and is_function(callback)) then
            pancake.out("Bad arguments provided to bm:pancake_idle_set_listener_for_selections");
            return;
        end;

        if not self.pancake_idle_listeners_for_selections then
            self.pancake_idle_listeners_for_selections = {};
        end;

        self.pancake_idle_listeners_for_selections[callback_key] = callback;
    end;

    function bm:pancake_idle_clear_listeners_for_selections()
        self.pancake_idle_listeners_for_selections = nil;
    end;

    --overrides the old, global function
    local original_battle_manager_unit_selection_handler = battle_manager_unit_selection_handler;
    battle_manager_unit_selection_handler = function(unit, is_selected)

        --note that this is a function, not a method; you can't use the self variable here

        if bm.pancake_idle_listeners_for_selections then
            for k, pancake_callback in next, bm.pancake_idle_listeners_for_selections do
                pancake_callback(unit, is_selected);
            end;
        end;

        original_battle_manager_unit_selection_handler(unit, is_selected);
    end;
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

--pancake 06/2020
function pancake:unit_is_effectively_idle(unit)
    return unit:is_idle() and not unit:is_in_melee();
end;

function pancake:has_been_idle_enough(timestamp_when_idle)

    local is_currently_idle = not not timestamp_when_idle;

    --self:debug("checking if idle long enough: "..tostring(timestamp_tick).." >= ? "..tostring(timestamp_when_idle).." + "..tostring(config.seconds_idle_before_marked));
    if is_currently_idle then
        return timestamp_tick >= timestamp_when_idle + config.seconds_idle_before_marked;
    else
        return false;
    end;
end;

--@p should_check_idle_first is an optional boolean. If true, then the ping will only be cleared if the unit is not idle
--          (Note: this should not need to check if a unit is excluded because pings should be removed when a unit is first excluded)
function pancake:clear_last_temporary_ping(should_check_idle_first)
    --remove the previous selection ping (especially helpful if the game is paused)
    if self.last_selected_idle and not config.no_ping_icon_for_next_unit then
        local prev_mock_su = self.map_key_to_mock_sus[self.last_selected_idle];
        if prev_mock_su.uic_ping_marker then

            local should_clear = not should_check_idle_first;
            
            if should_check_idle_first then
                --make sure it's still safe to reference the is_idle() function
                if not is_routing_or_dead(prev_mock_su, true) then
                    should_clear = true;
                    if self:find_unit_card(self.last_selected_idle) then --pancake edit 3/3/2020
                        should_clear = not self:unit_is_effectively_idle(prev_mock_su.unit);
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
    local mock_su_to_ping = self.map_key_to_mock_sus[unit_key];
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
    local mock_su_to_ping = self.map_key_to_mock_sus[unit_key];

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
    
    for unit_key, timestamp_when_idle in next, self.idle_timestamps do
        local current_mock_su = self.map_key_to_mock_sus[unit_key];
        if current_mock_su then
            if self:find_unit_card(unit_key) then
                if self:has_been_idle_enough(timestamp_when_idle) then
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
                    --if self.is_debug and timestamp_when_idle then
                    --    self:debug("was not idle long enough, so not marking it. Time idle = "..tostring(timestamp_tick - timestamp_when_idle));
                    --end;
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
    for unit_key, timestamp_when_idle in next, self.idle_timestamps do
        local current_mock_su = self.map_key_to_mock_sus[unit_key];
        if current_mock_su then
            if self:find_unit_card(unit_key) then
                self:clear_toggle_mark_for_unit(current_mock_su);
            end;
        end;
    end;
end;

-- This is just a helper function that loops through all the units in the given_alliance
-- and calls function_to_do(current_unit, current_army, unit_index_in_army) for each one
-- Note that we don't pass self to function_to_do, but most callers will already has a reference to our self
local function for_each_unit_in_alliance(given_alliance, function_to_do)

	local all_armies_in_alliance = given_alliance:armies();

    for army_num = 1, all_armies_in_alliance:count() do
        local current_army = all_armies_in_alliance:item(army_num);
        local units = current_army:units();
		for unit_num = 1, units:count() do
			local current_unit = units:item(unit_num);
			if current_unit then
				function_to_do(current_unit, current_army, unit_num);
            end;
		end;
	end;
	
end;

-- This is just a helper function that loops through all the unit cards
-- and calls function_to_do(uic_card) for each one
local function for_each_unit_card(function_to_do)
    local uic_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY");
	
	if uic_parent then
		for i = 0, uic_parent:ChildCount() - 1 do
			local uic_card = uic_parent:Find(i);
			if uic_card then
                uic_card = UIComponent(uic_card);
                function_to_do(uic_card);
            end;
		end;
    end;
end;

--this should only cache idle units in the player's alliance if those units are controlled by the local player
--this also updates map_key_to_mock_sus if needed (that is, if a key is missing from the map)
--
--IMPORTANT:    this function won't work if called immediately from within a hotkey listener. To use this function
--              with a hotkey, you need to use a callback (it seems like callbacks can have a delay of 0 if needed, but
--              a 0-delay is not guaranteed to work immediately when paused if there's a time-intensive script running in the hotkey context
--              Maybe hotkey listeners are on a different thread than the callback loop? Idk.)
--              The reason for this is that units:count() and unit:is_idle() don't work when called from a hotkey listener for some reason
function pancake:update_idles()

    local tmp_idle_timestamps = {};

    for_each_unit_in_alliance(
        bm:get_player_alliance(),
        function(current_unit, current_army, unit_index_in_army)
            local unit_key = tostring(current_unit:unique_ui_id());

            if not self:is_unit_excluded(unit_key) and self:find_unit_card(unit_key) then --this should filter out units controlled by other players (gifted in coop for example)
                if self:unit_is_effectively_idle(current_unit) then
                    tmp_idle_timestamps[unit_key] = timestamp_tick;
                    if self.map_key_to_mock_sus[unit_key] == nil then
                        --this handles all units, including reinforcements and summons

                        --Note: script_unit:new() has been replaced by a mock script unit. See the comments for pancake_mock_script_unit.lua
                        self.map_key_to_mock_sus[unit_key] = pancake_create_mock_script_unit(current_army, unit_index_in_army);
                    end;
                end;
            end;
        end
    );

    --clear anything that isn't effectively idle anymore
    for unit_key, idle_timestamp in next, self.idle_timestamps do
        if idle_timestamp and not tmp_idle_timestamps[unit_key] then
            self.idle_timestamps[unit_key] = false; --not nil, since we rely on having an entry in this table for clearing idle marks
        end;
    end;

    --transfer any new or updated values (this loop has some overlap with the previous loop, but this loops through a different table and handles different cases)
    for unit_key, idle_timestamp in next, tmp_idle_timestamps do
        if idle_timestamp and not self.idle_timestamps[unit_key] then
            self.idle_timestamps[unit_key] = idle_timestamp;
        end;
    end;

end;

--this method always updates the idles lists and flags, but it only marks them in the UI if is_marking_idle_units
function pancake:update_and_mark_all_idles()

    self:update_idles();
    if self.is_marking_idle_units then
        --self:debug("Preparing to mark_idles_ui");
        self:mark_idles_ui(); --this also clears idle marks for units that just started moving, so do this whether or not we found an idle now
        --self:debug("Done with mark_idles_ui");
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

    --self:debug("In helper_for_next_idle");

    local uic_card = self:find_unit_card(unit_key);
    if uic_card then
        self:select_unit(uic_card, true); --uic_card, not unit_key
        --self:debug("After select_unit");
        self:ping_unit_if_ok(unit_key, false);
        self.last_selected_idle = unit_key; --this needs to be set *after* (or at the end of) pancake:helper_for_next_idle()
        --self:debug("End helper_for_next_idle with true")
        return true;
    end;

    --self:debug("End helper_for_next_idle with false")

    return false;
end;

function pancake:is_card_selected(uic_card)
    return tostring(uic_card:CurrentState()):lower():find("selected");
end;

--[[
    I want to search based on the order of the unit cards, which is what I was trying to do here.
    However, this does things based on the initial order of the unit cards, ignoring any player reordering
    The best way I can think of to do this based on player ordering is to use the position on the screen
    But that doesn't seem worth the effort to make it robust and efficient,
    so I'm just searching in an arbitrary order (but one that still goes through all idle units before repeating)
    (see the alternate implementation of this method by the same name)


--is_callback_context is an optional parameter that moves the execution to a callback context
--note: this commented script  might not be fully up-to-date; for example, idle_flags now stores timestamps, not booleans
function pancake:select_next_idle(is_callback_context)
    if not self.esc_menu_is_visible() then

        if not is_callback_context then
            --calls this method again, but from within the callback loop, not the hotkey context
            bm:callback(function() self:select_next_idle(true) end, 0, "pancake:select_next_idle_in_callback");
            return;
        end;

        self:debug("Starting select_next_idle");

        self:update_idles(); --this also updates map_key_to_mock_sus if needed
    
        local found_idle = false;
        local last_index_of_current_selection = -1; --unit cards use a 0-based index

        local uic_parent = find_uicomponent(core:get_ui_root(), "layout", "battle_orders", "cards_panel", "review_DY");

        if not uic_parent then
            pancake.out("Error: cannot find UIComponent review_DY when trying to find the next idle unit.");
            return;
        end;

        local num_children = uic_parent:ChildCount() - 1;
    
        --loop through in reverse to find the last selected unit
        --  (this does *not* care if the last few units are selected and the first few are also selected
        --   it will still just look for the last unit selected)
        for i = num_children, 0, -1 do
            local uic_card = uic_parent:Find(i);
            if uic_card then
                uic_card = UIComponent(uic_card);
                if self:is_card_selected(uic_card) then
                    self:debug("Found a selected unit indes: "..tostring(i));
                    last_index_of_current_selection = i; --last_index_of_current_selection == -1 if nothing is selected
                    break;
                end;
            end;
        end;

        local respond_if_card_has_idle_unit = function(card_index)
            local uic_card = uic_parent:Find(card_index);
            local is_idle = false;
            if uic_card then
                uic_card = UIComponent(uic_card);
                local unique_ui_id = tostring(uic_card:Id());
                local tmp_is_idle = self.idle_flags[unique_ui_id];
                if tmp_is_idle then
                    is_idle = self:helper_for_next_idle(unique_ui_id);
                end;
            end;

            return is_idle;
        end;

        for i = last_index_of_current_selection + 1, num_children do
            found_idle = respond_if_card_has_idle_unit(i);
            if found_idle then
                break;
            end;
        end;

        if not found_idle then

            --then, if nothing was found so far, iterate from the beginning to the last selected
            for i = 0, last_index_of_current_selection do
                found_idle = respond_if_card_has_idle_unit(i);
                if found_idle then
                    break;
                end;
            end;

            if not found_idle then
                self:debug("No idle found");
                --clear the last temporary ping even if self.is_marking_idle_units, since that is a different kind of ping
                self:clear_last_temporary_ping();
                self.last_selected_idle = nil;
            end;
        end;
    end;

    self:debug("Done with select_next_idle");
end;
--]]

--is_callback_context is an optional parameter that moves the execution to a callback context
function pancake:select_next_idle(is_callback_context)

    if not self.esc_menu_is_visible() then

        if not is_callback_context then
            --calls this method again, but from within the callback loop, not the hotkey context
            bm:callback(function() self:select_next_idle(true) end, 0, "pancake:select_next_idle_in_callback");
            return;
        end;

        --self:debug("In select_next_idle");

        self:update_idles();

        --self:debug("After updating idles");
    
        local found_idle = false;
        local loop_around_to_beginning = (self.last_selected_idle ~= nil);
        local start_looping_from = self.last_selected_idle;

        --start looking after self.last_selected_idle, not from the beginning of the list
        for unit_key, timestamp_when_idle in next, self.idle_timestamps, start_looping_from do

            if self:has_been_idle_enough(timestamp_when_idle) then
                found_idle = self:helper_for_next_idle(unit_key);
                if found_idle then
                    break;
                end;
            end;
        end;

        if not found_idle then
            if loop_around_to_beginning then
                --then, if nothing was found, iterate from the beginning to the last selected
                for unit_key, timestamp_when_idle in next, self.idle_timestamps, nil do
                    if self:has_been_idle_enough(timestamp_when_idle) then
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

    --self:debug("End select_next_idle");
end;

--this sets up the background process (callback) for updating whether units are idle
--this should not set any flags indicating whether the idle units should be marked in the UI 
function pancake:set_update_idles_process(should_find)
    if should_find then
        bm:callback(function() self:update_and_mark_all_idles() end, 0, "pancake:update_and_mark_all_idles_once");
        if not self.has_callback_for_updating_idles then
            bm:repeat_callback(function() self:update_and_mark_all_idles() end, config.seconds_between_idle_checks, "pancake:update_and_mark_all_idles_repeating");
            self.has_callback_for_updating_idles = true;
        end;
    else
        bm:remove_process("pancake:update_and_mark_all_idles_once");
        if not self.keep_checking_in_background then
            bm:remove_process("pancake:update_and_mark_all_idles_repeating");
            self.has_callback_for_updating_idles = false; --this is used in association with keep_checking_in_background
        end;
        bm:callback(function() self:clear_idle_marks(); end, 0, "pancake:clear_idle_marks");
    end;
end;

--skip_popup is an optional parameter, and it's not needed if config.no_popup_msg is set
--it's primarily used for turning the toggle on automatically
function pancake:set_should_find_idle_units(should_find, skip_popup)
    
    self.toggle_was_toggled = true;

    if not self.is_battle_complete then
        self.is_marking_idle_units = should_find;
        
        if self.is_deployed then
            self:set_update_idles_process(should_find);
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

function pancake:setup_map_key_to_mock_sus()
    --self:debug("Setting up map_key_to_mock_sus")
    for_each_unit_in_alliance(
        bm:get_player_alliance(),
		function(current_unit, current_army, unit_index_in_army)
			local ui_id = tostring(current_unit:unique_ui_id());
			if not self.map_key_to_mock_sus[ui_id] then
                self.map_key_to_mock_sus[ui_id] = pancake_create_mock_script_unit(current_army, unit_index_in_army);
			end;
        end
	);
	--self:debug("End of setup_map_key_to_mock_sus");
end;

--This is a helper function that takes care of the details of adding a hotkey listener based on config values
--(creating the listener's functions using this function's parameters works because of closures and upvalues, in case you wondered)
function pancake:add_configured_hotkey_listener(listener_key, config_setting, default_hotkey_string, function_for_hotkey)
    
    --self:debug("in add_configured_hotkey_listener, listener_kay is "..tostring(listener_key)..", config_setting = "..tostring(config_setting).." isstring = "..tostring(is_string(config_setting)));

    --Note that this listener is only added if the user has set this configuration option
    --config.use_hotkey_to_exclude_unit could be set to true or to a string key indicating the hotkey
    local hotkey_string = default_hotkey_string; -- save(#) appears in the game as save(# + 1)
    if config_setting then

        if is_string(config_setting) and config_setting ~= "true" then
            hotkey_string = config_setting;
        end;

        core:add_listener(
            listener_key,
            "ShortcutTriggered",
            function(context) return context.string == hotkey_string; end,
            function_for_hotkey,
            true
        );
    end;
end;

--Note: this is currently called at the phase PrebattleWeather instead of Startup for MCT reasons.
function pancake:phase_prebattle() --TODO: if this change from startup to prebattle sticks, check to see if other renaming makes sense 

    local config_log_msg;

    config, config_log_msg = pancake_idle_load_config();

    if config_log_msg then
        --this provides some kind of visual indication of an error in the config file
        --it should appear whether or not config.no_popup_msg is set
        effect.advice(config_log_msg); --this should be ok even if the log msg is long, since the advisor can scroll
    end;

    if config.add_button_to_exclude_unit then
        require("battlemod_button_ext");
    end;

    self:setup_map_key_to_mock_sus();

    if config.exclude_spellcasters_by_default then
        self:exclude_spellcasters(true);
    end;

    pancake:add_configured_hotkey_listener(
        "pancake_idle_mark_listener",
        config.hotkey_for_toggle_find_all_idle,
        "camera_bookmark_save9", -- save9 appears in the game as Save10
        function()
            local pancake_object = pancake;
            pancake_object:set_should_find_idle_units(not pancake_object.is_marking_idle_units);
        end
    );

    pancake:add_configured_hotkey_listener(
        "pancake_next_idle_listener",
        config.hotkey_for_next_idle_unit,
        "camera_bookmark_save10", -- save10 appears in the game as Save11
        function()
            local pancake_object = pancake;
            --pancake_object:debug("In camera_bookmark_save10 for find_next_idle");
            if not pancake_object.is_battle_complete then
                if pancake_object.is_deployed then
                    pancake_object:select_next_idle(false);
                else
                    pancake_object:show_popup_msg_if_ok("Next idle is not enabled until the battle has started.");
                end;
            end;
        end
    );

    pancake:add_configured_hotkey_listener(
        "pancake_exclude_from_idle_listener",
        config.use_hotkey_to_exclude_unit,
        "camera_bookmark_save11",
        function()
            local pancake_object = pancake;
            --pancake_object:debug("Exclusion hotkey was pressed.");
            if not pancake_object.is_battle_complete then
                bm:callback(function() pancake_object:toggle_exclude_on_selected_units(true) end, 0, "pancake_toggle_exclude_selected");
            end;
        end
    );

    if config.add_button_to_exclude_unit then

        --self:debug("Adding battlemod button for excluding/including units.");
        self.pancake_idle_exclusion_button = battlemod_button_ext:add_battle_order_button("pancake_idle_exclusion_button",
                                                                                          false,
                                                                                          "ui/templates/square_medium_button");
        self.pancake_idle_exclusion_button:SetImagePath("ui\\pancake_images\\icon_find_idle_disabled.png", 0);

        function self:set_exclusion_button_state(selection_has_exclusion, any_unit_is_selected)
            
            if any_unit_is_selected then

                if selection_has_exclusion then
                    self.pancake_idle_exclusion_button:SetImagePath("ui\\pancake_images\\icon_find_idle_disabled.png", 0);
                    self.pancake_idle_exclusion_button:SetState("active"); --self.pancake_idle_exclusion_button:SetState("selected");
                else
                    self.pancake_idle_exclusion_button:SetImagePath("ui\\pancake_images\\icon_find_idle_enabled.png", 0);
                    self.pancake_idle_exclusion_button:SetState("active");
                end;
            else
                self.pancake_idle_exclusion_button:SetImagePath("ui\\pancake_images\\icon_find_idle_enabled.png", 0);
                self.pancake_idle_exclusion_button:SetState("inactive");
            end;
        end;

        function self:update_exclusion_button_state()

            local has_excluded_selection = false;
            local has_included_selection = false;

            for_each_unit_card(
                function(uic_card)
                    local unique_ui_id = tostring(uic_card:Id());
                    if tostring(uic_card:CurrentState()):lower():find("selected") then
                        if self:is_unit_excluded(unique_ui_id) then
                            has_excluded_selection = true;
                        else
                            has_included_selection = true;
                        end;
                    end;
                end
            );

            local has_any_selection = has_excluded_selection or has_included_selection;

            self:set_exclusion_button_state(has_excluded_selection, has_any_selection);

        end;

        --this could get called whether a unit is selected or deselected
        --(it can get called multiple times if multiple units are selected/deselected)
        function self:respond_to_unit_selections()
            self:update_exclusion_button_state();
        end;

        bm:pancake_idle_set_listener_for_selections(
            "find_idle_respond_to_selections",
            function(unit, is_selected)
                self:respond_to_unit_selections();
            end
        );

        core:add_listener(
            "pancake_battlemod_button_exclude_idle",
            "ComponentLClickUp",
            function(context) return context.string == "pancake_idle_exclusion_button"; end,
            function()
                --pancake:debug("The exclude/include button was pressed.");
                pancake:toggle_exclude_on_selected_units(false);
            end,
            true
        );

        self:set_exclusion_button_state(false, false);
    end;
end;

function pancake:respond_to_relevant_battle_commands(command_context)

    if not self.is_battle_complete then
        local command_name = tostring(command_context:get_name());

        --don't respond to an irrelevant command
        if not self.irrelevant_commands[command_name] then

            if pancake.is_paused() and not self.needs_update_after_command then

                if self.is_marking_idle_units or self.keep_checking_in_background then
                    self.needs_update_after_command = true;
                    bm:callback(function() self:update_and_mark_all_idles(); end, 0, "pancake:respond_to_relevant_battle_commands_all");
                else
                    bm:callback(function() self:clear_last_temporary_ping(true); end, 0, "pancake:respond_to_relevant_battle_commands_one");
                end;

            end;
        end;
    end;
end;

--the unit_key param will likely be something like tostring(su_to_check.unit:unique_ui_id())
function pancake:is_unit_excluded(unit_key)
    return toboolean(self.exclusion_map[unit_key]);
end;

function pancake:is_ok_phase_to_mark_idles()
    return self.is_deployed and not self.is_battle_complete;
end;

--this function excludes units in a batch so that the UI can be updated all at once
--this needs to be called from a callback context, not from a hotkey context
--this function will also call pancake:update_exclusion_button_state if that function exists
--IMPORTANT: this function assumes the given units are already in map_key_to_mock_sus
--           most units should be anyway, but if in doubt, check before calling this function 
function pancake:set_excluded_for_units(table_of_unit_keys, should_exclude, is_callback_context)

    --self:debug("In set_excluded_for_units");

    if not is_callback_context then
        bm:callback(
            function() pancake:set_excluded_for_units(table_of_unit_keys, should_exclude, true) end,
            0,
            "pancake_callback_exclude_fun"
        );

        --self:debug("set_excluded_for_units will wait for a callback. Returning for now");
        
        return;
    end;

    if not is_table(table_of_unit_keys) then
        table_of_unit_keys = {table_of_unit_keys};
    end;

    local changed_exclusions = false;

    for i = 1, #table_of_unit_keys do
        local unit_key = table_of_unit_keys[i];

        if self:is_unit_excluded(unit_key) ~= should_exclude then
            changed_exclusions = true;
            if should_exclude then
                self.exclusion_map[unit_key] = pancake_exclusion_condition:new();
            else
                self.exclusion_map[unit_key] = nil;
            end;
            --self:debug("Set exclusion list for "..tostring(unit_key).." to "..tostring(should_exclude));
        end;
    end;

    if changed_exclusions then
        if should_exclude then

            --self:debug("Exclusions looping through a second time now");
            for i = 1, #table_of_unit_keys do
                local unit_key = table_of_unit_keys[i];
                self.idle_timestamps[unit_key] = false;

                if self:is_ok_phase_to_mark_idles() then

                    if not self.map_key_to_mock_sus[unit_key] then
                        self:setup_map_key_to_mock_sus(); --this goes through all friendly units
                    end;

                    local current_mock_su = self.map_key_to_mock_sus[unit_key];

                    if current_mock_su.unit:can_use_magic() then
                        --this should only called/set after the deployed phase
                        --before that, num_spells_when_excluded is undefined
                        self.exclusion_map[unit_key].num_spells_when_excluded = self:count_available_spells_for(unit_key);
                    end;

                    self:clear_toggle_mark_for_unit(current_mock_su);

                end;
            end;
        elseif self:is_ok_phase_to_mark_idles() then
            self:update_and_mark_all_idles();
        end;
    end;

    if is_function(self.update_exclusion_button_state) then
        self:update_exclusion_button_state();
    end;

    --self:debug("End set unit excluded");
end;

--scrapes the UI to find how many spells are currently available to the spellcaster
--IMPORTANT: before the deployed phase, the UI doesn't show any spells as available
--So don't rely on any values from this method before the deployed phase 
function pancake:count_available_spells_for(unit_key)

    --self:debug("Starting count_available_spells_for "..tostring(unit_key));

    local num_spells = 0;
    local uic_spell_slot_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "battle_orders_pane",
                                           "card_panel_docker", "cards_panel", "review_DY",
                                           unit_key, "battle", "spell_state_parent", "slot_parent");

    if not uic_spell_slot_parent then
        self:debug("Warning. Couldn't find uic_spell_slot_parent");
        return num_spells;
    end;
    

    for spell_slot_index = 1, 6 do
        local uic_spell_slot = find_uicomponent(uic_spell_slot_parent, "slot"..tostring(spell_slot_index));

        if uic_spell_slot then
            local is_available = tostring(uic_spell_slot:CurrentState()) == "active";
            if is_available then
                num_spells = num_spells + 1;
            end;
        end;
    end;

    --self:debug("End count_available_spells_for "..tostring(unit_key)..". Returning "..tostring(num_spells));
    return num_spells;
end;

function pancake:include_spellcasters_if_mana_is_at_least(min_mana, is_callback_context)

    local current_mana = 0;
    local uic_magic_amount = find_uicomponent(core:get_ui_root(), "winds_of_magic", "mask", "label_magic_amount");
    
    if uic_magic_amount then
        local mana_str = uic_magic_amount:GetStateText();

        if mana_str then
            current_mana = tonumber(mana_str);
            if current_mana == nil then --if it can't be converted to a number
                current_mana = 0;
            end;
        end;
    end;
    
    --self:debug("Current magic amount is: "..tostring(current_mana));

    if current_mana >= min_mana then
        self:exclude_spellcasters(false, is_callback_context);
    end;
end;

--if should_exclude is false, then it will re-include the spellcasters
function pancake:exclude_spellcasters(should_exclude, is_callback_context)

    if should_exclude == nil then
        self:debug("Warning. No argument given to exclude_spellcasters. Assuming should_exclude = true.")
        should_exclude = true;
    end;

    --self:debug("Checking for spellcasters to exclude/include.");

    local tmp_unit_keys = {};

    for_each_unit_in_alliance(
        bm:get_player_alliance(),
        function(current_unit, current_army, unit_index_in_army)

            if current_unit:can_use_magic() then

                local unit_key = tostring(current_unit:unique_ui_id());

                if not self.map_key_to_mock_sus[unit_key] then
                    self.map_key_to_mock_sus[unit_key] = pancake_create_mock_script_unit(current_army, unit_index_in_army);
                end;

                table.insert(tmp_unit_keys, unit_key);

                --self:debug("Preparing to exclude/include spellcaster - " .. tostring(current_unit:name()));
            end;
        end
    );

    self:set_excluded_for_units(tmp_unit_keys, should_exclude, is_callback_context);
end;

function pancake:check_excluded_casters_for_available_spells(is_callback_context)

    local units_to_enable = {};
    for unit_key, exclusion_condition in next, self.exclusion_map do
        if exclusion_condition.num_spells_when_excluded then
            local num_spells_available = self:count_available_spells_for(unit_key);
            if num_spells_available > exclusion_condition.num_spells_when_excluded then
                table.insert(units_to_enable, unit_key);
            end;
        end;
    end;

    if #units_to_enable > 0 then
        self:set_excluded_for_units(units_to_enable, false, is_callback_context);
    end;
end;

--This scrapes the UI to see if a notification is given that the gates are being broken
--We do this by looking at the images used in the adc_buttons (since they
--  are less likely to be changed by localization than labels)
function pancake:check_for_break_gates_notification()

    --self:debug("In check_for_break_gates_notification");

    local uic_adc_frame = find_uicomponent(core:get_ui_root(), "radar_holder", "radar_group", "adc_frame");
    if uic_adc_frame then

        --Since there can be more than one UI Component named "event_icon", we check all children of uic_adc_frame,
        --leading to multiple versions of root > radar_holder > radar_group > adc_frame > event_icon > adc_button
        local num_chil = uic_adc_frame:ChildCount();
        for child_index = 0, num_chil - 1 do
            
            local uic = uic_adc_frame:Find(child_index); --most or all of these are named "event_icon"
            if uic then
                uic = UIComponent(uic);
                
                uic = find_uicomponent(uic, "adc_button");
                
                if uic then

                    local num_img = uic:NumImages();

                    --if self.is_debug then
                        --self:debug("UIC info is below.");
                        --self:debug("UIC isVisible: "..tostring(uic:Visible()));
                        --self:debug("UIC isInteractive: "..tostring(uic:IsInteractive()));
                        --self:debug("UIC CurrentState: "..tostring(uic:CurrentState()));
                        --self:debug("UIC NumStates: "..tostring(uic:NumStates()));
                        --self:debug("UIC GetStateText: "..tostring(uic:GetStateText()));
                        --self:debug("UIC NumImages: "..tostring(num_img));
                    --end;

                    --as of the time of this writing, the image we cared about was at index 1
                    --but check all to be safe in case the index changes in an update
                    for img_index = 0, num_img-1 do
                        --self:debug("UIC GetImagePath"..tostring(img_index)..": "..tostring(uic:GetImagePath(img_index)));
                        local img_path = tostring(uic:GetImagePath(img_index));

                        --at time of this writing, we wanted the one at UI/Battle UI/ADC_icons/icon_attacking_gates.png
                        if img_path:find("icon_attacking_gates") then
                            self:debug("Gates broken! Ending check_for_break_gates_notification.");
                            return true;
                        end;
                    end;
                end;
            end;
        end;
    end;

    --self:debug("Ending check_for_break_gates_notification and returning false");
    return false;
end;

local gates_already_broke_recently = false;
function pancake:include_again_if_gates_just_broke(is_callback_context)

    --self:debug("In include_again_if_gates_just_broke");

    local should_skip_this_check = gates_already_broke_recently;
    local is_showing_gate_notification = self:check_for_break_gates_notification();
    gates_already_broke_recently = is_showing_gate_notification;

    if is_showing_gate_notification and not should_skip_this_check then
        --the gates just broke, so re-include all units
        --use set_excluded_for_units() to make the code easier to maintain
        local units_to_include = {};
        for unit_key, exclusion_condition in next, self.exclusion_map do
            table.insert(units_to_include, unit_key);
        end;
        --self:debug("Since gates broke, call set_exclude_for_units");
        self:set_excluded_for_units(units_to_include, false, is_callback_context);
    else
        --wait until the notification appears, or until it goes away and reappears
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
    
    if pancake.keep_checking_in_background and not self.is_marking_idle_units then
        self:set_update_idles_process(true);
    end;
    
    bm:pancake_set_listener_for_battle_commands(
        "pancake:respond_to_relevant_battle_commands",
        function(command_context)
            self:respond_to_relevant_battle_commands(command_context);
        end
    );

    if config.include_again_if_mana_is_at_least then

        local min_mana = tonumber(config.include_again_if_mana_is_at_least);
        if not min_mana then --they might have entered "true" or something else that isn't a number
            pancake.out("Warning. include_again_if_mana_is_at_least is not a number. Defaulting to 25.")
            min_mana = 25;
        end;

        bm:repeat_callback(
            function() self:include_spellcasters_if_mana_is_at_least(min_mana, true) end,
            1300,
            "repeated_callback_include_again_if_mana_is_at_least"
        );
    end;

    if config.include_again_if_new_spell then
        --since we can't count available spells before the deployed phase has been going for a bit, we set any initial spell counts here
        bm:callback(
            function()
                self:debug("Starting initial count of available spells for excluded spellcasters");
                for_each_unit_in_alliance(
                    bm:get_player_alliance(),
                    function(current_unit, current_army, unit_index_in_army)
                        local unit_key = tostring(current_unit:unique_ui_id());
                
                        if self.exclusion_map[unit_key] then
                            if current_unit:can_use_magic() then
                                self.exclusion_map[unit_key].num_spells_when_excluded = self:count_available_spells_for(unit_key);
                            end;
                        end;
                    end
                );
            end,
            100,
            "initial_count_of_available_spells"
        );

        --also set up the repeating callback
        bm:repeat_callback(
            function() self:check_excluded_casters_for_available_spells(true) end,
            1400,
            "repeated_callback_check_excluded_casters_for_available_spells"
        );
    end;

    if config.include_again_if_gates_break and bm:is_siege_battle() then
        bm:repeat_callback(
            function() self:include_again_if_gates_just_broke(true) end,
            1300,
            "repeated_callback_include_again_if_gates_just_broke"
        );
    end;

end;

function pancake:phase_complete()
    self.is_deployed = false;
    self.is_battle_complete = true;

    bm:remove_process("pancake:auto_start_toggle");
    bm:remove_process("pancake:update_and_mark_all_idles_once");
    bm:remove_process("pancake:update_and_mark_all_idles_repeating");

    bm:pancake_clear_listeners_for_battle_commands();
    bm:pancake_idle_clear_listeners_for_selections();
end;

--the currently selected units will either be all excluded or all included by this method
--Note that if is_callback_context is false, the actual exclusion won't happen immediately in code until the callback
--returns true  if the selected units will be all be excluded after the callback
--returns false if the selected units will be all be included after the callback
--returns nil if nothing was selected (might change in the future)
function pancake:toggle_exclude_on_selected_units(is_callback_context)

    --self:debug("In toggle_exclude_on_selected_units");

    local uic_parent = find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY");
    local selected_ui_ids = {}; --list of string ids
    
    --populate selected_ui_ids
	if uic_parent then
		for i = 0, uic_parent:ChildCount() - 1 do
			local uic_card = uic_parent:Find(i);
			if uic_card then
                uic_card = UIComponent(uic_card);

                if tostring(uic_card:CurrentState()):lower():find("selected") then
                    local unique_ui_id = tostring(uic_card:Id());

                    table.insert(selected_ui_ids, unique_ui_id);
                end;
            end;
		end;
	end;

    if #selected_ui_ids == 0 then
        --TODO: if nothing was selected, should it reinclude everything, or exclude anything currently idle, or just do nothing?
        --Currently it just does nothing
        return nil;
    end;

    local first_selected_id = selected_ui_ids[1];
    local change_all_to_be_excluded = not self.exclusion_map[first_selected_id]; --use the opposite of the current exclusion state

    --ensure all selected units have the same rule, or else include them all back in
    for k, v in next, selected_ui_ids do
        if change_all_to_be_excluded == toboolean(self.exclusion_map[v]) then
            --some of the selected units were excluded before and some weren't, so reinclude everything
            change_all_to_be_excluded = false;
            break;
        end;
    end;
    
    self:set_excluded_for_units(selected_ui_ids, change_all_to_be_excluded, is_callback_context);

    --self:debug("End of toggle_exclude_on_selected_units");

    return change_all_to_be_excluded;
end;

--We shouldn't need a listener for gifted units, since all non-ui pings are removed in the update function
--core:add_listener(
--    "pancake_units_gifted_listener",
--    "ComponentLClickUp",
--    function(context) return context.string == "button_gift_unit"; end,
--    function() end,
--    true
--);

bm:register_phase_change_callback("PrebattleWeather", function() pancake:phase_prebattle(); end);
bm:register_phase_change_callback("Deployed", function() pancake:phase_deployed(); end);
bm:register_phase_change_callback("Complete", function() pancake:phase_complete(); end);
