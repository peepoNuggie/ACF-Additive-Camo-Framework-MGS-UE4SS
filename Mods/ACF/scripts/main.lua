RegisterConsoleCommandHandler("forcecamo", function(FullCommand, Parameters, Ar)
    local manager = FindFirstOf("UE4PairingCamouflageManager")
    if manager == nil or not manager:IsValid() then
        print("[ACF] Could not find UE4PairingCamouflageManager - are you loaded into a save?")
        return false
    end

    local facepaint = tonumber(Parameters[1]) or 0
    local camo = tonumber(Parameters[2]) or 0

    manager:UpdateCamouflageByNoPairing(facepaint, camo)

    local currentInfo = manager.CurrentInfo
    print("[ACF] forcecamo called with (" .. facepaint .. ", " .. camo .. ")")

    local dirtyManager = FindFirstOf("GsrDirtyManager")
    if dirtyManager ~= nil and dirtyManager:IsValid() then
        print("[ACF] GsrDirtyManager.OverrideCamouflageType now reads: " .. tostring(dirtyManager.OverrideCamouflageType))
    end

    return false
end)

RegisterConsoleCommandHandler("unlockcamo", function(FullCommand, Parameters, Ar)
    local pc = FindFirstOf("PlayerController")
    if pc == nil or not pc:IsValid() then
        print("[ACF] Could not find PlayerController")
        return false
    end

    local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if kismet == nil then
        print("[ACF] Could not find KismetSystemLibrary")
        return false
    end

    kismet:ExecuteConsoleCommand(pc, "UnlockAllCamouflage", pc)
    print("[ACF] Executed UnlockAllCamouflage via KismetSystemLibrary")
    return false
end)

RegisterConsoleCommandHandler("checksave", function(FullCommand, Parameters, Ar)
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame instance")
        return false
    end

    print("[ACF] Found save! Full name: " .. save:GetFullName())

    local camoList = save.CamouflageList
    if camoList == nil then
        print("[ACF] CamouflageList was nil")
        return false
    end

    print("[ACF] CamouflageList length: " .. tostring(#camoList))
    return false
end)
RegisterConsoleCommandHandler("unlocknew", function(FullCommand, Parameters, Ar)
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame instance")
        return false
    end

    local camoList = save.CamouflageList
    if camoList == nil then
        print("[ACF] CamouflageList was nil")
        return false
    end

    print("[ACF] Before: length = " .. tostring(#camoList))
    camoList[#camoList + 1] = true
    print("[ACF] After: length = " .. tostring(#camoList))

    return false
end)

RegisterConsoleCommandHandler("findassethelper", function(FullCommand, Parameters, Ar)
    local manager = FindFirstOf("UE4PairingCamouflageManager")
    if manager == nil or not manager:IsValid() then
        print("[ACF] Could not find UE4PairingCamouflageManager - are you loaded into a save?")
        return false
    end

    local helper = manager.DataAssetHelper
    if helper == nil or not helper:IsValid() then
        print("[ACF] manager.DataAssetHelper was nil/invalid")
        return false
    end

    print("[ACF] DataAssetHelper full name: " .. helper:GetFullName())
    print("[ACF] DataAssetHelper class: " .. helper:GetClass():GetFullName())
    return false
end)

RegisterConsoleCommandHandler("loadasset", function(FullCommand, Parameters, Ar)
    local manager = FindFirstOf("UE4PairingCamouflageManager")
    if manager == nil or not manager:IsValid() then
        print("[ACF] Could not find UE4PairingCamouflageManager - are you loaded into a save?")
        return false
    end

    local helper = manager.DataAssetHelper
    if helper == nil or not helper:IsValid() then
        print("[ACF] manager.DataAssetHelper was nil/invalid")
        return false
    end

    local wildcard = Parameters[1] or "Camouf_5"
    local ok, result = pcall(function() return helper:LoadDataAsset(wildcard) end)
    if not ok then
        print("[ACF] LoadDataAsset call failed: " .. tostring(result))
        return false
    end

    print("[ACF] LoadDataAsset(" .. wildcard .. ") returned type: " .. type(result))
    if result ~= nil and result.IsValid and result:IsValid() then
        print("[ACF] Returned object full name: " .. result:GetFullName())
    else
        print("[ACF] Returned value is nil/invalid or not an object")
    end
    return false
end)

RegisterConsoleCommandHandler("dumpfunc", function(FullCommand, Parameters, Ar)
    local funcName = Parameters[1] or "/Script/MGS3.DataAssetHelper:LoadDataAsset"
    local func = StaticFindObject(funcName)
    if func == nil or not func:IsValid() then
        print("[ACF] Function not found: " .. funcName)
        return false
    end

    print("[ACF] Parameters for " .. funcName .. ":")
    func:ForEachProperty(function(prop)
        print("[ACF]   " .. prop:GetClass():GetFName():ToString() .. " " .. prop:GetFName():ToString())
    end)
    return false
end)

RegisterConsoleCommandHandler("findallcamouflageassets", function(FullCommand, Parameters, Ar)
    local assets = FindAllOf("CamouflageAssetType")
    if assets == nil or #assets == 0 then
        print("[ACF] No live CamouflageAssetType instances found")
        return false
    end

    print("[ACF] Found " .. #assets .. " live CamouflageAssetType instance(s):")
    for i = 1, #assets do
        local a = assets[i]
        if a ~= nil and a:IsValid() then
            print("[ACF]   " .. a:GetFullName())
        end
    end
    return false
end)
print("ACF Loaded Fully")
print("")
print("[ACF] Lua ready. Type 'forcecamo <facepaint> <camo>' in console once loaded into a save.")
print("")
print("[ACF] Lua ready. Type 'checksave' in console once loaded into a save.")
print("")
print("[ACF] Lua ready. Type 'unlocknew' in console once loaded into a save")
print("")
print("[ACF] Lua ready. Type 'findassethelper' in console once loaded into a save.")
print("")
print("[ACF] Lua ready. Type 'findsnakegroup' in console once loaded into a save.")
print("")