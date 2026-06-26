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

function CalculationHandler.GetModelScreenBox(model, camera, options)
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
    local viewport = camera.ViewportSize
    local clampPadding = options.ClampPadding or 0
    local maxViewportScale = options.MaxViewportScale or 0.9
    local minSize = options.MinSize or 2

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local visible = false
    local validPoints = 0

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local world = cf:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
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

return CalculationHandler
