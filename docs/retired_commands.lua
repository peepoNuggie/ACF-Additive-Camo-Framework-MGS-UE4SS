-- ACF retired console commands - ARCHIVE ONLY, NOT LOADED
--
-- These 35 commands were removed from main.lua once the questions they were built to answer had
-- been settled. They are kept verbatim, with their original line numbers, because several encode
-- findings that are easy to lose and expensive to rediscover - and because a command that "did
-- nothing" is only useful evidence if you can still read what it did.
--
-- Do not add this file to mods.txt or require it. Several of these write to game memory through
-- offsets that were only ever valid for the build they were written against, and a few arm page
-- traps that make the game unplayable while active. If you want one back, read
-- docs/RETIRED_COMMANDS.md for why it was retired first - in most cases the answer is that the
-- mechanism it tested turned out not to be the one the game uses.
--
-- Removed 2026-07-31, at the same time the mod's own diagnostics were gated for release.

-- ============================================================================
-- registerhooks   (main.lua lines 81-84 before removal)
-- ============================================================================
RegisterConsoleCommandHandler("registerhooks", function(FullCommand, Parameters, Ar)
    ACF_EnsureHookRegistered()
    return false
end)


-- ============================================================================
-- realequip   (main.lua lines 86-106 before removal)
-- ============================================================================
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


-- ============================================================================
-- realequip2   (main.lua lines 108-128 before removal)
-- ============================================================================
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


-- ============================================================================
-- findcamowidget   (main.lua lines 130-152 before removal)
-- ============================================================================
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


-- ============================================================================
-- findcamocollection   (main.lua lines 154-166 before removal)
-- ============================================================================
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


-- ============================================================================
-- findrealclasspaths   (main.lua lines 168-185 before removal)
-- ============================================================================
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


-- ============================================================================
-- scanprobe   (main.lua lines 379-429 before removal)
-- ============================================================================
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


-- ============================================================================
-- findtex   (main.lua lines 691-748 before removal)
-- ============================================================================
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


-- ============================================================================
-- findunlock   (main.lua lines 750-824 before removal)
-- ============================================================================
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


-- ============================================================================
-- svcheck   (main.lua lines 827-888 before removal)
-- ============================================================================
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


-- ============================================================================
-- findsavefuncs   (main.lua lines 890-936 before removal)
-- ============================================================================
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


-- ============================================================================
-- tryload   (main.lua lines 938-995 before removal)
-- ============================================================================
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


-- ============================================================================
-- camobase   (main.lua lines 1711-1724 before removal)
-- ============================================================================
-- camobase - the camouflage index and the base value that feeds it.
--
-- From the MGS3-Delta-Trainer's "calcuateCamoIndexOffset" signature, which lands at Ghidra
-- 0x147ACEC10 in the legacy layer:
--     index = FUN_147a9d010( *(short*)(state + 0x2F88) + *(int*)(state + 0x820C), f )
--     (&DAT_1535C2064)[player * 0x58] = index          -- percentage x10
-- state is the same object ACF already uses for camo ownership (+0x3E84), so the base is a
-- two-byte field we can already reach. Watch the numbers against the HUD before trusting them.
RegisterConsoleCommandHandler("camobase", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("camobase") then
        print("[ACF] camobase: logging base + live index for 30s. Switch camos and move around.")
    end
    return true
end)


-- ============================================================================
-- camoval   (main.lua lines 1726-1736 before removal)
-- ============================================================================
-- camoval - print the live camouflage percentage from the object that holds it.
--
-- FUN_145342800, the debug version of the gauge update, reads the percentage from a persistent
-- object at +0xCD4 rather than from the queue the release path uses. Long-lived memory is what
-- every previous trap lacked. Verify it tracks the number on screen before trusting it.
RegisterConsoleCommandHandler("camoval", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("camoval") then
        print("[ACF] camoval: logging the live percentage for 30s - watch the HUD and compare.")
    end
    return true
end)


