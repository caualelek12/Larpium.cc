# Larpium Handlers

## Player attributes

`PlayersHandler` scans the Player, Character, and their descendants. Attribute changes, new descendants, removals, and respawns update the cache automatically.

```lua
local data = PlayersHandler.GetPlayer(player)
local stamina = PlayersHandler.GetStat(player, "Stamina", 0)
local health, healthSource = PlayersHandler.GetStat(player, "Health", 0)

for _, attribute in ipairs(PlayersHandler.GetAttributes(player)) do
    print(attribute.Name, attribute.Value, attribute.Path)
end

for statName, attribute in pairs(PlayersHandler.GetImportantAttributes(player)) do
    print(statName, attribute.Value, attribute.Source)
end
```

Detected stat families include health, stamina, shield, armor, energy, mana, hunger, thirst, and their maximum values. The original `PlayersHandler.Characters[player]` fields remain compatible.

## Simple ESP

The complete low-level API still exists. New scripts can use the shorter facade:

```lua
local esp = EspHandler.Create({
    Preset = "Standard", -- Minimal, Standard, or Detailed
    TeamCheck = true,
    MaxDistance = 1500,
    BoxType = "Corner",
    Weapon = true,
})

esp:SetFeature("Skeleton", true)
esp:Set({ Color = Color3.fromRGB(255, 60, 80), TextSize = 11 })
esp:Disable()
esp:Enable()
```

One-line usage:

```lua
EspHandler.Create({ Preset = "Standard" })
```

## Website controls

Staff creates groups and controls under `Web UI`. Buyer-access users open the same page, click `Pair Game`, and use the one-time code in the bridge. The editor is never returned to non-staff accounts.

```lua
local WebsiteUIBridge = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/WebsiteUIBridge.lua"
))()

local bridge = WebsiteUIBridge.new({
    BaseUrl = "http://your-domain.example:45916",
    PairCode = "LRP-UI-XXXXXXXX",
    PollInterval = 1,
})

-- Automatically calls EspHandler.SetEnabled(true/false).
bridge:BindFeature("esp_enabled", EspHandler, true)

bridge:BindValue("esp_distance", function(distance)
    EspHandler.Configure({ MaxDistance = distance })
end, true)

bridge:BindButton("refresh_players", function()
    PlayersHandler.Update2DPositions()
end)

bridge:BindToggle("aim_enabled", enableAim, disableAim, true)

bridge:OnConnection(function(connected)
    print("Web UI connected:", connected)
end, true)

bridge:Start()
```

`BindFeature` accepts a module with `SetEnabled(boolean)` or a controller with `Enable()` and `Disable()`. `BindValue` handles sliders and dropdowns, `BindToggle` handles toggles and checkboxes, and `BindButton` runs once per website click.

The pairing code is single-use and expires after ten minutes. The saved device token is scoped to one account and one UI project; rank or access removal is checked again on every poll. HTTP deployments are supported, but device tokens travel without transport encryption until the site is moved behind HTTPS.
