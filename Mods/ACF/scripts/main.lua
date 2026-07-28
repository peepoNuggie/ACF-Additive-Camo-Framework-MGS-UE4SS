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

        local verdict
        if not ok then
            verdict = "LoadAsset ERROR: " .. tostring(err)
        elseif isLoaded and wasLoaded then
            verdict = "already resident"
        elseif isLoaded then
            verdict = "LOADED - discoverable"
        else
            verdict = "NOT FOUND - undiscoverable"
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
RegisterConsoleCommandHandler("unlockcamo", function(FullCommand, Parameters, Ar)
    -- READ-ONLY unless you explicitly pass "write".
    --
    -- Running this in the MAIN MENU appeared to scramble displayed unlock state. The profile
    -- on disk turned out to be fine (writes never persisted), but the lesson stands: in the
    -- main menu, FindFirstOf("UserProfileSaveGame") may return a different/default instance
    -- than the real loaded profile. ONLY run the write path with a save actually loaded.
    local doWrite = false
    local maxId = 70
    for _, p in ipairs(Parameters or {}) do
        if tostring(p):lower() == "write" then doWrite = true
        elseif tonumber(p) ~= nil then maxId = tonumber(p) end
    end

    local save = FindFirstOf("UserProfileSaveGame")
    if save == nil or not save:IsValid() then
        print("[ACF] No live UserProfileSaveGame - load a save first.")
        return false
    end

    if not doWrite then
        print("[ACF] READ-ONLY mode. Nothing will be modified.")
        print("[ACF] Add the word 'write' to actually apply unlocks: unlockcamo write")
        print("[ACF] Do NOT run the write path from the main menu - load a save first.")
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

    local wrote = { list = 0, unlock = 0, viewer = 0 }
    for id = 0, maxId do
        if camoList ~= nil and (id + 1) <= #camoList then
            if pcall(function() camoList[id + 1] = true end) then wrote.list = wrote.list + 1 end
        end
        local m1 = save.UnlockCamouflageMap
        if m1 ~= nil and pcall(function() m1:Add(id, true) end) then wrote.unlock = wrote.unlock + 1 end
        local m2 = save.UnlockCamouflageCollectionViewerMap
        if m2 ~= nil and pcall(function() m2:Add(id, true) end) then wrote.viewer = wrote.viewer + 1 end
    end
    print("[ACF]   CamouflageList set:  " .. wrote.list .. (grew > 0 and ("  (grew by " .. grew .. ")") or ""))
    print("[ACF]   UnlockCamouflageMap: " .. wrote.unlock)
    print("[ACF]   ViewerMap:           " .. wrote.viewer)

    -- 3. Read back - did the writes actually persist into the maps?
    print("[ACF] === read-back verification ===")
    for _, field in ipairs({"UnlockCamouflageMap", "UnlockCamouflageCollectionViewerMap"}) do
        local m = save[field]
        if m ~= nil then
            local stuck = 0
            for id = 0, maxId do
                local ok, v = pcall(function() return m:Find(id) end)
                if ok and v ~= nil then stuck = stuck + 1 end
            end
            print("[ACF]   " .. field .. ": " .. stuck .. "/" .. (maxId + 1) .. " readable after write")
        end
    end
    if camoList ~= nil then
        local trues = 0
        for i = 1, #camoList do if camoList[i] == true then trues = trues + 1 end end
        print("[ACF]   CamouflageList: " .. trues .. "/" .. #camoList .. " true")
    end

    print("[ACF] Now open the Camouflage Collection and check the completion %.")
    print("[ACF] If it did not move, the viewer reads something else and we hunt that next.")
    return false
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
    { "unlockcamo [max]",       "unlock camos 0..max (default 70) via every mechanism, with read-back" },
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