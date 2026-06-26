local CalculationHandler = {}

local function getCamera(camera)
    return camera or workspace.CurrentCamera
end

function CalculationHandler.WorldToViewport(position, camera)
    camera = getCamera(camera)
    if not camera then
        return Vector3.zero, false
    end

    return camera:WorldToViewportPoint(position)
end

function CalculationHandler.WorldToScreen(position, camera)
    local point, visible = CalculationHandler.WorldToViewport(position, camera)
    return Vector2.new(point.X, point.Y), visible, point.Z
end

function CalculationHandler.AnchorPosition(position, size, anchor, offset)
    offset = offset or Vector2.zero

    if anchor == "Top" then
        return Vector2.new(position.X + size.X / 2, position.Y) + offset, true
    elseif anchor == "Bottom" then
        return Vector2.new(position.X + size.X / 2, position.Y + size.Y) + offset, true
    elseif anchor == "Left" then
        return Vector2.new(position.X, position.Y + size.Y / 2) + offset, false
    elseif anchor == "Right" then
        return Vector2.new(position.X + size.X, position.Y + size.Y / 2) + offset, false
    elseif anchor == "Center" then
        return Vector2.new(position.X + size.X / 2, position.Y + size.Y / 2) + offset, true
    end

    return position + offset, true
end

function CalculationHandler.EstimateTextWidth(text, size)
    return math.max(8, math.ceil(#tostring(text or "") * (size or 10) * 0.68))
end

local BodyPartNames = {
    HumanoidRootPart = true,
    Head = true,
    Torso = true,
    UpperTorso = true,
    LowerTorso = true,
    LeftArm = true,
    RightArm = true,
    LeftLeg = true,
    RightLeg = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}

local function hasAncestorOfClass(instance, className, stopAt)
    local parent = instance.Parent
    while parent and parent ~= stopAt do
        if parent:IsA(className) then
            return true
        end
        parent = parent.Parent
    end

    return false
end

local function shouldUsePart(part, model, options, bodyOnly)
    if not part:IsA("BasePart") then
        return false
    end

    if options.IgnoreTools ~= false and hasAncestorOfClass(part, "Tool", model) then
        return false
    end

    if options.IgnoreAccessories == true and hasAncestorOfClass(part, "Accessory", model) then
        return false
    end

    if bodyOnly and not BodyPartNames[part.Name] then
        return false
    end

    return true
end

function CalculationHandler.GetModelBoxParts(model, options)
    options = options or {}
    if not model then
        return {}
    end

    local descendants = model:GetDescendants()
    local parts = {}

    if options.BodyOnly ~= false then
        for _, descendant in ipairs(descendants) do
            if shouldUsePart(descendant, model, options, true) then
                parts[#parts + 1] = descendant
            end
        end
    end

    if #parts == 0 then
        for _, descendant in ipairs(descendants) do
            if shouldUsePart(descendant, model, options, false) then
                parts[#parts + 1] = descendant
            end
        end
    end

    return parts
end

function CalculationHandler.GetModelWorldBox(model)
    if not model or not model.GetBoundingBox then
        return nil, nil
    end

    local ok, cf, size = pcall(function()
        return model:GetBoundingBox()
    end)

    if not ok then
        return nil, nil
    end

    return cf, size
end

local function projectBoxPoints(camera, points, options)
    local viewport = camera.ViewportSize
    local clampPadding = options.ClampPadding or 0
    local maxViewportScale = options.MaxViewportScale or 0.9
    local minSize = options.MinSize or 2

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local visible = false
    local validPoints = 0

    for _, world in ipairs(points) do
        local screen, onScreen = camera:WorldToViewportPoint(world)

        if screen.Z > 0 then
            validPoints = validPoints + 1
            visible = visible or onScreen

            local sx = math.clamp(screen.X, -clampPadding, viewport.X + clampPadding)
            local sy = math.clamp(screen.Y, -clampPadding, viewport.Y + clampPadding)

            minX = math.min(minX, sx)
            minY = math.min(minY, sy)
            maxX = math.max(maxX, sx)
            maxY = math.max(maxY, sy)
        end
    end

    if validPoints == 0 or minX == math.huge or minY == math.huge then
        return Vector2.zero, Vector2.zero, false
    end

    local boxSize = Vector2.new(maxX - minX, maxY - minY)
    if boxSize.X < minSize or boxSize.Y < minSize then
        return Vector2.zero, Vector2.zero, false
    end

    if boxSize.X > viewport.X * maxViewportScale or boxSize.Y > viewport.Y * maxViewportScale then
        return Vector2.zero, Vector2.zero, false
    end

    return Vector2.new(minX, minY), boxSize, visible
end

local function addPartCorners(points, part)
    local cf = part.CFrame
    local half = part.Size * 0.5

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                points[#points + 1] = cf:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
            end
        end
    end
end

function CalculationHandler.GetModelPartsScreenBox(model, camera, options)
    camera = getCamera(camera)
    options = options or {}

    if not model or not camera then
        return Vector2.zero, Vector2.zero, false
    end

    local parts = CalculationHandler.GetModelBoxParts(model, options)
    if #parts == 0 then
        return Vector2.zero, Vector2.zero, false
    end

    local points = {}
    for _, part in ipairs(parts) do
        addPartCorners(points, part)
    end

    return projectBoxPoints(camera, points, options)
end

function CalculationHandler.GetModelRobloxScreenBox(model, camera, options)
    camera = getCamera(camera)
    options = options or {}

    if not model or not camera then
        return Vector2.zero, Vector2.zero, false
    end

    local cf, size = CalculationHandler.GetModelWorldBox(model)
    if not cf or not size then
        return Vector2.zero, Vector2.zero, false
    end

    local half = size * 0.5
    local points = {}

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                points[#points + 1] = cf:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
            end
        end
    end

    return projectBoxPoints(camera, points, options)
end

function CalculationHandler.GetModelScreenBox(model, camera, options)
    options = options or {}

    if options.Method == "Roblox" or options.BoxMethod == "Roblox" then
        return CalculationHandler.GetModelRobloxScreenBox(model, camera, options)
    end

    return CalculationHandler.GetModelPartsScreenBox(model, camera, options)
end

return CalculationHandler
