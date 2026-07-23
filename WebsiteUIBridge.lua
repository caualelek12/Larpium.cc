local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local AssetService = game:GetService("AssetService")

local WebsiteUIBridge = {}
WebsiteUIBridge.__index = WebsiteUIBridge
WebsiteUIBridge.Version = "2026-07-23-generic-model-geometry-v15"
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

local function contentUri(value)
    if value == nil then return "" end
    local ok, uri = pcall(function() return value.Uri end)
    return ok and type(uri) == "string" and uri or ""
end

local function contentPropertyUri(instance, property)
    local ok, value = pcall(function() return instance[property] end)
    return ok and contentUri(value) or ""
end

local function roundedNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    local scaled = value * 100000
    return (scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)) / 100000
end

local function appendVector3(target, value)
    target[#target + 1] = roundedNumber(value.X)
    target[#target + 1] = roundedNumber(value.Y)
    target[#target + 1] = roundedNumber(value.Z)
end

local function appendVector2(target, value)
    target[#target + 1] = roundedNumber(value.X)
    target[#target + 1] = roundedNumber(value.Y)
end

local function meshContentForPart(part, specialMesh)
    if part:IsA("MeshPart") then
        local ok, content = pcall(function() return part.MeshContent end)
        if ok and content then return content end
    end
    local uri = specialMesh and specialMesh.MeshId or (part:IsA("MeshPart") and part.MeshId or "")
    if uri == "" then return nil end
    local ok, content = pcall(function() return Content.fromUri(uri) end)
    return ok and content or nil
end

local function captureMeshGeometry(part, specialMesh, triangleLimit)
    if triangleLimit <= 0 then return nil, 0 end
    local deformation = "raw"
    local editableMesh
    local wrapDeformer = part:FindFirstChildWhichIsA("WrapDeformer", true)
    if wrapDeformer then
        local deformerOk, deformedMesh = pcall(function() return wrapDeformer:CreateEditableMeshAsync() end)
        if deformerOk and deformedMesh then
            editableMesh = deformedMesh
            deformation = "wrap"
        end
    end
    local content = not editableMesh and meshContentForPart(part, specialMesh) or nil
    if not editableMesh and not content then return nil, 0 end
    local ok = editableMesh ~= nil
    if not editableMesh then
        ok, editableMesh = pcall(function()
            return AssetService:CreateEditableMeshAsync(content)
        end)
    end
    if not ok or not editableMesh then return nil, 0 end

    local boneTransforms = {}
    if deformation == "raw" then
        local bonesOk, boneIds = pcall(function() return editableMesh:GetBones() end)
        if bonesOk then
            for _, boneId in ipairs(boneIds) do
                local nameOk, boneName = pcall(function() return editableMesh:GetBoneName(boneId) end)
                local bindOk, bindCFrame = pcall(function() return editableMesh:GetBoneCFrame(boneId) end)
                local liveBone = nameOk and part:FindFirstChild(boneName, true) or nil
                if bindOk and liveBone and liveBone:IsA("Bone") then
                    local currentOk, currentWorld = pcall(function() return liveBone.TransformedWorldCFrame end)
                    if currentOk then
                        boneTransforms[boneId] = part.CFrame:ToObjectSpace(currentWorld) * bindCFrame:Inverse()
                    end
                end
            end
        end
        if next(boneTransforms) then deformation = "bones" end
    end

    local function deformVertex(vertexId, position, normal)
        if deformation ~= "bones" then return position, normal end
        local idsOk, boneIds = pcall(function() return editableMesh:GetVertexBones(vertexId) end)
        local weightsOk, weights = pcall(function() return editableMesh:GetVertexBoneWeights(vertexId) end)
        if not idsOk or not weightsOk or #boneIds == 0 then return position, normal end
        local deformedPosition = Vector3.zero
        local deformedNormal = Vector3.zero
        local totalWeight = 0
        for index, boneId in ipairs(boneIds) do
            local transform = boneTransforms[boneId]
            local weight = tonumber(weights[index]) or 0
            if transform and weight > 0 then
                deformedPosition = deformedPosition + transform:PointToWorldSpace(position) * weight
                if normal then deformedNormal = deformedNormal + transform:VectorToWorldSpace(normal) * weight end
                totalWeight = totalWeight + weight
            end
        end
        if totalWeight <= 0 then return position, normal end
        if totalWeight < 1 then
            deformedPosition = deformedPosition + position * (1 - totalWeight)
            if normal then deformedNormal = deformedNormal + normal * (1 - totalWeight) end
        end
        return deformedPosition, normal and deformedNormal.Magnitude > 0 and deformedNormal.Unit or normal
    end

    local positions, normals, uvs = {}, {}, {}
    local captured = 0
    local facesOk, faces = pcall(function() return editableMesh:GetFaces() end)
    if facesOk then
        for _, faceId in ipairs(faces) do
            if captured >= triangleLimit then break end
            local verticesOk, vertices = pcall(function() return editableMesh:GetFaceVertices(faceId) end)
            local uvsOk, uvIds = pcall(function() return editableMesh:GetFaceUVs(faceId) end)
            local normalsOk, normalIds = pcall(function() return editableMesh:GetFaceNormals(faceId) end)
            if verticesOk and #vertices >= 3 then
                local facePositions, faceNormals, faceUvs = {}, {}, {}
                local valid = true
                for corner = 1, 3 do
                    local positionOk, position = pcall(function() return editableMesh:GetPosition(vertices[corner]) end)
                    if not positionOk then valid = false break end
                    local normal
                    if normalsOk and normalIds[corner] then
                        local normalOk, result = pcall(function() return editableMesh:GetNormal(normalIds[corner]) end)
                        if normalOk then normal = result end
                    end
                    position, normal = deformVertex(vertices[corner], position, normal)
                    appendVector3(facePositions, position)
                    if normal then appendVector3(faceNormals, normal) end
                    if uvsOk and uvIds[corner] then
                        local uvOk, uv = pcall(function() return editableMesh:GetUV(uvIds[corner]) end)
                        if uvOk then appendVector2(faceUvs, uv) end
                    end
                end
                if valid then
                    for _, value in ipairs(facePositions) do positions[#positions + 1] = value end
                    if #faceNormals == 9 then for _, value in ipairs(faceNormals) do normals[#normals + 1] = value end end
                    if #faceUvs == 6 then for _, value in ipairs(faceUvs) do uvs[#uvs + 1] = value end end
                    captured = captured + 1
                end
            end
        end
    end
    pcall(function() editableMesh:Destroy() end)
    if captured == 0 then return nil, 0 end
    return {
        positions = positions,
        normals = #normals == #positions and normals or nil,
        uvs = #uvs * 3 == #positions * 2 and uvs or nil,
        triangleCount = captured,
        deformation = deformation,
    }, captured
end

local function isSkeletonBodyPart(part, rootModel)
    if not part:IsA("BasePart") then return false end
    if part:FindFirstAncestorOfClass("Accessory") or part:FindFirstAncestorOfClass("Tool") then return false end
    return part:FindFirstAncestorOfClass("Model") == rootModel
end

local function createStaticPoseClone(model)
    local previousArchivable = model.Archivable
    model.Archivable = true
    local ok, clone = pcall(function() return model:Clone() end)
    model.Archivable = previousArchivable
    if not ok or not clone then return nil end

    local rootPart = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
    if not rootPart then return clone end

    local joints = {}
    local constraints = {}
    for _, descendant in ipairs(clone:GetDescendants()) do
        if (descendant:IsA("Motor6D") or descendant:IsA("Weld")) and descendant.Part0 and descendant.Part1 then
            table.insert(joints, descendant)
        elseif descendant:IsA("WeldConstraint") and descendant.Part0 and descendant.Part1 then
            table.insert(constraints, {
                Part0 = descendant.Part0,
                Part1 = descendant.Part1,
                Offset = descendant.Part0.CFrame:ToObjectSpace(descendant.Part1.CFrame),
            })
        end
    end
    rootPart.CFrame = CFrame.new(rootPart.Position)

    local solved = { [rootPart] = true }
    for _ = 1, #joints + #constraints + 1 do
        local changed = false
        for _, joint in ipairs(joints) do
            local part0, part1 = joint.Part0, joint.Part1
            if solved[part0] and not solved[part1] then
                part1.CFrame = part0.CFrame * joint.C0 * joint.C1:Inverse()
                solved[part1] = true
                changed = true
            elseif solved[part1] and not solved[part0] then
                part0.CFrame = part1.CFrame * joint.C1 * joint.C0:Inverse()
                solved[part0] = true
                changed = true
            end
        end
        for _, constraint in ipairs(constraints) do
            local part0, part1 = constraint.Part0, constraint.Part1
            if solved[part0] and not solved[part1] then
                part1.CFrame = part0.CFrame * constraint.Offset
                solved[part1] = true
                changed = true
            elseif solved[part1] and not solved[part0] then
                part0.CFrame = part1.CFrame * constraint.Offset:Inverse()
                solved[part0] = true
                changed = true
            end
        end
        if not changed then break end
    end
    return clone
end

function WebsiteUIBridge:CreateModelSnapshot(model, options)
    options = options or {}
    assert(typeof(model) == "Instance" and model:IsA("Model"), "CreateModelSnapshot expects a Model")
    local snapshotModel = options.StaticPose == true and createStaticPoseClone(model) or model
    if not snapshotModel then snapshotModel = model end
    local ownsSnapshotModel = snapshotModel ~= model
    local maximumParts = math.clamp(math.floor(tonumber(options.MaxParts) or 160), 1, 160)
    local maximumTriangles = math.clamp(math.floor(tonumber(options.MaxTriangles) or 80000), 0, 100000)
    local maximumTrianglesPerPart = math.clamp(math.floor(tonumber(options.MaxTrianglesPerPart) or 30000), 0, 40000)
    local remainingTriangles = maximumTriangles
    local pivot = snapshotModel:GetPivot()
    local parts, partIndexes = {}, {}
    for _, descendant in ipairs(snapshotModel:GetDescendants()) do
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
                skeletonPart = isSkeletonBodyPart(descendant, snapshotModel),
                layered = descendant:FindFirstChildWhichIsA("WrapLayer", true) ~= nil,
                textures = {},
            }
            if descendant:IsA("MeshPart") then
                item.meshId = descendant.MeshId ~= "" and descendant.MeshId or contentPropertyUri(descendant, "MeshContent")
                item.textureId = descendant.TextureID ~= "" and descendant.TextureID or contentPropertyUri(descendant, "TextureContent")
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
            if options.IncludeGeometry ~= false and item.meshId and remainingTriangles > 0 then
                local geometry, captured = captureMeshGeometry(descendant, specialMesh, math.min(maximumTrianglesPerPart, remainingTriangles))
                if geometry then
                    item.geometry = geometry
                    item.geometryStatus = "captured"
                else
                    item.geometryStatus = "unavailable"
                end
                remainingTriangles = remainingTriangles - captured
            elseif item.meshId and remainingTriangles <= 0 then
                item.geometryStatus = "budget"
            elseif descendant:IsA("PartOperation") then
                item.geometryStatus = "unsupported-csg"
            end
            local accessory = descendant:FindFirstAncestorOfClass("Accessory")
            if accessory then
                item.accessory = { name = accessory.Name, type = accessory.AccessoryType.Name }
            end
            for _, child in ipairs(descendant:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then
                    local textureReference = child.Texture
                    if textureReference == "" then textureReference = contentPropertyUri(child, "TextureContent") end
                    local textureItem = {
                        assetId = textureReference,
                        face = child.Face.Name,
                        kind = child.ClassName,
                    }
                    if child:IsA("Texture") then
                        textureItem.studsPerTileU = child.StudsPerTileU
                        textureItem.studsPerTileV = child.StudsPerTileV
                        textureItem.offsetStudsU = child.OffsetStudsU
                        textureItem.offsetStudsV = child.OffsetStudsV
                    end
                    table.insert(item.textures, textureItem)
                end
            end
            local surface = descendant:FindFirstChildOfClass("SurfaceAppearance")
            if surface then
                item.surfaceAppearance = {
                    colorMap = surface.ColorMap ~= "" and surface.ColorMap or contentPropertyUri(surface, "ColorMapContent"),
                    metalnessMap = surface.MetalnessMap ~= "" and surface.MetalnessMap or contentPropertyUri(surface, "MetalnessMapContent"),
                    normalMap = surface.NormalMap ~= "" and surface.NormalMap or contentPropertyUri(surface, "NormalMapContent"),
                    roughnessMap = surface.RoughnessMap ~= "" and surface.RoughnessMap or contentPropertyUri(surface, "RoughnessMapContent"),
                    alphaMode = surface.AlphaMode.Name,
                }
            end
            table.insert(parts, item)
            partIndexes[descendant] = #parts
        end
    end
    local joints = {}
    for _, descendant in ipairs(snapshotModel:GetDescendants()) do
        if descendant:IsA("Motor6D") and descendant:FindFirstAncestorOfClass("Model") == snapshotModel
            and descendant.Part0 and descendant.Part1
            and isSkeletonBodyPart(descendant.Part0, snapshotModel) and isSkeletonBodyPart(descendant.Part1, snapshotModel) then
            local fromIndex = partIndexes[descendant.Part0]
            local toIndex = partIndexes[descendant.Part1]
            if fromIndex and toIndex then
                table.insert(joints, { from = fromIndex, to = toIndex, name = descendant.Name })
            end
        end
    end
    local appearance = {}
    local shirt = snapshotModel:FindFirstChildOfClass("Shirt")
    local pants = snapshotModel:FindFirstChildOfClass("Pants")
    local shirtGraphic = snapshotModel:FindFirstChildOfClass("ShirtGraphic")
    if shirt then appearance.shirtTemplate = shirt.ShirtTemplate end
    if pants then appearance.pantsTemplate = pants.PantsTemplate end
    if shirtGraphic then appearance.shirtGraphic = shirtGraphic.Graphic end
    local snapshot = {
        version = 6,
        name = model.Name,
        userId = tostring(options.UserId or ""),
        sourceKind = options.AvatarThumbnail == true and "avatar" or "model",
        geometryTriangles = maximumTriangles - remainingTriangles,
        parts = parts,
        joints = joints,
        appearance = appearance,
    }
    if ownsSnapshotModel then snapshotModel:Destroy() end
    return snapshot
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
    options = options or {}
    local publishOptions = {}
    for key, value in pairs(options) do publishOptions[key] = value end
    publishOptions.UserId = publishOptions.UserId or player.UserId
    if publishOptions.AvatarThumbnail == nil then publishOptions.AvatarThumbnail = false end
    return self:PublishModel(character, publishOptions)
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
