----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
--
-- pancake_battle_ui_handler
--
-- Original script author: Andrew Draper (paperpancake/paperpancake5)
-- You may use this in any mod that uses scripting. I just ask that you leave this comment in the script so that
-- other modders can know who to ask if they have questions, need updates, want to attribute the source, etc.
-- To use this in your mod:
--      1. Copy the file to your mod.
--      2. Change the name of the file.
--      3. Use require("your_filename_without_an_extension") at the top of your script that uses this script.
--      4. Refer to example usage by looking for the .lua file in this mod that calls require() near the top
--
-- I hope to add additional functionality in future updates.
-- If you have ideas, requests, or code you've written to improve this, send me a message.
--
----------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------------------------------------
--- @section Pancake Battle UI Handler
--- 
-------------------------------------------------------------------------------------------------------------------------------

local bm = get_bm();

if not pancake_battle_ui_handler then --put this in an if statement so there will only be one of these at a time

    pancake_battle_ui_handler = {
        is_popup_open = false,
        is_popup_listener_added = false,
    };

    --Don't put future functions in this if statement. This ensures you will have the functions you expect
    --at the cost of possibly recompiling some of the functions unnecessarily
    --If you want to avoid recompiling, then put the other functions in their own if statements, like below
end;

local function need_function(f)
    return not f or not is_function(f);
end;

if need_function(pancake_battle_ui_handler.popup_dismiss) then

    function pancake_battle_ui_handler:popup_dismiss()
        if self.is_popup_open then
            bm:close_advisor();
            self.is_popup_open = false;
        end;
    end;

end;


if need_function(pancake_battle_ui_handler.show_popup_msg) then

    --For this function, duration is optional. Without a numeric duration, the message will show indefinitely.
    --Note that this might be different from config settings, so use an intermediate function to call this
    function pancake_battle_ui_handler:show_popup_msg(popup_str, duration)

        if (not is_number(duration)) or duration > 0 then
            if self.is_popup_open then
                bm:remove_process("pancake_popup_dismiss");
            end;

            effect.advice(tostring(popup_str));
            self.is_popup_open = true;

            if duration and is_number(duration) then
                bm:callback(function() pancake_battle_ui_handler:popup_dismiss(); end, duration, "pancake_popup_dismiss");
            end;

            if not self.is_popup_listener_added then
                core:add_listener(
                    "pancake_popup_listener",
                    "ComponentLClickUp", 
                    function(context) return context.string == __advisor_progress_button_name; end,
                    function(context) self.is_popup_open = false; end, 
                    true --Listener should persist. We'll reuse this over and over, and it doesn't do anything if self.is_popup_open is false
                );
                
                self.is_popup_listener_added = true;
            end;
        end;
    end;
end;