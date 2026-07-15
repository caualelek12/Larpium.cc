local HttpService = game:GetService("HttpService")

local WebsiteUIBridge = {}
WebsiteUIBridge.__index = WebsiteUIBridge
WebsiteUIBridge.Version = "2026-07-15-place-assets-v6"
WebsiteUIBridge.DefaultBaseUrl = "https://larpium.dedyn.io:45916"

local function trimSlash(value)
    return tostring(value or ""):gsub("/+$", "")
end

local function jsonRequest(url, method, body, token)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
    }
    if token and token ~= "" then
        headers.Authorization = "Bearer " .. token
    end

    local requestOk, response = pcall(request, {
        Url = url,
        Method = method or "GET",
        Headers = headers,
        Body = body and HttpService:JSONEncode(body) or nil,
    })
    if not requestOk then
        return nil, tostring(response), 0
    end
    local decoded = {}
    if response.Body and response.Body ~= "" then
        local ok, result = pcall(HttpService.JSONDecode, HttpService, response.Body)
        if ok and type(result) == "table" then decoded = result end
    end
    if not response.Success then
        return nil, decoded.error or response.StatusMessage or ("HTTP " .. tostring(response.StatusCode)), response.StatusCode
    end
    return decoded, nil, response.StatusCode
end

local function ensureFolder(path)
    local folder = path:match("^(.*)/[^/]+$")
    if folder and folder ~= "" and makefolder and isfolder and not isfolder(folder) then
        pcall(makefolder, folder)
    end
end

local function loadSaved(path)
    if not readfile or not isfile or not isfile(path) then return {} end
    local ok, raw = pcall(readfile, path)
    if not ok then return {} end
    local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    return decodedOk and type(decoded) == "table" and decoded or {}
end

local function saveData(path, data)
    if not writefile then return end
    ensureFolder(path)
    pcall(writefile, path, HttpService:JSONEncode(data))
end

function WebsiteUIBridge.new(options)
    options = options or {}
    local self = setmetatable({}, WebsiteUIBridge)
    self.BaseUrl = trimSlash(options.BaseUrl or WebsiteUIBridge.DefaultBaseUrl)
    assert(self.BaseUrl:match("^https?://"), "WebsiteUIBridge BaseUrl must start with http:// or https://")
    self.InsecureTransport = self.BaseUrl:match("^http://") ~= nil
    if self.InsecureTransport and options.WarnInsecure ~= false then
        warn("WebsiteUIBridge is using HTTP; device tokens are not encrypted in transit.")
    end

    self.PollInterval = math.max(tonumber(options.PollInterval) or 1, 0.25)
    self.StoragePath = options.StoragePath or "Larpium/website-ui.json"
    self.Bindings = {}
    self.Values = {}
    self.Project = nil
    self.EspLayout = nil
    self.EspLayoutJson = ""
    self.Revision = 0
    self.Running = false
    self.Connected = false
    self.OnError = options.OnError
    self.OnSchema = options.OnSchema
    self.OnEspLayout = options.OnEspLayout
    self.OnConnected = options.OnConnected
    self.Changed = Instance.new("BindableEvent")
    self.ConnectionChanged = Instance.new("BindableEvent")

    local saved = loadSaved(self.StoragePath)
    self.Token = options.Token or saved.token
    self.DeviceId = saved.deviceId or HttpService:GenerateGUID(false)
    if options.PairCode then
        local ok, err = self:Pair(options.PairCode)
        if not ok then warn("WebsiteUIBridge pairing failed: " .. tostring(err)) end
    end
    return self
end

function WebsiteUIBridge:_save()
    saveData(self.StoragePath, { token = self.Token, deviceId = self.DeviceId })
end

function WebsiteUIBridge:_error(message, statusCode)
    if type(self.OnError) == "function" then
        task.spawn(self.OnError, message, statusCode)
    else
        warn("WebsiteUIBridge: " .. tostring(message))
    end
end

function WebsiteUIBridge:Pair(code)
    local data, err = jsonRequest(self.BaseUrl .. "/api/ui/device/pair", "POST", {
        code = tostring(code or ""),
        deviceId = self.DeviceId,
    })
    if not data then return false, err end
    self.Token = data.token
    self:_save()
    return true
end

function WebsiteUIBridge:Bind(flag, callback, fireImmediately)
    assert(type(flag) == "string" and flag ~= "", "Bind flag must be a non-empty string")
    assert(type(callback) == "function", "Bind callback must be a function")
    self.Bindings[flag] = self.Bindings[flag] or {}
    table.insert(self.Bindings[flag], callback)
    if fireImmediately and self.Values[flag] ~= nil then
        task.spawn(callback, self.Values[flag], nil, flag)
    end
    return callback
