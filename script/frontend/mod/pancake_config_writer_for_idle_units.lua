
require("script/pancake_lib/pancake_config_loader");

--The following was removed from the initial config text:
--      In 05/2020:
--          The comment:     -- The following settings are placeholders
--                           -- They won't do anything until future updates
--          include_again_if_new_ability = false
local pancake_default_config_text = 
[[
-- Anything that starts with a -- is a comment.
-- Comments are just notes to yourself. They don't do anything.
-- You can add, change, or delete comments all you'd like.
-- I put my comments above or on the line they refer to.

--------------------------------------------------------------------------------------------
-- How many seconds should the advisor be visible before being dismissed?
-- You can set this to false or 0 if you don't want it to appear at all.

popup_msg_duration = 1.3

--------------------------------------------------------------------------------------------
-- Change any of the below to true to disable a feature that's normally included in this mod

no_card_pulsing_for_toggle = false
no_ping_icon_for_toggle = false

no_ping_icon_for_next_unit = true
no_camera_pan_for_next_unit = false

--------------------------------------------------------------------------------------------
-- This option controls what type of ping this mod uses when it needs one.
-- Set this to "zzz", "magnifying_glass", or "default"
-- (yes, use quotes your choice; "default" uses the yellow circle with an eye inside)
-- This does not control whether or not the ping will appear. Use the above options for that.

idle_ping_image = "zzz"

---------------------------------------------------------------------------------------------
-- The "Find All Idle Units" toggle is normally off at the beginning of a battle.
-- If you want it to turn on automatically each battle, then change the value to be
-- the number of seconds to wait before turning on (decimals are allowed).
-- You can use 0 to have it turn on immediately
-- If you use a hotkey to turn this on even sooner in a battle, this will be ignored
-- Use false or a negative number to leave it turned off until you use a hotkey

toggle_on_automatically_after = false

---------------------------------------------------------------------------------------------
-- The following options tell this mod to exclude or ignore units
-- Excluded units won't be marked as idle or be included in "Next Idle Unit"
-- unless you include them again with the button or hotkey, or unless the conditions are met
-- for them to be automatically included again.

add_button_to_exclude_unit = false
use_hotkey_to_exclude_unit = false
exclude_spellcasters_by_default = false     -- this was added in 05/2020

-- The following don't do anything unless at least one of the exclude options is true

include_again_if_new_spell = false
include_again_if_mana_is_at_least = 99
include_again_if_gates_break = false

----------------------------------------------------------------------------------------------
-- To reduce false positives, this mod waits until a unit is idle for
-- at least seconds_idle_before_marked before marking it or including it in the
-- next idle unit hotkey.

seconds_idle_before_marked = 1.8
seconds_between_idle_checks = 0.6

----------------------------------------------------------------------------------------------
-- These options allow you to change the hotkeys this mod piggybacks on or to get rid of the
-- piggybacking altogether
-- You probably don't need to edit these unless you need them for another mod or you need
-- a lot of camera bookmark hotkeys and wish this mod didn't use so many.
-- Set these to have this function as described in mod's description ("Save Camera Bookmark 10" and 11)
-- Set either or both of these to false to not it use at all
-- Or you can set these to one of the allowed modding hotkeys (F2 to F4) like "script_shift_F2"

hotkey_for_toggle_find_all_idle = true
hotkey_for_next_idle_unit = true

]]

local pancake_2020_05_update_text = 
[[
----------------------------------------------------------------------------------------------
--        ******* New for 05/2020 *********
----------------------------------------------------------------------------------------------
-- All but one of the options that were placeholders should now work except for one:
-- 	Sadly, include_again_if_new_ability doesn't do anything,
-- 	so you can delete that line from the config file above
--
-- Excluded units won't be marked as idle or be included in "Next Idle Unit"
-- unless you include them again with the button or hotkey, or unless the conditions are met
-- for them to be automatically included again.
--
-- To use Save Camera Bookmark 12 as the exclusion hotkey, set use_hotkey_to_exclude_unit = true
-- Then in the game's Controls menu you can bind Save Camera Bookmark 12 to whatever key you want.
-- If that creates a conflict for you, the discussion on Steam explains other options.

---------------------------------------------------------------------------------------------
-- You can automatically start with all spellcasters excluded from this mod
--  at the beginning of the battle by setting the following to true.

exclude_spellcasters_by_default = false

]]

