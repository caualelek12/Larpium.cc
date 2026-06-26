local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera

local PlayersHandler = getgenv().PlayersHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/PlayersHandler.lua"))()
local DrawingHelp = getgenv().DrawingHelp or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/DrawingHelp.lua"))()
local CalculationHandler = getgenv().CalculationHandler or loadstring(game:HttpGet("https://raw.githubusercontent.com/caualelek12/Larpium.cc/refs/heads/main/CalculationHandler.lua"))()
getgenv().PlayersHandler = PlayersHandler
getgenv().DrawingHelp = DrawingHelp
getgenv().CalculationHandler = CalculationHandler

local PreviousEspHandler = getgenv().EspHandler
if type(PreviousEspHandler) == "table" then
    if type(PreviousEspHandler.Cleanup) == "function" then
        pcall(PreviousEspHandler.Cleanup)
    elseif type(PreviousEspHandler.StopGroup) == "function" then
        pcall(PreviousEspHandler.StopGroup, nil, true)
    end
end

local EspHandler = {}

EspHandler.Version = "2026-06-26-text-bounds-layout"
EspHandler.Enabled = false
EspHandler.Connections = {}
EspHandler.Running = {}
EspHandler.Objects = {}
EspHandler.ObjectIds = setmetatable({}, { __mode = "k" })
EspHandler.NextObjectId = 0
EspHandler.CornerOutlineCleanup = {}
EspHandler.Settings = {
    Players = {
        Enabled = true,
        TeamCheck = false,
        HealthCheck = true,
        MaxDistance = 5000,

        BoxCalculation = {
            Method = "Parts",
            BodyOnly = true,
            IgnoreTools = true,
            IgnoreAccessories = false,
            MinWidth = 32,
            MinHeight = 48,
            FitSideText = true,
        },

        Box = {
            Enabled = true,
            Type = "Corner", -- Square / Corner
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 4,
            CornerSize = 12,
            Outline = true,
            OutlineColor = Color3.fromRGB(0, 0, 0),
            OutlineThickness = 1,
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
                Width = nil, -- nil = use Drawing.TextBounds
                Outline = true,
                OutlineColor = Color3.fromRGB(0, 0, 0),
            },
        },

        Texts = {
            Name = {
                Enabled = true,
                Anchor = "Left",
                Text = function(player)
                    return player.Name
                end,
                Color = Color3.fromRGB(255, 255, 255),
                Size = 10,
                Spacing = 12,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 1,
            },

            Distance = {
                Enabled = true,
                Anchor = "Left",
                Text = function(_, _, info)
                    return tostring(math.floor(info.Distance)) .. "m"
                end,
                Color = Color3.fromRGB(200, 200, 200),
                Size = 10,
                Spacing = 12,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 2,
            },

            Weapon = {
                Enabled = false,
                Anchor = "Left",
                Text = function(_, character)
                    local tool = character and character:FindFirstChildOfClass("Tool")
                    return tool and tool.Name or "None"
                end,
                Color = Color3.fromRGB(255, 220, 120),
                Size = 10,
                Spacing = 12,
                Offset = Vector2.zero,
                Padding = 1,
                Order = 3,
            },

            State = {
                Enabled = false,
                Anchor = "Left",
                Text = function(_, character)
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    return humanoid and humanoid:GetState().Name or "Unknown"
                end,
                Color = Color3.fromRGB(160, 220, 255),
                Size = 10,
                Spacing = 12,
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

local function getMinimumBoxSize(settings, boxSettings)
    local minWidth = tonumber(boxSettings.MinWidth) or 32
    local minHeight = tonumber(boxSettings.MinHeight) or 48

    if boxSettings.FitSideText == false then
        return minWidth, minHeight
    end

    local sideLayouts = {
        Left = { Count = 0, Size = 0, Spacing = 0 },
        Right = { Count = 0, Size = 0, Spacing = 0 },
    }

    for _, textSettings in pairs(settings.Texts or {}) do
        local side = textSettings.Anchor
        local layout = sideLayouts[side]
        if layout and textSettings.Enabled then
            local textSize = math.floor(tonumber(textSettings.Size) or 10)
            layout.Count = layout.Count + 1
            layout.Size = math.max(layout.Size, textSize)
            layout.Spacing = math.max(layout.Spacing, tonumber(textSettings.Spacing) or 0, textSize + 4, 12)
        end
    end

    local healthSettings = settings.Health or {}
    local healthText = healthSettings.Text or {}
    local healthLayout = sideLayouts[healthSettings.Side]
    if healthLayout and healthSettings.Enabled and healthText.Enabled then
        local textSize = math.floor(tonumber(healthText.Size) or 10)
        healthLayout.Count = healthLayout.Count + 1
        healthLayout.Size = math.max(healthLayout.Size, textSize)
        healthLayout.Spacing = math.max(healthLayout.Spacing, tonumber(healthText.Spacing) or 0, textSize + 4, 12)
    end

    for _, layout in pairs(sideLayouts) do
        if layout.Count > 0 then
            minHeight = math.max(minHeight, (layout.Count - 1) * layout.Spacing + layout.Size + 8)
        end
    end

    return minWidth, minHeight
end

local function getBox(character, settings)
    settings = settings or {}
    local boxSettings = settings.BoxCalculation or settings.BoxSize or {}

    local position, size, visible = CalculationHandler.GetModelScreenBox(character, Camera, {
        Method = boxSettings.Method or settings.BoxMethod or "Parts",
        BodyOnly = boxSettings.BodyOnly,
        IgnoreTools = boxSettings.IgnoreTools,
        IgnoreAccessories = boxSettings.IgnoreAccessories,
        ClampPadding = 0,
        MaxViewportScale = 0.9,
        MinSize = 2,
    })

    if not visible or boxSettings.EnforceMinimum == false then
        return position, size, visible
    end

    local minWidth, minHeight = getMinimumBoxSize(settings, boxSettings)
    local width = math.max(size.X, minWidth)
    local height = math.max(size.Y, minHeight)
    local center = position + size / 2

    return center - Vector2.new(width, height) / 2, Vector2.new(width, height), true
end

local function hideCornerBoxOutlines(espName, objectId, part)
    updateDraw(espName, objectId, "BoxOutline_" .. part, { Visible = false })
    updateDraw(espName, objectId, "BoxSegment_" .. part, { Visible = false })
    updateDraw(espName, objectId, "BoxSegmentOutline_" .. part, { Visible = false })

    for index = 1, 4 do
        updateDraw(espName, objectId, "BoxOutline_" .. part .. "_" .. index, { Visible = false })
    end
end

local function snapVector2(value)
    return Vector2.new(math.floor(value.X + 0.5), math.floor(value.Y + 0.5))
end

local function cleanupLegacyCornerOutlines(espName, objectId, parts)
    local cleanupKey = espName .. ":" .. getObjectId(objectId)
    if EspHandler.CornerOutlineCleanup[cleanupKey] then return end

    EspHandler.CornerOutlineCleanup[cleanupKey] = true
    for _, part in ipairs(parts) do
        updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
        updateDraw(espName, objectId, "BoxOutline_" .. part, { Visible = false })
        for index = 1, 4 do
            updateDraw(espName, objectId, "BoxOutline_" .. part .. "_" .. index, { Visible = false })
        end
    end
end

local function expandRect(position, size, amount)
    local padding = Vector2.new(amount, amount)
    return position - padding, size + padding * 2
end

local function updateCornerBox(espName, objectId, position, size, boxSettings)
    local topLeft = snapVector2(position)
    local bottomRight = snapVector2(position + size)
    local width = math.max(bottomRight.X - topLeft.X, 1)
    local height = math.max(bottomRight.Y - topLeft.Y, 1)
    local thickness = math.max(math.floor((tonumber(boxSettings.Thickness) or 1) + 0.5), 1)
    local color = boxSettings.Color or Color3.fromRGB(255, 255, 255)
    local corner = math.max(
        thickness,
        math.min(math.floor((tonumber(boxSettings.CornerSize) or 12) + 0.5), math.floor(width / 2), math.floor(height / 2))
    )
    local outline = boxSettings.Outline ~= false
    local outlineColor = boxSettings.OutlineColor or Color3.fromRGB(0, 0, 0)
    local outlineThickness = math.max(math.floor((tonumber(boxSettings.OutlineThickness) or 1) + 0.5), 1)
    local x, y = topLeft.X, topLeft.Y
    local right, bottom = bottomRight.X, bottomRight.Y

    local segments = {
        { "TL_H", Vector2.new(x, y), Vector2.new(corner, thickness) },
        { "TL_V", Vector2.new(x, y), Vector2.new(thickness, corner) },
        { "TR_H", Vector2.new(right - corner, y), Vector2.new(corner, thickness) },
        { "TR_V", Vector2.new(right - thickness, y), Vector2.new(thickness, corner) },
        { "BL_H", Vector2.new(x, bottom - thickness), Vector2.new(corner, thickness) },
        { "BL_V", Vector2.new(x, bottom - corner), Vector2.new(thickness, corner) },
        { "BR_H", Vector2.new(right - corner, bottom - thickness), Vector2.new(corner, thickness) },
        { "BR_V", Vector2.new(right - thickness, bottom - corner), Vector2.new(thickness, corner) },
    }

    cleanupLegacyCornerOutlines(espName, objectId, { "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" })

    for _, segment in ipairs(segments) do
        local segmentPosition, segmentSize = segment[2], segment[3]
        local outlinePosition, outlineSize = expandRect(segmentPosition, segmentSize, outlineThickness)

        createDraw(espName, objectId, "BoxSegmentOutline_" .. segment[1], "Square")
        updateDraw(espName, objectId, "BoxSegmentOutline_" .. segment[1], {
            Visible = outline,
            Position = outlinePosition,
            Size = outlineSize,
            Color = outlineColor,
            Filled = true,
        })
    end

    for _, segment in ipairs(segments) do
        createDraw(espName, objectId, "BoxSegment_" .. segment[1], "Square")
        updateDraw(espName, objectId, "BoxSegment_" .. segment[1], {
            Visible = true,
            Position = segment[2],
            Size = segment[3],
            Color = color,
            Filled = true,
        })
    end

    updateDraw(espName, objectId, "Box", { Visible = false })
    updateDraw(espName, objectId, "BoxOutline", { Visible = false })
end

local function updateSquareBox(espName, objectId, position, size, boxSettings)
    local thickness = boxSettings.Thickness or 1
    local outline = boxSettings.Outline ~= false
    local outlineThickness = boxSettings.OutlineThickness or 2

    createDraw(espName, objectId, "BoxOutline", "Square")
    updateDraw(espName, objectId, "BoxOutline", {
        Visible = outline,
        Position = position - Vector2.new(outlineThickness, outlineThickness),
        Size = size + Vector2.new(outlineThickness * 2, outlineThickness * 2),
        Color = boxSettings.OutlineColor or Color3.fromRGB(0, 0, 0),
        Thickness = thickness + outlineThickness,
        Filled = false,
    })

    createDraw(espName, objectId, "Box", "Square")
    updateDraw(espName, objectId, "Box", {
        Visible = true,
        Position = position,
        Size = size,
        Color = boxSettings.Color or Color3.fromRGB(255, 255, 255),
        Thickness = thickness,
        Filled = false,
    })

    for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
        updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
        hideCornerBoxOutlines(espName, objectId, part)
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
    local healthTextInfo
    if textSettings.Enabled then
        local textSize = math.floor(tonumber(textSettings.Size) or tonumber(settings.TextSize) or 10)
        local textValue = formatHealthText(health, maxHealth, healthPercent, textSettings)
        local textWidth = tonumber(textSettings.Width)
        local reserveTextWidth = textWidth or estimateTextWidth(textValue, textSize)
        local textPosition
        local textCenter = false

        if isHorizontal then
            textCenter = true
            textPosition = Vector2.new(bgPosition.X + bgSize.X / 2, side == "Top" and bgPosition.Y - textSize - textGap or bgPosition.Y + thickness + textGap)
        else
            healthTextInfo = {
                Value = textValue,
                Settings = {
                    Enabled = true,
                    Anchor = side,
                    Text = textValue,
                    Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
                    Size = textSize,
                    Font = textSettings.Font,
                    Width = textWidth,
                    Spacing = textSettings.Spacing,
                    Padding = textGap,
                    Order = textSettings.Order or 0,
                    Outline = textSettings.Outline,
                    OutlineColor = textSettings.OutlineColor,
                },
            }
        end

        if isHorizontal then
            createDraw(espName, objectId, "HealthText", "Text")
            updateDraw(espName, objectId, "HealthText", {
                Visible = true,
                Text = textValue,
                Position = textPosition,
                Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
                Size = textSize,
                Font = textSettings.Font,
                Center = textSettings.Center ~= nil and textSettings.Center or textCenter,
                Outline = textSettings.Outline ~= false,
                OutlineColor = textSettings.OutlineColor or Color3.fromRGB(0, 0, 0),
            })
        else
            updateDraw(espName, objectId, "HealthText", { Visible = false })
        end

        if not isHorizontal and settings.ReserveTextSpace ~= false then
            reserve = reserve + textGap + reserveTextWidth
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
        Text = healthTextInfo,
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
            Element = "Text_" .. textName,
            Settings = textSettings,
            Order = textSettings.Order or 100,
        }
    end

    if info and info.HealthBar and info.HealthBar.Text then
        local healthText = info.HealthBar.Text
        items[#items + 1] = {
            Name = "HealthText",
            Element = "HealthText",
            Settings = healthText.Settings,
            Order = healthText.Settings.Order or 0,
        }
    else
        updateDraw(espName, objectId, "HealthText", { Visible = false })
    end

    table.sort(items, function(a, b)
        if a.Order == b.Order then
            return tostring(a.Name) < tostring(b.Name)
        end

        return a.Order < b.Order
    end)

    local counts = {
        Top = 0,
        Bottom = 0,
        Left = 0,
        Right = 0,
        Center = 0,
    }

    for _, item in ipairs(items) do
        local textSettings = item.Settings
        if textSettings.Enabled then
            local anchor = textSettings.Anchor or "Top"
            counts[anchor] = (counts[anchor] or 0) + 1
        end
    end

    local used = {
        Top = 0,
        Bottom = 0,
        Left = 0,
        Right = 0,
        Center = 0,
    }

    for _, item in ipairs(items) do
        local textName = item.Name
        local element = item.Element or ("Text_" .. textName)
        local textSettings = item.Settings

        if textSettings.Enabled then
            local value = textSettings.Text
            if type(value) == "function" then
                value = value(player, character, info)
            end
            value = tostring(value or "")

            local anchor = textSettings.Anchor or "Top"
            local textSize = math.floor(tonumber(textSettings.Size) or 10)
            local drawing = createDraw(espName, objectId, element, "Text")
            updateDraw(espName, objectId, element, {
                Text = value,
                Size = textSize,
                Font = textSettings.Font,
                Outline = textSettings.Outline ~= false,
                OutlineColor = textSettings.OutlineColor or Color3.fromRGB(0, 0, 0),
            })

            local textBounds = drawing and drawing.TextBounds or Vector2.zero
            local measuredWidth = textBounds.X > 0 and math.ceil(textBounds.X) or estimateTextWidth(value, textSize)
            local measuredHeight = textBounds.Y > 0 and math.ceil(textBounds.Y) or textSize
            local spacing = math.max(tonumber(textSettings.Spacing) or 0, measuredHeight + 2, 12)
            local offset = textSettings.Offset or Vector2.zero
            local slot = used[anchor] or 0
            used[anchor] = slot + 1

            if anchor == "Top" then
                offset = offset + Vector2.new(0, -slot * spacing)
            elseif anchor == "Bottom" then
                offset = offset + Vector2.new(0, slot * spacing)
            elseif anchor == "Left" then
                offset = offset + Vector2.new(0, (slot - ((counts.Left or 1) - 1) / 2) * spacing)
            elseif anchor == "Right" then
                offset = offset + Vector2.new(0, (slot - ((counts.Right or 1) - 1) / 2) * spacing)
            end

            local sidePadding = math.max(textSettings.Padding or 2, 1)
            local sideWidth = textSettings.Width or measuredWidth
            local position, center = anchorPosition(boxPosition, boxSize, anchor, offset)
            local healthBar = info and info.HealthBar
            local attachedToHealth = healthBar
                and not healthBar.IsHorizontal
                and (anchor == healthBar.Side or textSettings.AttachTo == "HealthBar")

            if attachedToHealth then
                local healthPosition = healthBar.Position
                local healthSize = healthBar.Size

                if anchor == "Left" then
                    local maxRight = healthPosition.X - sidePadding
                    position = Vector2.new(maxRight - sideWidth, position.Y)
                else
                    local minLeft = healthPosition.X + healthSize.X + sidePadding
                    position = Vector2.new(minLeft, position.Y)
                end

                center = false
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

            updateDraw(espName, objectId, element, {
                Visible = true,
                Text = value,
                Position = position,
                Color = textSettings.Color or Color3.fromRGB(255, 255, 255),
                Size = textSize,
                Font = textSettings.Font,
                Center = textSettings.Center ~= nil and textSettings.Center or center,
                Outline = textSettings.Outline ~= false,
                OutlineColor = textSettings.OutlineColor or Color3.fromRGB(0, 0, 0),
            })
        else
            updateDraw(espName, objectId, element, { Visible = false })
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

    local position, size, visible = getBox(character, settings)
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
        updateDraw(espName, objectId, "BoxOutline", { Visible = false })
        for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
            updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
            hideCornerBoxOutlines(espName, objectId, part)
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
        updateDraw(espName, objectId, "BoxOutline", { Visible = false })
        for _, part in ipairs({ "TL_H", "TL_V", "TR_H", "TR_V", "BL_H", "BL_V", "BR_H", "BR_V" }) do
            updateDraw(espName, objectId, "Box_" .. part, { Visible = false })
            hideCornerBoxOutlines(espName, objectId, part)
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
        OutlineColor = textSettings.OutlineColor or Color3.fromRGB(0, 0, 0),
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
function EspHandler.GetBox(character, settings)
    return getBox(character, settings)
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

getgenv().EspHandler = EspHandler
return EspHandler