end

function WebsiteUIBridge:BindValue(flag, callback, fireImmediately)
    return self:Bind(flag, callback, fireImmediately)
end

function WebsiteUIBridge:BindToggle(flag, enableCallback, disableCallback, fireImmediately)
    assert(type(enableCallback) == "function", "BindToggle enable callback must be a function")
    assert(type(disableCallback) == "function", "BindToggle disable callback must be a function")
    return self:Bind(flag, function(enabled, previous)
        if enabled == true then
            enableCallback(previous)
        else
            disableCallback(previous)
        end
    end, fireImmediately)
end

function WebsiteUIBridge:BindFeature(flag, feature, fireImmediately)
    assert(type(feature) == "table", "BindFeature feature must be a table")
    local setEnabled = feature.SetEnabled
    if type(setEnabled) == "function" then
        return self:Bind(flag, function(enabled)
            setEnabled(enabled == true)
        end, fireImmediately)
    end

    assert(type(feature.Enable) == "function", "BindFeature feature needs Enable or SetEnabled")
    assert(type(feature.Disable) == "function", "BindFeature feature needs Disable or SetEnabled")
    return self:BindToggle(flag, function()
        feature:Enable()
    end, function()
        feature:Disable()
    end, fireImmediately)
end

function WebsiteUIBridge:BindButton(flag, callback)
    assert(type(callback) == "function", "BindButton callback must be a function")
    return self:Bind(flag, function(sequence, previous)
        callback(sequence, previous)
    end, false)
end

function WebsiteUIBridge:OnConnection(callback, fireImmediately)
    assert(type(callback) == "function", "OnConnection callback must be a function")
    local connection = self.ConnectionChanged.Event:Connect(callback)
    if fireImmediately then task.spawn(callback, self.Connected) end
    return connection
end

function WebsiteUIBridge:BindEspHandler(espHandler, espName, fireImmediately)
    assert(type(espHandler) == "table" and type(espHandler.ApplyLayout) == "function", "ESP handler must provide ApplyLayout")
    local function apply(layout)
        espHandler.ApplyLayout(layout, espName)
    end
    self.OnEspLayout = apply
    if fireImmediately ~= false and self.EspLayout then task.spawn(apply, self.EspLayout) end
    return apply
end

