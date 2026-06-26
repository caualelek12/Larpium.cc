local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera

local PlayersHandler = getgenv().PlayersHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/PlayersHandler.lua"))()
local DrawingHelp = getgenv().DrawingHelp or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/DrawingHelp.lua"))()
local CalculationHandler = getgenv().CalculationHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/CalculationHandler.lua"))()
getgenv().PlayersHandler = PlayersHandler
getgenv().DrawingHelp = DrawingHelp
getgenv().CalculationHandler = CalculationHandler

local EspHandler = {}

EspHandler.Enabled = false
EspHandler.Connections = {}
EspHandler.Running = {}
EspHandler.Objects = {}
EspHandler.ObjectIds = setmetatable({}, { __mode = "k" })
EspHandler.NextObjectId = 0
EspHandler.Settings = {
    Players = {
        Enabled = true,
        TeamCheck = false,
        HealthCheck = true,
        MaxDistance = 5000,

        Box = {
            Enabled = true,
            Type = "Corner", -- Square / Corner
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 4,
            CornerSize = 12,
        },

        HeadCircle = {
            Enabled = false,
            Color = Color3.fromRGB(255, 255, 255),
            Radius = 8,
            Thickness = 1,
            Filled = false,
        },

        Skeleton = {
            Enabled = false,
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 2,
            Transparency = 1,
        },
        Health = {
            Enabled = true,
            Side = "Left", -- Left / Right / Top / Bottom
            Width = 4,
            Color = Color3.fromRGB(255, 50, 50),
            LowColor = Color3.fromRGB(255, 60, 60),
            BackgroundColor = Color3.fromRGB(30, 30, 30),
            Gap = 1,
            TextGap = 1,
            ReserveTextSpace = false,
            Length = nil, -- nil = auto scale to box height/width
            Text = {
                Enabled = true,
                Format = "Percent", -- Percent / Value / Custom function
                Color = Color3.fromRGB(255, 255, 255),
                Size = 10,
                Font = nil,
                Width = 24,
                Outline = true,
            },
        },

        Texts = {
            Name = {
                Enabled = true,
                Anchor = "Right",
                AttachTo = "HealthBar",
                Text = function(player)
                    return player.Name
                end,
                Color = Color3.fromRGB(255, 255, 255),
                Size = 10,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 1,
            },

            Distance = {
                Enabled = true,
                Anchor = "Right",
                AttachTo = "HealthBar",
                Text = function(_, _, info)
                    return tostring(math.floor(info.Distance)) .. "m"
                end,
                Color = Color3.fromRGB(200, 200, 200),
                Size = 10,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 2,
            },

            Weapon = {
                Enabled = false,
                Anchor = "Right",
                AttachTo = "HealthBar",
                Text = function(_, character)
                    local tool = character and character:FindFirstChildOfClass("Tool")
                    return tool and tool.Name or "None"
                end,
                Color = Color3.fromRGB(255, 220, 120),
                Size = 10,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 3,
            },

            State = {
                Enabled = false,
                Anchor = "Right",
                AttachTo = "HealthBar",
                Text = function(_, character)
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    return humanoid and humanoid:GetState().Name or "Unknown"
                end,
                Color = Color3.fromRGB(160, 220, 255),
                Size = 10,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 4,
            },
        },
    },
}

local LocalPlayer = Players.LocalPlayer
local DEFAULT_ESP = "Players"

local function getGroup(espName)
    espName = espName or DEFAULT_ESP
    DrawingHelp.DrawCaches[espName] = DrawingHelp.DrawCaches[espName] or {}
    EspHandler.Settings[espName] = EspHandler.Settings[espName] or { Enabled = true }
    return espName
end

local function mergeTable(base, changes)
    if type(base) ~= "table" or type(changes) ~= "table" then return base end

    for key, value in pairs(changes) do
        if type(value) == "table" and type(base[key]) == "table" then
            mergeTable(base[key], value)
        else
            base[key] = value
        end
    end

    return base
end

local function getObjectId(object)
    local objectType = type(object)

    if objectType == "string" or objectType == "number" then
        return tostring(object)
    end

    if objectType == "table" or objectType == "userdata" then
        if EspHandler.ObjectIds[object] then
            return EspHandler.ObjectIds[object]
        end

        EspHandler.NextObjectId = EspHandler.NextObjectId + 1
        local id = "Object_" .. tostring(EspHandler.NextObjectId)
        EspHandler.ObjectIds[object] = id
        return id
    end

    return tostring(object)
end

