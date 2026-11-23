-- Velocity Chat Frames: the client interface. Flavour files implement exactly these methods;
-- Client_Select.lua binds the right one onto NS.Client. Never branch on flavour at a use site.
local ADDON_NAME, NS = ...

local Client = {}
NS.Client = Client
NS.ClientFlavours = {}

Client.INTERFACE = {
  "PlayerKey",            -- UnitGUID("player")
  "PlayerDisplayName",    -- Era "Kuro"; Forever "Kuro Oakheart"
  "PlayerFirstName",      -- UnitName("player"): what chat sender names compare against
  "TabRestAlpha",         -- (tab, isSelected) -> the stock no-mouse alpha for that tab
}