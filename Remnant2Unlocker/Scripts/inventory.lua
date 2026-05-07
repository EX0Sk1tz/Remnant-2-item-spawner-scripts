local Inventory = {}

local function NormalizePath(path)
    local value = tostring(path or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("|", "")

    if value:lower():sub(1, 7) == "summon " then
        value = value:sub(8)
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return value
end

local function GetInventoryComponent()
    local components = FindAllOf("RemnantPlayerInventoryComponent")

    if components then
        for _, component in ipairs(components) do
            if component and component:IsValid() then
                print("[Remnant2Unlocker] Inventory found: " .. component:GetFullName())
                return component
            end
        end
    end

    components = FindAllOf("PlayerInventoryComponent")

    if components then
        for _, component in ipairs(components) do
            if component and component:IsValid() then
                print("[Remnant2Unlocker] PlayerInventory found: " .. component:GetFullName())
                return component
            end
        end
    end

    return nil
end

local function LoadItemClass(path)
    local normalizedPath = NormalizePath(path)

    local candidates = {
        normalizedPath,
        normalizedPath:gsub("_C$", ""),
        normalizedPath:gsub("%.%w+_C$", ""),
        normalizedPath:gsub("%.%w+$", "")
    }

    for _, candidate in ipairs(candidates) do
        local itemClass = StaticFindObject(candidate)

        if itemClass and itemClass:IsValid() then
            print("[Remnant2Unlocker] StaticFindObject class found: " .. itemClass:GetFullName())
            return itemClass
        end
    end

    print("[Remnant2Unlocker] Could not find item class: " .. normalizedPath)
    return nil
end

local function PrintResult(result)
    if not result then
        print("[Remnant2Unlocker] K2_AddItem result is nil")
        return
    end

    local okName, fullName = pcall(function()
        return result:GetFullName()
    end)

    if okName then
        print("[Remnant2Unlocker] K2_AddItem result object: " .. tostring(fullName))
    else
        print("[Remnant2Unlocker] K2_AddItem result returned")
    end

    for key, value in pairs(result) do
        print("[Remnant2Unlocker] Result." .. tostring(key) .. " = " .. tostring(value))
    end
end

function Inventory.AddItem(path, quantity, reason)
    local normalizedPath = NormalizePath(path)
    local amount = tonumber(quantity) or 1
    local notifyReason = tonumber(reason) or 0

    ExecuteInGameThread(function()
        local inventory = GetInventoryComponent()

        if not inventory then
            print("[Remnant2Unlocker] Inventory component not found")
            return
        end

        local itemClass = LoadItemClass(normalizedPath)

        if not itemClass then
            print("[Remnant2Unlocker] Item class not found")
            return
        end

        print("[Remnant2Unlocker] K2_AddItem path: " .. normalizedPath)
        print("[Remnant2Unlocker] K2_AddItem reason: " .. tostring(notifyReason))

        local ok, result = pcall(function()
            return inventory:K2_AddItem(
                itemClass,
                amount,
                1,
                notifyReason,
                true
            )
        end)

        if ok then
            print("[Remnant2Unlocker] K2_AddItem called successfully")
            PrintResult(result)

            local okNotify = pcall(function()
                inventory:NotifyPickupItem(itemClass, amount, 1, notifyReason)
            end)

            if okNotify then
                print("[Remnant2Unlocker] NotifyPickupItem called")
            end

            local okRoute = pcall(function()
                inventory:RouteNotifyPickupItem(itemClass, amount, 1, notifyReason)
            end)

            if okRoute then
                print("[Remnant2Unlocker] RouteNotifyPickupItem called")
            end

            local okRep = pcall(function()
                inventory:MulticastOnInventoryChanged()
            end)

            if okRep then
                print("[Remnant2Unlocker] MulticastOnInventoryChanged called")
            end
        else
            print("[Remnant2Unlocker] K2_AddItem failed: " .. tostring(result))
        end
    end)

    return true, normalizedPath
end

return Inventory