-- ============================================================================
-- findcamo   (main.lua lines 1738-1751 before removal)
-- ============================================================================
-- findcamo - locate the per-camo base value table in the running game.
--
-- The values cannot be found in Ghidra because the legacy Mgs3 data is loaded at runtime into
-- memory that holds nothing in the file on disk - the same reason svarena's strings show as "??".
-- One pass over the game image, on demand, then it stops. This is not the timer-driven sweep of
-- all process memory that caused trouble before.
--
-- Looks for six consecutive known base values, ids 55-60: 5, 15, 45, 0, -100, 20.
RegisterConsoleCommandHandler("findcamo", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("findcamo") then
        print("[ACF] findcamo: searching - see UE4SS.log (takes a moment).")
    end
    return true
end)


-- ============================================================================
-- svarena   (main.lua lines 1790-1811 before removal)
-- ============================================================================
-- svarena - follow the two pointers each camo record carries into the legacy data arena.
--
-- The 0x50 record holds a pointer at +0x2C and another at +0x34, different per camo. They aim at
-- the region the Mgs3 layer fills at startup - the same range the legacy dispatcher returns for
-- kind 0x56 - which is NOT in the executable's initialised data, so Ghidra shows "??" there and it
-- can only be read from the running game.
--
-- Point of the exercise: Gold displays -100 and Olive Drab and Naked do not, so the static
-- camouflage value should be the field that differs between their blocks.
--
--   svarena            Gold (59), Olive Drab (0), Naked (11)
--   svarena 59 0       specific ids
RegisterConsoleCommandHandler("svarena", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil then
        for _, v in ipairs(Parameters) do arg = arg .. " " .. tostring(v) end
    end
    if ACF_SvRequest("arena" .. arg) then
        print("[ACF] svarena: dumping the arena blocks - see UE4SS.log.")
    end
    return true
end)


-- ============================================================================
-- svcap   (main.lua lines 1913-1959 before removal)
-- ============================================================================
-- svcap - call the Survival Viewer's own caption getters.
--
-- UCCamouflageMenuState exposes two siblings:
--   FString GetCaptionText(ETabType tabType, int32 Index)
--   FString GetCaptionExplainText(ETabType tabType, int32 Index)
-- GetCaptionText is what resolves through Mgs3UniformCobraUiKeyMap (the map we already patch for
-- names), so its sibling is the description P2 is missing. Calling both side by side shows the raw
-- key the description path wants, the same way svrows exposed "-IT_EqAdditionalUniform2-2".
--
-- ETab_Face=0 ETab_Uniform=1 ETab_Weapon=2 ETab_Item=3
--   svcap                 uniform tab, indices 0-24
--   svcap <start> <count> [tab]
RegisterConsoleCommandHandler("svcap", function(FullCommand, Parameters, Ar)
    local start = tonumber(Parameters and Parameters[1]) or 0
    local count = tonumber(Parameters and Parameters[2]) or 25
    local tab   = tonumber(Parameters and Parameters[3]) or 1

    local state = FindFirstOf("CCamouflageMenuState")
    if state == nil or not state:IsValid() then
        print("[ACF] No live CCamouflageMenuState - open the Survival Viewer first.")
        return false
    end

    for _, fn in ipairs({ "GetCaptionText", "GetCaptionExplainText" }) do
        local ok, f = pcall(function() return state[fn] end)
        print(string.format("[ACF] %s present=%s", fn, tostring(ok and f ~= nil)))
    end

    print(string.format("[ACF] --- tab %d, indices %d..%d ---", tab, start, start + count - 1))
    for i = start, start + count - 1 do
        local okN, name = pcall(function() return state:GetCaptionText(tab, i) end)
        local okE, expl = pcall(function() return state:GetCaptionExplainText(tab, i) end)
        local sName = okN and ACF_Str(name) or ("ERR " .. tostring(name):sub(1, 50))
        local sExpl = okE and ACF_Str(expl) or ("ERR " .. tostring(expl):sub(1, 50))
        -- Escape the embedded newlines. Both getters return multi-line text, and UE4SS writes log
        -- entries without separators, so raw newlines made consecutive rows run together and the
        -- name/explain columns looked misaligned by one row.
        sName = sName:gsub("[\r\n]", "\\n")
        sExpl = sExpl:gsub("[\r\n]", "\\n")
        -- Skip fully blank rows so the output stays readable past the end of the real list.
        if sName ~= "" or sExpl ~= "" then
            print(string.format("[ACF]  %3d  name=[%s]", i, sName))
            print(string.format("[ACF]       expl=[%s]", sExpl))
        end
    end
    return true
end)


