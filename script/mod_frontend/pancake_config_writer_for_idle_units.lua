
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

no_ping_icon_for_next_unit = false
no_camera_pan_for_next_unit = false


---------------------------------------------------------------------------------------------

-- The "Find All Idle Units" toggle is normally off at the beginning of a battle.
-- If you want it to turn on automatically each battle, then change the value to be
-- the number of seconds to wait before turning on (decimals are allowed).
-- You can use 0 to have it turn on immediately
-- If you use a hotkey to turn this on even sooner in a battle, this will be ignored
-- Use false or a negative number to leave it turned off until you use a hotkey

toggle_on_automatically_after = false

---------------------------------------------------------------------------------------------
-- The following settings are placeholders
-- They won't do anything until future updates

add_button_to_exclude_unit = false
use_hotkey_to_exclude_unit = false

-- These don't do anything unless one of the exclude settings above is true
include_again_if_new_ability = false
include_again_if_new_spell = false
include_again_if_mana_is_at_least = 25
include_again_if_gates_break = false
]]

local function file_exists(filename)
    -- see https://stackoverflow.com/a/4991602/1019330
    local f = io.open(filename,"r")
    if f ~= nil then io.close(f) return true else return false end
end

--check for file_exists before calling this function, if appropriate
local function pancake_write_default_file(filename)

    local file, err_str = io.open(filename, "w");
    if file then
        file:write(pancake_default_config_text);
        file:close();
        out("&&&& created default config file: "..filename);
    else
        out("&&&& pancake could not write the config file. Perhaps the folder doesn't exist.\n"..tostring(err_str));
    end;
end;

local filename = "./mod_config/find_idle_units_config.txt";

if file_exists(filename) then
    out("&&&& "..filename.." found.");
else
    pancake_write_default_file(filename);
end;