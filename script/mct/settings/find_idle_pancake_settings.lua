local this_mod_key = "pancake_find_idle";

local mct_mod = mct:register_mod(this_mod_key);

-------------------------------------------------------------------------------------------------------------------------------
--- @class pancake_dependency_group
--- @desc This handles situations where a group of options is enabled/disabled depending on the selected settings of another group of options
-------------------------------------------------------------------------------------------------------------------------------
local pancake_dependency_group = {};

function pancake_dependency_group:new()
    local obj = {
        master_option_checks = {}, --master_option_checks[string_option_key] = {option = option, check_function = function returning true iff the current option selection can exclude units};
        dependent_options = {}, --dependent_options[string_option_key] = {option = option}

    };

    setmetatable(obj, self);
    self.__index = self;
    obj.__tostring = function() return "pancake_dependency_group" end;
	obj.__type = function() return "pancake_dependency_group" end;

    return obj;
end;

--@param [check_function_to_add] should be a function returning true iff the current option selection can exclude units.
--                               it is optional; the default function will return the value of option_to_add:get_selected_setting();
function pancake_dependency_group:add_master_option(option_to_add, check_function_to_add)

    if not is_function(check_function_to_add) then
        check_function_to_add = function()
            return option_to_add:get_selected_setting();
        end;
    end;

    self.master_option_checks[option_to_add:get_key()] = {option = option_to_add,
                                                          check_function = check_function_to_add};

    local current_dependency_group = self;
    option_to_add:add_option_set_callback(
        function(option)
            current_dependency_group:update_all_dependent_enabled();
        end
    );
end;

function pancake_dependency_group:add_dependent_option(option_to_add)
    self.dependent_options[option_to_add:get_key()] = {option = option_to_add};
end;

function pancake_dependency_group:should_enable_dependent_options()
    local should_enable = false;
    for k, v in next, self.master_option_checks do
        if v.check_function() then
            should_enable = true;
        end;
    end;
    return should_enable;
end;

--see also update_all_dependent_enabled
function pancake_dependency_group:set_all_dependent_enabled(should_enable)
    local should_lock = not should_enable;
    for k, v in next, self.dependent_options do
        v.option:set_uic_locked(should_lock);
        -- v.option:set_uic_visibility(should_enable);
    end;
end;

function pancake_dependency_group:update_all_dependent_enabled()
    self:set_all_dependent_enabled(self:should_enable_dependent_options());
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Helper functions
-------------------------------------------------------------------------------------------------------------------------------

local function file_exists(filename)
    -- see https://stackoverflow.com/a/4991602/1019330
    local f = io.open(filename,"r");
    if f ~= nil then io.close(f) return true; else return false; end;
end;

local function create_local_option(section_key, ...)
    local tmp = mct_mod:add_new_option(...);
    tmp:set_local_only(true);
    tmp:set_assigned_section(section_key);
    return tmp;
end;

--NOTE: camera_bookmark_save9 in English localization appears as "Save Camera Bookmark 10"
local function create_configured_hotkey_dropdown(section_key, option_key, camera_bookmark_number, use_camera_bookmark_as_default)

    local new_dropdown = create_local_option(section_key, option_key, "dropdown");
    new_dropdown:add_dropdown_value("no", "No", "", not use_camera_bookmark_as_default);

    if is_number(camera_bookmark_number) then

         --NOTE: camera_bookmark_save5 in English localization appears as "Save Camera Bookmark 6"
        local bookmark_key = "camera_bookmark_save"..tostring(camera_bookmark_number);
        local bookmark_loc = "shortcut_localisation_onscreen_"..bookmark_key;

        new_dropdown:add_dropdown_value(bookmark_key, bookmark_loc, "Bind to whatever keys you want in the Controls menu.", use_camera_bookmark_as_default);
    end;

    new_dropdown:add_dropdown_value("script_F2", "F2", "");
    new_dropdown:add_dropdown_value("script_shift_F2", "Shift + F2", "");
    new_dropdown:add_dropdown_value("script_ctrl_F2", "Ctrl + F2", "");
    new_dropdown:add_dropdown_value("script_F3", "F3", "");
    new_dropdown:add_dropdown_value("script_shift_F3", "Shift + F3", "");
    new_dropdown:add_dropdown_value("script_ctrl_F3", "Ctrl + F3", "");
    new_dropdown:add_dropdown_value("script_F4", "F4", "");
    new_dropdown:add_dropdown_value("script_shift_F4", "Shift + F4", "");
    new_dropdown:add_dropdown_value("script_ctrl_F4", "Ctrl + F4", "");

    return new_dropdown;
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section Create sections
-------------------------------------------------------------------------------------------------------------------------------

