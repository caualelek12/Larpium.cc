local HttpService = game:GetService("HttpService")

local WebsiteUIBridge = {}
WebsiteUIBridge.__index = WebsiteUIBridge
WebsiteUIBridge.Version = "2026-07-14"

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

    local response = request({
        Url = url,
        Method = method or "GET",
        Headers = headers,
        Body = body and HttpService:JSONEncode(body) or nil,
    })
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
    self.BaseUrl = trimSlash(options.BaseUrl)
    assert(self.BaseUrl:match("^https?://"), "WebsiteUIBridge BaseUrl must start with http:// or https://")
    local localHttp = self.BaseUrl:match("^http://localhost[:/]") or self.BaseUrl:match("^http://127%.0%.0%.1[:/]")
    assert(not self.BaseUrl:match("^http://") or localHttp or options.AllowInsecure == true,
        "WebsiteUIBridge requires HTTPS. Set AllowInsecure = true only for temporary HTTP testing.")

    self.PollInterval = math.max(tonumber(options.PollInterval) or 1, 0.25)
    self.StoragePath = options.StoragePath or "Larpium/website-ui.json"
    self.Bindings = {}
    self.Values = {}
    self.Project = nil
    self.Revision = 0
    self.Running = false
    self.OnError = options.OnError
    self.OnSchema = options.OnSchema
    self.Changed = Instance.new("BindableEvent")

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

function WebsiteUIBridge:PollOnce()
    if not self.Token or self.Token == "" then return false, "Pair the bridge first." end
    local data, err, statusCode = jsonRequest(self.BaseUrl .. "/api/ui/device/config", "GET", nil, self.Token)
    if not data then
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
    if projectChanged and type(self.OnSchema) == "function" then
        task.spawn(self.OnSchema, self.Project)
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
    return self
end

function WebsiteUIBridge:ForgetDevice()
    self:Stop()
    self.Token = nil
    self.Values = {}
    self.Project = nil
    self:_save()
end

function WebsiteUIBridge:Destroy()
    self:Stop()
    self.Bindings = {}
    self.Changed:Destroy()
end

return WebsiteUIBridge
