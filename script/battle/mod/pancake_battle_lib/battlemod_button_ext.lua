-- Script author: Andrew Draper (paperpancake/paperpancake5)

--[[ example usage:
require("battlemod_button_ext");
local bm = get_bm();

local function pancake_phase_startup()
    
    local uic_left = battlemod_button_ext:add_battle_order_button("left_test_1", true);
    --do other stuff with this button like setting images, etc
    local uic_other_right = battlemod_button_ext:add_battle_order_button("right_test_end", false);
    --do other stuff with this button like setting images, etc
    local uic_moar_example = battlemod_button_ext:add_battle_order_button("left_test_2", true);
    --do other stuff with this button like setting images, etc

end;

bm:register_phase_change_callback("Startup", function() pancake_phase_startup() end);
]]--

local bm = get_bm();

--just a helper method to avoid duplicate code
local function get_battle_orders_parent_width(uic_battle_orders_parent)
    local orders_parent_padding = 84; --the width of the unusable decorative area on each side (this is just a guess for now)
    return 2 * orders_parent_padding + uic_battle_orders_parent:Width();
end;

--[[
    battlemod_button_ext is not a real component; it just serves to keep track of information for components added
    to the pre-exisiting bottom bar component.
    battlemod_button_ext should be global, not local
    there should only be one of these button extenders, so no battlemod_button_ext:new() function is provided
--]]
if not battlemod_button_ext then
    local init_margin = 10; --This is a guess for now
    battlemod_button_ext = {
        small_button_margin = init_margin,
        right_side_width = init_margin, -- The width starts out with a button's margin on one side. As buttons are added, the margin on the other side is added
        left_side_width = init_margin,
        original_bottom_bar_width = -1,
        cached_card_panel_width = -1,
    };

    local init_right_width = battlemod_button_ext.right_side_width;
    local init_left_width = battlemod_button_ext.left_side_width;
    function battlemod_button_ext:has_components()
        return (self.right_side_width > init_right_width) or (self.left_side_width > init_left_width);
    end;

    --@p new_name
    --@p [add_to_left_side = false] defaults to false, adding to the right side instead
    --                  buttons are added starting closest to the center, so...
    --                  buttons added to the right side are added from left to right
    --                  buttons added to the left side are added from right to left
    --@p [button_type = "ui/templates/square_medium_button"] string indicating the type of button to create
    function battlemod_button_ext:add_battle_order_button(new_name, add_to_left_side, button_type)

        local new_button = nil;

        local uic_orders_pane = find_uicomponent(core:get_ui_root(), "layout", "battle_orders", "battle_orders_pane");
        if uic_orders_pane then

            local uic_bottom_bar = find_uicomponent(uic_orders_pane, "bottom_bar");
            if uic_bottom_bar then

                local uic_battle_orders_parent = find_uicomponent(uic_orders_pane, "orders_parent");
                if uic_battle_orders_parent then

                    if not (button_type and is_string(button_type)) then
                        button_type = "ui/templates/square_medium_button";
                    end;

                    new_button = UIComponent(uic_bottom_bar:CreateComponent(new_name, button_type));

                    -- dock the new button
                    local orders_parent_width = get_battle_orders_parent_width(uic_battle_orders_parent);
                    local x_offset = math.floor(orders_parent_width/2 + 0.5);
                    if add_to_left_side then
                        x_offset = -1 * (x_offset + self.left_side_width + self.small_button_margin);
                        self.left_side_width = self.left_side_width + self.small_button_margin + new_button:Width();
                    else
                        x_offset = x_offset + self.right_side_width + self.small_button_margin;
                        self.right_side_width = self.right_side_width + self.small_button_margin + new_button:Width();
                    end;

                    new_button:SetDockingPoint(8); --DOCK_POINT_BC for bottom-center docking
                    new_button:SetDockOffset(x_offset, 0);

                    self:refresh_layout();
                end;
            end;
        end;

        return new_button;
    end;

    function battlemod_button_ext:refresh_layout()

        local uic_orders_pane = find_uicomponent(core:get_ui_root(), "layout", "battle_orders", "battle_orders_pane");

        if uic_orders_pane then
            local uic_bottom_bar = find_uicomponent(uic_orders_pane, "bottom_bar");
            local uic_battle_orders_parent = find_uicomponent(uic_orders_pane, "orders_parent");

            if uic_bottom_bar and uic_battle_orders_parent then

                local orders_parent_width = get_battle_orders_parent_width(uic_battle_orders_parent);

                --bottom_bar (the wider visual part)
                --With big armies, this could be already big enough if the player's army is large, since the bottom bar stretches under all the unit cards, too.
                local old_bottom_width = uic_bottom_bar:Width();
                if self.original_bottom_bar_width < 0 then
                    self.original_bottom_bar_width = old_bottom_width;
                end;
                local button_holder_on_right = find_uicomponent(uic_bottom_bar, "button_holder");
                local room_on_right = 0;
                if button_holder_on_right then
                    room_on_right = button_holder_on_right:Width();
                end;
                local bottom_bar_image_padding = 200; --the width of the button bar that is decorative only (this is just a guess for now)
                local total_mod_extension_width = 2*math.max(self.left_side_width, self.right_side_width);

                local middle_stuff_width = orders_parent_width + total_mod_extension_width + room_on_right;

                --check that the bottom bar is also the right size as the card panel's width changes 
                local uic_card_panel = find_uicomponent(uic_orders_pane, "card_panel_docker", "cards_panel");
                if uic_card_panel then
                    self.cached_card_panel_width = uic_card_panel:Width();
                    if self.cached_card_panel_width > middle_stuff_width then
                        middle_stuff_width = self.cached_card_panel_width;
                    end;
                end;

                local min_bottom_bar_width = bottom_bar_image_padding + middle_stuff_width;

                if min_bottom_bar_width ~= old_bottom_width then
                    local old_bottom_height = uic_bottom_bar:Height();
                    --this is needed to correctly position the built-in button that hides unit cards
                    uic_bottom_bar:SetCanResizeWidth(true);
                    uic_bottom_bar:Resize(min_bottom_bar_width, old_bottom_height, false);
                    
                     --Setting CanResize to false prevents reinforcements from resizing the bottom bar, which isn't great,
                     --but without it, our buttons get resized, too
                     --the fix is probably to just straight up make this whole thing its own component,
                     --but I'm not sure of the best way to do that.
                     --What filepath would I give to uicomponent:CreateComponent()?
                     --Is there a way to see the code inside ui template files
                    uic_bottom_bar:SetCanResizeWidth(false);

                end;

                uic_bottom_bar:Layout();
            end;
        end;
    end;

    local function battlemod_phase_deployed()
    
        --periodically check to see if the bottom bar needs to be resized
        --this is normally done by the game, but the layout changes we make somehow stop this from happening
        --so we need to do it ourselves
        bm:repeat_callback(
            function()

                if battlemod_button_ext:has_components() then
                    local uic_card_panel = find_uicomponent(core:get_ui_root(), "layout", "battle_orders",
                                                            "battle_orders_pane", "card_panel_docker", "cards_panel");

                    if uic_card_panel then
                        local current_card_panel_width = uic_card_panel:Width();
                        if current_card_panel_width ~= battlemod_button_ext.cached_card_panel_width then
                            battlemod_button_ext:refresh_layout();
                        end;
                    end;
                end;
            end,
            400,
            "battlemod_check_for_resized_cards_panel"
        );
    
    end;
    
    bm:register_phase_change_callback("Deployed", battlemod_phase_deployed);
end;