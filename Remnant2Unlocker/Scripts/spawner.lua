local UEHelpers = require("UEHelpers")
local json = require("json")

local Spawner = {}

-- Actor(s) created by the most recent SpawnPath call, tracked so DestroyLastSpawned (see
-- Scripts/destroy.lua) can target them by object reference instead of a camera-aim trace, which
-- is what makes the built-in "DestroyTarget" console command hit the floor instead of a small
-- item pickup. Only the latest spawn is kept -- actor references don't survive a game restart,
-- so DestroyNearbySpawned can't use them for older items; see knownSpawnedClasses below instead.
local lastSpawnedActors = {}

-- Every Blueprint class name ever spawned through this mod, persisted to disk so
-- DestroyNearbySpawned can scan for old items after a restart without having to FindAllOf() the
-- entire ~800-class item catalog every time (that took ~48s and crashed on a class default
-- object in testing -- see Scripts/destroy.lua). Lazily loaded once, then kept in memory as a
-- set and only re-written to disk when a genuinely new class is spawned.
local SPAWNED_CLASSES_PATH = "Mods/Remnant2Unlocker/spawned_classes.json"
local knownSpawnedClasses = nil

local function NormalizePath(path)
    if not path then
        return ""
    end

    local value = tostring(path)
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("|", "")

    if value:lower():sub(1, 7) == "summon " then
        value = value:sub(8)
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return value
end

local function ClampNumber(value, fallback, minValue, maxValue)
    local n = tonumber(value) or fallback

    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end

    return n
end

local function BuildSummonCommand(path, dropQuantity, stackSize, itemLevel)
    local normalizedPath = NormalizePath(path)

    if normalizedPath == "" then
        return nil, "Empty spawn path"
    end

    local drop = ClampNumber(dropQuantity, 1, 1, 999)
    local stack = ClampNumber(stackSize, 1, 1, 999)
    local level = tonumber(itemLevel) or 0

    if level > 0 then
        return string.format("summon %s %d %d %d", normalizedPath, drop, stack, level), nil
    end

    return string.format("summon %s %d %d", normalizedPath, drop, stack), nil
end

local function IsValidObject(obj)
    if not obj then return false end

    local ok, valid = pcall(function()
        if obj.IsValid then
            return obj:IsValid()
        end

        return true
    end)

    return ok and valid == true
end

-- The spawn path looks like "/Game/.../Weapon_CrescentMoon.Weapon_CrescentMoon_C" -- the
-- segment after the last "." is the actual Blueprint class name, which is what FindAllOf
-- expects.
local function GetClassNameFromPath(path)
    if not path then return nil end

    return tostring(path):match("%.([%w_]+)$")
end

-- GetFullName() returns a name that is unique per UObject instance within the running game
-- (engine-enforced), so it's a safe identity key across two separate FindAllOf snapshots even
-- though each call returns fresh Lua wrapper tables for the same underlying objects.
local function GetActorKey(actor)
    local ok, name = pcall(function() return actor:GetFullName() end)

    if ok and name then
        return name
    end

    return tostring(actor)
end

local function SnapshotActorsByClass(className)
    local snapshot = {}

    if not className then
        return snapshot
    end

    local ok, list = pcall(function() return FindAllOf(className) end)

    if not ok or not list then
        return snapshot
    end

    for _, actor in ipairs(list) do
        if IsValidObject(actor) then
            snapshot[GetActorKey(actor)] = actor
        end
    end

    return snapshot
end

local function LoadKnownSpawnedClasses()
    if knownSpawnedClasses then
        return knownSpawnedClasses
    end

    local set = {}

    pcall(function()
        local file = io.open(SPAWNED_CLASSES_PATH, "r")
        if not file then return end

        local content = file:read("*a")
        file:close()

        local list = json.decode(content)
        if not list then return end

        for _, className in ipairs(list) do
            set[className] = true
        end
    end)

    knownSpawnedClasses = set

    return set
end

local function RememberSpawnedClass(className)
    if not className then return end

    local set = LoadKnownSpawnedClasses()

    if set[className] then
        return
    end

    set[className] = true

    local list = {}

    for name in pairs(set) do
        table.insert(list, name)
    end

    pcall(function()
        local file = io.open(SPAWNED_CLASSES_PATH, "w")
        if not file then return end

        file:write(json.encode(list))
        file:close()
    end)
end

local function ExecuteConsoleCommand(command, className)
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local ksl = UEHelpers.GetKismetSystemLibrary(true)
            local context = UEHelpers.GetWorldContextObject()
            local player = UEHelpers.GetPlayerController()

            -- ksl:ExecuteConsoleCommand is a native UFunction call; an invalid context/player
            -- (e.g. no active world yet, loading screen, death/respawn) makes UE4SS jump through
            -- a null function pointer and crash the whole game. pcall cannot catch that, so the
            -- validity check has to happen before the call, not around it.
            if not IsValidObject(ksl) or not IsValidObject(context) or not IsValidObject(player) then
                print("[Remnant2Unlocker] ExecuteConsoleCommand skipped: world/player context not ready")
                return
            end

            print("[Remnant2Unlocker] ExecuteConsoleCommand: " .. command)

            -- "summon" spawns its actor(s) synchronously inside this native call, so the
            -- before/after snapshot taken immediately around it reliably captures exactly the
            -- actor(s) this command just created.
            local before = SnapshotActorsByClass(className)

            ksl:ExecuteConsoleCommand(context, command, player)

            if className then
                local after = SnapshotActorsByClass(className)
                local newActors = {}

                for key, actor in pairs(after) do
                    if not before[key] then
                        table.insert(newActors, actor)
                    end
                end

                if #newActors > 0 then
                    lastSpawnedActors = newActors
                end

                RememberSpawnedClass(className)
            end
        end)

        if ok then
            print("[Remnant2Unlocker] ExecuteConsoleCommand called successfully")
        else
            print("[Remnant2Unlocker] ExecuteConsoleCommand failed: " .. tostring(err))
        end
    end)
end

function Spawner.SpawnPath(path, dropQuantity, stackSize, itemLevel)
    local command, err = BuildSummonCommand(path, dropQuantity, stackSize, itemLevel)

    if not command then
        return false, err
    end

    ExecuteConsoleCommand(command, GetClassNameFromPath(NormalizePath(path)))

    return true, command
end

-- Returns the actor(s) created by the most recent SpawnPath call (there can be more than one
-- if dropQuantity > 1), or an empty table if nothing is tracked yet.
function Spawner.GetLastSpawnedActors()
    return lastSpawnedActors
end

-- Every Blueprint class name ever spawned through this mod (this session or a previous one).
function Spawner.GetKnownSpawnedClassNames()
    local set = LoadKnownSpawnedClasses()
    local list = {}

    for className in pairs(set) do
        table.insert(list, className)
    end

    return list
end

function Spawner.SpawnItem(item, dropQuantity, stackSize)
    if not item then
        return false, "Item is nil"
    end

    local itemLevel = 0

    local path = tostring(item.path or "")
    local name = tostring(item.name or "")
    local itemType = tostring(item.type or "")

    if path:find("RelicFragment_", 1, true)
        or path:lower():find("/items/gems/", 1, true)
        or name:lower():find("relic fragment", 1, true)
        or itemType:lower():find("relic fragment", 1, true) then
        itemLevel = 31
    end

    return Spawner.SpawnPath(item.path, dropQuantity, stackSize, itemLevel)
end

return Spawner