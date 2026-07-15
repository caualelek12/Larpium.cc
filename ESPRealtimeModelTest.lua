-- Replace these two values, then execute this file after your character has spawned.
local BASE_URL = "https://larpium.dedyn.io:45916"
local PAIR_CODE = "LRP-UI-XXXXXXXX"

local WebsiteUIBridge = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/WebsiteUIBridge.lua"
))()

local bridge = WebsiteUIBridge.new({
    BaseUrl = BASE_URL,
    PairCode = PAIR_CODE,
    PollInterval = 1,
})

local ok, result = bridge:PublishLocalCharacter({ MaxParts = 160, CacheAssets = true })
if not ok then
    error("Model publish failed: " .. tostring(result))
end

local cache = result.assetCache or {}
print(string.format(
    "Model uploaded: %d parts. Assets requested: %d, cached: %d, failed: %d.",
    tonumber(result.parts) or 0,
    tonumber(cache.requested) or 0,
    #(cache.cached or {}),
    #(cache.failed or {})
))
if cache.error then warn("Asset cache test failed: " .. tostring(cache.error)) end
for _, failure in ipairs(cache.failed or {}) do
    warn("Asset " .. tostring(failure.assetId) .. " failed: " .. tostring(failure.error))
end

bridge:StartModelStreaming(function()
    local player = game:GetService("Players").LocalPlayer
    return player and player.Character
end, 10, { MaxParts = 160, CacheAssets = false })

bridge:Start()
print("LocalPlayer model streaming to the ESP designer.")
