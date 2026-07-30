local ACF_HookRegistered = false
local function ACF_EnsureHookRegistered()
    if ACF_HookRegistered then return end
    ACF_HookRegistered = true

    local function TryHook(path, label)
        local ok, err = pcall(function()
            RegisterHook(path, function(Context, ...)
                print("[ACF] [HOOK-PRE] " .. label .. " called")
            end, function(Context, ...)
                print("[ACF] [HOOK-POST] " .. label .. " finished")
            end)
        end)
        if not ok then
            print("[ACF] Failed to register hook for " .. label .. " (" .. path .. "): " .. tostring(err))
        else
            print("[ACF] Hook registered successfully for " .. label .. " (" .. path .. ")")
        end
    end

    local function TryPrintValue(v)
        if v == nil then return "nil" end
        local ok, s = pcall(function() return v:ToString() end)
        if ok then return s end
        local ok2, s2 = pcall(function() return v:GetFullName() end)
        if ok2 then return s2 end
        return tostring(v)
    end

    local function TryHookWithArgs(path, label)
        local func = StaticFindObject(path)
        local ok, err = pcall(function()
            RegisterHook(path, function(Context, ...)
                local args = {...}
                print("[ACF] [HOOK-PRE] " .. label .. " called")
                if func ~= nil then
                    local i = 0
                    func:ForEachProperty(function(prop)
                        i = i + 1
                        local argWrapper = args[i]
                        if argWrapper ~= nil then
                            print("[ACF]   " .. prop:GetFName():ToString() .. " = " .. TryPrintValue(argWrapper:get()))
                        end
                    end)
                end
            end, function(Context, ...)
                print("[ACF] [HOOK-POST] " .. label .. " finished")
            end)
        end)
        if not ok then
            print("[ACF] Failed to register hook for " .. label .. " (" .. path .. "): " .. tostring(err))
        else
            print("[ACF] Hook registered successfully for " .. label .. " (" .. path .. ")")
        end
    end

    TryHook("/Script/MGS3.DataAssetHelper:LoadDataAsset", "DataAssetHelper:LoadDataAsset")
    TryHook("/Script/Gsr.GsrCollectionItemController:CreateItem", "GsrCollectionItemController:CreateItem")
    TryHook("/Script/Gsr.GsrCollectionItemController:ItemNameToItemId", "GsrCollectionItemController:ItemNameToItemId")
    TryHookWithArgs("/Script/GsrDirtyControlSystem.GsrDirtyManager:ChangeCamouflage", "GsrDirtyManager:ChangeCamouflage")
    TryHook("/Game/Gsr/Blueprints/Player/BP_Player.BP_Player_C:OnBeginCamouflageApplying", "BP_Player:OnBeginCamouflageApplying")
    TryHookWithArgs("/Game/Gsr/Blueprints/Player/BP_Player.BP_Player_C:OnChangeCamouflageApply", "BP_Player:OnChangeCamouflageApply")
    TryHook("/Game/Gsr/Blueprints/Player/BP_Player.BP_Player_C:OnEndCamouflageApplying", "BP_Player:OnEndCamouflageApplying")
    TryHookWithArgs("/CobraUI/Blueprint/sv_camouflage/sv_camouflage.sv_camouflage_C:GetCamouflageByIndex", "sv_camouflage_C:GetCamouflageByIndex")
    TryHook("/CobraUI/Blueprint/sv_camouflage/sv_camouflage.sv_camouflage_C:ReceiveEnterState", "sv_camouflage_C:ReceiveEnterState")
    TryHook("/CobraUI/Blueprint/sv_camouflage/sv_camouflage.sv_camouflage_C:ReceiveExitState", "sv_camouflage_C:ReceiveExitState")
    TryHook("/CobraUI/Blueprint/sv_camouflage/sv_camouflage.sv_camouflage_C:ExecuteUbergraph_sv_camouflage", "sv_camouflage_C:ExecuteUbergraph")

    -- Found via Ghidra: these ARE registered UFunctions on CPropMenuBaseState, even though
    -- ForEachFunction never listed them (UClass::FuncMap is a TMap -> known bulk-read bug).
    -- Hooking FindPropDataForSelectIndex tells us exactly which slot indices the menu asks
    -- about when it builds/browses the list, and how many there are.
    -- Confirmed via findpropfunc: these live on CSVTabViewWidget (NOT CPropMenuBaseState).
    -- sv_camouflage_C reaches one via its Target property; CPropMenuBaseState via sv_tab_switch.
    -- The two TMaps Ghidra found (+0x748 propdata, +0x798 index->button) are on THIS object.
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindPropDataForSelectIndex", "CSVTabViewWidget:FindPropDataForSelectIndex")
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindButtonForSelectIndex", "CSVTabViewWidget:FindButtonForSelectIndex")
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindPropDataForKindIndex", "CSVTabViewWidget:FindPropDataForKindIndex")
end

RegisterConsoleCommandHandler("registerhooks", function(FullCommand, Parameters, Ar)
    ACF_EnsureHookRegistered()
    return false
end)

RegisterConsoleCommandHandler("realequip", function(FullCommand, Parameters, Ar)
    local dirtyManager = FindFirstOf("GsrDirtyManager")
    if dirtyManager == nil or not dirtyManager:IsValid() then
        print("[ACF] Could not find GsrDirtyManager - are you loaded into a save?")
        return false
    end

    local camo = tonumber(Parameters[1]) or 0
    print("[ACF] Calling GsrDirtyManager:ChangeCamouflage(" .. camo .. ") directly")

    local ok, err = pcall(function()
        dirtyManager:ChangeCamouflage(camo)
    end)

    if not ok then
        print("[ACF] ChangeCamouflage call failed: " .. tostring(err))
    else
        print("[ACF] ChangeCamouflage(" .. camo .. ") completed without error")
    end
    return false
end)

RegisterConsoleCommandHandler("realequip2", function(FullCommand, Parameters, Ar)
    local player = FindFirstOf("BP_Player_C")
    if player == nil or not player:IsValid() then
        print("[ACF] Could not find BP_Player_C - are you loaded into a save?")
        return false
    end

    local camo = tonumber(Parameters[1]) or 0
    print("[ACF] Calling BP_Player_C:OnChangeCamouflageApply(false, true, 0, " .. camo .. ") directly")

    local ok, err = pcall(function()
        player:OnChangeCamouflageApply(false, true, 0, camo)
    end)

    if not ok then
        print("[ACF] OnChangeCamouflageApply call failed: " .. tostring(err))
    else
        print("[ACF] OnChangeCamouflageApply(...) completed without error")
    end
    return false
end)