local pancake_2020_06_update_text =
[[
----------------------------------------------------------------------------------------------
--        ******* New for 06/2020 *********
----------------------------------------------------------------------------------------------

-- To reduce false positives, this mod now waits until a unit is idle for
-- at least seconds_idle_before_marked before marking it or including it in the
-- next idle unit hotkey.

seconds_idle_before_marked = 1.8
seconds_between_idle_checks = 0.6

]]

local pancake_2020_08_04_update_text =
[[
----------------------------------------------------------------------------------------------
--        ******* New for 08/2020 *********
----------------------------------------------------------------------------------------------

-- These options allow you to change this mod's primary hotkeys or get rid of them altogether
-- You probably don't need to edit these unless you need them for another mod or you need
-- a lot of camera bookmark hotkeys and wish this mod didn't use so many.
-- Set these to true to use the hotkeys in the mods description ("Save Camera Bookmark 10" and 11)
-- Set either or both of these to false to not use it at all
-- Or you can set these to one of the allowed modding hotkeys (F2 to F4) like "script_shift_F2"

hotkey_for_toggle_find_all_idle = true
hotkey_for_next_idle_unit = true

]]

local pancake_2020_08_18_update_text =
[[
----------------------------------------------------------------------------------------------
--        ******* AND ANOTHER ONE (2nd update for 08/2020) *********
--------------------------------------------------------------------------------------------

-- This option controls what type of ping this mod uses when it needs one.
-- Set this to "zzz", "magnifying_glass", or "default"
-- (yes, use quotes your choice; "default" uses the yellow circle with an eye inside)

idle_ping_image = "zzz"

]]

local config_filename = "./mod_config/find_idle_units_config.txt";

--@param a config table that reflects the current environmnet state (variables and their values) that are in the config file
local function pancake_update_config_file_if_needed(config)

    --update for May 2020
    if config.exclude_spellcasters_by_default == nil then
        local file, err_str = io.open(config_filename, "a");
        if file then
            file:write("");
            file:write(pancake_2020_05_update_text);
            file:close();
            out("&&&& added the 05/2020 update to the end of "..tostring(config_filename));
        else
            out("&&&& Could not update the config file at "..tostring(config_filename));
            out("&&&& "..tostring(err_str));
        end;
    end;

    --update for June 2020
    if config.seconds_idle_before_marked == nil and config.seconds_between_idle_checks == nil then
        local file, err_str = io.open(config_filename, "a");
        if file then
            file:write("");
            file:write(pancake_2020_06_update_text);
            file:close();
            out("&&&& added the 06/2020 update to the end of "..tostring(config_filename));
        else
            out("&&&& Could not update the config file at "..tostring(config_filename));
            out("&&&& "..tostring(err_str));
        end;
    end;

    --first update for August 2020
    if config.hotkey_for_toggle_find_all_idle == nil and config.hotkey_for_next_idle_unit == nil then
        local file, err_str = io.open(config_filename, "a");
        if file then
            file:write("");
            file:write(pancake_2020_08_04_update_text);
            file:close();
            out("&&&& added the 08/2020 update to the end of "..tostring(config_filename));
        else
            out("&&&& Could not update the config file at "..tostring(config_filename));
            out("&&&& "..tostring(err_str));
        end;
    end;

    --second update for August 2020
    if config.idle_ping_image == nil then
        local file, err_str = io.open(config_filename, "a");
        if file then
            file:write("");
            file:write(pancake_2020_08_18_update_text);
            file:close();
            out("&&&& added the 08/2020 update to the end of "..tostring(config_filename));
        else
            out("&&&& Could not update the config file at "..tostring(config_filename));
            out("&&&& "..tostring(err_str));
        end;
    end;
    
end;

--check whether the file exists before calling this function
local function pancake_write_default_file(config_filename)

    local file, err_str = io.open(config_filename, "w");
    if file then
        file:write(pancake_default_config_text);
        file:close();
        out("&&&& created default config file: "..config_filename);
    else
        --out("&&&& pancake could not write the config file. Perhaps the folder doesn't exist.\n"..tostring(err_str));
    end;
end;

local load_success, file_found, msg;
local config;

--TODO: Ideally this would inform the user if there was an error in their config file, but can we use the advisor on the front end?
--      If not, we can always try to make our own dialog

--set default values before loading the config file
config = {};

load_success, file_found, msg, config = pancake_config_loader.load_file(config_filename, config);

if load_success then
    pancake_update_config_file_if_needed(config);
else
    if not file_found then
        pancake_write_default_file(config_filename);
    else
        out("&&&& "..config_filename.." was found, but it could not be read perhaps due to an error in it.");
        out("&&&& The message: "..tostring(msg));
    end;
end;
