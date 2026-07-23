-- Replace these two values, then execute this file after your character has spawned.
local BASE_URL = "https://larpium.dedyn.io:45916"
local PAIR_CODE = "LRP-UI-XXXXXXXX"
local MODEL_TO_PUBLISH = nil -- Example: workspace.NPCs.Guard or workspace.Loot.Crate

local WebsiteUIBridge = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/caualelek12/Larpium.cc/aa99aecf4aa4e9c8163f6d5a0e5d09b2e2199a9e/WebsiteUIBridge.lua"
))()

local bridge = WebsiteUIBridge.new({
    BaseUrl = BASE_URL,
    PairCode = PAIR_CODE,
    PollInterval = 1,
})

local publishOptions = {
    MaxParts = 160,
    MaxTriangles = 80000,
    MaxTrianglesPerPart = 30000,
    IncludeGeometry = true,
    CacheAssets = true,
    StaticPose = true,
}
local ok, result
if MODEL_TO_PUBLISH then
    ok, result = bridge:PublishModel(MODEL_TO_PUBLISH, publishOptions)
else
    ok, result = bridge:PublishLocalCharacter(publishOptions)
end
if not ok then
    error("Model publish failed: " .. tostring(result))
end

local cache = result.assetCache or {}
print("WebsiteUIBridge version: " .. tostring(WebsiteUIBridge.Version))
print(string.format(
    "Model uploaded: %d parts, %d streamed triangles, %d deformed parts, %d CharacterMesh parts, %d mesh proxies, %d CSG proxies. Assets requested: %d, cached: %d, failed: %d.",
    tonumber(result.parts) or 0,
    tonumber(result.geometryTriangles) or 0,
    tonumber(result.deformedParts) or 0,
    tonumber(result.characterMeshParts) or 0,
    tonumber(result.meshProxies) or 0,
    tonumber(result.csgProxies) or 0,
    tonumber(cache.requested) or 0,
    #(cache.cached or {}),
    #(cache.failed or {})
))
if cache.error then warn("Asset cache test failed: " .. tostring(cache.error)) end
if (tonumber(cache.requested) or 0) == 0 then
    warn("The character exposed no mesh or texture asset IDs. The preview will use part geometry and colors only.")
end
for _, failure in ipairs(cache.failed or {}) do
    warn("Asset " .. tostring(failure.assetId) .. " failed: " .. tostring(failure.error))
end

bridge:Start()
print("Static LocalPlayer model published to the ESP designer.")
