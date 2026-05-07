local Player = {}

function Player.GetValidPlayerController()
    local controllers = FindAllOf("PlayerController")

    if not controllers then
        return nil
    end

    for _, pc in ipairs(controllers) do
        if pc and pc:IsValid() then
            local ok, isLocal = pcall(function()
                return pc:IsLocalPlayerController()
            end)

            if ok and isLocal then
                return pc
            end
        end
    end

    return nil
end

function Player.GetCheatManager()
    local pc = Player.GetValidPlayerController()

    if not pc then
        return nil, "No valid PlayerController found"
    end

    if not pc.CheatManager then
        return nil, "CheatManager not found"
    end

    if not pc.CheatManager:IsValid() then
        return nil, "CheatManager is invalid"
    end

    return pc.CheatManager, nil
end

return Player