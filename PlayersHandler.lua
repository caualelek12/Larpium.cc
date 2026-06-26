local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera

local CalculationHandler = getgenv().CalculationHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/CalculationHandler.lua"))()
getgenv().CalculationHandler = CalculationHandler

local PlayersHandlers = {}

PlayersHandlers.Characters = {}
PlayersHandlers.Connections = {}

local function setCharacter(player, character)
    PlayersHandlers.Characters[player] = {
        Character = character,
    }
end

local function addConnection(connection)
    table.insert(PlayersHandlers.Connections, connection)
    return connection
end

local function addPlayer(player)
    if player.Character then
        setCharacter(player, player.Character)
    end

    addConnection(player.CharacterAdded:Connect(function(character)
        setCharacter(player, character)
    end))
end

local function removePlayer(player)
    PlayersHandlers.Characters[player] = nil
end

function PlayersHandlers.GetCharacter(player)
    local data = PlayersHandlers.Characters[player]
    return data and data.Character or player.Character
end

function PlayersHandlers.Update2DPositions()
    Camera = workspace.CurrentCamera

    for player, data in pairs(PlayersHandlers.Characters) do
        local character = player.Character or data.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if root then
            local position, visible, depth = CalculationHandler.WorldToScreen(root.Position, Camera)
            data.Char2dpos = position
            data.CharOnScreen = visible
            data.CharDepth = depth
        else
            data.Char2dpos = nil
            data.CharOnScreen = false
            data.CharDepth = nil
        end
    end
end

PlayersHandlers.update2dPositions = PlayersHandlers.Update2DPositions

function PlayersHandlers.Cleanup()
    for _, connection in ipairs(PlayersHandlers.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(PlayersHandlers.Connections)
    table.clear(PlayersHandlers.Characters)
end

for _, player in ipairs(Players:GetPlayers()) do
    addPlayer(player)
end

addConnection(Players.PlayerAdded:Connect(addPlayer))
addConnection(Players.PlayerRemoving:Connect(removePlayer))

return PlayersHandlers