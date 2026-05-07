local UEHelpers = require("UEHelpers")

local Spawner = {}

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

local function BuildSummonCommand(path)
    local normalizedPath = NormalizePath(path)

    if normalizedPath == "" then
        return ""
    end

    return "summon " .. normalizedPath .. " 1 1 0"
end

function Spawner.SpawnPath(path)
    local summonCommand = BuildSummonCommand(path)

    if summonCommand == "" then
        return false, "Empty spawn path"
    end

    ExecuteInGameThread(function()
        local ksl = UEHelpers.GetKismetSystemLibrary(true)
        local player = UEHelpers.GetPlayerController()
        local context = UEHelpers.GetWorldContextObject()

        if not ksl then
            print("[Remnant2Unlocker] KismetSystemLibrary missing")
            return
        end

        if not player then
            print("[Remnant2Unlocker] PlayerController missing")
            return
        end

        if not context then
            print("[Remnant2Unlocker] WorldContext missing")
            return
        end

        print("[Remnant2Unlocker] ExecuteConsoleCommand: " .. summonCommand)

        local ok, result = pcall(function()
            ksl:ExecuteConsoleCommand(context, summonCommand, player)
        end)

        if ok then
            print("[Remnant2Unlocker] ExecuteConsoleCommand called successfully")
        else
            print("[Remnant2Unlocker] ExecuteConsoleCommand failed: " .. tostring(result))
        end
    end)

    return true, summonCommand
end

function Spawner.SpawnItem(item)
    if not item then
        return false, "Item is nil"
    end

    return Spawner.SpawnPath(item.path)
end

return Spawner