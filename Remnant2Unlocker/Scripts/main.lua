print("[Remnant2Unlocker] main.lua loaded")

local Queue = require("queue")

Queue.Start()

RegisterKeyBind(Key.F8, function()
    print("[Remnant2Unlocker] Bridge is running")
end)