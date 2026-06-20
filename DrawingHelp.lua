local DrawingHelp = {}

local ValidDraws = {
    Square = true,
    Line = true,
    Text = true,
    Circle = true,
    Triangle = true,
    Image = true,
}

DrawingHelp.DrawCaches = {}

--[[function DrawingHelp.CreateDrawing(drawingType,Name,Group) -- Old Version Mostly No use Will be removed On Next Update
        if not ValidDraws[drawingType] then
        return nil, "Invalid drawing type: " .. tostring(drawingType)
        end

        if Name and DrawingHelp.DrawCaches[Name] then
        return DrawingHelp.DrawCaches[Name]
        end

        local drawing = Drawing.new(drawingType)

        if Name then
        DrawingHelp.DrawCaches[Name] = drawing
        end

          return drawing
end]]

function DrawingHelp.CreateDrawing(drawingType,Name,Group) -- Fucking Savior For organazing Shit
    if not ValidDraws[drawingType] then return nil, "Invalid draw" end
    if not type(Name) == "string" or not type(Group) == "string" then return nil, "Invalid Name/Group Expected String" end

    if Name and not Group then
        DrawingHelp.DrawCaches.Default[Name] = Drawing.new(drawingType)
        return DrawingHelp.DrawCaches.Default[Name]
    elseif Name and Group then
        DrawingHelp.DrawCaches[Group][Name] = Drawing.new(drawingType)
        return DrawingHelp.DrawCaches[Group][Name]
    end
end

function DrawingHelp.GetDrawing(Name,Group) -- Kinda useless
    if not Name then return nil, "Expected Name" end
    if Group then
        return DrawingHelp.DrawCaches[Group][Name]
    elseif not Group then
        return DrawingHelp.DrawCaches.Default[Name]
    end
end

function DrawingHelp.UpdateDraw(name, group, properties) -- Properties = Table
    if type(group) == "table" and properties == nil then properties, group = group, nil end
    if type(name) ~= "string" then return nil, "Invalid name: expected string" end
    if group ~= nil and type(group) ~= "string" then return nil, "Invalid group: expected string" end
    if type(properties) ~= "table" then return nil, "Invalid properties: expected table" end

    local cache = group and DrawingHelp.DrawCaches[group] or DrawingHelp.DrawCaches.Default
    if not cache then
        return nil, "Draw cache not found: " .. tostring(group or "Default")
    end

    local drawing = cache[name]
    if not drawing then
        return nil, "Drawing not found: " .. tostring(name)
    end

    for property, value in pairs(properties) do
        drawing[property] = value
    end

    return drawing
end

return DrawingHelp