--rename the default section
local default_section_title = "Configuration Source";
local default_section_title_is_localized = false;

local default_section = mct_mod:get_section_by_key("default");
if default_section then
    default_section:set_localised_text(default_section_title, default_section_title_is_localized);
else
    mct_mod:add_new_section("default", default_section_title, default_section_title_is_localized);
end;

mct_mod:add_new_section("section_main_hotkeys", "MCT Settings for Find Idle Units - Main Hotkeys");
mct_mod:add_new_section("section_misc", "MCT Settings for Find Idle Units - Misc Options");
mct_mod:add_new_section("section_exclude_include", "MCT Settings for Find Idle Units - Exclude/Include Options");

mct_mod:set_section_sort_function("index_sort");
mct_mod:set_option_sort_function_for_all_sections("index_sort");

-------------------------------------------------------------------------------------------------------------------------------
--- @section default section (renamed to "Configuration Source")
-------------------------------------------------------------------------------------------------------------------------------

local option_which_config = create_local_option("default", "option_which_config", "dropdown");

option_which_config:add_dropdown_value("mct", "MCT Settings", "");
option_which_config:add_dropdown_value("file", "File (find_idle_units_config.txt)", "");
option_which_config:add_dropdown_value("original", "Original Settings", "");

if file_exists("./mod_config/find_idle_units_config.txt") then
    option_which_config:set_default_value("file");
else
    option_which_config:set_default_value("mct");
end;

-------------------------------------------------------------------------------------------------------------------------------
--- @section section_main_hotkeys
-------------------------------------------------------------------------------------------------------------------------------

local hotkey_for_toggle_find_all_idle = create_configured_hotkey_dropdown("section_main_hotkeys", "hotkey_for_toggle_find_all_idle", 9, true);

local hotkey_for_next_idle_unit = create_configured_hotkey_dropdown("section_main_hotkeys", "hotkey_for_next_idle_unit", 10, true);

-------------------------------------------------------------------------------------------------------------------------------
--- @section section_misc
-------------------------------------------------------------------------------------------------------------------------------

local popup_msg_duration = create_local_option("section_misc", "popup_msg_duration", "slider");
popup_msg_duration:slider_set_min_max(0, 99);
popup_msg_duration:slider_set_precision(1);
popup_msg_duration:set_default_value(1.2);
popup_msg_duration:slider_set_step_size(0.6, 1);

local pulse_toggle = create_local_option("section_misc", "pulse_toggle", "checkbox");
pulse_toggle:set_default_value(true);

local ping_toggle = create_local_option("section_misc", "ping_toggle", "checkbox");
ping_toggle:set_default_value(true);

local ping_next = create_local_option("section_misc", "ping_next", "checkbox");
ping_next:set_default_value(false);

local camera_pan_next = create_local_option("section_misc", "camera_pan_next", "checkbox");
camera_pan_next:set_default_value(true);

local toggle_on_automatically_after = create_local_option("section_misc", "toggle_on_automatically_after", "slider");
toggle_on_automatically_after:slider_set_min_max(-1, 99999);
toggle_on_automatically_after:slider_set_precision(1);
toggle_on_automatically_after:set_default_value(-1);
toggle_on_automatically_after:slider_set_step_size(7, 1);

local seconds_idle_before_marked = create_local_option("section_misc", "seconds_idle_before_marked", "slider");
seconds_idle_before_marked:slider_set_min_max(0, 99999);
seconds_idle_before_marked:slider_set_precision(1);
seconds_idle_before_marked:set_default_value(1.8);
seconds_idle_before_marked:slider_set_step_size(0.3, 1);

local seconds_between_idle_checks = create_local_option("section_misc", "seconds_between_idle_checks", "slider");
seconds_between_idle_checks:slider_set_min_max(0.1, 99999);
seconds_between_idle_checks:slider_set_precision(1);
seconds_between_idle_checks:set_default_value(0.6);
seconds_between_idle_checks:slider_set_step_size(0.1, 1);

-------------------------------------------------------------------------------------------------------------------------------
--- @section section_exclude_include
--- @desc Options that can exclude or re-include units require special handling to control whether the options are enabled
-------------------------------------------------------------------------------------------------------------------------------

local exclude_dependency_group = pancake_dependency_group:new();

