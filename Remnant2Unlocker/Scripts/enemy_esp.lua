local json = require("json")
local UEHelpers = require("UEHelpers")

local EnemyEsp = {}

local SETTINGS_PATH = "Mods/Remnant2Unlocker/cheats.json"

local ENEMY_CLASS_NAMES = { "BP_Monster_Base_C" }

local CUSTOM_DEPTH_STENCIL_VALUE = 2
local RADIUS = 3000

local MESH_CANDIDATES = { "CharacterMesh0", "Mesh" }

local enemyEspEnabled = false
local lastLogged = {}
local markedActors = {}

local function LogOnce(key, message)
    if lastLogged[key] == message then
        return
    end

    lastLogged[key] = message
    print("[Remnant2Unlocker] " .. message)
end

local function ReadAllText(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    return content
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

local function GetPlayerPawn()
    local ok, pawn = pcall(function()
        local pc = UEHelpers.GetPlayerController()

        if pc and pc.Pawn then
            return pc.Pawn
        end

        return FindFirstOf("RemnantPlayerCharacter")
    end)

    if ok and IsValidObject(pawn) then
        return pawn
    end

    return nil
end

local function IsRealPlayerCharacter(player)
    if not IsValidObject(player) then
        return false
    end

    local ok, className = pcall(function() return player:GetClass():GetFName():ToString() end)

    return ok and className ~= nil and tostring(className):find("Character_.-Player") ~= nil
end

local function IsDefaultObject(actor)
    local ok, name = pcall(function() return actor:GetFullName() end)
    return ok and name ~= nil and tostring(name):find("Default__", 1, true) ~= nil
end

local function GetMeshComponent(actor)
    for _, propertyName in ipairs(MESH_CANDIDATES) do
        local ok, component = pcall(function() return actor[propertyName] end)

        if ok and IsValidObject(component) then
            return component
        end
    end

    return nil
end

local function DistanceBetween(a, b)
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    local dz = (a.Z or 0) - (b.Z or 0)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function SetHighlight(component, enabled)
    pcall(function()
        component.bRenderCustomDepth = enabled
        component.CustomDepthStencilValue = CUSTOM_DEPTH_STENCIL_VALUE
    end)

    pcall(function() component:MarkRenderStateDirty() end)
end

local function ReloadSettings()
    local content = ReadAllText(SETTINGS_PATH)
    if not content then return end

    local ok, settings = pcall(function()
        return json.decode(content)
    end)

    if not ok or not settings then return end

    local newEnabled = settings.enemyEsp == true

    if newEnabled ~= enemyEspEnabled then
        enemyEspEnabled = newEnabled
        print("[Remnant2Unlocker] Enemy ESP toggled: " .. tostring(enemyEspEnabled))
    end
end

local function ClearAllMarked()
    for _, component in pairs(markedActors) do
        SetHighlight(component, false)
    end

    markedActors = {}
end

local function ApplyEnemyEsp()
    if not enemyEspEnabled then
        if next(markedActors) then
            ExecuteInGameThread(ClearAllMarked)
        end

        return
    end

    ExecuteInGameThread(function()
        local player = GetPlayerPawn()
        if not IsRealPlayerCharacter(player) then return end

        local okLoc, playerLocation = pcall(function() return player:K2_GetActorLocation() end)
        if not okLoc or not playerLocation then return end

        local stillPresent = {}
        local marked = 0

        for _, className in ipairs(ENEMY_CLASS_NAMES) do
            local okList, list = pcall(function() return FindAllOf(className) end)

            if okList and list then
                for _, actor in ipairs(list) do
                    if IsValidObject(actor) and not IsDefaultObject(actor) then
                        local okActorLoc, actorLocation = pcall(function() return actor:K2_GetActorLocation() end)

                        if okActorLoc and actorLocation and DistanceBetween(playerLocation, actorLocation) <= RADIUS then
                            local component = GetMeshComponent(actor)

                            if component then
                                local okKey, key = pcall(function() return actor:GetFullName() end)
                                key = (okKey and key) or tostring(actor)

                                SetHighlight(component, true)
                                stillPresent[key] = component
                                marked = marked + 1
                            end
                        end
                    end
                end
            else
                LogOnce("class_missing_" .. className, "Enemy ESP: class not found or not loaded yet: " .. className)
            end
        end

        for key, component in pairs(markedActors) do
            if not stillPresent[key] and IsValidObject(component) then
                SetHighlight(component, false)
            end
        end

        markedActors = stillPresent

        LogOnce("marked_count", "Enemy ESP: highlighting " .. tostring(marked) .. " enemy/enemies within " .. tostring(RADIUS) .. " units")
    end)
end

function EnemyEsp.Start()
    ReloadSettings()

    LoopAsync(1000, function()
        ReloadSettings()
    end)

    LoopAsync(1000, function()
        ApplyEnemyEsp()
    end)

    print("[Remnant2Unlocker] Enemy ESP system initialized")
end

return EnemyEsp
