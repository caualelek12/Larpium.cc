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

function DrawingHelp.CreateDrawing(drawingType,Name) -- Fucking Savior For organazing Shit
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
end

function DrawingHelp.GetDrawing(name) -- Kinda useless
    return DrawingHelp.DrawCaches[name]
end

function DrawingHelp.UpdateDraw(name, properties) --Properties = Table
    local drawing = DrawingHelp.DrawCaches[name]
    if not drawing then
        warn("Drawing not found: " .. tostring(name))
        return
    end

    for property, value in pairs(properties) do
        drawing[property] = value
    end
end

return DrawingHelp