local add_button_to_exclude_unit = create_local_option("section_exclude_include", "add_button_to_exclude_unit", "checkbox");
add_button_to_exclude_unit:set_default_value(false);
exclude_dependency_group:add_master_option(add_button_to_exclude_unit, nil);

local use_hotkey_to_exclude_unit = create_local_option("section_exclude_include", "use_hotkey_to_exclude_unit", "dropdown");
use_hotkey_to_exclude_unit:add_dropdown_value("no", "No", "", true);
use_hotkey_to_exclude_unit:add_dropdown_value("camera_bookmark_save11", "Save Camera Bookmark 12", "Bind to whatever keys you want in the Controls menu."); --NOTE: camera_bookmark_save5 in English localization appears as Save Camera Bookmark 6"
use_hotkey_to_exclude_unit:add_dropdown_value("script_F2", "F2", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_shift_F2", "Shift + F2", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_ctrl_F2", "Ctrl + F2", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_F3", "F3", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_shift_F3", "Shift + F3", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_ctrl_F3", "Ctrl + F3", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_F4", "F4", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_shift_F4", "Shift + F4", "");
use_hotkey_to_exclude_unit:add_dropdown_value("script_ctrl_F4", "Ctrl + F4", "");
exclude_dependency_group:add_master_option(use_hotkey_to_exclude_unit, function() return use_hotkey_to_exclude_unit:get_selected_setting() ~= "no"; end);

local exclude_spellcasters_by_default = create_local_option("section_exclude_include", "exclude_spellcasters_by_default", "checkbox");
exclude_spellcasters_by_default:set_default_value(false);
exclude_dependency_group:add_master_option(exclude_spellcasters_by_default, nil);

local include_again_if_new_spell = create_local_option("section_exclude_include", "include_again_if_new_spell", "checkbox");
include_again_if_new_spell:set_default_value(false);
exclude_dependency_group:add_dependent_option(include_again_if_new_spell);

--TODO: hide this behind an enabling checkbox?
local include_again_if_mana_is_at_least = create_local_option("section_exclude_include", "include_again_if_mana_is_at_least", "slider");
include_again_if_mana_is_at_least:slider_set_min_max(0, 99999);
include_again_if_mana_is_at_least:slider_set_precision(0);
include_again_if_mana_is_at_least:set_default_value(25);
include_again_if_mana_is_at_least:slider_set_step_size(1, 0);
exclude_dependency_group:add_dependent_option(include_again_if_mana_is_at_least);

local include_again_if_gates_break = create_local_option("section_exclude_include", "include_again_if_gates_break", "checkbox");
include_again_if_gates_break:set_default_value(false);
exclude_dependency_group:add_dependent_option(include_again_if_gates_break);

-------------------------------------------------------------------------------------------------------------------------------
--- @section MCT Listeners
-------------------------------------------------------------------------------------------------------------------------------

--this does not affect option_which_config and needs to be mindful of pancake_dependency_group objects
local function set_enabled_for_all_options(use_mct_settings)
    local should_lock = not use_mct_settings;

    --this would be better in a loop, but since MCT sections are being actively developed, I figured listing each was safer
    --this one should always stay visible: mct_mod:set_section_visibility("default", show_most_options);
    --mct_mod:set_section_visibility("section_main_hotkeys", show_most_options);
    --mct_mod:set_section_visibility("section_misc", show_most_options);
    --mct_mod:set_section_visibility("section_exclude_include", show_most_options);
    
    --handle dependencies for option_which_config
    --This could use a pancake_dependency_group, but that would require adding all options as dependencies. Not worth it atm.
    local options_table = mct_mod:get_options();
    for k, current_option in next, options_table do
        if k ~= "option_which_config" then
            --current_option:set_uic_locked(should_lock);
            current_option:set_uic_visibility(use_mct_settings);
        end;
    end;

    if use_mct_settings then
        exclude_dependency_group:update_all_dependent_enabled();
    end;
end;

local function update_my_option_states(option_which_config)
    local config_choice = option_which_config:get_selected_setting();
    local show_most_options = (config_choice == "mct");
    set_enabled_for_all_options(show_most_options);
end;

option_which_config:add_option_set_callback(
    function(option)
        update_my_option_states(option);
    end
);

core:add_listener(
    "mct_populated_enable_check_for_"..tostring(this_mod_key),
    "MctPanelPopulated",
    function(context) return context:mod():get_key() == this_mod_key end,
    function(context)
        if not core:is_battle() then --all options are currently disabled during battle

            local option_which_config = context:mod():get_option_by_key("option_which_config");

            update_my_option_states(option_which_config);
        end;
    end,
    true
);
