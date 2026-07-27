print("[Remnant2Unlocker] main.lua loaded")

local Queue = require("queue")
local Hotkeys = require("hotkeys")
local MovementSpeed = require("movement_speed")
local Cheats = require("cheats")
local Fov = require("fov")
local DebugDump = require("debug_dump")
local InventoryCheats = require("inventory_cheats")
local EnemyEsp = require("enemy_esp")
local WeaponModCommands = require("weapon_mod_commands")

-- An uncaught error in any one module's Start() used to abort this entire chunk, silently
-- skipping every module listed after it (confirmed in testing: a failed RegisterHook call in
-- Cheats.Start() took Fov/DebugDump/InventoryCheats down with it for the whole session). Each
-- module is now started independently so one module's failure can never disable the others.
local function SafeStart(name, module)
    local ok, err = pcall(function() module.Start() end)

    if not ok then
        print("[Remnant2Unlocker] " .. name .. ".Start() failed: " .. tostring(err))
    end
end

SafeStart("Queue", Queue)
SafeStart("Hotkeys", Hotkeys)
SafeStart("MovementSpeed", MovementSpeed)
SafeStart("Cheats", Cheats)
SafeStart("Fov", Fov)
SafeStart("DebugDump", DebugDump)
SafeStart("InventoryCheats", InventoryCheats)
SafeStart("EnemyEsp", EnemyEsp)
SafeStart("WeaponModCommands", WeaponModCommands)

RegisterKeyBind(Key.F8, function()
    print("[Remnant2Unlocker] Bridge is running")
end)