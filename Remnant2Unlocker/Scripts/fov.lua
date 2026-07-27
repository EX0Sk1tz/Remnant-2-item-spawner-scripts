local json = require("json")
local UEHelpers = require("UEHelpers")

local Fov = {}

local SETTINGS_PATH = "Mods/Remnant2Unlocker/hotkeys.json"
local DEFAULT_FOV = 90.0

local targetFov = DEFAULT_FOV
local baseFov = nil
local wasActive = false
local lastAppliedFov = nil
local lastLogged = {}

local function ReadAllText(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    return content
end

local function LogOnce(key, message)
    if lastLogged[key] == message then
        return
    end

    lastLogged[key] = message
    print("[Remnant2Unlocker] " .. message)
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

local function ReloadSettings()
    local content = ReadAllText(SETTINGS_PATH)
    if not content then return end

    local ok, settings = pcall(function()
        return json.decode(content)
    end)

    if not ok or not settings then return end

    local fov = tonumber(settings.fovValue) or DEFAULT_FOV

    if fov < 60.0 then fov = 60.0 end
    if fov > 120.0 then fov = 120.0 end

    if fov ~= targetFov then
        targetFov = fov
        print("[Remnant2Unlocker] FOV setting updated: " .. tostring(targetFov))
    end
end

-- PlayerCameraManager is a stable, non-game-specific UE base-class field, unlike the
-- Health/Stamina candidates in cheats.lua -- higher confidence this resolves on the first try.
local function GetCameraManager()
    local ok, camManager = pcall(function()
        local pc = UEHelpers.GetPlayerController()

        if pc then
            return pc.PlayerCameraManager
        end

        return nil
    end)

    if ok and IsValidObject(camManager) then
        return camManager
    end

    return nil
end

local function ResetFovIfNeeded()
    if not wasActive then
        return
    end

    ExecuteInGameThread(function()
        local camManager = GetCameraManager()
        if not camManager or not baseFov then return end

        local ok = pcall(function() camManager.FOVAngle = baseFov end)

        if ok then
            print("[Remnant2Unlocker] FOV reset to base: " .. tostring(baseFov))
        end

        wasActive = false
        lastAppliedFov = nil
    end)
end

local function ApplyFov()
    if targetFov == DEFAULT_FOV then
        ResetFovIfNeeded()
        return
    end

    ExecuteInGameThread(function()
        local camManager = GetCameraManager()

        if not camManager then
            LogOnce("fov_cam_missing", "FOV: PlayerCameraManager not found")
            return
        end

        if not baseFov then
            local okRead, currentFov = pcall(function() return camManager.FOVAngle end)
            baseFov = (okRead and tonumber(currentFov)) or DEFAULT_FOV
            print("[Remnant2Unlocker] FOV base detected: " .. tostring(baseFov))
        end

        -- NOTE: camManager:SetFOV() was tried here and confirmed broken on this game build --
        -- it always throws "Tried calling a member function but the UObject instance is nullptr"
        -- (see UE4SS.log from 2026-07-06 17:28), so it's been removed rather than left as silent
        -- log spam. The direct field write below succeeds (no error) but has been confirmed to
        -- have no visible in-game effect -- most likely this game recomputes camera FOV every
        -- frame from its own logic (sprint/aim FOV blending is common in third-person games),
        -- overwriting this write before it renders. Making FOV actually stick would need a
        -- RegisterHook on the camera update function, which is a bigger step not attempted yet.
        local okWrite, err = pcall(function() camManager.FOVAngle = targetFov end)

        if not okWrite then
            LogOnce("fov_write_failed", "FOV: FOVAngle write failed: " .. tostring(err))
            return
        end

        wasActive = true

        if lastAppliedFov ~= targetFov then
            lastAppliedFov = targetFov
            print("[Remnant2Unlocker] FOV applied: " .. tostring(targetFov))
        end
    end)
end

function Fov.Start()
    ReloadSettings()

    LoopAsync(1000, function()
        ReloadSettings()
    end)

    LoopAsync(250, function()
        ApplyFov()
    end)

    print("[Remnant2Unlocker] FOV system initialized")
end

return Fov
