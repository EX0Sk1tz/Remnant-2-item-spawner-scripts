local Spawner = require("spawner")
local json = require("json")

local Queue = {}

local MOD_DIR = "Mods/Remnant2Unlocker/"
local ITEMS_PATH = MOD_DIR .. "items.json"
local QUEUE_PATH = MOD_DIR .. "command_queue.json"
local STATUS_PATH = MOD_DIR .. "status.json"

local lastProcessedId = 0
local isBusy = false
local items = {}

local status = {
    ready = false,
    busy = false,
    lastCommandId = 0,
    lastAction = "none",
    lastMessage = "Starting bridge",
    lastSpawned = nil,
    processedCount = 0,
    totalCount = 0,
    error = nil
}

local function ReadAllText(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    return content
end

local function WriteAllText(path, content)
    local file = io.open(path, "w")
    if not file then return false end

    file:write(content)
    file:close()

    return true
end

local function DecodeJson(content)
    if not content or content == "" then return nil end

    local ok, decoded = pcall(function()
        return json.decode(content)
    end)

    if not ok then
        print("[Remnant2Unlocker] JSON decode failed: " .. tostring(decoded))
        return nil
    end

    return decoded
end

local function EncodeJson(value)
    local ok, encoded = pcall(function()
        return json.encode(value)
    end)

    if not ok then
        print("[Remnant2Unlocker] JSON encode failed: " .. tostring(encoded))
        return "{}"
    end

    return encoded
end

local function SaveStatus()
    status.busy = isBusy
    WriteAllText(STATUS_PATH, EncodeJson(status))
end

local function SetStatus(message, errorMessage)
    status.lastMessage = message
    status.error = errorMessage
    SaveStatus()
    print("[Remnant2Unlocker] " .. message)
end

local function LoadItems()
    local content = ReadAllText(ITEMS_PATH)

    if not content then
        items = {}
        SetStatus("items.json not found", "Missing items.json")
        return
    end

    local decoded = DecodeJson(content)

    if not decoded then
        items = {}
        SetStatus("items.json could not be parsed", "Invalid items.json")
        return
    end

    items = decoded
    status.totalCount = #items
    status.ready = true

    SetStatus("Loaded " .. tostring(#items) .. " items", nil)
end

local function FindItemByName(name)
    if not name then return nil end

    local query = tostring(name):lower()

    for _, item in ipairs(items) do
        if item.name and tostring(item.name):lower() == query then
            return item
        end
    end

    return nil
end

local function GetPathsForTypes(types)
    local lookup = {}
    local paths = {}

    if not types then return paths end

    for _, itemType in ipairs(types) do
        lookup[tostring(itemType):lower()] = true
    end

    for _, item in ipairs(items) do
        local itemType = tostring(item.type or ""):lower()

        if lookup[itemType] and item.path then
            table.insert(paths, item.path)
        end
    end

    return paths
end

local function SpawnSingle(command)
    local path = command.path

    if not path and command.name then
        local item = FindItemByName(command.name)
        if item then
            path = item.path
        end
    end

    local ok, result = Spawner.SpawnPath(path)

    if ok then
        status.lastSpawned = result
        status.processedCount = status.processedCount + 1
        SetStatus("Spawned item: " .. tostring(command.name or result), nil)
    else
        SetStatus("Spawn failed", result)
    end
end

local function SpawnManyImmediate(paths)
    if not paths then
        SetStatus("No paths provided", "Missing paths")
        return
    end

    local count = 0
    local failed = 0

    for _, path in ipairs(paths) do
        local ok, result = Spawner.SpawnPath(path)

        if ok then
            count = count + 1
            status.lastSpawned = result
            status.processedCount = status.processedCount + 1
        else
            failed = failed + 1
            print("[Remnant2Unlocker] Spawn failed: " .. tostring(result))
        end

        SaveStatus()
    end

    if failed > 0 then
        SetStatus("Spawned " .. tostring(count) .. " items, failed " .. tostring(failed), "Some items failed")
    else
        SetStatus("Spawned " .. tostring(count) .. " items", nil)
    end
end

local function UnlockTypes(command)
    local paths = GetPathsForTypes(command.types)
    SpawnManyImmediate(paths)
end

local function ProcessCommand(command)
    if not command then return end

    local commandId = tonumber(command.id) or 0

    if commandId <= lastProcessedId then
        return
    end

    lastProcessedId = commandId

    if command.action == "idle" then
        return
    end

    status.lastCommandId = commandId
    status.lastAction = tostring(command.action or "unknown")

    isBusy = true
    SaveStatus()

    print("[Remnant2Unlocker] Processing command " .. tostring(commandId) .. ": " .. tostring(command.action))

    if command.action == "spawn" then
        SpawnSingle(command)
    elseif command.action == "spawn_many" then
        SpawnManyImmediate(command.paths)
    elseif command.action == "unlock_types" then
        UnlockTypes(command)
    elseif command.action == "reload_items" then
        LoadItems()
    else
        SetStatus("Unknown command: " .. tostring(command.action), "Unknown action")
    end

    isBusy = false
    SaveStatus()
end

function Queue.Tick()
    if isBusy then return end

    local content = ReadAllText(QUEUE_PATH)

    if not content then
        SetStatus("command_queue.json not found", "Missing command_queue.json")
        return
    end

    local command = DecodeJson(content)

    if not command then
        SetStatus("command_queue.json could not be parsed", "Invalid command_queue.json")
        return
    end

    ProcessCommand(command)
end

local function ScheduleTick()
    ExecuteWithDelay(250, function()
        Queue.Tick()
        ScheduleTick()
    end)
end

function Queue.Start()
    LoadItems()
    SaveStatus()

    local content = ReadAllText(QUEUE_PATH)
    local command = DecodeJson(content)

    if command and command.id then
        lastProcessedId = tonumber(command.id) or 0
    else
        lastProcessedId = 0
    end

    print("[Remnant2Unlocker] Queue baseline id: " .. tostring(lastProcessedId))

    ScheduleTick()
end

return Queue