RegisterConsoleCommandHandler("findcamowidget", function(FullCommand, Parameters, Ar)
    local widgets = FindAllOf("UserWidget")
    if widgets == nil or #widgets == 0 then
        print("[ACF] No live UserWidget instances found")
        return false
    end

    print("[ACF] Scanning " .. #widgets .. " live UserWidget instance(s) for camo-related names...")
    local found = 0
    for i = 1, #widgets do
        local w = widgets[i]
        if w ~= nil and w:IsValid() then
            local ok, fullName = pcall(function() return w:GetFullName() end)
            if ok and (fullName:lower():find("camo") or fullName:lower():find("uniform")) then
                found = found + 1
                print("[ACF]   " .. fullName)
                print("[ACF]     class: " .. w:GetClass():GetFullName())
            end
        end
    end
    print("[ACF] Found " .. found .. " matching widget(s)")
    return false
end)

RegisterConsoleCommandHandler("findcamocollection", function(FullCommand, Parameters, Ar)
    local candidates = {"BP_CamouflageCollectionSnake_C", "BP_CamouflageCollectionSnake"}
    for _, name in ipairs(candidates) do
        local obj = FindFirstOf(name)
        if obj ~= nil and obj:IsValid() then
            print("[ACF] Found live instance via FindFirstOf(\"" .. name .. "\"): " .. obj:GetFullName())
            print("[ACF] Its class: " .. obj:GetClass():GetFullName())
        else
            print("[ACF] FindFirstOf(\"" .. name .. "\") found nothing")
        end
    end
    return false
end)

RegisterConsoleCommandHandler("findrealclasspaths", function(FullCommand, Parameters, Ar)
    local candidates = {"GsrDirtyManager", "GsrPlayer", "UE4PairingCamouflageManager", "GsrCollectionItemController"}
    for _, name in ipairs(candidates) do
        local obj = FindFirstOf(name)
        if obj ~= nil and obj:IsValid() then
            print("[ACF] " .. name .. " live full name: " .. obj:GetFullName())
            print("[ACF] " .. name .. " real class path: " .. obj:GetClass():GetFullName())
            local cls = obj:GetClass()
            print("[ACF] " .. name .. " functions:")
            cls:ForEachFunction(function(fn)
                print("[ACF]     " .. fn:GetFName():ToString())
            end)
        else
            print("[ACF] FindFirstOf(\"" .. name .. "\") found nothing")
        end
    end
    return false
end)

-- ---------------------------------------------------------------------------
-- Diagnostics: what does the game actually do when we ask for a camo?
-- ---------------------------------------------------------------------------
-- DataAssetHelper.InfoArray is a small live cache of currently-loaded assets.
-- Watching it change across a camo switch is how the "Camouf_<ID>" naming
-- convention was found in the first place, and it is the only way to see the
-- real loader work - the LoadDataAsset *hook* never fires, because the game
-- calls it native-to-native and UE4SS only intercepts VM dispatch.

local function ACF_GetAssetHelper()
    local manager = FindFirstOf("UE4PairingCamouflageManager")
    if manager == nil or not manager:IsValid() then
        return nil, nil, "no live UE4PairingCamouflageManager (are you loaded into a save?)"
    end
    local helper = manager.DataAssetHelper
    if helper == nil or not helper:IsValid() then
        return manager, nil, "manager.DataAssetHelper was nil/invalid"
    end
    return manager, helper, nil
end

-- Returns an array of NameWildcard strings, or nil + an error message.
local function ACF_SnapshotInfoArray()
    local _, helper, err = ACF_GetAssetHelper()
    if helper == nil then return nil, err end

    local out = {}
    local ok, perr = pcall(function()
        local arr = helper.InfoArray
        for i = 1, #arr do
            local name = "<unreadable>"
            pcall(function()
                local w = arr[i].NameWildcard
                if w ~= nil then name = w:ToString() end
            end)
            -- Blank slots are just unused cache entries; keep them so indices line up.
            out[i] = name
        end
    end)
    if not ok then return nil, tostring(perr) end
    return out
end

local function ACF_PrintInfoArray(label, snap)
    print("[ACF] " .. label .. ":")
    local shown = 0
    for i = 1, #snap do
        if snap[i] ~= nil and snap[i] ~= "" then
            print("[ACF]     [" .. i .. "] " .. snap[i])
            shown = shown + 1
        end
    end
    if shown == 0 then print("[ACF]     (all slots empty)") end
end

-- camotest <id> - the decisive render diagnostic.
-- Snapshots the asset cache, forces the camo, snapshots again, and reports what
-- changed. If "Camouf_<id>" appears, the game DID look for our asset and the
-- problem is the asset itself. If nothing changes, the game never even asked -
-- which means the camo ID never reaches the loader, a completely different bug.
RegisterConsoleCommandHandler("camotest", function(FullCommand, Parameters, Ar)
    local camo = tonumber(Parameters[1])
    if camo == nil then
        print("[ACF] Usage: camotest <camo id>   (e.g. camotest 60)")
        return false
    end

    local manager, helper, err = ACF_GetAssetHelper()
    if helper == nil then
        print("[ACF] " .. tostring(err))
        return false
    end

    local before, berr = ACF_SnapshotInfoArray()
    if before == nil then
        print("[ACF] Could not read InfoArray before: " .. tostring(berr))
        return false
    end
    ACF_PrintInfoArray("BEFORE (cache contents)", before)

    print("[ACF] --> UpdateCamouflageByNoPairing(0, " .. camo .. ")")
    local okCall, callErr = pcall(function()
        manager:UpdateCamouflageByNoPairing(0, camo)
    end)
    if not okCall then
        print("[ACF] The call itself FAILED: " .. tostring(callErr))
        return false
    end

    local after, aerr = ACF_SnapshotInfoArray()
    if after == nil then
        print("[ACF] Could not read InfoArray after: " .. tostring(aerr))
        return false
    end
    ACF_PrintInfoArray("AFTER", after)

    local changes = 0
    for i = 1, math.max(#before, #after) do
        local b, a = before[i], after[i]
        if b ~= a then
            print("[ACF]   CHANGED [" .. i .. "]: '" .. tostring(b) .. "' -> '" .. tostring(a) .. "'")
            changes = changes + 1
        end
    end

    if changes == 0 then
        print("[ACF] VERDICT: cache did NOT change. The game never requested Camouf_" .. camo ..
              " - the ID is being rejected before the loader is reached.")
    else
        local found = false
        for i = 1, #after do
            if after[i] == ("Camouf_" .. camo) then found = true end
        end
        if found then
            print("[ACF] VERDICT: the game DID request Camouf_" .. camo ..
                  " - the loader was reached, so any failure is in our asset/pak.")
        else
            print("[ACF] VERDICT: cache changed but Camouf_" .. camo ..
                  " is NOT in it - the game substituted a different camo (silent fallback).")
        end
    end

    -- DECISIVE CHECK: did the game actually LOAD the asset object?
    --
    -- The cache diff above only proves the game ASKED for the name. This proves whether it
    -- really resolved: a UObject exists in memory only if the package was found and loaded.
    -- No judging what Snake looks like on screen.
    --
    -- This is precisely what tells us whether a patched AssetRegistry.bin took effect:
    -- registry knows the name -> AssetManager registers it -> package resolves -> object exists.
    local objPath = "/Game/Maps/AssetCamouflage/Camouf_" .. camo .. "_asset.Camouf_" .. camo .. "_asset"
    local obj = StaticFindObject(objPath)
    if obj ~= nil and obj:IsValid() then
        print("[ACF] ASSET OBJECT IN MEMORY: YES -> " .. obj:GetFullName())
        print("[ACF]   Package resolved and loaded - this id IS registered.")
    else
        print("[ACF] ASSET OBJECT IN MEMORY: no")
        print("[ACF]   Name was requested but no object exists - package never resolved,")
        print("[ACF]   i.e. this id is NOT registered.")
    end

    -- Cross-check: what camo assets ARE currently loaded? Anything listed here resolved fine,
    -- which makes this a built-in control for the check above.
    local live = FindAllOf("CamouflageAssetType")
    if live ~= nil and #live > 0 then
        local names = {}
        for i = 1, #live do
            if live[i] ~= nil and live[i]:IsValid() then
                names[#names + 1] = live[i]:GetFName():ToString()
            end
        end
        table.sort(names)
        print("[ACF] loaded CamouflageAssetType objects (" .. #names .. "): " .. table.concat(names, ", "))
    end

    local dirtyManager = FindFirstOf("GsrDirtyManager")
    if dirtyManager ~= nil and dirtyManager:IsValid() then
        print("[ACF] GsrDirtyManager.OverrideCamouflageType now reads: " .. tostring(dirtyManager.OverrideCamouflageType))
    end

    return false
end)

-- dumpusmap - generate a .usmap mappings file.
--
-- This game uses UE5 "unversioned properties": the struct layouts are not stored in the
-- assets themselves, so an offline tool cannot decode a DataTable row - UAssetGUI dumps
-- the rows as one opaque blob (RawExport) instead of editable fields.
--
-- A .usmap describes every struct/enum layout, generated from the LIVE game's reflection
-- data. With it, UAssetGUI can parse DT_CamouflageCollection properly, which is what lets
-- us add rows offline and ship the table in a pak - bypassing the runtime AddRow limit
-- entirely (only one row per session survives; the game's TSet cannot be grown by UE4SS).
--
-- Output lands next to the game exe, in Binaries/Win64/ as Mappings.usmap.
RegisterConsoleCommandHandler("dumpusmap", function(FullCommand, Parameters, Ar)
    if DumpUSMAP == nil then
        print("[ACF] DumpUSMAP is not available in this UE4SS build/config.")
        print("[ACF] Alternative: the UE4SS GUI has a 'Generate .usmap file' button under Dumpers.")
        return false
    end

    print("[ACF] Generating .usmap - this can take a few seconds and may hitch the game...")
    local ok, err = pcall(function() DumpUSMAP() end)
    if not ok then
        print("[ACF] DumpUSMAP failed: " .. tostring(err))
    else
        print("[ACF] Done. Look for Mappings.usmap in Binaries/Win64/.")
    end
    return false
end)

-- scanprobe - can we make the game re-scan for assets at runtime?
--
-- CamouflageAssetType already scans /Game/Maps, and our assets live in
-- /Game/Maps/AssetCamouflage - so the PATH is covered. The problem is purely timing: the scan
-- runs at startup against the cooked asset registry, which predates our pak.
--
-- If any of these are reachable, we can force a rescan after mounting and our assets register
-- themselves - which would make Camouf_61+ findable with no repackaging at all.
--
-- Uses StaticFindObject per candidate rather than ForEachFunction: direct lookup has been
-- reliable on this build where enumeration is not.
RegisterConsoleCommandHandler("scanprobe", function(FullCommand, Parameters, Ar)
    local candidates = {
        -- AssetRegistry: teaches the engine that files exist
        "/Script/AssetRegistry.AssetRegistryImpl:ScanPathsSynchronous",
        "/Script/AssetRegistry.AssetRegistryImpl:ScanFilesSynchronous",
        "/Script/AssetRegistry.AssetRegistryImpl:SearchAllAssets",
        "/Script/AssetRegistry.AssetRegistryImpl:PrioritizeSearchPath",
        "/Script/AssetRegistry.AssetRegistryImpl:GetAssetsByPath",
        "/Script/AssetRegistry.AssetRegistryImpl:GetAssetByObjectPath",
        "/Script/AssetRegistry.AssetRegistryHelpers:GetAssetRegistry",
        -- AssetManager: turns registry entries into PrimaryAssets (the map LoadDataAsset reads)
        "/Script/Engine.AssetManager:GetPrimaryAssetIdList",
        "/Script/Engine.AssetManager:GetPrimaryAssetPath",
        "/Script/Engine.AssetManager:GetPrimaryAssetObject",
        "/Script/Engine.AssetManager:LoadPrimaryAsset",
        "/Script/Engine.AssetManager:UnloadPrimaryAsset",
        "/Script/Engine.AssetManager:GetPrimaryAssetsWithBundleState",
    }
    print("[ACF] === probing for a runtime rescan/registration entry point ===")
    local hits = 0
    for _, path in ipairs(candidates) do
        local fn = StaticFindObject(path)
        local found = (fn ~= nil and fn:IsValid())
        if found then hits = hits + 1 end
        print("[ACF]   " .. (found and "FOUND  " or "missing") .. " " .. path)
    end

    -- Is the registry object itself reachable?
    print("[ACF] === live registry objects ===")
    for _, cls in ipairs({"AssetRegistryImpl", "AssetRegistry", "AssetManager"}) do
        local o = FindFirstOf(cls)
        if o ~= nil and o:IsValid() then
            print("[ACF]   " .. cls .. " -> " .. o:GetFullName())
        else
            print("[ACF]   " .. cls .. " -> not found")
        end
    end
    print("[ACF] " .. hits .. " candidate function(s) reachable.")
    return false
end)

-- assetmgr - inspect the AssetManager registry that decides whether an asset "exists".
--
-- Ghidra traced DataAssetHelper::LoadDataAsset -> FUN_145052ca0 -> FUN_143bee420, and that last
-- one is UAssetManager::GetPrimaryAssetData: a two-level TMap walk (PrimaryAssetType -> AssetMap
-- -> FName). If the name is not in there, LoadDataAsset returns 0 and NOTHING renders - which is
-- exactly what happens for Camouf_61+. Our pak is fine; the asset was simply never registered.
--
-- AssetTypeMap is built at startup from PrimaryAssetTypesToScan (a UPROPERTY on
-- UAssetManagerSettings, so reflection can read it). This reports what is configured to scan,
-- so we can see whether /Game/Maps/AssetCamouflage is covered.
RegisterConsoleCommandHandler("assetmgr", function(FullCommand, Parameters, Ar)
    print("[ACF] === AssetManager ===")
    local mgr = FindFirstOf("AssetManager")
    if mgr ~= nil and mgr:IsValid() then
        print("[ACF]   live: " .. mgr:GetFullName())
        print("[ACF]   class: " .. mgr:GetClass():GetFullName())
    else
        print("[ACF]   FindFirstOf('AssetManager') found nothing")
    end

    print("[ACF] === AssetManagerSettings.PrimaryAssetTypesToScan ===")
    local settings = FindFirstOf("AssetManagerSettings")
    if settings == nil or not settings:IsValid() then
        settings = StaticFindObject("/Script/Engine.Default__AssetManagerSettings")
    end
    if settings == nil or not settings:IsValid() then
        print("[ACF]   AssetManagerSettings not found")
        return false
    end
    print("[ACF]   " .. settings:GetFullName())

    local ok, err = pcall(function()
        local list = settings.PrimaryAssetTypesToScan
        if list == nil then print("[ACF]   PrimaryAssetTypesToScan is nil"); return end
        print("[ACF]   entries: " .. #list)
        for i = 1, #list do
            local e = list[i]
            local pname, dirs = "?", {}
            pcall(function() pname = e.PrimaryAssetType:ToString() end)
            pcall(function()
                local d = e.Directories
                for j = 1, #d do
                    -- .Path is an FString, so it needs ToString() - printing it directly
                    -- just yields "FString: <address>".
                    local p = "?"
                    pcall(function()
                        local raw = d[j].Path
                        if type(raw) == "string" then p = raw
                        elseif raw ~= nil and raw.ToString ~= nil then p = raw:ToString()
                        else p = tostring(raw) end
                    end)
                    dirs[#dirs + 1] = tostring(p)
                end
            end)
            print(string.format("[ACF]   [%d] %-28s dirs: %s", i, pname,
                  (#dirs > 0 and table.concat(dirs, ", ") or "(none)")))
        end
    end)
    if not ok then print("[ACF]   read failed: " .. tostring(err)) end

    -- What can we actually CALL on the asset manager? If anything rescans or registers,
    -- that is the whole fix: our assets get into AssetTypeMap and become findable.
    if mgr ~= nil and mgr:IsValid() then
        print("[ACF] === GsrAssetManager functions (whole hierarchy) ===")
        local cls = mgr:GetClass()
        while cls ~= nil and cls:IsValid() do
            local cname = cls:GetFName():ToString()
            local any = false
            pcall(function()
                cls:ForEachFunction(function(fn)
                    any = true
                    print("[ACF]   " .. cname .. ":" .. fn:GetFName():ToString())
                end)
            end)
            if not any then print("[ACF]   " .. cname .. ": (no functions listed)") end
            cls = cls:GetSuperStruct()
        end
    end

    print("[ACF] Looking for a type whose directory covers /Game/Maps/AssetCamouflage.")
    print("[ACF] If one exists, our pak's assets were simply missing from the cooked")
    print("[ACF] asset registry at startup - which is the real reason 61+ never render.")
    return false
end)

-- swapthumb <rowName> <textureName> - patch a row's Thumbnail LIVE, to test UI caching.
--
-- The question: does the Collection Viewer read the row's Thumbnail every time it draws, or does
-- it cache when the row list is first built?
--
-- This matters because our custom texture only enters memory AFTER registration (it arrives as
-- an import of the camo asset), so we patch the row late. If the viewer caches, a late patch can
-- never show up - and the fix is to get the texture loaded EARLIER, not to fix the texture.
--
-- Uses two VANILLA textures, both of which definitely render, so nothing about custom assets is
-- involved in the answer.
--   swapthumb IT_EqACFSlot61 8951363     (row 61: Moss -> Hornet Stripe)
RegisterConsoleCommandHandler("swapthumb", function(FullCommand, Parameters, Ar)
    local rowName = Parameters[1]
    local texName = Parameters[2]
    if rowName == nil or texName == nil then
        print("[ACF] Usage: swapthumb <rowName> <textureName>")
        print("[ACF]   e.g. swapthumb IT_EqACFSlot61 8951363")
        return false
    end

    local dt = StaticFindObject("/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection.DT_CamouflageCollection")
    if dt == nil or not dt:IsValid() then print("[ACF] DataTable not found"); return false end

    local path = "/CobraUI/textures/sv/camouflage/" .. texName .. "." .. texName
    local tex = StaticFindObject(path)
    if tex == nil or not tex:IsValid() then
        print("[ACF] texture not in memory: " .. path)
        return false
    end
    print("[ACF] texture found: " .. tex:GetFullName())
    print("[ACF] NOTE: the Lua side cannot write the row struct directly - this only confirms the")
    print("[ACF] texture is resident. The C++ mod does the actual patch each tick.")
    print("[ACF] Test procedure:")
    print("[ACF]   1. open the Camouflage Collection and look at the row")
    print("[ACF]   2. close it, reopen it")
    print("[ACF]   3. if the image only appears on the SECOND open, the viewer caches and our")
    print("[ACF]      late patch is the problem - not the texture")
    return false
end)

-- uacgame [write] - unlock camos in the SURVIVAL VIEWER (the in-game equip list).
--
-- THE KEY INSIGHT, found by reading the save files rather than guessing: the in-game owned-camo
-- list is NOT in UserProfileSaveGame. It lives in the GAMEPLAY save (SaveGames1_0.sav) in a map
-- called `UniformCheckFlagMap`, a TMap<ECamouflageType, bool>.
--
-- That save held exactly 14 camo entries, matching exactly the 14 the player had in game:
--   NORMAL TIGER_STRIPE LEAF TREE_BARK SQUARES BLACK DESERT_TIGER SNEAKING_PW
--   BATTLEDRESS_PW ADDITIONAL_UNIFORM_1 NAKED_WOODLAND NAKED_BELTLINK GOLD NAKED
--
-- This explains everything: uacwrite unlocked the COLLECTION VIEWER because that reads the
-- profile, while the Survival Viewer reads this map and was never touched. Sibling maps
-- FacepaintCheckFlagMap and FoodCheckFlagMap follow the same pattern.
--
-- Read-only unless you pass "write".
RegisterConsoleCommandHandler("uacgame", function(FullCommand, Parameters, Ar)
    local doWrite, maxId = false, 70
    for _, p in ipairs(Parameters or {}) do
        if tostring(p):lower() == "write" then doWrite = true
        elseif tonumber(p) ~= nil then maxId = tonumber(p) end
    end

    -- Find whatever live object owns UniformCheckFlagMap. The gameplay SaveGame class is not
    -- named in the file (it is compressed past the GVAS header), so search live SaveGame objects.
    -- Detect properly: ASK THE CLASS whether it declares the property.
    --
    -- The first version just read `o.UniformCheckFlagMap` and treated a non-nil result as proof.
    -- That accepted everything - EnhancedInputUserSettings and UserProfileSaveGame both "passed"
    -- and then every write silently failed. Reading a missing property does not return nil here.
    -- Detect by BEHAVIOUR, not by asking the class.
    --
    -- Two previous attempts both failed, in opposite directions:
    --   1. "read the property and accept non-nil" - accepted EVERYTHING, including
    --      EnhancedInputUserSettings, because a missing property does not return nil here.
    --   2. "ask the class via ForEachProperty" - found NOTHING, because property enumeration is
    --      unreliable on this UE4SS build (documented at the top of dllmain.cpp).
    --
    -- So test what we actually need: does Find(0) come back with a value? Camo 0 is
    -- GM_CAMOUF_NORMAL, which the player owns, so the real map answers and junk objects do not.
    -- The map is NESTED, which is why every direct access failed. Structure, read out of the
    -- save file and confirmed against the .usmap:
    --
    --   InventoryCheckStatus            (StructProperty)
    --     -> AllInvCheckStatusStruct
    --          WeaponCheckFlagMap
    --          ItemCheckFlagMap
    --          UniformCheckFlagMap      <- camos
    --          FacepaintCheckFlagMap
    --          FoodCheckFlagMap
    --
    -- This is INVENTORY state, updated when a camo is picked up in game - not merely save data.
    -- FULL PATH, read out of the save file's property sequence:
    --
    --   SaveGameData                       (/Script/MGS3.SaveGameData - the class name is in
    --                                       the .sav as the only /Script/ path)
    --     CurrentSaveData                  StructProperty -> SingleSaveGameData
    --       InventoryCheckStatus           StructProperty -> AllInvCheckStatusStruct
    --         UniformCheckFlagMap          TMap<ECamouflageType, bool>   <- camos
    --
    -- Siblings of UniformCheckFlagMap: WeaponCheckFlagMap, ItemCheckFlagMap,
    -- FacepaintCheckFlagMap, FoodCheckFlagMap - same trick will unlock those.
    --
    -- TWO struct layers, not one. Earlier attempts stopped at InventoryCheckStatus and found
    -- nothing, which is why every object came back empty even though SaveGameData was in the list.
    local function looksLikeTheMap(o)
        local ok, cur = pcall(function() return o.CurrentSaveData end)
        if not ok or cur == nil then return nil end
        local ok2, inv = pcall(function() return cur.InventoryCheckStatus end)
        if not ok2 or inv == nil then return nil end
        local ok3, m = pcall(function() return inv.UniformCheckFlagMap end)
        if not ok3 or m == nil then return nil end
        -- Behavioural check: camo 0 (GM_CAMOUF_NORMAL) is owned, so the real map answers.
        local ok4, v = pcall(function() return m:Find(0) end)
        if not ok4 or v == nil then return nil end
        return m
    end

    local holders = {}
    local scanned = 0
    -- Inventory state may live on a manager rather than a SaveGame object, since camos are
    -- acquired as pickups at runtime - so search both.
    for _, cls in ipairs({ "SaveGameData", "SaveGame", "GsrSaveGame", "MGS3SaveGame",
                           "Rg5SystemSaveData", "UserProfileSaveGame",
                           "GsrItemManager", "GsrPlayer", "BP_Player_C",
                           "BP_CobraGameInstance_C", "GsrGameInstance" }) do
        local objs = FindAllOf(cls) or {}
        for i = 1, #objs do
            local o = objs[i]
            if o ~= nil and o:IsValid() then
                scanned = scanned + 1
                local m = looksLikeTheMap(o)
                if m ~= nil then holders[#holders + 1] = { obj = o, map = m } end
            end
        end
    end
    print("[ACF] scanned " .. scanned .. " candidate object(s), " .. #holders .. " hold a usable UniformCheckFlagMap")

    if #holders == 0 then
        print("[ACF] No live object with UniformCheckFlagMap found.")
        print("[ACF] Load into an actual save (not the main menu) and try again.")
        return false
    end

    for i, h in ipairs(holders) do
        print("[ACF] [" .. i .. "] " .. h.obj:GetFullName())
        local have = 0
        for id = 0, maxId do
            local ok, v = pcall(function() return h.map:Find(id) end)
            if ok and v ~= nil then have = have + 1 end
        end
        print("[ACF]     currently holds " .. have .. " camo entries")
    end

    if not doWrite then
        print("[ACF] READ-ONLY. Run 'uacgame write' to unlock.")
        return false
    end

    for i, h in ipairs(holders) do
        local n = 0
        for id = 0, maxId do
            if pcall(function() h.map:Add(id, true) end) then n = n + 1 end
        end
        local after = 0
        for id = 0, maxId do
            local ok, v = pcall(function() return h.map:Find(id) end)
            if ok and v ~= nil then after = after + 1 end
        end
        print("[ACF] [" .. i .. "] wrote " .. n .. ", now readable: " .. after .. "/" .. (maxId + 1))
    end
    print("[ACF] Open the Survival Viewer (TAB) and check the camo list.")
    return false
end)

-- findtex - can a BRAND NEW texture package be loaded?
--
-- This decides whether custom thumbnails are possible. The row's Thumbnail field is a hard
-- UObject pointer, so we can only assign a texture that is already IN MEMORY. Our ACFT01 is a
-- new package name that was never in the cooked AssetRegistry - the same situation that made
-- Camouf_61_asset invisible - except the detour cannot help here, since it only intercepts
-- CamouflageAssetType lookups.
--
-- A vanilla thumbnail is checked alongside as a CONTROL. If the control is not found either,
-- the probe is wrong and the result means nothing (that mistake has been made twice already).
RegisterConsoleCommandHandler("findtex", function(FullCommand, Parameters, Ar)
    local base = "/CobraUI/textures/sv/camouflage/"
    -- Three targets, deliberately. The first run of this test was flawed: the only vanilla
    -- control was ALREADY resident, so LoadAsset was never exercised on it. That proved
    -- StaticFindObject works and nothing about whether LoadAsset can load anything - and
    -- LoadAsset is known to lie (it called vanilla camo 12 undiscoverable).
    --
    -- 10040860 is a vanilla thumbnail that should NOT be loaded during normal play, so it tests
    -- LoadAsset itself:
    --   if it loads   -> LoadAsset works, and ACFT01 failing is a real result
    --   if it doesn't -> LoadAsset cannot load ANY unloaded texture, and the ACFT01 result is
    --                    meaningless; we need a different way to force a load
    local targets = { { "669275",   "vanilla, expected ALREADY LOADED - tests StaticFindObject" },
                      { "10040860", "vanilla, expected NOT loaded - tests LoadAsset itself" },
                      { "ACFT01",   "OUR custom thumbnail" } }
    if Parameters[1] ~= nil then targets = { { Parameters[1], "requested" } } end

    for _, t in ipairs(targets) do
        local name, label = t[1], t[2]
        local full = base .. name .. "." .. name
        print("[ACF] === " .. name .. "  (" .. label .. ") ===")

        local obj = StaticFindObject(full)
        local resident = (obj ~= nil and obj:IsValid())
        print("[ACF]   already in memory: " .. (resident and ("YES - " .. obj:GetFullName()) or "no"))

        if not resident then
            local ok, err = pcall(function() LoadAsset(base .. name) end)
            if not ok then
                print("[ACF]   LoadAsset errored: " .. tostring(err))
            else
                local after = StaticFindObject(full)
                if after ~= nil and after:IsValid() then
                    print("[ACF]   LOADED on demand -> " .. after:GetFullName())
                else
                    print("[ACF]   still not in memory after LoadAsset")
                end
            end
        end
    end
    print("[ACF] Read it as a matrix:")
    print("[ACF]   10040860 LOADS + ACFT01 does not -> new texture packages really are")
    print("[ACF]        unreachable by name; custom thumbnails need the texture referenced from")
    print("[ACF]        an asset that loads (the way the Nexus mods' meshes do).")
    print("[ACF]   NEITHER loads -> LoadAsset simply cannot load an unloaded texture, so this")
    print("[ACF]        test says nothing about ACFT01 and we need another way to force a load.")
    return false
end)

-- findunlock - hunt for the function the GAME calls when you acquire a camo.
--
-- Why: none of the three save fields drives the Survival Viewer / equip menu. Proven - all of
-- CamouflageList, UnlockCamouflageMap and ViewerMap were set for every id (and CamouflageList
-- was even patched to 75/75 on disk and reloaded) and the menu was unchanged.
--
-- So the menu is populated by native code from its own state. The clean way in is not to poke
-- that state directly but to call whatever the game itself calls when the player picks a camo
-- up - then the menu populates the way it normally would.
--
-- Enumeration is unreliable on this build, so candidate paths are looked up directly AND live
-- objects are scanned for anything acquire/unlock/add shaped.
RegisterConsoleCommandHandler("findunlock", function(FullCommand, Parameters, Ar)
    print("[ACF] === direct lookups (reliable) ===")
    local paths = {
        "/Script/MGS3.GsrItemManager:AcquireItem",
        "/Script/MGS3.GsrItemManager:AddItem",
        "/Script/MGS3.UserProfileSaveGame:SetCamouflageAcquired",
        "/Script/Gsr.GsrCollectionItemController:CreateItem",
        "/Script/Gsr.GsrCollectionItemController:ItemNameToItemId",
        "/Script/GsrDirtyControlSystem.GsrDirtyManager:ChangeCamouflage",
        "/Script/CobraUI.CSVTabViewWidget:FindPropDataForSelectIndex",
        "/Script/CobraUI.CSVTabViewWidget:FindPropDataForKindIndex",
    }
    for _, p in ipairs(paths) do
        local fn = StaticFindObject(p)
        print("[ACF]   " .. ((fn ~= nil and fn:IsValid()) and "FOUND  " or "missing") .. " " .. p)
    end

    -- The old version tried to discover function names itself, by walking live objects with
    -- ForEachFunction. That is the exact reflection path this build is unreliable on, and worse,
    -- it could not tell "found nothing" from "never looked": a missing instance was skipped
    -- silently and a bare pcall swallowed enumeration errors. Both print nothing.
    --
    -- So don't hand-roll it. UE4SS ships C++ dumpers that bypass Lua reflection entirely and
    -- write EVERY class and EVERY UFunction, with parameters, to disk. Parameters matter as
    -- much as the name here - finding an acquire function is useless if we cannot call it.
    --
    --   findunlock          generate the C++ headers (function signatures) - what we want
    --   findunlock dump     also dump all objects and properties
    local mode = (Parameters ~= nil and Parameters[1] ~= nil) and tostring(Parameters[1]):lower() or "sdk"
    -- (svwatch, defined below, is the one that catches the pickup handler.)

    -- Both dumpers hardcode their output to UE4SS's working directory (Binaries\Win64) - there
    -- is no setting for it - so they drop loose files next to the exe. Move them into ACF Logs
    -- afterwards to keep the game folder clean. Relative paths resolve against the same working
    -- directory, so this needs no absolute path.
    local function stow(name)
        local ok, err = os.rename(name, "ACF Logs\\" .. name)
        if ok then
            print("[ACF]   moved -> ACF Logs\\" .. name)
        else
            -- Most likely a leftover from a previous run; os.rename will not overwrite.
            print("[ACF]   left in place (" .. tostring(err) .. ")")
        end
    end

    print("[ACF] === UE4SS built-in dump (this pauses the game for a bit) ===")
    if mode == "dump" then
        local ok, err = pcall(function() DumpAllObjects() end)
        print("[ACF] DumpAllObjects: " .. (ok and "done" or ("FAILED: " .. tostring(err))))
        if ok then stow("UE4SS_ObjectDump.txt") end
    end

    local ok, err = pcall(function() GenerateSDK() end)
    if ok then
        print("[ACF] GenerateSDK: done")
        stow("CXXHeaderDump")
        print("[ACF] Every class and UFunction in the game is now on disk. Grep it for the")
        print("[ACF] acquire path rather than guessing at names.")
    else
        print("[ACF] GenerateSDK FAILED: " .. tostring(err))
    end
    return false
end)


-- svcheck - which save field actually drives the SURVIVAL VIEWER (the in-game TAB camo list)?
--
-- We know uacwrite fixes the COLLECTION VIEWER (Extras) by writing
-- UnlockCamouflageMap = EGsrExtraAcquiredStatus::NewAcquired. The in-game list is a separate
-- system and still shows only genuinely-owned camos.
--
-- The clue from the save: UnlockCamouflageMap had 67 entries (mostly Unaquired) while
-- CamouflageList had 30 true - and ~30 matches what the player actually owns. So
-- CamouflageList is the better candidate for what the Survival Viewer reads.
--
-- This prints both fields side by side for every camo id, so it can be lined up against what
-- the TAB menu actually shows. Whichever column matches the menu is the one to write.
RegisterConsoleCommandHandler("svcheck", function(FullCommand, Parameters, Ar)
    local maxId = tonumber(Parameters[1]) or 70
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] No live UserProfileSaveGame - load a save first.")
        return false
    end

    local camoList = save.CamouflageList
    local unlockMap = save.UnlockCamouflageMap
    local viewerMap = save.UnlockCamouflageCollectionViewerMap

    local camoEnum = StaticFindObject("/Script/MGS3.ECamouflageType")
    local function enumName(v)
        if camoEnum == nil or not camoEnum:IsValid() then return "?" end
        local ok, n = pcall(function() return camoEnum:GetNameByValue(v):ToString() end)
        if not ok or n == nil then return "?" end
        return (tostring(n):gsub("^ECamouflageType::", ""))
    end
    local function mapVal(m, id)
        if m == nil then return "-" end
        local ok, v = pcall(function() return m:Find(id) end)
        if not ok or v == nil then return "absent" end
        local ok2, u = pcall(function() return v:get() end)
        local n = ok2 and u or v
        if n == 0 then return "Unaquired"
        elseif n == 1 then return "Acquired"
        elseif n == 2 then return "NewAcquired"
        else return tostring(n) end
    end

    print("[ACF] id  list  UnlockCamouflageMap  ViewerMap        name")
    local listTrue = 0
    for id = 0, maxId do
        local lv = "-"
        if camoList ~= nil and (id + 1) <= #camoList then
            lv = (camoList[id + 1] == true) and "TRUE " or "false"
            if camoList[id + 1] == true then listTrue = listTrue + 1 end
        end
        print(string.format("[ACF] %-3d %-5s %-20s %-16s %s",
              id, lv, mapVal(unlockMap, id), mapVal(viewerMap, id), enumName(id)))
    end
    print("[ACF] CamouflageList: " .. listTrue .. " true of " .. (camoList and #camoList or 0))
    print("[ACF] Now open the TAB / Survival Viewer camo list and compare:")
    print("[ACF]   if the menu matches the 'list' column  -> CamouflageList drives it")
    print("[ACF]   if it matches UnlockCamouflageMap      -> that map drives it")
    print("[ACF]   if it matches neither                  -> the list is built natively and")
    print("[ACF]                                            neither save field controls it")
    return false
end)

-- findsavefuncs - locate whatever actually writes the profile to disk.
--
-- Last night's unlockcamo wrote into the live UserProfileSaveGame and nothing persisted:
-- inspecting UserProfile_{0,1}.sav afterwards showed 30 entries true, not the 71 we set.
-- Writing the object is not enough - something has to flush it. This hunts for that.
RegisterConsoleCommandHandler("findsavefuncs", function(FullCommand, Parameters, Ar)
    -- 1. Stock UE entry points, looked up directly (enumeration is unreliable on this build).
    print("[ACF] === stock UGameplayStatics save functions ===")
    for _, path in ipairs({
        "/Script/Engine.GameplayStatics:SaveGameToSlot",
        "/Script/Engine.GameplayStatics:AsyncSaveGameToSlot",
        "/Script/Engine.GameplayStatics:DoesSaveGameExist",
        "/Script/Engine.GameplayStatics:LoadGameFromSlot",
    }) do
        local fn = StaticFindObject(path)
        print("[ACF]   " .. (fn ~= nil and fn:IsValid() and "FOUND  " or "missing") .. " " .. path)
    end

    -- 2. Live objects whose class looks save/profile related.
    print("[ACF] === live save/profile-ish objects and their Save* functions ===")
    local seen = {}
    for _, cls in ipairs({"UserProfileSaveGame", "GsrSaveManager", "SaveManager", "GsrGameInstance",
                          "BP_CobraGameInstance_C", "CobraGameInstance", "GameInstance"}) do
        local obj = FindFirstOf(cls)
        if obj ~= nil and obj:IsValid() then
            local full = obj:GetClass():GetFullName()
            if not seen[full] then
                seen[full] = true
                print("[ACF]   " .. cls .. " -> " .. full)
                local c = obj:GetClass()
                while c ~= nil and c:IsValid() do
                    local ok = pcall(function()
                        c:ForEachFunction(function(fn)
                            local n = fn:GetFName():ToString()
                            if n:lower():find("save") or n:lower():find("profile") or n:lower():find("unlock") then
                                print("[ACF]       " .. c:GetFName():ToString() .. ":" .. n)
                            end
                        end)
                    end)
                    if not ok then print("[ACF]       <function enumeration failed on this class>") end
                    c = c:GetSuperStruct()
                end
            end
        end
    end
    return false
end)

-- tryload - the discoverability test.
--
-- Vanilla ships Camouf_1..51 and 54..60 and nothing above that. Camo 60 renders from our
-- pak because we OVERRIDE a package the game already knows about; 61-65 and 72 are brand
-- new package names. This command asks the engine to load each one by explicit path and
-- reports which names it can actually find - the difference between "our file is wrong"
-- and "the engine will not look for names that were not present at cook time".
RegisterConsoleCommandHandler("tryload", function(FullCommand, Parameters, Ar)
    local ids = {}
    if Parameters[1] ~= nil then
        for _, p in ipairs(Parameters) do
            local n = tonumber(p)
            if n ~= nil then ids[#ids + 1] = n end
        end
    else
        -- 12/60 are known-good controls (vanilla names), the rest are new names.
        ids = {12, 60, 61, 62, 63, 64, 65, 72}
    end

    print("[ACF] Attempting to load each package by explicit path:")
    for _, id in ipairs(ids) do
        local path = "/Game/Maps/AssetCamouflage/Camouf_" .. id .. "_asset"
        local full = path .. ".Camouf_" .. id .. "_asset"

        local wasLoaded = StaticFindObject(full)
        wasLoaded = (wasLoaded ~= nil and wasLoaded:IsValid())

        local ok, err = pcall(function() LoadAsset(path) end)

        local obj = StaticFindObject(full)
        local isLoaded = (obj ~= nil and obj:IsValid())

        -- DO NOT trust a negative from this command.
        --
        -- It once reported vanilla Camouf_12 as "NOT FOUND - undiscoverable" - flatly wrong,
        -- since camo 12 renders fine. UE4SS's LoadAsset logs "Asset was found but not loaded,
        -- could be a package" and declines to load it, so the follow-up StaticFindObject misses
        -- and we conclude the package does not exist. A miss here means NOTHING on its own.
        --
        -- The trustworthy probe is `camotest <id>`: let the GAME load the camo, then check
        -- whether the object exists. Positives here are still meaningful; negatives are not.
        local verdict
        if not ok then
            verdict = "LoadAsset ERROR: " .. tostring(err)
        elseif isLoaded and wasLoaded then
            verdict = "already resident (was loaded before this call)"
        elseif isLoaded then
            verdict = "LOADED - discoverable (trustworthy positive)"
        else
            verdict = "inconclusive - LoadAsset declines packages; use 'camotest " .. id .. "'"
        end

        print(string.format("[ACF]   Camouf_%-3d %s", id, verdict))
    end
    print("[ACF] If 12/60 load and the rest do not, mod paks cannot introduce NEW package")
    print("[ACF] names - only override existing ones. That is the core blocker for ACF.")
    return false
end)

-- camodiag <id> - everything we know about one camo ID, in one place.
RegisterConsoleCommandHandler("camodiag", function(FullCommand, Parameters, Ar)
    local camo = tonumber(Parameters[1])
    if camo == nil then
        print("[ACF] Usage: camodiag <camo id>   (e.g. camodiag 60)")
        return false
    end

    print("[ACF] ===== camo " .. camo .. " =====")

    -- 1. What does the enum call this value?
    local camoEnum = StaticFindObject("/Script/MGS3.ECamouflageType")
    if camoEnum ~= nil and camoEnum:IsValid() then
        local ok, name = pcall(function() return camoEnum:GetNameByValue(camo):ToString() end)
        print("[ACF] enum name: " .. (ok and tostring(name) or ("<lookup failed: " .. tostring(name) .. ">")))
    else
        print("[ACF] enum name: <ECamouflageType not found>")
    end

    -- 2. Is the data asset already resident in memory?
    local assetPath = "/Game/Maps/AssetCamouflage/Camouf_" .. camo .. "_asset.Camouf_" .. camo .. "_asset"
    local asset = StaticFindObject(assetPath)
    if asset ~= nil and asset:IsValid() then
        print("[ACF] asset in memory: YES - " .. asset:GetFullName())
    else
        print("[ACF] asset in memory: no (may simply not be loaded yet, which is normal)")
    end

    -- 3. Try to actually LOAD it by explicit path.
    --
    -- This is the question StaticFindObject cannot answer: that only reports what is
    -- ALREADY in memory, so "no" there means nothing on its own. LoadAsset asks the
    -- engine to go and find the package on disk.
    --
    -- (We do not call DataAssetHelper:LoadDataAsset here - it takes 3 parameters, not 1,
    -- and its signature is still unconfirmed. LoadAsset tests the same thing more directly.)
    local okLoad, loadErr = pcall(function()
        LoadAsset("/Game/Maps/AssetCamouflage/Camouf_" .. camo .. "_asset")
    end)
    if not okLoad then
        print("[ACF] LoadAsset: call failed - " .. tostring(loadErr))
    else
        local nowLoaded = StaticFindObject(assetPath)
        if nowLoaded ~= nil and nowLoaded:IsValid() then
            print("[ACF] LoadAsset: SUCCESS - package is discoverable and loaded")
        else
            print("[ACF] LoadAsset: ran, but the object still is not in memory")
            print("[ACF]            -> this package name is NOT discoverable by the engine")
        end
    end

    -- 4. Save-side unlock state.
    local save = FindFirstOf("UserProfileSaveGame")
    if save ~= nil and save:IsValid() then
        local camoList = save.CamouflageList
        if camoList ~= nil then
            local len = #camoList
            local idx = camo + 1
            if idx <= len then
                print("[ACF] CamouflageList[" .. idx .. "] = " .. tostring(camoList[idx]) .. "  (length " .. len .. ")")
            else
                print("[ACF] CamouflageList too short: length " .. len .. ", need index " .. idx)
            end
        end
        local function readMap(fieldName)
            local m = save[fieldName]
            if m == nil then return "<nil>" end
            local ok, v = pcall(function() return m:Find(camo) end)
            if not ok then return "<read failed>" end
            if v == nil then return "not set" end
            local ok2, unwrapped = pcall(function() return v:get() end)
            return tostring(ok2 and unwrapped or v)
        end
        print("[ACF] UnlockCamouflageMap[" .. camo .. "] = " .. readMap("UnlockCamouflageMap"))
        print("[ACF] UnlockCamouflageCollectionViewerMap[" .. camo .. "] = " .. readMap("UnlockCamouflageCollectionViewerMap"))
    else
        print("[ACF] save: no live UserProfileSaveGame")
    end

    return false
end)

-- unlockall [max] - apply every unlock mechanism we know of, to every camo id.
-- Covers vanilla AND modded ids in one shot, and reports what actually stuck
-- instead of assuming the writes worked.
RegisterConsoleCommandHandler("unlockall", function(FullCommand, Parameters, Ar)
    local maxId = tonumber(Parameters[1]) or 65

    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame instance - load a save first")
        return false
    end

    local camoList = save.CamouflageList
    if camoList == nil then
        print("[ACF] CamouflageList was nil")
        return false
    end

    -- Grow one element at a time: bulk TArray operations are not safe on this
    -- UE4SS build, single appends are the proven-safe pattern.
    local grew = 0
    while #camoList < (maxId + 1) do
        camoList[#camoList + 1] = true
        grew = grew + 1
        if grew > 200 then
            print("[ACF] Refusing to grow further - something is wrong.")
            break
        end
    end
    if grew > 0 then print("[ACF] Extended CamouflageList by " .. grew .. " (now " .. #camoList .. ")") end

    local unlockMap = save.UnlockCamouflageMap
    local viewerMap = save.UnlockCamouflageCollectionViewerMap

    local setList, setUnlock, setViewer, failed = 0, 0, 0, 0
    for id = 0, maxId do
        local idx = id + 1
        if idx <= #camoList then
            if pcall(function() camoList[idx] = true end) then setList = setList + 1 else failed = failed + 1 end
        end
        if unlockMap ~= nil then
            if pcall(function() unlockMap:Add(id, true) end) then setUnlock = setUnlock + 1 else failed = failed + 1 end
        end
        if viewerMap ~= nil then
            if pcall(function() viewerMap:Add(id, true) end) then setViewer = setViewer + 1 else failed = failed + 1 end
        end
    end

    print("[ACF] unlockall 0.." .. maxId .. " complete:")
    print("[ACF]   CamouflageList entries set true: " .. setList)
    print("[ACF]   UnlockCamouflageMap adds:        " .. setUnlock)
    print("[ACF]   ViewerMap adds:                  " .. setViewer)
    if failed > 0 then print("[ACF]   FAILED operations: " .. failed) end
    print("[ACF] Note: none of these have ever affected the TAB equip menu (native-only).")
    print("[ACF] Check the Collection Viewer / Extras, which is what these actually drive.")

    return false
end)

RegisterConsoleCommandHandler("forcecamo", function(FullCommand, Parameters, Ar)
    ACF_EnsureHookRegistered()

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

-- unlockcamo [maxId] - actually unlock camos, and REPORT what stuck.
--
-- The old version just fired the game's own "UnlockAllCamouflage" console command, which
-- does nothing. This writes every save-side mechanism we know of and then reads each one
-- back, so we can tell "the write failed" apart from "the write worked but the game does
-- not read this field".
--
-- Step 1 inspects entries the game itself wrote, for camos you have ALREADY unlocked. That
-- tells us the real value shape before we write anything - guessing `true` is how earlier
-- attempts may have silently written the wrong type.
-- Shared implementation behind both `unlockcamo` and `uacwrite`.
--
-- CONFIRMED WORKING 2026-07-29: run from the main menu it revealed every uniform in the
-- Camouflage Collection. The fix was writing EGsrExtraAcquiredStatus (0=Unaquired, 1=Acquired,
-- 2=NewAcquired) instead of `true` - these maps are enum->enum, never boolean.
local function ACF_UnlockCamos(Parameters, forceWrite)
    local doWrite = forceWrite or false
    local maxId = 70
    for _, p in ipairs(Parameters or {}) do
        if tostring(p):lower() == "write" then doWrite = true
        elseif tonumber(p) ~= nil then maxId = tonumber(p) end
    end

    -- Find EVERY live UserProfileSaveGame, not just the first.
    --
    -- FindFirstOf returns whichever instance the engine happens to hand back, and that is not
    -- necessarily the profile the game is actually using. This already caused real damage once:
    -- writes went into one instance and a SaveGameToSlot call then wrote THAT object over the
    -- real profile on disk, dropping unlocks from 30 to 27.
    --
    -- It is also the likeliest reason this works from the main menu but not in-game: a different
    -- instance is live in each context. So write to all of them and report what was found.
    local saves = FindAllOf("UserProfileSaveGame") or {}
    local live = {}
    for i = 1, #saves do
        if saves[i] ~= nil and saves[i]:IsValid() then live[#live + 1] = saves[i] end
    end
    if #live == 0 then
        print("[ACF] No live UserProfileSaveGame found.")
        return false
    end
    print("[ACF] found " .. #live .. " live UserProfileSaveGame instance(s):")
    for i, s in ipairs(live) do
        local n = "?"
        local cl = s.CamouflageList
        if cl ~= nil then
            local t = 0
            for k = 1, #cl do if cl[k] == true then t = t + 1 end end
            n = t .. "/" .. #cl .. " unlocked"
        end
        print("[ACF]   [" .. i .. "] " .. s:GetFullName() .. "  (" .. n .. ")")
    end
    local save = live[1]

    if not doWrite then
        print("[ACF] READ-ONLY mode. Nothing will be modified.")
        print("[ACF] Add the word 'write' to actually apply unlocks: unlockcamo write")
    end

    local function describe(v)
        if v == nil then return "nil" end
        local ok, unwrapped = pcall(function() return v:get() end)
        if ok then return type(unwrapped) .. "(" .. tostring(unwrapped) .. ")" end
        return type(v) .. "(" .. tostring(v) .. ")"
    end

    -- 1. What do the game's OWN entries look like?
    print("[ACF] === existing entries written by the game ===")
    for _, field in ipairs({"UnlockCamouflageMap", "UnlockCamouflageCollectionViewerMap"}) do
        local m = save[field]
        if m == nil then
            print("[ACF]   " .. field .. ": <nil>")
        else
            local found = 0
            for id = 0, maxId do
                local ok, v = pcall(function() return m:Find(id) end)
                if ok and v ~= nil then
                    if found < 4 then print("[ACF]   " .. field .. "[" .. id .. "] = " .. describe(v)) end
                    found = found + 1
                end
            end
            print("[ACF]   " .. field .. ": " .. found .. " existing entries")
        end
    end

    local camoList = save.CamouflageList
    if camoList ~= nil then
        local trues = 0
        for i = 1, #camoList do if camoList[i] == true then trues = trues + 1 end end
        print("[ACF]   CamouflageList: length " .. #camoList .. ", " .. trues .. " set true")
    end

    -- 2. Write everything - only when explicitly opted in.
    if not doWrite then
        print("[ACF] Read-only: stopping before any modification.")
        print("[ACF] To apply: load a save, then run   unlockcamo write")
        return false
    end
    print("[ACF] === writing unlocks for 0.." .. maxId .. " ===")
    local grew = 0
    if camoList ~= nil then
        while #camoList < (maxId + 1) and grew < 200 do
            camoList[#camoList + 1] = true
            grew = grew + 1
        end
    end

    -- The unlock maps do NOT store booleans. Decoded straight out of UserProfile_0.sav:
    --
    --   UnlockCamouflageMap                 : TMap<ECamouflageType, EGsrExtraAcquiredStatus>
    --   UnlockCamouflageCollectionViewerMap : TMap<EItemName,       EGsrExtraAcquiredStatus>
    --   EGsrExtraAcquiredStatus             : Unaquired | Acquired | NewAcquired   (sic)
    --
    -- Every previous attempt passed `true` into an ENUM property, which is meaningless - that
    -- alone explains why unlocking has never worked, across every mechanism we tried.
    --
    -- Resolve the numeric value of "Acquired" from the enum rather than assuming 0/1/2, since
    -- declaration order is not guaranteed.
    local acquired, statusEnum = nil, StaticFindObject("/Script/Gsr.EGsrExtraAcquiredStatus")
    if statusEnum == nil or not statusEnum:IsValid() then
        statusEnum = StaticFindObject("/Script/MGS3.EGsrExtraAcquiredStatus")
    end
    if statusEnum ~= nil and statusEnum:IsValid() then
        print("[ACF]   status enum: " .. statusEnum:GetFullName())
        for v = 0, 8 do
            local ok, nm = pcall(function() return statusEnum:GetNameByValue(v):ToString() end)
            if ok and nm ~= nil and nm ~= "" then
                print("[ACF]     " .. v .. " = " .. nm)
                if nm:find("NewAcquired") then acquired = v
                elseif nm:find("Acquired") and acquired == nil then acquired = v end
            end
        end
    else
        print("[ACF]   EGsrExtraAcquiredStatus NOT FOUND - falling back to numeric 1")
    end
    if acquired == nil then acquired = 1 end
    print("[ACF]   writing acquired-status value: " .. acquired)

    -- CAMOS ONLY. Deliberately does not touch UnlockCamouflageCollectionViewerMap:
    -- that map is keyed by EItemName, not ECamouflageType, so camo ids are simply the wrong
    -- key for it. Facepaints/items will get their own command once we have the camo -> item
    -- mapping from DT_CamouflageCollection's ItemType column.
    -- Write to EVERY live instance. In-game and main-menu appear to use different
    -- UserProfileSaveGame objects, and picking the wrong one is why this looked like it only
    -- worked from the menu. Writing to all of them removes the guess.
    local wrote = { list = 0, unlock = 0 }
    for si, s in ipairs(live) do
        local cl = s.CamouflageList
        -- grow one at a time: bulk TArray ops are not safe on this UE4SS build
        local g = 0
        if cl ~= nil then
            while #cl < (maxId + 1) and g < 200 do cl[#cl + 1] = true; g = g + 1 end
        end
        local m1 = s.UnlockCamouflageMap
        local w = { list = 0, unlock = 0 }
        for id = 0, maxId do
            if cl ~= nil and (id + 1) <= #cl then
                if pcall(function() cl[id + 1] = true end) then w.list = w.list + 1 end
            end
            if m1 ~= nil and pcall(function() m1:Add(id, acquired) end) then w.unlock = w.unlock + 1 end
        end
        print(string.format("[ACF]   [%d] CamouflageList %d set%s, UnlockCamouflageMap %d set",
              si, w.list, (g > 0 and (" (grew by " .. g .. ")") or ""), w.unlock))
        wrote.list = wrote.list + w.list
        wrote.unlock = wrote.unlock + w.unlock
    end
    print("[ACF]   totals across " .. #live .. " instance(s): list=" .. wrote.list .. " map=" .. wrote.unlock)

    -- 3. Read back - did the writes actually persist into the maps?
    print("[ACF] === read-back verification ===")
    -- Only the camo map, since that is the only one this command writes.
    do
        local m = save.UnlockCamouflageMap
        if m ~= nil then
            local stuck = 0
            for id = 0, maxId do
                local ok, v = pcall(function() return m:Find(id) end)
                if ok and v ~= nil then stuck = stuck + 1 end
            end
            print("[ACF]   UnlockCamouflageMap: " .. stuck .. "/" .. (maxId + 1) .. " readable after write")
        end
    end
    if camoList ~= nil then
        local trues = 0
        for i = 1, #camoList do if camoList[i] == true then trues = trues + 1 end end
        print("[ACF]   CamouflageList: " .. trues .. "/" .. #camoList .. " true")
    end

    -- 4. DO NOT CALL SaveGameToSlot HERE. It is destructive on this game.
    --
    -- Measured: we set 75 entries true in memory, called SaveGameToSlot(save, "UserProfile", 0),
    -- and UserProfile_1.sav came out with 27 true - DOWN from 30. It reported "no error".
    --
    -- Why: FindFirstOf("UserProfileSaveGame") does not return the profile the game is actually
    -- using. We edit that other instance, then SaveGameToSlot serialises OUR object over the
    -- real profile file, discarding genuine unlock data. This is the same mechanism that
    -- appeared to wipe unlocks from the main menu.
    --
    -- Before any save call is reinstated, we must first identify the REAL live profile object
    -- (probably reachable from the game instance rather than by FindFirstOf) and confirm writes
    -- to it show up in game. Until then this command is memory-only.
    print("[ACF] === NOT saving to disk (SaveGameToSlot is destructive here - see comment) ===")
    print("[ACF] Changes are in memory only and will be lost on exit.")

    print("[ACF] Done. Open the Camouflage Collection and check the completion %.")
    print("[ACF] Note: the % covers uniforms AND facepaints together, so it will not reach")
    print("[ACF] 100% from camo unlocks alone.")
    return false
end

-- uacwrite - the short one. Unlocks immediately, no 'write' argument needed.
RegisterConsoleCommandHandler("uacwrite", function(FullCommand, Parameters, Ar)
    return ACF_UnlockCamos(Parameters, true)
end)

-- svunlock - unlocks camos in the SURVIVAL VIEWER (the in-game equip menu), which is a
-- different system from the Extras Camouflage Collection that uacwrite handles.
--
-- Ownership for the equip menu lives in the legacy MGS3 save blob, not in any UE property, so
-- the actual work happens in the C++ mod - Lua cannot read raw process memory. This just drops
-- a request file that the C++ side picks up on its next tick (well under a second).
--
--   svunlock          unlock six IDs proven ownable (4, 6, 8, 13, 17, 29) - the safe test
--   svunlock all      unlock the whole vanilla camo range, 0-60
--   svunlock 4 29     unlock specific camo IDs
--
-- Nothing is written to disk by this. Save in-game afterwards and the game persists it itself,
-- exactly as it does when you pick a camo up during play.
-- svsnap / svdiff - find out what a REAL camo grant changes.
--
-- Writing the ownership flag ourselves is provably not enough: the byte reads back correctly
-- and the Survival Viewer ignores it, while a genuine pickup sets the same byte in the same
-- block and the viewer updates instantly. So a grant touches more than one field.
--
--   svsnap    copy the whole live legacy block
--   ...then acquire a camo in game...
--   svdiff    report every byte that changed
local function ACF_SvRequest(word)
    local f, err = io.open("ACF Logs\\ACF_svunlock.txt", "w")
    if f == nil then
        print("[ACF] Could not write request file: " .. tostring(err))
        return false
    end
    f:write(word)
    f:close()
    return true
end

-- svread - does the Survival Viewer even LOOK at the camo ownership table?
--
-- We can set the ownership flag in the live block and the viewer ignores it, yet a real pickup
-- sets the same byte and the viewer updates at once. Either a grant writes something else too,
-- or the viewer reads its ownership from somewhere entirely different. This settles which.
--
-- Guards the camo table with PAGE_NOACCESS so READS fault as well as writes, then logs whoever
-- touches it. Arm it, then open the Survival Viewer.
--
--   No hits at all  -> the viewer never consults this table, and writing it can never work.
--   Hits            -> the GHIDRA address is the code that reads ownership; work back from there.
RegisterConsoleCommandHandler("svread", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("watch read") then
        print("[ACF] svread: arming on READS of the camo table. Now open the Survival Viewer.")
        print("[ACF] Expect a big frame-rate hit while armed - 'svwatch off' to stop.")
    end
    return true
end)

-- svlock - revoke camos. The counterpart to svunlock, and not optional:
-- ids 52 (BONSAI) and 53 (USMX) are ECamouflageType entries with NO asset behind them (the
-- cooked registry has Camouf_1..51 and 54..60 and nothing for those two). Selecting one is a
-- hard crash, so anything able to grant them must be able to take them back.
--
--   svlock 52 53   revoke those ids
-- svkeymap - read/patch Mgs3UniformCobraUiKeyMap, the live copy of DT_Mgs3UniformToCobraUIKey.
--
-- The row label resolves as:
--   uniform -> DT_Mgs3UniformToCobraUIKey -> "アイテム名定義-IT_EqAdditionalUniform2-2"
--           -> MGS3InGameLocTable -> display text
-- MGS3InGameLocTable has no entry for the AdditionalUniform slots (vanilla never authored them),
-- so the lookup fails and the game prints the key with the namespace stripped - which is exactly
-- the "-IT_EqAdditionalUniform2-2" seen on screen.
--
-- That fallback already renders arbitrary text. So if the stored value were "アイテム名定義ACF Mod 1",
-- the same fallback should print "ACF Mod 1". This tests that without touching any pak.
--
--   svkeymap        read the current values
--   svkeymap set    overwrite ADDITIONAL2-5 with the ACF names
RegisterConsoleCommandHandler("svkeymap", function(FullCommand, Parameters, Ar)
    local doSet = (Parameters ~= nil and Parameters[1] ~= nil
                   and tostring(Parameters[1]):lower() == "set")

    local state = FindFirstOf("CCamouflageMenuState")
    if state == nil or not state:IsValid() then
        print("[ACF] No live CCamouflageMenuState - open the Survival Viewer first.")
        return false
    end

    local ok, map = pcall(function() return state.Mgs3UniformCobraUiKeyMap end)
    if not ok or map == nil then
        print("[ACF] Could not read Mgs3UniformCobraUiKeyMap: " .. tostring(map))
        return false
    end

    -- Single-key Find/Add only. Bulk TMap iteration hard-crashes this build.
    local NS = "\227\130\162\227\130\164\227\131\134\227\131\160\229\144\141\229\174\154"  -- アイテム名定義 (UTF-8)
    local slots = {
        { key = "ADDITIONAL2", name = "ACF Mod 1" },
        { key = "ADDITIONAL3", name = "ACF Mod 2" },
        { key = "ADDITIONAL4", name = "ACF Mod 3" },
        { key = "ADDITIONAL5", name = "ACF Mod 4" },
    }
    -- A vanilla entry to compare against, so a nil read is distinguishable from a wrong key.
    local probes = { "ADDITIONAL1", "GOLD", "ADDITIONAL2" }

    print("[ACF] --- current values ---")
    for _, k in ipairs(probes) do
        local ok2, v = pcall(function() return map:Find(k) end)
        -- :get() yields an FString OBJECT, so tostring() on it prints a pointer. Unwrap with
        -- :ToString() (on the FString, or on the wrapper directly) to get readable text.
        local shown = "nil"
        if ok2 and v ~= nil then
            local ok3, s = pcall(function() return v:get():ToString() end)
            if not ok3 then ok3, s = pcall(function() return v:ToString() end) end
            if not ok3 then ok3, s = pcall(function() return tostring(v:get()) end) end
            shown = ok3 and tostring(s) or ("<unreadable: " .. tostring(v) .. ">")
        end
        print(string.format("[ACF]   %-14s -> %s", k, shown))
    end

    if not doSet then
        print("[ACF] Run 'svkeymap set' to overwrite ADDITIONAL2-5, then reopen the viewer.")
        return true
    end

    for _, s in ipairs(slots) do
        local ok4, err = pcall(function() map:Add(s.key, NS .. s.name) end)
        print(string.format("[ACF]   set %-14s -> %s%s  %s",
              s.key, NS, s.name, ok4 and "ok" or ("FAILED: " .. tostring(err))))
    end
    print("[ACF] Now CLOSE and REOPEN the Survival Viewer - the list is rebuilt on open.")
    return true
end)

-- svrows - dump what the Survival Viewer is actually rendering each row from.
--
-- Rows come from FPropData structs in a TMap on CSVTabViewWidget (layout from Ghidra's
-- FindPropDataForSelectIndex plus the SDK dump): Name at +0x10, Icon at +0x30, Camouf at +0x34.
-- So ACF's rows showing "-IT_EqAdditionalUniform2-2" is an unresolved key sitting in an FString
-- we can read - not an unreachable localisation table.
--
-- READ-ONLY. Open the Survival Viewer first so a live widget exists.
--   svrows       dump only (read-only)
--   svrows fix   also rewrite ACF's row names in place
RegisterConsoleCommandHandler("svrows", function(FullCommand, Parameters, Ar)
    local fix = (Parameters ~= nil and Parameters[1] ~= nil
                 and tostring(Parameters[1]):lower() == "fix")
    if ACF_SvRequest(fix and "rows fix" or "rows") then
        if fix then
            print("[ACF] svrows fix: renaming ACF rows in place, then dumping.")
        else
            print("[ACF] svrows: dumping FPropData rows - see UE4SS.log.")
        end
    end
    return true
end)

RegisterConsoleCommandHandler("svlock", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil then
        for _, v in ipairs(Parameters) do arg = arg .. " " .. tostring(v) end
    end
    arg = arg:gsub("^%s+", "")
    if arg == "" then arg = "52 53" end
    if ACF_SvRequest("clear " .. arg) then
        print("[ACF] svlock: revoking " .. arg)
    end
    return true
end)

RegisterConsoleCommandHandler("svsnap", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("snap") then
        print("[ACF] svsnap: capturing live state. Now go acquire a camo, then run svdiff.")
    end
    return true
end)

RegisterConsoleCommandHandler("svdiff", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("diff") then
        print("[ACF] svdiff: comparing against the snapshot - see UE4SS.log.")
    end
    return true
end)

-- svwatch - catch the function the game runs when you pick a camo up off the ground.
--
-- Setting the ownership flag by hand is not enough: the write lands (the table reads back
-- correctly) but the Survival Viewer does not change, while a real pickup updates it instantly
-- with no save involved. So the pickup path does more, and this finds that code.
--
-- Marks the page holding the camo table read-only. Any write faults, the mod records the
-- faulting instruction, lets the write through and re-arms. Pick a camo up and the handler
-- names itself - the log prints a GHIDRA: address to jump straight to.
--
--   svwatch        arm
--   svwatch off    disarm
--   svwatch rows   trap the FPropData buffer instead, to catch whoever populates it
RegisterConsoleCommandHandler("svwatch", function(FullCommand, Parameters, Ar)
    local arg = "watch"
    local p = (Parameters ~= nil and Parameters[1] ~= nil) and tostring(Parameters[1]):lower() or ""
    if p == "off" then arg = "watch off" elseif p == "rows" then arg = "watch rows" end
    local f, err = io.open("ACF Logs\\ACF_svunlock.txt", "w")
    if f == nil then
        print("[ACF] Could not write request file: " .. tostring(err))
        return false
    end
    f:write(arg)
    f:close()
    if arg == "watch off" then
        print("[ACF] svwatch: disarming.")
    else
        print("[ACF] svwatch: arming. Now go PICK UP A CAMO off the ground.")
        print("[ACF] The log will print 'camo id N written by ... GHIDRA: 0x...'")
    end
    return true
end)

RegisterConsoleCommandHandler("svunlock", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil then
        for _, v in ipairs(Parameters) do arg = arg .. " " .. tostring(v) end
    end
    arg = arg:gsub("^%s+", "")
    if arg == "" then arg = "4 6 8 13 17 29" end

    -- Relative on purpose - see the matching note in dllmain.cpp. TEMP is NOT the same on both
    -- sides (the game process resolves a different one than a shell does), but the working
    -- directory is, because Lua and the C++ mod run in the same process. Resolves to
    -- Binaries\Win64\ACF Logs.
    local path = "ACF Logs\\ACF_svunlock.txt"
    local f, err = io.open(path, "w")
    if f == nil then
        print("[ACF] Could not write request file: " .. tostring(err))
        return false
    end
    f:write(arg)
    f:close()

    print("[ACF] svunlock requested: " .. arg)
    print("[ACF] The C++ side will pick this up within a second - check UE4SS.log for")
    print("[ACF] 'legacy camo table @ ...'. Then open the Survival Viewer, and SAVE to persist.")
    return true
end)

-- unlockcamo - read-only unless you pass 'write'. Kept for the safe inspection path.
RegisterConsoleCommandHandler("unlockcamo", function(FullCommand, Parameters, Ar)
    return ACF_UnlockCamos(Parameters, false)
end)

-- The game's own console command, kept separately since it appears to be a no-op.
RegisterConsoleCommandHandler("unlockcamovanillacmd", function(FullCommand, Parameters, Ar)
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
    print("[ACF] Executed UnlockAllCamouflage via KismetSystemLibrary (historically a no-op)")
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

RegisterConsoleCommandHandler("unlockindex", function(FullCommand, Parameters, Ar)
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

    local enumValue = tonumber(Parameters[1])
    if enumValue == nil then
        print("[ACF] Usage: unlockindex <enum value> (e.g. unlockindex 60 for GM_CAMOUF_ADDITIONAL_UNIFORM_1)")
        return false
    end

    local luaIndex = enumValue + 1
    print("[ACF] CamouflageList length = " .. tostring(#camoList) .. ", setting index " .. luaIndex .. " (enum value " .. enumValue .. ") to true")

    if luaIndex > #camoList then
        print("[ACF] WARNING: index " .. luaIndex .. " is beyond current array length " .. #camoList .. " - this would be an append, not a direct set. Aborting to be safe.")
        return false
    end

    camoList[luaIndex] = true
    print("[ACF] Done. CamouflageList[" .. luaIndex .. "] = " .. tostring(camoList[luaIndex]))

    return false
end)

RegisterConsoleCommandHandler("unlockviewerkey", function(FullCommand, Parameters, Ar)
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame instance")
        return false
    end

    local viewerMap = save.UnlockCamouflageCollectionViewerMap
    if viewerMap == nil then
        print("[ACF] UnlockCamouflageCollectionViewerMap was nil")
        return false
    end

    local enumValue = tonumber(Parameters[1])
    if enumValue == nil then
        print("[ACF] Usage: unlockviewerkey <enum value> (e.g. unlockviewerkey 60)")
        return false
    end

    local ok, err = pcall(function()
        viewerMap:Add(enumValue, true)
    end)

    if not ok then
        print("[ACF] Failed to set key " .. enumValue .. ": " .. tostring(err))
    else
        print("[ACF] Set UnlockCamouflageCollectionViewerMap[" .. enumValue .. "] = true (no error)")
        local ok2, val = pcall(function() return viewerMap:Find(enumValue) end)
        if ok2 then
            print("[ACF] Read back: " .. tostring(val))
        else
            print("[ACF] Read back failed: " .. tostring(val))
        end
    end

    return false
end)

RegisterConsoleCommandHandler("unlockcamoflag", function(FullCommand, Parameters, Ar)
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame instance")
        return false
    end

    local unlockMap = save.UnlockCamouflageMap
    if unlockMap == nil then
        print("[ACF] UnlockCamouflageMap was nil")
        return false
    end

    local enumValue = tonumber(Parameters[1])
    if enumValue == nil then
        print("[ACF] Usage: unlockcamoflag <enum value> (e.g. unlockcamoflag 60)")
        return false
    end

    local ok, err = pcall(function()
        unlockMap:Add(enumValue, true)
    end)

    if not ok then
        print("[ACF] Failed to set key " .. enumValue .. ": " .. tostring(err))
    else
        print("[ACF] Set UnlockCamouflageMap[" .. enumValue .. "] = true (no error)")
    end

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

RegisterConsoleCommandHandler("findsortdatatable", function(FullCommand, Parameters, Ar)
    local widget = FindFirstOf("sv_camouflage_C")
    if widget == nil or not widget:IsValid() then
        print("[ACF] Could not find live sv_camouflage_C instance - open the TAB menu first, or it may not persist when closed")
        return false
    end

    print("[ACF] Found sv_camouflage_C: " .. widget:GetFullName())

    local cls = widget:GetClass()
    while cls ~= nil and cls:IsValid() do
        print("[ACF] === functions on " .. cls:GetFName():ToString() .. " ===")
        cls:ForEachFunction(function(fn)
            print("[ACF]     " .. fn:GetFName():ToString())
        end)
        cls = cls:GetSuperStruct()
    end

    local sortTable = widget.UniformSortDeltaDataTable
    if sortTable ~= nil and sortTable:IsValid() then
        print("[ACF] UniformSortDeltaDataTable: " .. sortTable:GetFullName())
    else
        print("[ACF] UniformSortDeltaDataTable is nil/invalid")
    end

    local facepaintSortTable = widget.FacepaintSortDeltaDataTable
    if facepaintSortTable ~= nil and facepaintSortTable:IsValid() then
        print("[ACF] FacepaintSortDeltaDataTable: " .. facepaintSortTable:GetFullName())
    else
        print("[ACF] FacepaintSortDeltaDataTable is nil/invalid")
    end

    print("[ACF] SelectIndex: " .. tostring(widget.SelectIndex))

    local keyMap = widget.Mgs3UniformCobraUiKeyMap
    if keyMap == nil then
        print("[ACF] Mgs3UniformCobraUiKeyMap is nil")
    else
        local ok, num = pcall(function() return keyMap:Num() end)
        if ok then
            print("[ACF] Mgs3UniformCobraUiKeyMap:Num() = " .. tostring(num))
        else
            print("[ACF] Mgs3UniformCobraUiKeyMap:Num() failed: " .. tostring(num))
        end
    end
    return false
end)

RegisterConsoleCommandHandler("refreshcamomenu", function(FullCommand, Parameters, Ar)
    local widget = FindFirstOf("sv_camouflage_C")
    if widget == nil or not widget:IsValid() then
        print("[ACF] Could not find live sv_camouflage_C instance - open the TAB menu first")
        return false
    end

    print("[ACF] Calling InitFromDataTable() on sv_camouflage_C - watch for a crash")
    local ok, err = pcall(function()
        widget:InitFromDataTable()
    end)

    if not ok then
        print("[ACF] InitFromDataTable call failed: " .. tostring(err))
    else
        print("[ACF] InitFromDataTable() completed without error")
    end
    return false
end)

RegisterConsoleCommandHandler("getcamobyindex", function(FullCommand, Parameters, Ar)
    local widget = FindFirstOf("sv_camouflage_C")
    if widget == nil or not widget:IsValid() then
        print("[ACF] Could not find live sv_camouflage_C instance - open the TAB menu first")
        return false
    end

    local startIdx = tonumber(Parameters[1]) or 0
    local endIdx = tonumber(Parameters[2]) or startIdx

    for i = startIdx, endIdx do
        local outTable = {}
        local ok, a = pcall(function() return widget:GetCamouflageByIndex(i, outTable) end)
        if ok then
            local parts = {}
            for k, v in pairs(outTable) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            end
            print("[ACF] GetCamouflageByIndex(" .. i .. ") returned=" .. tostring(a) .. " outTable={" .. table.concat(parts, ", ") .. "}")
        else
            print("[ACF] GetCamouflageByIndex(" .. i .. ") failed: " .. tostring(a))
        end
    end
    return false
end)

RegisterConsoleCommandHandler("findtabview", function(FullCommand, Parameters, Ar)
    -- FindPropDataForSelectIndex was referenced by GetCamouflageByIndex but wasn't on
    -- any class in sv_camouflage_C's own hierarchy. It may live on CSVTabViewWidget,
    -- which sv_camouflage_C references via its Target and sv_tab_switch properties.
    local cls = StaticFindObject("/Script/CobraUI.CSVTabViewWidget")
    if cls == nil or not cls:IsValid() then
        print("[ACF] Could not find class /Script/CobraUI.CSVTabViewWidget")
    else
        local c = cls
        while c ~= nil and c:IsValid() do
            print("[ACF] === functions on " .. c:GetFName():ToString() .. " ===")
            c:ForEachFunction(function(fn)
                print("[ACF]     " .. fn:GetFName():ToString())
            end)
            c = c:GetSuperStruct()
        end
    end

    local widget = FindFirstOf("sv_camouflage_C")
    if widget ~= nil and widget:IsValid() then
        for _, propName in ipairs({"Target", "sv_tab_switch"}) do
            local obj = widget[propName]
            if obj ~= nil and obj:IsValid() then
                print("[ACF] live " .. propName .. " = " .. obj:GetFullName())
                print("[ACF] live " .. propName .. " class = " .. obj:GetClass():GetFullName())
            else
                print("[ACF] live " .. propName .. " is nil/invalid")
            end
        end
    else
        print("[ACF] No live sv_camouflage_C (open the camo menu first if you want the live instances)")
    end
    return false
end)

RegisterConsoleCommandHandler("findpropfunc", function(FullCommand, Parameters, Ar)
    -- Ghidra showed FindPropDataForSelectIndex IS a registered UFunction, sitting in the
    -- same table as OnButtonBaseHovered (which we know is on CPropMenuBaseState).
    -- Our ForEachFunction enumeration missed it, almost certainly because UClass::FuncMap
    -- is a TMap and bulk TMap reads are broken on this UE4SS build.
    -- So: look these up directly by name instead of relying on enumeration.
    local classes = {
        "/Script/CobraUI.CPropMenuBaseState",
        "/Script/CobraUI.CCamouflageMenuState",
        "/Script/CobraUI.CSVMenuStateBase",
        "/Script/CobraUI.CSVTabViewWidget",
        "/Script/CobraUI.SurvivalViewerStateSubsystem",
    }
    local funcs = {
        "FindPropDataForSelectIndex",
        "FindPropDataForKindIndex",
        "FindButtonForSelectIndex",
        "GetInvoker",
        "GetIsInputEnable",
        "GetMultiTabDefaultTabType",
    }

    for _, clsPath in ipairs(classes) do
        for _, fnName in ipairs(funcs) do
            local path = clsPath .. ":" .. fnName
            local fn = StaticFindObject(path)
            if fn ~= nil and fn:IsValid() then
                print("[ACF] FOUND " .. path)
                local ok = pcall(function()
                    fn:ForEachProperty(function(prop)
                        print("[ACF]     " .. prop:GetClass():GetFName():ToString() .. " " .. prop:GetFName():ToString())
                    end)
                end)
                if not ok then print("[ACF]     (could not list params)") end
            end
        end
    end
    print("[ACF] findpropfunc done")
    return false
end)

RegisterConsoleCommandHandler("findbuttons", function(FullCommand, Parameters, Ar)
    -- Ghidra told us the menu's list is made of CPropButtonBase objects held in two TMaps
    -- on CSVTabViewWidget. This looks at the LIVE buttons to find out what they actually are:
    --   * class name ending in _C  -> Blueprint widget (creation may be hookable)
    --   * plain native class       -> native-only (needs a code detour)
    -- Their outer/owner path also tells us whether they're spawned at runtime or are a
    -- fixed pool baked into a widget Blueprint (which we could edit via our pak pipeline).
    local buttons = FindAllOf("CPropButtonBase")
    if buttons == nil or #buttons == 0 then
        print("[ACF] No live CPropButtonBase instances found - is the camo menu open?")
    else
        print("[ACF] Found " .. #buttons .. " live CPropButtonBase instance(s)")

        local byClass = {}
        local order = {}
        for i = 1, #buttons do
            local b = buttons[i]
            if b ~= nil and b:IsValid() then
                local ok, clsName = pcall(function() return b:GetClass():GetFullName() end)
                if ok then
                    if byClass[clsName] == nil then
                        byClass[clsName] = { count = 0, example = nil }
                        order[#order + 1] = clsName
                    end
                    byClass[clsName].count = byClass[clsName].count + 1
                    if byClass[clsName].example == nil then
                        local ok2, full = pcall(function() return b:GetFullName() end)
                        if ok2 then byClass[clsName].example = full end
                    end
                end
            end
        end

        for _, clsName in ipairs(order) do
            local info = byClass[clsName]
            print("[ACF]   " .. info.count .. "x  " .. clsName)
            print("[ACF]      e.g. " .. tostring(info.example))
        end
    end

    -- Also grab the tab view widget that owns the two maps.
    local tabView = FindFirstOf("CSVTabViewWidget")
    if tabView ~= nil and tabView:IsValid() then
        print("[ACF] CSVTabViewWidget instance: " .. tabView:GetFullName())
        print("[ACF] CSVTabViewWidget class: " .. tabView:GetClass():GetFullName())
    else
        print("[ACF] No live CSVTabViewWidget found")
    end

    print("[ACF] findbuttons done")
    return false
end)

RegisterConsoleCommandHandler("hookbuttoncreate", function(FullCommand, Parameters, Ar)
    -- The camo list buttons turned out to be Blueprint widgets (sv_tab_switch_item_C),
    -- created dynamically (count grew 7 -> 21 -> 28 while browsing). Blueprint widget
    -- construction goes through paths UE4SS CAN hook, unlike the native map writes.
    -- If any of these fire while the camo list builds, we've found a reachable entry point.
    local targets = {
        {"/CobraUI/Blueprint/sv_camouflage/sv_tab_switch_item.sv_tab_switch_item_C:Construct", "item:Construct"},
        {"/CobraUI/Blueprint/sv_camouflage/sv_tab_switch_item.sv_tab_switch_item_C:PreConstruct", "item:PreConstruct"},
        {"/CobraUI/Blueprint/sv_camouflage/sv_tab_switch_list.sv_tab_switch_list_C:Construct", "list:Construct"},
        {"/CobraUI/Blueprint/sv_camouflage/sv_tab_switch.sv_tab_switch_C:Construct", "tabswitch:Construct"},
        {"/Script/UMG.WidgetBlueprintLibrary:Create", "UMG:CreateWidget"},
        {"/Script/UMG.UserWidget:Construct", "UserWidget:Construct"},
    }

    for _, t in ipairs(targets) do
        local path, label = t[1], t[2]
        local ok, err = pcall(function()
            RegisterHook(path, function(Context, ...)
                print("[ACF] [CREATE] " .. label)
            end)
        end)
        if ok then
            print("[ACF] hooked " .. label)
        else
            print("[ACF] could NOT hook " .. label .. " -> " .. tostring(err))
        end
    end
    return false
end)

RegisterConsoleCommandHandler("findcamotabview", function(FullCommand, Parameters, Ar)
    -- FindFirstOf grabbed the backpack tab view; we want the camouflage one specifically.
    local all = FindAllOf("CSVTabViewWidget")
    if all == nil or #all == 0 then
        print("[ACF] No CSVTabViewWidget instances found")
        return false
    end
    print("[ACF] " .. #all .. " CSVTabViewWidget instance(s):")
    for i = 1, #all do
        local w = all[i]
        if w ~= nil and w:IsValid() then
            local ok, full = pcall(function() return w:GetFullName() end)
            local ok2, cls = pcall(function() return w:GetClass():GetFullName() end)
            if ok and ok2 then
                print("[ACF]   " .. full)
                print("[ACF]      class: " .. cls)
            end
        end
    end
    return false
end)

RegisterConsoleCommandHandler("dumpcamolist", function(FullCommand, Parameters, Ar)
    -- CamouflageList is NOT indexed by ECamouflageType value: it shipped with 66 entries
    -- while the enum has 71. So "set index <enum value>" was meaningless.
    --
    -- Dump the true/false pattern so it can be matched against the camos actually owned.
    -- The Collection Viewer lists camos in DT_UniformSortDelta order, and unacquired ones
    -- render as NO DATA, so the pattern of trues should line up with the visible list and
    -- reveal what the index actually means.
    --
    -- Single-index TArray reads are safe on this build; bulk/iterated reads are not, so this
    -- reads one element at a time rather than iterating the array object.
    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] Could not find UserProfileSaveGame")
        return false
    end

    local camoList = save.CamouflageList
    if camoList == nil then
        print("[ACF] CamouflageList was nil")
        return false
    end

    local count = #camoList
    print("[ACF] CamouflageList has " .. count .. " entries (1-based Lua indices):")

    local owned = {}
    for i = 1, count do
        local ok, v = pcall(function() return camoList[i] end)
        if ok and v == true then
            owned[#owned + 1] = tostring(i)
        end
    end

    print("[ACF] TRUE at indices: " .. table.concat(owned, ", "))
    print("[ACF] (" .. #owned .. " of " .. count .. " set)")
    return false
end)

-- ---------------------------------------------------------------------------
-- Help
-- ---------------------------------------------------------------------------
-- Most of these need a save loaded before they will find anything.

local ACF_COMMANDS = {
    { "-- diagnostics (start here) --" },
    { "dumpusmap",             "generate Mappings.usmap so DataTables can be edited offline" },
    { "findsavefuncs",          "find what actually flushes the profile to disk" },
    { "tryload [ids...]",       "can the engine LOAD each Camouf_<id>_asset? (default: 12 60 61-65 72)" },
    { "camotest <camo>",        "forcecamo + asset-cache before/after diff; says if the game even asked" },
    { "camodiag <camo>",        "enum name, asset resident?, LoadDataAsset result, unlock state" },
    { "unlockall [max]",        "every unlock mechanism, every id 0..max (default 65)" },

    { "-- camo / equip --" },
    { "forcecamo <fp> <camo>",  "preview-only camo swap; REVERTS on pause/area change" },
    { "realequip <camo>",       "GsrDirtyManager:ChangeCamouflage (no visible effect alone)" },
    { "realequip2 <camo>",      "BP_Player:OnChangeCamouflageApply (no visible effect alone)" },

    { "-- save / unlock --" },
    { "checksave",              "report CamouflageList length" },
    { "unlocknew",              "append one 'true' to CamouflageList" },
    { "unlockindex <enum>",     "set CamouflageList[enum+1] = true" },
    { "unlockcamoflag <enum>",  "UnlockCamouflageMap:Add(enum, true)" },
    { "unlockviewerkey <enum>", "UnlockCamouflageCollectionViewerMap:Add(enum, true)" },
    { "uacwrite [max]",         "UNLOCK ALL CAMOS - works; writes EGsrExtraAcquiredStatus, memory-only" },
    { "uacgame [write]",        "UNLOCK CAMOS IN THE SURVIVAL VIEWER via UniformCheckFlagMap" },
    { "findtex [name]",         "can a new texture package load? (custom thumbnail test)" },
    { "findunlock",             "hunt for the game's own 'acquire camo' function (in-game unlock)" },
    { "svcheck [max]",          "compare CamouflageList vs unlock maps against the Survival Viewer" },
    { "unlockcamo [max]",       "same, but read-only unless you add 'write'" },
    { "unlockcamovanillacmd",   "the game's own UnlockAllCamouflage console cmd (a no-op)" },

    { "-- discovery --" },
    { "findassethelper",        "locate the live DataAssetHelper" },
    { "findallcamouflageassets","list loaded CamouflageAssetType assets (Camouf_<id>_asset)" },
    { "loadasset <name>",       "call DataAssetHelper:LoadDataAsset" },
    { "findcamowidget",         "scan live UserWidgets for camo/uniform names" },
    { "findcamocollection",     "look for BP_CamouflageCollectionSnake" },
    { "findcamotabview",        "list every CSVTabViewWidget (camo one, not backpack)" },
    { "findbuttons",            "group live CPropButtonBase buttons by class" },
    { "findsortdatatable",      "dump sv_camouflage_C sort tables + class functions" },
    { "findtabview",            "list CSVTabViewWidget functions" },
    { "findpropfunc",           "look up Find*/Get* funcs directly (enumeration is unreliable)" },
    { "findrealclasspaths",     "real class paths + functions for the main managers" },
    { "dumpfunc <path>",        "list a UFunction's parameters" },

    { "-- hooks / experiments --" },
    { "registerhooks",          "install the camo-change hooks" },
    { "hookbuttoncreate",       "hook widget construction (never fires - creation is native)" },
    { "refreshcamomenu",        "call sv_camouflage_C:InitFromDataTable" },
    { "getcamobyindex <a> <b>", "call GetCamouflageByIndex over a range" },
}

RegisterConsoleCommandHandler("acfhelp", function(FullCommand, Parameters, Ar)
    print("[ACF] Available commands:")
    for _, entry in ipairs(ACF_COMMANDS) do
        if entry[2] == nil then
            print("[ACF]")
            print("[ACF] " .. entry[1])
        else
            print(string.format("[ACF]   %-26s %s", entry[1], entry[2]))
        end
    end
    return false
end)

print("[ACF] Lua ready - " .. #ACF_COMMANDS .. " entries registered. Type 'acfhelp' for the command list.")