-- ============================================================================
-- svexplain   (main.lua lines 1974-2016 before removal)
-- ============================================================================
RegisterConsoleCommandHandler("svexplain", function(FullCommand, Parameters, Ar)
    if ACF_explainHooked then
        print("[ACF] svexplain hook already installed for this session.")
        return true
    end

    local target = "/Script/CobraUI.CCamouflageMenuState:GetCaptionExplainText"
    local ok, err = pcall(function()
        RegisterHook(target,
            function() end,
            function(self, tabType, Index, ReturnValue)
                local okI, idx = pcall(function() return Index:get() end)
                local okT, tab = pcall(function() return tabType:get() end)
                if not okI then return end
                local was = "?"
                pcall(function() was = ACF_Str(ReturnValue:get()) end)
                print(string.format("[ACF][explain] tab=%s index=%s was=[%s]",
                      tostring(okT and tab or "?"), tostring(idx),
                      tostring(was):gsub("[\r\n]", "\\n")))

                -- Try both readings of the index at once: the row it names and the row after it.
                local meta = ACF_LoadSlotMeta()
                for _, slot in ipairs({ idx, idx + 1 }) do
                    local m = meta[slot]
                    if m ~= nil and m.Description ~= nil and m.Description ~= "" then
                        local text = string.format("[idx=%d slot=%d] %s", idx, slot, m.Description)
                        local okS = pcall(function() ReturnValue:set(text) end)
                        print(string.format("[ACF][explain]   -> override %s", okS and "ok" or "FAILED"))
                        return
                    end
                end
            end)
    end)

    if not ok then
        print("[ACF] could not hook " .. target .. ": " .. tostring(err))
        return false
    end
    ACF_explainHooked = true
    print("[ACF] hooked " .. target)
    print("[ACF] Open the Survival Viewer and move over the ACF rows - each call is logged.")
    return true
end)


-- ============================================================================
-- unlockcamo   (main.lua lines 2142-2145 before removal)
-- ============================================================================
-- unlockcamo - read-only unless you pass 'write'. Kept for the safe inspection path.
RegisterConsoleCommandHandler("unlockcamo", function(FullCommand, Parameters, Ar)
    return ACF_UnlockCamos(Parameters, false)
end)


-- ============================================================================
-- unlockcamovanillacmd   (main.lua lines 2147-2162 before removal)
-- ============================================================================
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


-- ============================================================================
-- checksave   (main.lua lines 2164-2181 before removal)
-- ============================================================================
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


-- ============================================================================
-- unlocknew   (main.lua lines 2182-2200 before removal)
-- ============================================================================
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


-- ============================================================================
-- unlockindex   (main.lua lines 2202-2233 before removal)
-- ============================================================================
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


-- ============================================================================
-- unlockviewerkey   (main.lua lines 2235-2271 before removal)
-- ============================================================================
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


-- ============================================================================
-- unlockcamoflag   (main.lua lines 2273-2303 before removal)
-- ============================================================================
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


-- ============================================================================
-- findassethelper   (main.lua lines 2305-2321 before removal)
-- ============================================================================
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


-- ============================================================================
-- dumpfunc   (main.lua lines 2352-2365 before removal)
-- ============================================================================
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


-- ============================================================================
-- findsortdatatable   (main.lua lines 2384-2430 before removal)
-- ============================================================================
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


-- ============================================================================
-- refreshcamomenu   (main.lua lines 2432-2450 before removal)
-- ============================================================================
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


-- ============================================================================
-- getcamobyindex   (main.lua lines 2452-2476 before removal)
-- ============================================================================
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


-- ============================================================================
-- findtabview   (main.lua lines 2478-2511 before removal)
-- ============================================================================
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


-- ============================================================================
-- findpropfunc   (main.lua lines 2513-2552 before removal)
-- ============================================================================
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


-- ============================================================================
-- findbuttons   (main.lua lines 2554-2605 before removal)
-- ============================================================================
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


-- ============================================================================
-- hookbuttoncreate   (main.lua lines 2607-2635 before removal)
-- ============================================================================
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


-- ============================================================================
-- findcamotabview   (main.lua lines 2637-2657 before removal)
-- ============================================================================
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


