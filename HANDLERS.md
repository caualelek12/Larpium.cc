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

Staff creates groups and controls under `Web UI`. Buyer-access users open the same page, click `Pair Game`, and use the one-time code in the bridge. Buyer-access users can edit and save their own ESP layout; project controls and custom element definitions remain developer-managed.

```lua
local WebsiteUIBridge = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/WebsiteUIBridge.lua"
))()

local bridge = WebsiteUIBridge.new({
    BaseUrl = "https://larpium.dedyn.io:45916",
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

## Website ESP designer

Buyer-access users can open `Web UI` and switch to `ESP Designer`. The game can publish a character model for the rotatable preview, while the saved box, health bar, skeleton, head circle, and text placements are applied through the existing ESP handler.

```lua
local Players = game:GetService("Players")

bridge:BindEspHandler(EspHandler, "Players", true)

-- Publish once when opening the designer.
bridge:PublishLocalCharacter({ CacheAssets = true })

-- Or keep the preview current while characters respawn/change.
bridge:StartModelStreaming(function()
    return Players.LocalPlayer.Character
end, 20)

bridge:Start()
```

`PublishModel` sends sanitized visual part data, full part rotation matrices, MeshPart and SpecialMesh references, SpecialMesh scale/offset/tint, accessory metadata, Decal and Texture children, shirt/pants/T-shirt templates, SurfaceAppearance maps, material data, and Motor6D connections. With `CacheAssets = true`, the paired device asks the server to cache up to 80 unique character asset IDs found in that exact snapshot. The ESP designer decodes supported Roblox FileMesh versions and applies cached images only to matching mesh UVs. Ordinary parts can fall back to Roblox size, shape, and color data; an accessory whose mesh is unavailable is omitted and reported instead of being shown as a misleading textured box. The Roblox security cookie remains server-side and is never sent to the game. Scripts, attributes, object values, and arbitrary executable instances are not uploaded. The skeleton is generated from those connections and cannot be repositioned independently. The preview expires from server memory when updates stop. `EspHandler.ApplyLayout(layout, groupName)` can also apply an exported layout directly without using the bridge.

ESP elements use ordered `Top`, `Bottom`, `Left`, and `Right` slots. Box, skeleton, and head-circle geometry stay attached to the projected character. Developers can connect a custom website element to runtime behavior without changing the handler:

```lua
EspHandler.RegisterLayoutElement("armor", function(settings, element, options)
    settings.Texts.State = {
        Enabled = element.enabled ~= false,
        Anchor = element.side or "Right",
        Order = tonumber(element.order) or 0,
        Color = Color3.fromHex((options.color or "#ffffff"):gsub("#", "")),
        Text = function(player)
            return "Armor: " .. tostring(player:GetAttribute("Armor") or 0)
        end,
    }
end)
```

`ESPRealtimeModelTest.lua` is a LocalPlayer model-and-asset test. Set its HTTPS site URL and one-time pairing code before running it. The first upload prints part, requested asset, cached asset, and failed asset counts and warns when the character exposes no downloadable IDs; later streaming uploads avoid repeatedly downloading the same assets.

The pairing code is single-use and expires after ten minutes. The saved device token is scoped to one account and one UI project; rank or access removal is checked again on every poll. HTTP deployments are supported, but device tokens travel without transport encryption until the site is moved behind HTTPS.