local function colorHex(color)
    return string.format("#%02x%02x%02x", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function assetIdFromReference(value)
    local text = tostring(value or "")
    return text:match("^%s*(%d+)%s*$")
        or text:match("[Rr][Bb][Xx][Aa][Ss][Ss][Ee][Tt][Ii][Dd]://(%d+)")
        or text:match("[?&][Ii][Dd]=(%d+)")
end

function WebsiteUIBridge:CreateModelSnapshot(model, options)
    options = options or {}
    assert(typeof(model) == "Instance" and model:IsA("Model"), "CreateModelSnapshot expects a Model")
    local maximumParts = math.clamp(math.floor(tonumber(options.MaxParts) or 160), 1, 160)
    local pivot = model:GetPivot()
    local parts, partIndexes = {}, {}
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and #parts < maximumParts then
            local relative = pivot:ToObjectSpace(descendant.CFrame)
            local rx, ry, rz = relative:ToOrientation()
            local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relative:GetComponents()
            local shape = "Box"
            if descendant:IsA("Part") then
                if descendant.Shape == Enum.PartType.Ball then shape = "Ball"
                elseif descendant.Shape == Enum.PartType.Cylinder then shape = "Cylinder" end
            end
            local item = {
                name = descendant.Name,
                className = descendant.ClassName,
                shape = shape,
                size = { descendant.Size.X, descendant.Size.Y, descendant.Size.Z },
                position = { relative.Position.X, relative.Position.Y, relative.Position.Z },
                rotation = { rx, ry, rz },
                rotationMatrix = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
                color = colorHex(descendant.Color),
                transparency = descendant.Transparency,
                material = descendant.Material.Name,
                reflectance = descendant.Reflectance,
                textures = {},
            }
            if descendant:IsA("MeshPart") then
                item.meshId = descendant.MeshId
                item.textureId = descendant.TextureID
                item.meshSize = { descendant.MeshSize.X, descendant.MeshSize.Y, descendant.MeshSize.Z }
            end
            local specialMesh = descendant:FindFirstChildOfClass("SpecialMesh")
            if specialMesh then
                item.meshId = specialMesh.MeshId
                item.textureId = specialMesh.TextureId
                item.meshScale = { specialMesh.Scale.X, specialMesh.Scale.Y, specialMesh.Scale.Z }
                item.meshOffset = { specialMesh.Offset.X, specialMesh.Offset.Y, specialMesh.Offset.Z }
                item.meshVertexColor = { specialMesh.VertexColor.X, specialMesh.VertexColor.Y, specialMesh.VertexColor.Z }
            end
            local accessory = descendant:FindFirstAncestorOfClass("Accessory")
            if accessory then
                item.accessory = { name = accessory.Name, type = accessory.AccessoryType.Name }
            end
            for _, child in ipairs(descendant:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    table.insert(item.textures, {
                        assetId = child.Texture,
                        face = child.Face.Name,
                        kind = child.ClassName,
                    })
                end
            end
            local surface = descendant:FindFirstChildOfClass("SurfaceAppearance")
            if surface then
                item.surfaceAppearance = {
                    colorMap = surface.ColorMap,
                    metalnessMap = surface.MetalnessMap,
                    normalMap = surface.NormalMap,
                    roughnessMap = surface.RoughnessMap,
                    alphaMode = surface.AlphaMode.Name,
                }
            end
            table.insert(parts, item)
            partIndexes[descendant] = #parts
        end
    end
    local joints = {}
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            local fromIndex = partIndexes[descendant.Part0]
            local toIndex = partIndexes[descendant.Part1]
            if fromIndex and toIndex then
                table.insert(joints, { from = fromIndex, to = toIndex, name = descendant.Name })
            end
        end
    end
    local appearance = {}
    local shirt = model:FindFirstChildOfClass("Shirt")
    local pants = model:FindFirstChildOfClass("Pants")
    local shirtGraphic = model:FindFirstChildOfClass("ShirtGraphic")
    if shirt then appearance.shirtTemplate = shirt.ShirtTemplate end
    if pants then appearance.pantsTemplate = pants.PantsTemplate end
    if shirtGraphic then appearance.shirtGraphic = shirtGraphic.Graphic end
    return { version = 3, name = model.Name, parts = parts, joints = joints, appearance = appearance }
end

function WebsiteUIBridge:GetModelAssetIds(snapshot)
    local ids, seen = {}, {}
    local function add(value)
        local id = assetIdFromReference(value)
        if id and id ~= "0" and not seen[id] and #ids < 80 then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    for _, part in ipairs(type(snapshot) == "table" and snapshot.parts or {}) do
        add(part.meshId)
        add(part.textureId)
        for _, texture in ipairs(type(part.textures) == "table" and part.textures or {}) do
            add(texture.assetId)
        end
        local surface = part.surfaceAppearance
        if type(surface) == "table" then
            add(surface.colorMap)
            add(surface.metalnessMap)
            add(surface.normalMap)
            add(surface.roughnessMap)
        end
    end
    local appearance = type(snapshot) == "table" and snapshot.appearance or nil
    if type(appearance) == "table" then
        add(appearance.shirtTemplate)
        add(appearance.pantsTemplate)
        add(appearance.shirtGraphic)
    end
    return ids
end

function WebsiteUIBridge:CacheAssets(assetIds, placeId)
    if not self.Token or self.Token == "" then return false, "Pair the bridge first." end
    local unique, seen = {}, {}
    for _, value in ipairs(type(assetIds) == "table" and assetIds or {}) do
        local id = assetIdFromReference(value)
        if id and id ~= "0" and not seen[id] and #unique < 80 then
            seen[id] = true
            table.insert(unique, id)
        end
    end
    if #unique == 0 then return true, { requested = 0, cached = {}, failed = {} } end
    local data, err = jsonRequest(self.BaseUrl .. "/api/ui/device/assets/cache", "POST", {
        assetIds = unique,
        placeId = tostring(placeId or game.PlaceId or ""),
    }, self.Token)
    if not data then return false, err end
    return true, data
end

function WebsiteUIBridge:PublishLocalCharacter(options)
    local players = game:GetService("Players")
    local player = players.LocalPlayer
    local character = player and player.Character
    if not character then return false, "LocalPlayer character is not available." end
    return self:PublishModel(character, options)
end

function WebsiteUIBridge:PublishModel(model, options)
    if not self.Token or self.Token == "" then return false, "Pair the bridge first." end
    local snapshot = self:CreateModelSnapshot(model, options)
    local data, err = jsonRequest(self.BaseUrl .. "/api/ui/device/model", "POST", { snapshot = snapshot }, self.Token)
    if not data then return false, err end
    if options and options.CacheAssets == true then
        local cacheOk, cacheResult = self:CacheAssets(self:GetModelAssetIds(snapshot), game.PlaceId)
        data.assetCache = cacheOk and cacheResult or { requested = 0, cached = {}, failed = {}, error = cacheResult }
    end
    return true, data
end

function WebsiteUIBridge:StartModelStreaming(modelProvider, interval, options)
    assert(type(modelProvider) == "function" or typeof(modelProvider) == "Instance", "Model provider must be a Model or function")
    self.ModelStreaming = true
    task.spawn(function()
        while self.ModelStreaming do
            local model = type(modelProvider) == "function" and modelProvider() or modelProvider
            if typeof(model) == "Instance" and model:IsA("Model") then
                local ok, err = self:PublishModel(model, options)
                if not ok then self:_error(err, 0) end
            end
            task.wait(math.max(tonumber(interval) or 20, 5))
        end
    end)
    return self
end

function WebsiteUIBridge:StopModelStreaming()
    self.ModelStreaming = false
    return self
end

function WebsiteUIBridge:Unbind(flag, callback)
    local callbacks = self.Bindings[flag]
    if not callbacks then return end
    for index = #callbacks, 1, -1 do
        if not callback or callbacks[index] == callback then
            table.remove(callbacks, index)
        end
    end
end

function WebsiteUIBridge:Get(flag, defaultValue)
    local value = self.Values[flag]
    return value == nil and defaultValue or value
end

function WebsiteUIBridge:_dispatch(flag, value, previous)
    self.Changed:Fire(flag, value, previous)
    for _, callback in ipairs(self.Bindings[flag] or {}) do
        task.spawn(function()
            local ok, err = pcall(callback, value, previous, flag)
            if not ok then self:_error("Callback for " .. flag .. " failed: " .. tostring(err)) end
        end)
    end
end

function WebsiteUIBridge:_setConnected(connected)
    connected = connected == true
    if self.Connected == connected then return end
    self.Connected = connected
    self.ConnectionChanged:Fire(connected)
    if connected and type(self.OnConnected) == "function" then
        task.spawn(self.OnConnected, self.Project)
    end
end

function WebsiteUIBridge:PollOnce()
    if not self.Token or self.Token == "" then
        self:_setConnected(false)
        return false, "Pair the bridge first."
    end
    local data, err, statusCode = jsonRequest(self.BaseUrl .. "/api/ui/device/config", "GET", nil, self.Token)
    if not data then
        self:_setConnected(false)
        if statusCode == 401 or statusCode == 403 then
            self.Token = nil
            self:_save()
        end
        self:_error(err, statusCode)
        return false, err
    end

    local projectChanged = not self.Project or self.Revision ~= tonumber(data.project and data.project.revision)
    self.Project = data.project
    self.Revision = tonumber(data.project and data.project.revision) or self.Revision
    self:_setConnected(true)
    if projectChanged and type(self.OnSchema) == "function" then
        task.spawn(self.OnSchema, self.Project)
    end

    local espLayoutJson = HttpService:JSONEncode(data.espLayout or {})
    if espLayoutJson ~= self.EspLayoutJson then
        self.EspLayout = data.espLayout
        self.EspLayoutJson = espLayoutJson
        if type(self.OnEspLayout) == "function" then task.spawn(self.OnEspLayout, self.EspLayout) end
    end

    local controlTypes = {}
    for _, group in ipairs((self.Project and self.Project.groups) or {}) do
        for _, control in ipairs(group.controls or {}) do
            controlTypes[control.flag] = control.type
        end
    end

    for flag, value in pairs(data.values or {}) do
        local previous = self.Values[flag]
        self.Values[flag] = value
        if (previous ~= nil and previous ~= value) or (previous == nil and controlTypes[flag] ~= "button") then
            self:_dispatch(flag, value, previous)
        end
    end
    return true, data
end

function WebsiteUIBridge:Start()
    if self.Running then return self end
    self.Running = true
    task.spawn(function()
        self:PollOnce()
        while self.Running do
            task.wait(self.PollInterval)
            self:PollOnce()
        end
    end)
    return self
end

function WebsiteUIBridge:Stop()
    self.Running = false
    self.ModelStreaming = false
    self:_setConnected(false)
    return self
end

function WebsiteUIBridge:ForgetDevice()
    self:Stop()
    self.Token = nil
    self.Values = {}
    self.Project = nil
    self.EspLayout = nil
    self.EspLayoutJson = ""
    self:_setConnected(false)
    self:_save()
end

function WebsiteUIBridge:Destroy()
    self:Stop()
    self.Bindings = {}
    self.Changed:Destroy()
    self.ConnectionChanged:Destroy()
end

return WebsiteUIBridge
