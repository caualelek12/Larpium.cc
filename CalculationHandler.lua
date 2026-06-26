local CalculationHandler = {}
local ModelPartCache = setmetatable({}, { __mode = "k" })

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
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
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
        if part.Parent ~= model then
            return false
        end
    end

    return true
end

function CalculationHandler.GetModelBoxParts(model, options)
    options = options or {}
    if not model then
        return {}
    end

    local useCache = options.CacheParts ~= false and options.BodyOnly ~= false
    if useCache then
        local cached = ModelPartCache[model]
        if cached then
            local valid = true
            for index = 1, #cached do
                if cached[index].Parent == nil then
                    valid = false
                    break
                end
            end

            if valid then
                return cached
            end
        end
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

    if useCache and #parts >= 6 then
        ModelPartCache[model] = parts
    end

    return parts
end

function CalculationHandler.InvalidateModelCache(model)
    ModelPartCache[model] = nil
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

function CalculationHandler.GetModelPartsExactScreenBox(model, camera, options)
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

local function getPartsOrientedBounds(model, parts)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local count = 0
    local root = model:FindFirstChild("HumanoidRootPart")
    local basis = root and root.CFrame or parts[1].CFrame

    for index = 1, #parts do
        local part = parts[index]
        if part.Parent then
            local cf = basis:ToObjectSpace(part.CFrame)
            local half = part.Size * 0.5
            local right = cf.RightVector
            local up = cf.UpVector
            local look = cf.LookVector
            local extentX = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z
            local extentY = math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(look.Y) * half.Z
            local extentZ = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
            local position = cf.Position

            minX = math.min(minX, position.X - extentX)
            minY = math.min(minY, position.Y - extentY)
            minZ = math.min(minZ, position.Z - extentZ)
            maxX = math.max(maxX, position.X + extentX)
            maxY = math.max(maxY, position.Y + extentY)
            maxZ = math.max(maxZ, position.Z + extentZ)
            count = count + 1
        end
    end

    if count == 0 then
        return nil, nil, nil
    end

    return basis, Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
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

    local basis, minimum, maximum = getPartsOrientedBounds(model, parts)
    if not basis then
        CalculationHandler.InvalidateModelCache(model)
        return Vector2.zero, Vector2.zero, false
    end

    local points = {
        basis:PointToWorldSpace(Vector3.new(minimum.X, minimum.Y, minimum.Z)),
        basis:PointToWorldSpace(Vector3.new(minimum.X, minimum.Y, maximum.Z)),
        basis:PointToWorldSpace(Vector3.new(minimum.X, maximum.Y, minimum.Z)),
        basis:PointToWorldSpace(Vector3.new(minimum.X, maximum.Y, maximum.Z)),
        basis:PointToWorldSpace(Vector3.new(maximum.X, minimum.Y, minimum.Z)),
        basis:PointToWorldSpace(Vector3.new(maximum.X, minimum.Y, maximum.Z)),
        basis:PointToWorldSpace(Vector3.new(maximum.X, maximum.Y, minimum.Z)),
        basis:PointToWorldSpace(Vector3.new(maximum.X, maximum.Y, maximum.Z)),
    }

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
    elseif options.Method == "PartsExact" or options.BoxMethod == "PartsExact" then
        return CalculationHandler.GetModelPartsExactScreenBox(model, camera, options)
    end

    return CalculationHandler.GetModelPartsScreenBox(model, camera, options)
end

return CalculationHandler
