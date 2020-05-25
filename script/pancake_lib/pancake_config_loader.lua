----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
--
-- pancake_config_loader
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
-- I might add additional functionality in future updates.
-- If you have ideas, requests, or code you've written to improve this, send me a message.
--
----------------------------------------------------------------------------------------------

if not pancake_config_loader then --put this in an if statement so there will only be one of these at a time
    pancake_config_loader = {};
end;

local function need_function(f)
    return not f or not is_function(f);
end;

if need_function(pancake_config_loader.file_exists) then --this just makes sure the function is only defined once

    function pancake_config_loader.file_exists(filename)
        -- see https://stackoverflow.com/a/4991602/1019330
        local f = io.open(filename,"r");
        if f ~= nil then io.close(f) return true; else return false; end;
    end;

end;

if need_function(pancake_config_loader.load_file) then

    --- Loads a config file from the /data/text/ folder as isolated lua code
    -- @param filename_to_load the name of the file to load, including any path and extension
    -- @param config_environment optional - a table to be used as the environment for the config
    --                                      This can be used to pass in default values for config settings
    --                                      For example, {my_num_setting = 12, my_str_setting = "Hello World"}
    -- @return success boolean
    -- @return file_was_found boolean false if the config file was not present or readable
    -- @return msg any error or warning message
    -- @return config_environment a table with the config_environment, altered by the config file if one was found
    --                            (for simple config files, this will just be key-value pairs of the variables set in the config file)
    function pancake_config_loader.load_file(filename_to_load, config_environment)

        if not is_string(filename_to_load) then
            local msg = "ERROR: pancake_config_loader.load_file called but supplied path [" .. tostring(path) .. "] is not a string";
            return false, false, msg, config_environment;
        end;

        if not config_environment then
            config_environment = {};
        elseif not is_table(config_environment) then
            local msg = "ERROR: pancake_config_loader.load_file() called but supplied config_environment is not a table.";
            return false, false, msg, config_environment;
        end;

        if not pancake_config_loader.file_exists(filename_to_load) then
            return false, false, "No config file was found", config_environment;
        else

            local loaded_function, load_err = loadfile(filename_to_load);

            --adapted from https://www.luafaq.org/#T1.32
            if not loaded_function then
                return false, true, load_err, config_environment;
            else
                --run the config file in its own environment
                --this environment gives the config file access to nothing as of now, since it should just be setting variables
                setfenv(loaded_function, config_environment);
                local success, pcall_msg = pcall(loaded_function); --this is where the config_environment can actually change
                return success, true, pcall_msg, config_environment;
            end;

        end;
    end;
end;

if need_function(pancake_config_loader.convert_to_ms) then

    ---@function convert_to_ms
    ---@desc This function can be called after you have the config environment set or loaded from the file (or with any table)
    --       converts seconds to milliseconds, rounded to the nearest 100 milliseconds
    --       negative and non-numeric values (except false) are converted to nil
    --@p value to convert
    --@p true_is_allowed is optional. It will leave a value of true unconverted
    --@return the converted value
    function pancake_config_loader.convert_to_ms(value, true_is_allowed)

        if value then
            if true_is_allowed and value == true then
                --leave value as is
            elseif not is_number(value) or value < 0 then
                value = nil;
            else
                --convert to milliseconds, rounded to nearest 100 milliseconds
                value = math.floor(math.floor(value * 10 + 0.5) * 100 + 0.5);
            end;
        end;

        return value;
    end;
end;