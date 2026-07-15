-- Replace these two values, then execute this file after your character has spawned.
local BASE_URL = "https://your-domain.example"
local PAIR_CODE = "LRP-UI-XXXXXXXX"

local WebsiteUIBridge = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/WebsiteUIBridge.lua"
))()

local bridge = WebsiteUIBridge.new({
    BaseUrl = BASE_URL,
    PairCode = PAIR_CODE,
    PollInterval = 1,
})

local ok, result = bridge:PublishLocalCharacter({ MaxParts = 160 })
if not ok then
    error("Model publish failed: " .. tostring(result))
end

bridge:StartModelStreaming(function()
    local player = game:GetService("Players").LocalPlayer
    return player and player.Character
end, 10, { MaxParts = 160 })

bridge:Start()
print("LocalPlayer model streaming to the ESP designer.")
