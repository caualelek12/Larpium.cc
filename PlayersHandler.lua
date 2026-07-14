local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera

local CalculationHandler = getgenv().CalculationHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/CalculationHandler.lua"))()
getgenv().CalculationHandler = CalculationHandler

local PlayersHandlers = {}

PlayersHandlers.Version = "2026-07-14-attribute-discovery"
PlayersHandlers.Characters = {}
PlayersHandlers.Connections = {}
PlayersHandlers.PlayerConnections = {}

local IMPORTANT_ALIASES = {
    MaxHealth = { "maxhealth", "healthmax", "maximumhealth", "maxhp", "hpmax" },
    Health = { "health", "currenthealth", "hitpoints", "currenthp", "hp" },
    MaxStamina = { "maxstamina", "staminamax", "maximumstamina" },
    Stamina = { "stamina", "currentstamina" },
    MaxShield = { "maxshield", "shieldmax", "maximumshield" },
    Shield = { "shield", "currentshield", "overshield" },
    MaxArmor = { "maxarmor", "armormax", "maximumarmor", "maxarmour", "armourmax" },
    Armor = { "armor", "currentarmor", "armour", "currentarmour" },
    MaxEnergy = { "maxenergy", "energymax", "maximumenergy" },
    Energy = { "energy", "currentenergy" },
    MaxMana = { "maxmana", "manamax", "maximummana" },
    Mana = { "mana", "currentmana" },
    Hunger = { "hunger", "food" },
    Thirst = { "thirst", "hydration" },
}

local IMPORTANT_ORDER = {
    "MaxHealth", "Health", "MaxStamina", "Stamina", "MaxShield", "Shield",
    "MaxArmor", "Armor", "MaxEnergy", "Energy", "MaxMana", "Mana", "Hunger", "Thirst",
}

local function normalizeName(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function safeFullName(instance)
    local ok, result = pcall(instance.GetFullName, instance)
    return ok and result or instance.Name
end

local function addConnection(connection, bucket)
    table.insert(bucket or PlayersHandlers.Connections, connection)
    return connection
end

local function disconnectAll(connections)
    for _, connection in ipairs(connections or {}) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)
end

local function detectImportant(attributeName)
    local normalized = normalizeName(attributeName)
    local simplified = normalized
        :gsub("^current", "")
        :gsub("^player", "")
        :gsub("^character", "")
        :gsub("value$", "")
        :gsub("amount$", "")
        :gsub("stat$", "")

    for _, canonical in ipairs(IMPORTANT_ORDER) do
        for _, alias in ipairs(IMPORTANT_ALIASES[canonical]) do
            if normalized == alias then
                return canonical, 100
            end
            if simplified == alias then
                return canonical, 90
            end
        end
    end

    for _, canonical in ipairs(IMPORTANT_ORDER) do
        for _, alias in ipairs(IMPORTANT_ALIASES[canonical]) do
            if #alias >= 5 and string.find(normalized, alias, 1, true) then
                return canonical, 50
            end
        end
    end

    return nil, 0
end

local function recordAttribute(data, source, name, value, sourceKind)
    local canonical, score = detectImportant(name)
    local record = {
        Name = name,
        NormalizedName = normalizeName(name),
        Value = value,
        Source = source,
        SourceKind = sourceKind,
        Path = safeFullName(source),
        ImportantName = canonical,
    }

    table.insert(data.Attributes, record)
    data.AttributesByName[name] = data.AttributesByName[name] or {}
    table.insert(data.AttributesByName[name], record)

    local normalized = record.NormalizedName
    data.AttributesByNormalizedName[normalized] = data.AttributesByNormalizedName[normalized] or {}
    table.insert(data.AttributesByNormalizedName[normalized], record)

    if canonical then
        local current = data.ImportantAttributes[canonical]
        local sourceBonus = source == data.Character and 20 or (sourceKind == "Character" and 10 or 0)
        record.MatchScore = score + sourceBonus
        if not current or record.MatchScore > (current.MatchScore or 0) then
            data.ImportantAttributes[canonical] = record
        end
    end
end

local function collectInstances(root, output, seen)
    if not root or seen[root] then return end
    seen[root] = true
    table.insert(output, root)

    local ok, descendants = pcall(root.GetDescendants, root)
    if ok then
        for _, descendant in ipairs(descendants) do
            if not seen[descendant] then
                seen[descendant] = true
                table.insert(output, descendant)
            end
        end
    end
end

local function scheduleRefresh(player)
    local data = PlayersHandlers.Characters[player]
    if not data or data.RefreshQueued then return end

    data.RefreshQueued = true
    task.defer(function()
        local current = PlayersHandlers.Characters[player]
        if current ~= data then return end
        data.RefreshQueued = false
        PlayersHandlers.RefreshAttributes(player)
    end)
end

