local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera


local PlayersHandlers = {}

PlayersHandlers.Characters = {}

local function setCharacter(player, character)
        PlayersHandlers.Characters[player] = {
        Character = character
    }
end

local function addPlayer(player)
    if player.Character then
        setCharacter(player, player.Character)
    end

    player.CharacterAdded:Connect(function(character)
        setCharacter(player, character)
    end)
end

local function removePlayer(player)
    PlayersHandlers.Characters[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
    task.defer(addPlayer, player)
end

function PlayersHandlers.update2dPositions()

    for Player , Data in ipairs(PlayersHandlers.Characters) do
        if Player.Character or Data.Character then
            local Char = Player.Character or Data.Character
            local root = Char and Char:FindFirstChild("HumanoidRootPart")
            local Char2dpos , CharOnScreen = Camera:WorldToScreenPoint(root.Position)

            Data.Char2dpos = Char2dpos
            Data.CharOnScreen = CharOnScreen

        end
    end
    
end

Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(removePlayer)

return PlayersHandlers