local function drawName(espName, objectId, element)
    return getObjectId(objectId) .. "_" .. tostring(element)
end

local function createDraw(espName, objectId, element, drawType)
    espName = getGroup(espName)

    local name = drawName(espName, objectId, element)
    local cache = DrawingHelp.DrawCaches[espName]
    if cache[name] then return cache[name], name end

    local drawing = DrawingHelp.CreateDrawing(drawType, name, espName)
    return drawing, name
end

local function updateDraw(espName, objectId, element, properties)
    espName = getGroup(espName)
    return DrawingHelp.UpdateDraw(drawName(espName, objectId, element), espName, properties)
end

local function removeDraw(espName, objectId, element)
    espName = getGroup(espName)

    local cache = DrawingHelp.DrawCaches[espName]
    local name = drawName(espName, objectId, element)
    local drawing = cache[name]
    if not drawing then return end

    drawing.Visible = false
    drawing:Remove()
    cache[name] = nil
end

local function hideObject(espName, objectId)
    espName = getGroup(espName)

    local prefix = getObjectId(objectId) .. "_"
    for name, drawing in pairs(DrawingHelp.DrawCaches[espName]) do
        if string.sub(name, 1, #prefix) == prefix then
            drawing.Visible = false
        end
    end
end

local function removeObject(espName, objectId)
    espName = getGroup(espName)

    local prefix = getObjectId(objectId) .. "_"
    for name, drawing in pairs(DrawingHelp.DrawCaches[espName]) do
        if string.sub(name, 1, #prefix) == prefix then
            drawing.Visible = false
            drawing:Remove()
            DrawingHelp.DrawCaches[espName][name] = nil
        end
    end
end

local function hideGroup(espName)
    espName = getGroup(espName)

    for _, drawing in pairs(DrawingHelp.DrawCaches[espName]) do
        drawing.Visible = false
    end
end

local function removeGroup(espName)
    espName = getGroup(espName)

    for name, drawing in pairs(DrawingHelp.DrawCaches[espName]) do
        drawing.Visible = false
        drawing:Remove()
        DrawingHelp.DrawCaches[espName][name] = nil
    end
end

local function ensureRenderLoop()
    if EspHandler.Connections.Render then return end

    EspHandler.Connections.Render = RunService.RenderStepped:Connect(function()
        EspHandler.Update()
    end)
end

local function stopRenderLoop()
    if not EspHandler.Connections.Render then return end

    EspHandler.Connections.Render:Disconnect()
    EspHandler.Connections.Render = nil
end

local function hasRunningGroups()
    for _ in pairs(EspHandler.Running) do
        return true
    end

    return false
end

local function anchorPosition(position, size, anchor, offset)
    return CalculationHandler.AnchorPosition(position, size, anchor, offset)
end

local function getBox(character)
    return CalculationHandler.GetModelScreenBox(character, Camera, {
        ClampPadding = 0,
        MaxViewportScale = 0.9,
        MinSize = 2,
    })
end
local function updateCornerBox(espName, objectId, position, size, boxSettings)
    local thickness = boxSettings.Thickness or 1
    local color = boxSettings.Color or Color3.fromRGB(255, 255, 255)
    local corner = math.min(boxSettings.CornerSize or 12, size.X / 2, size.Y / 2)

    local lines = {
        { "TL_H", position, Vector2.new(position.X + corner, position.Y) },
        { "TL_V", position, Vector2.new(position.X, position.Y + corner) },
        { "TR_H", Vector2.new(position.X + size.X, position.Y), Vector2.new(position.X + size.X - corner, position.Y) },
        { "TR_V", Vector2.new(position.X + size.X, position.Y), Vector2.new(position.X + size.X, position.Y + corner) },
        { "BL_H", Vector2.new(position.X, position.Y + size.Y), Vector2.new(position.X + corner, position.Y + size.Y) },
        { "BL_V", Vector2.new(position.X, position.Y + size.Y), Vector2.new(position.X, position.Y + size.Y - corner) },
        { "BR_H", Vector2.new(position.X + size.X, position.Y + size.Y), Vector2.new(position.X + size.X - corner, position.Y + size.Y) },
        { "BR_V", Vector2.new(position.X + size.X, position.Y + size.Y), Vector2.new(position.X + size.X, position.Y + size.Y - corner) },
    }

    for _, line in ipairs(lines) do
        createDraw(espName, objectId, "Box_" .. line[1], "Line")
        updateDraw(espName, objectId, "Box_" .. line[1], {
            Visible = true,
            From = line[2],
            To = line[3],
            Color = color,
            Thickness = thickness,
        })
    end

    updateDraw(espName, objectId, "Box", { Visible = false })
end

local function updateSquareBox(espName, objectId, position, size, boxSettings)
    createDraw(espName, objectId, "Box", "Square")
    updateDraw(espName, objectId, "Box", {
        Visible = true,
        Position = position,
        Size = size,
        Color = boxSettings.Color or Color3.fromRGB(255, 255, 255),
        Thickness = boxSettings.Thickness or 1,
        Filled = false,
    })

    for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
        updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
    end
end

local function estimateTextWidth(text, size)
    return CalculationHandler.EstimateTextWidth(text, size)
end

local function formatHealthText(health, maxHealth, healthPercent, textSettings)
    if type(textSettings.Format) == "function" then
        return textSettings.Format(health, maxHealth, healthPercent)
    elseif textSettings.Format == "Value" then
        return tostring(math.floor(health)) .. "/" .. tostring(math.floor(maxHealth))
    end

    return tostring(math.floor(healthPercent * 100)) .. "%"
end

local function updateHealthValue(espName, objectId, position, size, health, maxHealth, settings)
    settings = settings or {}
    if settings.Enabled == false or not health or not maxHealth or maxHealth <= 0 then
        updateDraw(espName, objectId, "HealthBG", { Visible = false })
        updateDraw(espName, objectId, "Health", { Visible = false })
        updateDraw(espName, objectId, "HealthText", { Visible = false })
        return 0, nil
    end

    local healthPercent = math.clamp(health / maxHealth, 0, 1)
    local side = settings.Side or "Left"
    local isHorizontal = side == "Top" or side == "Bottom"
    local thickness = settings.Thickness or settings.Width or 4
    local gap = settings.Gap or 1
    local textGap = settings.TextGap or 1
    local bgPosition
    local bgSize
    local fillPosition
    local fillSize

    if isHorizontal then
        local fullWidth = settings.Length or size.X
        local fillWidth = fullWidth * healthPercent
        local barX = position.X + (size.X - fullWidth) / 2
        local barY = side == "Top" and position.Y - thickness - gap or position.Y + size.Y + gap

        bgPosition = Vector2.new(barX, barY)
        bgSize = Vector2.new(fullWidth, thickness)
        fillPosition = Vector2.new(barX, barY)
        fillSize = Vector2.new(fillWidth, thickness)
    else
        local fullHeight = settings.Length or size.Y
        local fillHeight = fullHeight * healthPercent
        local barX = side == "Right" and position.X + size.X + gap or position.X - thickness - gap
        local barY = position.Y + (size.Y - fullHeight) / 2

        bgPosition = Vector2.new(barX, barY)
        bgSize = Vector2.new(thickness, fullHeight)
        fillPosition = Vector2.new(barX, barY + fullHeight - fillHeight)
        fillSize = Vector2.new(thickness, fillHeight)
    end

    createDraw(espName, objectId, "HealthBG", "Square")
    createDraw(espName, objectId, "Health", "Square")

    updateDraw(espName, objectId, "HealthBG", {
        Visible = true,
        Position = bgPosition,
        Size = bgSize,
        Color = settings.BackgroundColor or Color3.fromRGB(30, 30, 30),
        Filled = true,
    })

    updateDraw(espName, objectId, "Health", {
        Visible = true,
        Position = fillPosition,
        Size = fillSize,
        Color = healthPercent > 0.35 and (settings.Color or Color3.fromRGB(255, 50, 50)) or (settings.LowColor or Color3.fromRGB(255, 60, 60)),
        Filled = true,
    })

    local reserve = isHorizontal and 0 or (thickness + gap)
    local reserveSide = isHorizontal and nil or side
    local textSettings = settings.Text or {}
    if textSettings.Enabled then
        local textWidth = textSettings.Width or 24
        local textSize = textSettings.Size or 10
        local textPosition
        local textCenter = false

        if isHorizontal then
            textCenter = true
            textPosition = Vector2.new(bgPosition.X + bgSize.X / 2, side == "Top" and bgPosition.Y - textSize - textGap or bgPosition.Y + thickness + textGap)
        elseif side == "Right" then
            textPosition = Vector2.new(bgPosition.X + thickness + textGap, bgPosition.Y + bgSize.Y - textSize)
        else
            textPosition = Vector2.new(bgPosition.X - textWidth - textGap, bgPosition.Y + bgSize.Y - textSize)
        end

        createDraw(espName, objectId, "HealthText", "Text")
        updateDraw(espName, objectId, "HealthText", {
            Visible = true,
            Text = formatHealthText(health, maxHealth, healthPercent, textSettings),
            Position = textPosition,
            Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
            Size = textSize,
            Font = textSettings.Font,
            Center = textSettings.Center ~= nil and textSettings.Center or textCenter,
            Outline = textSettings.Outline ~= false,
        })

        if not isHorizontal and settings.ReserveTextSpace ~= false then
            reserve = reserve + textGap + textWidth
        end
    else
        updateDraw(espName, objectId, "HealthText", { Visible = false })
    end

    if isHorizontal or not settings.ReserveTextSpace then
        reserve = 0
        reserveSide = nil
    end

    return reserve, reserveSide, {
        Side = side,
        Position = bgPosition,
        Size = bgSize,
        IsHorizontal = isHorizontal,
    }
end
local function updateHealth(espName, objectId, position, size, humanoid, settings)
    if not humanoid then
        updateDraw(espName, objectId, "HealthBG", { Visible = false })
        updateDraw(espName, objectId, "Health", { Visible = false })
        updateDraw(espName, objectId, "HealthText", { Visible = false })
        return 0, nil
    end

    return updateHealthValue(espName, objectId, position, size, humanoid.Health, humanoid.MaxHealth, settings)
end
local function updateTexts(espName, objectId, player, character, boxPosition, boxSize, info, texts)
    if type(texts) ~= "table" then return end

    local items = {}
    for textName, textSettings in pairs(texts) do
        items[#items + 1] = {
            Name = textName,
            Settings = textSettings,
            Order = textSettings.Order or 100,
        }
    end

    table.sort(items, function(a, b)
        if a.Order == b.Order then
            return tostring(a.Name) < tostring(b.Name)
        end

        return a.Order < b.Order
    end)

    local used = {
        Top = 0,
        Bottom = 0,
        Left = 0,
        Right = 0,
        Center = 0,
    }

    for _, item in ipairs(items) do
        local textName = item.Name
        local textSettings = item.Settings

        if textSettings.Enabled then
            local value = textSettings.Text
            if type(value) == "function" then
                value = value(player, character, info)
            end

            local anchor = textSettings.Anchor or "Top"
            local textSize = textSettings.Size or 10
            local spacing = textSettings.Spacing or textSize + 2
            local offset = textSettings.Offset or Vector2.zero
            local slot = used[anchor] or 0
            used[anchor] = slot + 1

            if anchor == "Top" then
                offset = offset + Vector2.new(0, -slot * spacing)
            elseif anchor == "Bottom" then
                offset = offset + Vector2.new(0, slot * spacing)
            elseif anchor == "Left" then
                offset = offset + Vector2.new(0, slot * spacing)
            elseif anchor == "Right" then
                offset = offset + Vector2.new(0, slot * spacing)
            end

            local sidePadding = textSettings.Padding or 1
            local sideWidth = textSettings.Width or estimateTextWidth(value, textSize)
            local position
            local center
            local attachedToHealth = textSettings.AttachTo == "HealthBar" and info and info.HealthBar and not info.HealthBar.IsHorizontal

            if attachedToHealth then
                local healthBar = info.HealthBar
                local healthPosition = healthBar.Position
                local healthSize = healthBar.Size
                local healthSide = healthBar.Side
                local baseY = healthPosition.Y + healthSize.Y / 2

                if healthSide == "Left" then
                    position = Vector2.new(healthPosition.X + healthSize.X + sidePadding, baseY) + offset
                else
                    position = Vector2.new(healthPosition.X - sideWidth - sidePadding, baseY) + offset
                end

                center = false
            else
                position, center = anchorPosition(boxPosition, boxSize, anchor, offset)
            end

            if attachedToHealth then
                center = false
            elseif anchor == "Left" then
                position = position - Vector2.new(sideWidth + sidePadding, 0)
                center = false
            elseif anchor == "Right" then
                position = position + Vector2.new(sidePadding, 0)
                center = false
            end

            createDraw(espName, objectId, "Text_" .. textName, "Text")
            updateDraw(espName, objectId, "Text_" .. textName, {
                Visible = true,
                Text = tostring(value or ""),
                Position = position,
                Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
                Size = textSize,
                Font = textSettings.Font,
                Center = textSettings.Center ~= nil and textSettings.Center or center,
                Outline = textSettings.Outline ~= false,
            })
        else
            updateDraw(espName, objectId, "Text_" .. textName, { Visible = false })
        end
    end
end
local function updateHeadCircle(espName, objectId, character, settings)
    if not settings.Enabled then
        updateDraw(espName, objectId, "HeadCircle", { Visible = false })
        return
    end

    local head = character:FindFirstChild("Head")
    if not head then return end

    local screen, visible = Camera:WorldToViewportPoint(head.Position)
    createDraw(espName, objectId, "HeadCircle", "Circle")
    updateDraw(espName, objectId, "HeadCircle", {
        Visible = visible,
        Position = Vector2.new(screen.X, screen.Y),
        Radius = settings.Radius or 8,
        Color = settings.Color or Color3.fromRGB(255, 255, 255),
        Thickness = settings.Thickness or 1,
        Filled = settings.Filled or false,
    })
end

local SkeletonBones = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
    { "Head", "Torso" },
    { "Torso", "Left Arm" },
    { "Torso", "Right Arm" },
    { "Torso", "Left Leg" },
    { "Torso", "Right Leg" },
}

local function hideSkeleton(espName, objectId)
    for index in ipairs(SkeletonBones) do
        updateDraw(espName, objectId, "Skeleton_" .. index, { Visible = false })
    end
end

local function updateSkeleton(espName, objectId, model, settings)
    settings = settings or {}
    if settings.Enabled == false or not model then
        hideSkeleton(espName, objectId)
        return
    end

    local color = settings.Color or Color3.fromRGB(255, 255, 255)
    local thickness = settings.Thickness or 2
    local transparency = settings.Transparency or 1

    for index, bone in ipairs(SkeletonBones) do
        local partA = model:FindFirstChild(bone[1])
        local partB = model:FindFirstChild(bone[2])
        local element = "Skeleton_" .. index

        if partA and partB then
            local pointA, visibleA = Camera:WorldToViewportPoint(partA.Position)
            local pointB, visibleB = Camera:WorldToViewportPoint(partB.Position)

            createDraw(espName, objectId, element, "Line")
            updateDraw(espName, objectId, element, {
                Visible = visibleA or visibleB,
                From = Vector2.new(pointA.X, pointA.Y),
                To = Vector2.new(pointB.X, pointB.Y),
                Color = color,
                Thickness = thickness,
                Transparency = transparency,
            })
        else
            updateDraw(espName, objectId, element, { Visible = false })
        end
    end
end
local function isValidPlayer(player, data, settings)
    if player == LocalPlayer then return false end
    if not data or not data.Character then return false end
    if settings.TeamCheck and LocalPlayer.Team == player.Team then return false end

    local character = data.Character
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if not root then return false end
    if settings.HealthCheck and humanoid and humanoid.Health <= 0 then return false end

    return true, character, root, humanoid
end

local function updatePlayerEsp(player, data)
    local espName = DEFAULT_ESP
    local settings = EspHandler.Settings[espName]
    if not settings or not settings.Enabled or settings.Paused then
        hideObject(espName, player.UserId)
        return
    end

    local valid, character, root, humanoid = isValidPlayer(player, data, settings)
    if not valid then
        hideObject(espName, player.UserId)
        return
    end

    local distance = (Camera.CFrame.Position - root.Position).Magnitude
    if distance > settings.MaxDistance then
        hideObject(espName, player.UserId)
        return
    end

    local position, size, visible = getBox(character)
    if not visible then
        hideObject(espName, player.UserId)
        return
    end

    local objectId = player.UserId
    if settings.Box and settings.Box.Enabled then
        if settings.Box.Type == "Square" then
            updateSquareBox(espName, objectId, position, size, settings.Box)
        else
            updateCornerBox(espName, objectId, position, size, settings.Box)
        end
    else
        updateDraw(espName, objectId, "Box", { Visible = false })
        for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
            updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
        end
    end

    local _, _, healthBar = updateHealth(espName, objectId, position, size, humanoid, settings.Health or {})
    updateHeadCircle(espName, objectId, character, settings.HeadCircle or {})
    updateSkeleton(espName, objectId, character, settings.Skeleton or {})
    updateTexts(espName, objectId, player, character, position, size, {
        Distance = distance,
        Root = root,
        Humanoid = humanoid,
        HealthBar = healthBar,
    }, settings.Texts)
end

local function isTrackedObjectValid(object, settings)
    if object == nil then return false end

    if type(settings.IsValid) == "function" then
        return settings.IsValid(object, settings) == true
    end

    local okParent, parent = pcall(function()
        return object.Parent
    end)

    if okParent and parent == nil then
        return false
    end

    local okPlayer, isPlayer = pcall(function()
        return object:IsA("Player")
    end)

    if okPlayer and isPlayer then
        local character = object.Character
        if not character then return false end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health <= 0 then return false end

        return true
    end

    local okHumanoid, humanoid = pcall(function()
        if object:IsA("Model") then
            return object:FindFirstChildOfClass("Humanoid")
        end
    end)

    if okHumanoid and humanoid and humanoid.Health <= 0 then
        return false
    end

    return true
end
local function updateCustomEsp(espName, settings)
    if espName == DEFAULT_ESP then return end
    if not EspHandler.Running[espName] then return end
    if not settings or not settings.Enabled or settings.Paused then return end
    if type(settings.Render) ~= "function" then return end

    local objects = EspHandler.Objects[espName]
    if type(objects) ~= "table" then return end

    for objectId, object in pairs(objects) do
        if isTrackedObjectValid(object, settings) then
            settings.Render({
                EspName = espName,
                ObjectId = objectId,
                Object = object,
                Settings = settings,
                Handler = EspHandler,
            })
        else
            hideObject(espName, objectId)
        end
    end
end
function EspHandler.CreateEsp(espName, settings)
    espName = getGroup(espName)
    settings = settings or {}

    EspHandler.Objects[espName] = EspHandler.Objects[espName] or {}

    if settings.Objects then
        EspHandler.SetObjects(espName, settings.Objects)
        settings.Objects = nil
    end

    EspHandler.Settings[espName] = mergeTable(EspHandler.Settings[espName], settings)
    return EspHandler.Settings[espName]
end

function EspHandler.SetObjects(espName, objects)
    espName = getGroup(espName)
    EspHandler.Objects[espName] = {}

    if type(objects) ~= "table" then
        return EspHandler.Objects[espName]
    end

    for key, object in pairs(objects) do
        if type(key) == "string" then
            EspHandler.Objects[espName][key] = object
        else
            EspHandler.Objects[espName][getObjectId(object)] = object
        end
    end

    return EspHandler.Objects[espName]
end

function EspHandler.AddObject(espName, object, objectId)
    espName = getGroup(espName)
    EspHandler.Objects[espName] = EspHandler.Objects[espName] or {}

    objectId = getObjectId(objectId or object)
    EspHandler.Objects[espName][objectId] = object
    return objectId, object
end

function EspHandler.GetObject(espName, objectId)
    espName = getGroup(espName)
    objectId = getObjectId(objectId)
    return EspHandler.Objects[espName] and EspHandler.Objects[espName][objectId]
end

function EspHandler.GetObjects(espName)
    espName = getGroup(espName)
    return EspHandler.Objects[espName]
end

function EspHandler.RemoveObjectFromList(espName, objectId)
    espName = getGroup(espName)
    objectId = getObjectId(objectId)

    if EspHandler.Objects[espName] then
        EspHandler.Objects[espName][objectId] = nil
    end

    removeObject(espName, objectId)
end

function EspHandler.SetAspect(espName, aspect, properties)
    espName = getGroup(espName)
    EspHandler.Settings[espName][aspect] = EspHandler.Settings[espName][aspect] or {}
    mergeTable(EspHandler.Settings[espName][aspect], properties or {})
    return EspHandler.Settings[espName][aspect]
end

function EspHandler.SetText(espName, textName, properties)
    espName = getGroup(espName)
    EspHandler.Settings[espName].Texts = EspHandler.Settings[espName].Texts or {}
    EspHandler.Settings[espName].Texts[textName] = EspHandler.Settings[espName].Texts[textName] or {}
    mergeTable(EspHandler.Settings[espName].Texts[textName], properties or {})
    return EspHandler.Settings[espName].Texts[textName]
end

function EspHandler.CreateDrawings(espName, objectId, drawings)
    if type(drawings) ~= "table" then
        return nil, "Invalid drawings: expected table"
    end

    local created = {}
    for element, data in pairs(drawings) do
        if type(data) == "table" and data.Type then
            created[element] = EspHandler.CreateDrawing(espName, objectId, element, data.Type, data.Properties)
        end
    end

    return created
end

function EspHandler.StartGroup(espName, settings)
    if type(espName) == "table" then
        settings, espName = espName, nil
    end

    if espName == nil then
        for groupName in pairs(EspHandler.Settings) do
            EspHandler.StartGroup(groupName, settings)
        end
        return EspHandler.Settings
    end

    espName = getGroup(espName)
    if settings then
        EspHandler.SetSettings(espName, settings)
    end

    EspHandler.Settings[espName].Enabled = true
    EspHandler.Settings[espName].Paused = false
    EspHandler.Running[espName] = true
    EspHandler.Enabled = true
    ensureRenderLoop()
    return EspHandler.Settings[espName]
end
function EspHandler.PauseGroup(espName, hide)
    if espName == nil then
        for groupName in pairs(EspHandler.Settings) do
            EspHandler.PauseGroup(groupName, hide)
        end
        return EspHandler.Settings
    end

    espName = getGroup(espName)
    EspHandler.Settings[espName].Paused = true

    if hide ~= false then
        hideGroup(espName)
    end

    return EspHandler.Settings[espName]
end
function EspHandler.StopGroup(espName, removeDrawings)
    if espName == nil then
        for groupName in pairs(EspHandler.Settings) do
            EspHandler.StopGroup(groupName, removeDrawings)
        end
        return EspHandler.Settings
    end

    espName = getGroup(espName)
    EspHandler.Settings[espName].Enabled = false
    EspHandler.Settings[espName].Paused = false
    EspHandler.Running[espName] = nil

    if removeDrawings then
        removeGroup(espName)
    else
        hideGroup(espName)
    end

    if not hasRunningGroups() then
        EspHandler.Enabled = false
        stopRenderLoop()
    end

    return EspHandler.Settings[espName]
end
function EspHandler.UpdateGroup(espName)
    Camera = workspace.CurrentCamera
    espName = getGroup(espName)

    if espName == DEFAULT_ESP then
        for player, data in pairs(PlayersHandler.Characters) do
            updatePlayerEsp(player, data)
        end
    else
        updateCustomEsp(espName, EspHandler.Settings[espName])
    end
end

function EspHandler.UpdateObject(espName, objectId)
    espName = getGroup(espName)
    local settings = EspHandler.Settings[espName]
    local object = EspHandler.GetObject(espName, objectId)

    if type(settings.Render) == "function" and object then
        settings.Render({
            EspName = espName,
            ObjectId = getObjectId(objectId),
            Object = object,
            Settings = settings,
            Handler = EspHandler,
        })
    end
end
function EspHandler.SetSettings(espName, settings)
    if type(espName) == "table" then
        settings, espName = espName, DEFAULT_ESP
    end

    espName = getGroup(espName)
    mergeTable(EspHandler.Settings[espName], settings or {})
    return EspHandler.Settings[espName]
end

function EspHandler.CreateDrawing(espName, objectId, element, drawType, properties)
    local drawing = createDraw(espName, objectId, element, drawType)
    if properties then
        updateDraw(espName, objectId, element, properties)
    end
    return drawing
end

function EspHandler.GetDrawing(espName, objectId, element)
    espName = getGroup(espName)
    return DrawingHelp.GetDrawing(drawName(espName, objectId, element), espName)
end

function EspHandler.GetDrawings(espName, objectId)
    espName = getGroup(espName)
    local objectPrefix = getObjectId(objectId) .. "_"
    local drawings = {}

    for name, drawing in pairs(DrawingHelp.DrawCaches[espName]) do
        if string.sub(name, 1, #objectPrefix) == objectPrefix then
            drawings[name] = drawing
        end
    end

    return drawings
end

function EspHandler.UpdateDrawing(espName, objectId, element, properties)
    return updateDraw(espName, objectId, element, properties)
end

function EspHandler.UpdateTextPosition(espName, objectId, element, boxPosition, boxSize, anchor, offset)
    local position, center = anchorPosition(boxPosition, boxSize, anchor, offset)
    return updateDraw(espName, objectId, element, {
        Position = position,
        Center = center,
    })
end

function EspHandler.HideObject(espName, objectId)
    hideObject(espName, objectId)
end

function EspHandler.RemoveObject(espName, objectId)
    removeObject(espName, objectId)
end

function EspHandler.RemoveDrawing(espName, objectId, element)
    removeDraw(espName, objectId, element)
end

function EspHandler.UpdateBox(espName, objectId, position, size, boxSettings)
    boxSettings = boxSettings or {}

    if boxSettings.Enabled == false then
        updateDraw(espName, objectId, "Box", { Visible = false })
        for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
            updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
        end
        return
    end

    if boxSettings.Type == "Square" then
        updateSquareBox(espName, objectId, position, size, boxSettings)
    else
        updateCornerBox(espName, objectId, position, size, boxSettings)
    end

    return EspHandler.GetDrawings(espName, objectId)
end

function EspHandler.UpdateText(espName, objectId, textName, text, position, textSettings)
    textSettings = textSettings or {}
    local element = "Text_" .. tostring(textName)

    createDraw(espName, objectId, element, "Text")
    return updateDraw(espName, objectId, element, {
        Visible = textSettings.Visible ~= false,
        Text = tostring(text or ""),
        Position = position,
        Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
        Size = textSettings.Size or 13,
        Font = textSettings.Font,
        Center = textSettings.Center ~= false,
        Outline = textSettings.Outline ~= false,
    })
end

function EspHandler.UpdateAnchoredText(espName, objectId, textName, text, boxPosition, boxSize, anchor, offset, textSettings)
    local position, center = anchorPosition(boxPosition, boxSize, anchor, offset)
    textSettings = textSettings or {}
    if textSettings.Center == nil then
        textSettings.Center = center
    end

    return EspHandler.UpdateText(espName, objectId, textName, text, position, textSettings)
end

function EspHandler.UpdateHeadCircle(espName, objectId, position, circleSettings)
    circleSettings = circleSettings or {}

    createDraw(espName, objectId, "HeadCircle", "Circle")
    return updateDraw(espName, objectId, "HeadCircle", {
        Visible = circleSettings.Visible ~= false,
        Position = position,
        Radius = circleSettings.Radius or 8,
        Color = circleSettings.Color or Color3.fromRGB(255, 255, 255),
        Thickness = circleSettings.Thickness or 1,
        Filled = circleSettings.Filled or false,
    })
end

function EspHandler.UpdateSkeleton(espName, objectId, model, skeletonSettings)
    skeletonSettings = skeletonSettings or {}
    if skeletonSettings.Enabled == nil then
        skeletonSettings.Enabled = true
    end

    return updateSkeleton(espName, objectId, model, skeletonSettings)
end
function EspHandler.UpdateHealthBar(espName, objectId, position, size, health, maxHealth, healthSettings)
    if type(maxHealth) == "table" then
        healthSettings = maxHealth
        maxHealth = 1
    end

    maxHealth = maxHealth or 1
    health = health or 0
    return updateHealthValue(espName, objectId, position, size, health, maxHealth, healthSettings)
end

function EspHandler.UpdateHealth(espName, objectId, position, size, health, maxHealth, healthSettings)
    return EspHandler.UpdateHealthBar(espName, objectId, position, size, health, maxHealth, healthSettings)
end
function EspHandler.GetBox(character)
    return getBox(character)
end

function EspHandler.GetAnchorPosition(position, size, anchor, offset)
    return anchorPosition(position, size, anchor, offset)
end

function EspHandler.Update()
    Camera = workspace.CurrentCamera

    if EspHandler.Running[DEFAULT_ESP] then
        for player, data in pairs(PlayersHandler.Characters) do
            updatePlayerEsp(player, data)
        end
    end

    for espName, settings in pairs(EspHandler.Settings) do
        updateCustomEsp(espName, settings)
    end
end

function EspHandler.Start(espName, settings)
    if type(espName) == "string" then
        return EspHandler.StartGroup(espName, settings)
    end

    if type(espName) == "table" then
        settings, espName = espName, nil
    else
        espName = nil
    end

    return EspHandler.StartGroup(espName, settings)
end

function EspHandler.Pause(espName, hide)
    if type(espName) == "string" then
        return EspHandler.PauseGroup(espName, hide)
    end

    if type(espName) == "boolean" then
        hide, espName = espName, nil
    else
        espName = nil
    end

    return EspHandler.PauseGroup(espName, hide)
end
function EspHandler.Stop()
    EspHandler.Enabled = false
    EspHandler.Running = {}
    stopRenderLoop()

    for espName in pairs(EspHandler.Settings) do
        hideGroup(espName)
    end
end

function EspHandler.SetEnabled(enabled, settings)
    if enabled then
        EspHandler.Start(settings)
    else
        EspHandler.Stop()
    end
end

function EspHandler.Cleanup()
    EspHandler.Stop()

    for espName, cache in pairs(DrawingHelp.DrawCaches) do
        if EspHandler.Settings[espName] then
            for name, drawing in pairs(cache) do
                drawing:Remove()
                cache[name] = nil
            end
        end
    end
end

Players.PlayerRemoving:Connect(function(player)
    removeObject(DEFAULT_ESP, player.UserId)
end)

return EspHandler