function PlayersHandlers.RefreshAttributes(player)
    local data = PlayersHandlers.Characters[player]
    if not data then return nil end

    disconnectAll(data.AttributeConnections)
    data.Attributes = {}
    data.AttributesByName = {}
    data.AttributesByNormalizedName = {}
    data.ImportantAttributes = {}

    local instances = {}
    local seen = {}
    collectInstances(player, instances, seen)
    collectInstances(data.Character, instances, seen)

    if data.Character then
        addConnection(data.Character.DescendantAdded:Connect(function()
            scheduleRefresh(player)
        end), data.AttributeConnections)
        addConnection(data.Character.DescendantRemoving:Connect(function()
            scheduleRefresh(player)
        end), data.AttributeConnections)
    end

    for _, instance in ipairs(instances) do
        local sourceKind = data.Character and instance:IsDescendantOf(data.Character) and "Character" or "Player"
        local ok, attributes = pcall(instance.GetAttributes, instance)
        if ok then
            for name, value in pairs(attributes) do
                recordAttribute(data, instance, name, value, sourceKind)
            end
        end

        local attributeChanged = instance.AttributeChanged
        if attributeChanged then
            addConnection(attributeChanged:Connect(function()
                scheduleRefresh(player)
            end), data.AttributeConnections)
        end
    end

    local humanoid = data.Character and data.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        recordAttribute(data, humanoid, "Health", humanoid.Health, "HumanoidProperty")
        recordAttribute(data, humanoid, "MaxHealth", humanoid.MaxHealth, "HumanoidProperty")
        addConnection(humanoid.HealthChanged:Connect(function()
            scheduleRefresh(player)
        end), data.AttributeConnections)
        addConnection(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
            scheduleRefresh(player)
        end), data.AttributeConnections)
    end

    data.AttributesUpdatedAt = os.clock()
    return data.Attributes, data.ImportantAttributes
end

local function setCharacter(player, character)
    local data = PlayersHandlers.Characters[player]
    if not data then
        data = {
            AttributeConnections = {},
            Attributes = {},
            AttributesByName = {},
            AttributesByNormalizedName = {},
            ImportantAttributes = {},
        }
        PlayersHandlers.Characters[player] = data
    end

    disconnectAll(data.AttributeConnections)
    data.Character = character
    PlayersHandlers.RefreshAttributes(player)
end

local function addPlayer(player)
    local playerConnections = {}
    PlayersHandlers.PlayerConnections[player] = playerConnections
    setCharacter(player, player.Character)

    addConnection(player.CharacterAdded:Connect(function(character)
        setCharacter(player, character)
    end), playerConnections)

    addConnection(player.CharacterRemoving:Connect(function(character)
        if CalculationHandler.InvalidateModelCache then
            CalculationHandler.InvalidateModelCache(character)
        end

        local data = PlayersHandlers.Characters[player]
        if data and data.Character == character then
            setCharacter(player, nil)
        end
    end), playerConnections)

    addConnection(player.DescendantAdded:Connect(function()
        scheduleRefresh(player)
    end), playerConnections)
    addConnection(player.DescendantRemoving:Connect(function()
        scheduleRefresh(player)
    end), playerConnections)
    addConnection(player.AttributeChanged:Connect(function()
        scheduleRefresh(player)
    end), playerConnections)
end

local function removePlayer(player)
    local data = PlayersHandlers.Characters[player]
    if data then
        disconnectAll(data.AttributeConnections)
    end
    disconnectAll(PlayersHandlers.PlayerConnections[player])
    PlayersHandlers.PlayerConnections[player] = nil
    PlayersHandlers.Characters[player] = nil
end

function PlayersHandlers.GetPlayer(player)
    return PlayersHandlers.Characters[player]
end

function PlayersHandlers.GetCharacter(player)
    local data = PlayersHandlers.Characters[player]
    return player.Character or (data and data.Character)
end

function PlayersHandlers.GetAttributes(player)
    local data = PlayersHandlers.Characters[player]
    return data and data.Attributes or {}
end

function PlayersHandlers.GetAttribute(player, name)
    local data = PlayersHandlers.Characters[player]
    if not data then return nil end
    local records = data.AttributesByName[name] or data.AttributesByNormalizedName[normalizeName(name)]
    local record = records and records[1]
    return record and record.Value, record
end

function PlayersHandlers.GetImportantAttributes(player)
    local data = PlayersHandlers.Characters[player]
    return data and data.ImportantAttributes or {}
end

function PlayersHandlers.GetStat(player, name, defaultValue)
    local data = PlayersHandlers.Characters[player]
    if not data then return defaultValue end

    local canonical = detectImportant(name)
    local record = data.ImportantAttributes[canonical or name]
    if record then return record.Value, record end

    local value, attribute = PlayersHandlers.GetAttribute(player, name)
    if attribute then return value, attribute end
    return defaultValue
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
    for player in pairs(PlayersHandlers.Characters) do
        removePlayer(player)
    end
    disconnectAll(PlayersHandlers.Connections)
    table.clear(PlayersHandlers.PlayerConnections)
    table.clear(PlayersHandlers.Characters)
end

for _, player in ipairs(Players:GetPlayers()) do
    addPlayer(player)
end

addConnection(Players.PlayerAdded:Connect(addPlayer))
addConnection(Players.PlayerRemoving:Connect(removePlayer))

return PlayersHandlers
