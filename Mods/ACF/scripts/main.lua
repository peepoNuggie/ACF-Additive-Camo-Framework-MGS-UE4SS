-- UE4SS's print does not terminate the line, so every message this file emits ran together into
-- one wall of text in the console and the log
--
-- Shadowing print here fixes all 186 call sites at once. It has to be declared before anything
-- uses it: Lua resolves the name lexically, so a definition further down would leave every
-- earlier call still bound to the global.
local _print = print
local function print(message)
    _print(tostring(message) .. "\n")
end

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
    -- Confirmed via findpropfunc (command since retired): these live on CSVTabViewWidget (NOT CPropMenuBaseState).
    -- sv_camouflage_C reaches one via its Target property; CPropMenuBaseState via sv_tab_switch.
    -- The two TMaps Ghidra found (+0x748 propdata, +0x798 index->button) are on THIS object.
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindPropDataForSelectIndex", "CSVTabViewWidget:FindPropDataForSelectIndex")
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindButtonForSelectIndex", "CSVTabViewWidget:FindButtonForSelectIndex")
    TryHookWithArgs("/Script/CobraUI.CSVTabViewWidget:FindPropDataForKindIndex", "CSVTabViewWidget:FindPropDataForKindIndex")
end

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

-- camodesc - can a mod author color part of their description?
--
-- Spider's entry shows a white line then an ORANGE one, but the row struct has exactly one
-- description string (DescryptionText) and no effect field. So either that orange is rich-text
-- markup inside the one string - in which case an author can write it - or it is not
-- author-supplied at all.
--
-- Both halves of the answer come from built-in Blueprint functions, no memory work:
--   UDataTableFunctionLibrary reads the column, and the widget hands over its own style set.
--
-- Read the output for two things:
--   1. does Spider's string contain <tags>?  If yes, markup is the mechanism.
--   2. is the string readable English, or a loc key?  A key means the markup lives in
--      MGS3InGameLocTable, which ACF cannot add rows to - so it would NOT be author-supplied.
-- UE4SS wraps values in RemoteUnrealParam, sometimes more than one layer deep, and a wrapper
-- prints as "RemoteUnrealParam: 0x..." rather than failing. Unwrap until a real string appears,
-- because a half-unwrapped value looks like a legitimate answer.
local function ACF_Text(v, depth)
    depth = depth or 0
    if v == nil then return "" end
    if type(v) == "string" then return v end
    if type(v) == "userdata" then
        if v.ToString ~= nil then
            local ok, s = pcall(function() return v:ToString() end)
            if ok and type(s) == "string" then return s end
        end
        if depth < 4 and v.get ~= nil then
            local ok, inner = pcall(function() return v:get() end)
            if ok then return ACF_Text(inner, depth + 1) end
        end
    end
    return tostring(v)
end

-- Describe whatever came back, so an unhandled return shape is visible instead of silently
-- iterating zero times and reading as "the table is empty".
local function ACF_Shape(v)
    local t = type(v)
    if t ~= "table" and t ~= "userdata" then return t .. " (" .. tostring(v) .. ")" end
    local bits = { t }
    if t == "table" then
        local n, keys = 0, {}
        for k, _ in pairs(v) do
            n = n + 1
            if n <= 6 then keys[#keys + 1] = tostring(k) end
        end
        bits[#bits + 1] = "#=" .. tostring(#v)
        bits[#bits + 1] = "pairs=" .. n
        if #keys > 0 then bits[#bits + 1] = "keys[" .. table.concat(keys, ",") .. "]" end
    else
        for _, m in ipairs({ "ForEach", "get", "GetArrayNum", "ToString", "type" }) do
            if v[m] ~= nil then bits[#bits + 1] = m .. "()" end
        end
    end
    return table.concat(bits, " ")
end

-- UE4SS hands arrays back in more than one shape depending on the call, so accept either.
local function ACF_EachArray(arr, fn)
    if arr == nil then return false end
    if type(arr) == "table" then
        for i = 1, #arr do fn(i, ACF_Text(arr[i])) end
        return true
    end
    if type(arr) == "userdata" then
        if arr.get ~= nil and arr.ForEach == nil then
            local ok, inner = pcall(function() return arr:get() end)
            if ok then return ACF_EachArray(inner, fn) end
        end
        if arr.ForEach ~= nil then
            arr:ForEach(function(i, e) fn(i, ACF_Text(e)) end)
            return true
        end
    end
    return false
end

RegisterConsoleCommandHandler("camodesc", function(FullCommand, Parameters, Ar)
    local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    if lib == nil or not lib:IsValid() then
        print("[ACF] DataTableFunctionLibrary CDO not found")
        return true
    end

    local dt = StaticFindObject("/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection.DT_CamouflageCollection")
    if dt == nil or not dt:IsValid() then
        print("[ACF] DT_CamouflageCollection not loaded - open the Camouflage Collection once first")
        return true
    end

    -- UE4SS returns nil here and writes the out param into the table you hand it, so keep the
    -- reference and read that afterwards rather than using the return value.
    local names = {}
    local okNames = pcall(function() lib:GetDataTableRowNames(dt, names) end)
    local okCol, col = pcall(function() return lib:GetDataTableColumnAsString(dt, FName("DescryptionText")) end)
    if not okCol then
        print("[ACF] GetDataTableColumnAsString failed: " .. tostring(col))
        return true
    end

    local rowNames = {}
    if okNames then ACF_EachArray(names, function(i, s) rowNames[i] = s end) end
    if next(rowNames) == nil then
        print("[ACF] row names unavailable - GetDataTableRowNames shape: " ..
              (okNames and ACF_Shape(names) or ("error " .. tostring(names))))
    end

    print("[ACF] --- DescryptionText, raw ---")
    local shown, tagged, wrapped = 0, 0, 0
    local listed = ACF_EachArray(col, function(i, text)
        if text == "" then return end
        shown = shown + 1
        if text:find("<", 1, true) ~= nil then tagged = tagged + 1 end
        if text:find("RemoteUnrealParam", 1, true) ~= nil then wrapped = wrapped + 1 end
        print(string.format("[ACF]   %-28s %s", rowNames[i] or ("row " .. i), text))
    end)
    if not listed then
        print("[ACF] could not iterate the column - unexpected return shape: " .. type(col))
        return true
    end

    -- A value that never unwrapped still prints and still counts, so say so loudly rather than
    -- letting "0 containing '<'" read as a finding.
    if wrapped > 0 then
        print(string.format("[ACF] %d of %d values did NOT unwrap - the counts below mean nothing.",
              wrapped, shown))
        return true
    end

    print(string.format("[ACF] %d non-empty, %d containing '<'", shown, tagged))
    if tagged == 0 then
        print("[ACF] No markup here. Either these are loc keys and the tags live in the loc table,")
        print("[ACF] or the orange line is not part of this string at all.")
    end

    -- The tag vocabulary: whatever row names a style set carries. Most rich text blocks on screen
    -- have no style set, so take every live one rather than the first - FindFirstOf picked a bare
    -- one and reported "no TextStyleSet" as though that settled it.
    local blocks = FindAllOf("CobraRichTextBlock")
    if blocks == nil or #blocks == 0 then
        print("[ACF] No CobraRichTextBlock live - open a menu that shows a description, then rerun.")
        return true
    end

    local seen, withSet = {}, 0
    for i = 1, #blocks do
        local b = blocks[i]
        if b ~= nil and b:IsValid() then
            local okSet, styleSet = pcall(function() return b.TextStyleSet end)
            if okSet and styleSet ~= nil and styleSet:IsValid() then
                local path = styleSet:GetFullName()
                if not seen[path] then
                    seen[path] = true
                    withSet = withSet + 1
                    print("[ACF] --- valid tags (rows of " .. path .. ") ---")
                    local setNames = {}
                    local okS = pcall(function() lib:GetDataTableRowNames(styleSet, setNames) end)
                    if not okS then
                        print("[ACF] GetDataTableRowNames raised an error")
                    else
                        local any = false
                        ACF_EachArray(setNames, function(_, s) any = true; print("[ACF]   <" .. s .. ">") end)
                        if not any then
                            print("[ACF] returned nothing usable. shape: " .. ACF_Shape(setNames))
                        end
                    end
                end
            end
        end
    end
    print(string.format("[ACF] %d rich text block(s) live, %d distinct style set(s)", #blocks, withSet))
    return true
end)

-- whichtext [needle] - which widget is actually drawing a given piece of text?
--
-- Written because ACF's description came out with its rich-text tags shown literally. A
-- UCobraRichTextBlock exists in the Survival Viewer (UCSVTabViewWidget::item_flavor_text), but
-- "a rich text block exists in that menu" is not the same claim as "our string goes into it" -
-- and only the second one matters. This asks the widgets directly instead of inferring.
--
-- Reports the class, so a plain UCobraTextBlock is distinguishable from a rich one, and for rich
-- ones whether a TextStyleSet is attached - a rich block with no style set parses nothing.
RegisterConsoleCommandHandler("whichtext", function(FullCommand, Parameters, Ar)
    local needle = "Plain text"
    if Parameters ~= nil and #Parameters > 0 then needle = table.concat(Parameters, " ") end

    -- "all" lists every text widget with what it is showing. Needed for the infinity marker,
    -- which cannot be typed into the console as a search term - and if the HUD's ammo widget does
    -- NOT appear here holding a glyph, then the marker is not text at all, which is the assumption
    -- the whole current theory rests on.
    if needle:lower() == "all" then
        print("[ACF] --- every live text widget with non-empty text ---")
        local shown = 0
        for _, className in ipairs({ "CobraRichTextBlock", "CobraTextBlock", "RichTextBlock", "TextBlock" }) do
            local blocks = FindAllOf(className)
            if blocks ~= nil then
                for i = 1, #blocks do
                    local b = blocks[i]
                    if b ~= nil and b:IsValid() then
                        local ok, txt = pcall(function() return ACF_Text(b:GetText()) end)
                        if ok and txt ~= nil and txt ~= "" then
                            shown = shown + 1
                            -- Byte length differing from character count means non-ASCII, which is
                            -- how a glyph like the infinity sign shows up in a console that cannot
                            -- render it.
                            local bytes = ""
                            if #txt <= 12 then
                                for c = 1, #txt do bytes = bytes .. string.format("%02X ", txt:byte(c)) end
                            end
                            -- Owner matters as much as the text: several widgets share a name
                            -- (BulletCountText appears on the corner HUD and on every weapon-wheel
                            -- entry), and only the outer chain tells them apart.
                            print(string.format("[ACF]  %-22s %-24s '%s'  %s",
                                  b:GetClass():GetFName():ToString(),
                                  b:GetFName():ToString(), txt, bytes))
                            print("[ACF]      owner: " .. b:GetFullName())
                        end
                    end
                end
            end
        end
        print(string.format("[ACF] %d widget(s) showing text", shown))
        return true
    end

    local lowerNeedle = needle:lower()
    print("[ACF] looking for widgets whose text contains: '" .. needle .. "'")

    local hits, scanned = 0, 0
    for _, className in ipairs({ "CobraRichTextBlock", "CobraTextBlock", "RichTextBlock", "TextBlock" }) do
        local blocks = FindAllOf(className)
        if blocks ~= nil then
            for i = 1, #blocks do
                local b = blocks[i]
                if b ~= nil and b:IsValid() then
                    scanned = scanned + 1
                    local ok, txt = pcall(function() return ACF_Text(b:GetText()) end)
                    if ok and txt ~= nil and txt:lower():find(lowerNeedle, 1, true) ~= nil then
                        hits = hits + 1
                        local styleNote = ""
                        local okSet, styleSet = pcall(function() return b.TextStyleSet end)
                        if okSet and styleSet ~= nil and styleSet:IsValid() then
                            styleNote = "  styleSet=" .. styleSet:GetFullName()
                        elseif className:find("Rich", 1, true) ~= nil then
                            styleNote = "  styleSet=NONE  <- rich block, but nothing to resolve tags against"
                        end
                        print("[ACF] --------------------------------------------------")
                        print("[ACF]   class : " .. b:GetClass():GetFName():ToString())
                        print("[ACF]   object: " .. b:GetFullName())
                        print("[ACF]   text  : " .. txt)
                        if styleNote ~= "" then print("[ACF]  " .. styleNote) end
                    end
                end
            end
        end
    end
    print(string.format("[ACF] %d match(es) across %d live text widget(s)", hits, scanned))
    if hits == 0 then
        print("[ACF] Nothing matched - make sure the text is ON SCREEN when you run this.")
    end
    return true
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
    -- Detect by BEHAVIOR, not by asking the class.
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
        -- Behavioral check: camo 0 (GM_CAMOUF_NORMAL) is owned, so the real map answers.
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

-- Unlock camos and REPORT what stuck. Reached through uacwrite; the older 'unlockcamo' command
-- that also used this was retired - see docs/retired_commands.lua.
--
-- The old version just fired the game's own "UnlockAllCamouflage" console command, which
-- does nothing. This writes every save-side mechanism we know of and then reads each one
-- back, so we can tell "the write failed" apart from "the write worked but the game does
-- not read this field".
--
-- Step 1 inspects entries the game itself wrote, for camos you have ALREADY unlocked. That
-- tells us the real value shape before we write anything - guessing `true` is how earlier
-- attempts may have silently written the wrong type.
-- Shared implementation behind uacwrite (and formerly unlockcamo, since retired).
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
        print("[ACF] Add the word 'write' to actually apply unlocks: uacwrite")
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
        print("[ACF] To apply: load a save, then run   uacwrite")
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
    -- using. We edit that other instance, then SaveGameToSlot serializes OUR object over the
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
-- ---------------------------------------------------------------------------------------------
-- Per-slot metadata supplied by the mod author
-- ---------------------------------------------------------------------------------------------
--
-- A mod ships a plain text file next to its pak:
--
--     Content/Paks/mods/MyCamo_P.pak        <- the camo
--     Content/Paks/mods/ACF_Slot61.txt      <- its metadata
--
--     Name=Ocelot's Uniform
--     Description=Worn by the young Ocelot.
--     Camo=-25
--
-- Key=Value rather than XML or JSON deliberately: Lua has no parser for either, so both would
-- mean hand-rolling one and handing authors new ways to fail silently. Description and Camo are
-- read but not yet used (see P2/P3) - declaring them now means an author writes the file once.
--
-- The filename carries the slot number, so there is no directory scanning: four fixed paths,
-- tried in turn. Relative, because Lua and the C++ side share the process working directory
-- (Binaries/Win64) - the same reasoning as the svunlock bridge file.
local ACF_SLOT_IDS  = { 61, 62, 63, 64, 65 }   -- 65 only lists with slotpatch applied
local ACF_slotMeta  = {}      -- [id] = { Name=..., Description=..., Camo=... }
local ACF_metaText  = nil     -- raw file contents last parsed; nil until the first successful read
local ACF_namesApplied = {}   -- [id] = true once written to the CURRENT state object
local ACF_lastStateAddr = nil -- which CCamouflageMenuState those writes went to

-- Reads the resolved list the C++ side writes at startup, NOT the author's files directly.
--
-- The first version opened Content/Paks/mods/ACF_Slot<ID>.txt at one fixed path. That breaks the
-- moment an author tidies their download into a subfolder - silently, falling back to the default
-- name with no error. The C++ side now searches all of Content/Paks recursively and publishes what
-- it found, so the lookup exists once rather than once per language.
--
-- Format, one field per line:   61|Name|Ocelot's Uniform
--
-- Re-read on every call, reparsing only when the bytes change. It must NOT latch after one read:
-- C++ regenerates this file once it has the DataTable, roughly 15 seconds into a session, while
-- Lua's first tick fires well before that. A one-shot read therefore picked up the PREVIOUS
-- session's file and kept it for the whole run - the names were a session behind the author's
-- edits, which looked exactly like ACF ignoring the .txt files.
local function ACF_LoadSlotMeta()
    local f = io.open("ACF Logs\\acf_slots_resolved.txt", "r")
    if f == nil then return ACF_slotMeta end
    local text = f:read("*a")
    f:close()
    if text == nil or text == ACF_metaText then return ACF_slotMeta end

    ACF_metaText = text
    ACF_slotMeta = {}
    for line in text:gmatch("[^\r\n]+") do
        if not line:match("^%s*[;#]") then
            local id, key, val = line:match("^(%d+)|([%w_]+)|(.*)$")
            if id ~= nil then
                id = tonumber(id)
                val = val:gsub("%s+$", "")
                if val ~= "" then
                    ACF_slotMeta[id] = ACF_slotMeta[id] or {}
                    ACF_slotMeta[id][key] = val
                end
            end
        end
    end

    -- New content means anything already written to the live menu is out of date.
    ACF_namesApplied = {}
    for _, id in ipairs(ACF_SLOT_IDS) do
        local m = ACF_slotMeta[id]
        if m ~= nil and m.Name ~= nil then
            print(string.format("[ACF] slot %d metadata: Name=%s", id, m.Name))
        end
    end
    return ACF_slotMeta
end

-- Apply author-supplied names to the live key map.
--
-- Proven mechanism: writing Mgs3UniformCobraUiKeyMap changes the row (this is what svkeymap set
-- demonstrated). The value is the アイテム名定義 namespace followed DIRECTLY by the text - the game
-- fails to resolve it as a loc key and prints the remainder verbatim, which is how ACF gets
-- arbitrary text into a menu that otherwise only shows localised strings.
--
-- Slots with no metadata file are left alone, so they keep the "ACF Mod N" default that
-- ACF_Names_P bakes into the DataTable.
local ACF_NS = "\227\130\162\227\130\164\227\131\134\227\131\160\229\144\141\229\174\154"  -- アイテム名定義

-- Which key in Mgs3UniformCobraUiKeyMap belongs to a slot.
--
-- 61-64 are ADDITIONAL2..5, i.e. id - 59. Slot 65 is NOT ADDITIONAL6 - svkeys read the table and
-- the sequence stops at 5.
--
-- What svkeys did show is that the 31 entries are uniform NAMES and the map turns a name into a
-- CobraUI key: the row names in the DataTable are placeholders (NewRow, NewRow_0 ..), and the key
-- is a column inside each row. That reframes what "UNLOCKED" on slot 65's row is. For 61-64 the
-- lookup succeeds and returns an unresolvable loc key, which the game prints with the namespace
-- stripped. For 65 the lookup finds nothing and the game prints the uniform's own name - and the
-- uniform's own name is UNLOCKED.
--
-- If that reading is right, the entry simply does not exist yet and adding it under UNLOCKED is
-- the whole fix, with no DataTable rebuild. If it is wrong, this write lands in the map and the
-- row does not change, which is a cheap and clearly readable failure.
local ACF_SLOT_KEY_OVERRIDE = { [65] = "UNLOCKED" }

local function ACF_CobraKeyFor(id)
    return ACF_SLOT_KEY_OVERRIDE[id] or ("ADDITIONAL" .. (id - 59))
end

local function ACF_ApplySlotNames()
    local meta = ACF_LoadSlotMeta()
    if next(meta) == nil then return end

    local state = FindFirstOf("CCamouflageMenuState")
    if state == nil or not state:IsValid() then return end

    -- The state object is destroyed and rebuilt when the viewer is reopened, so a per-session
    -- latch would write the names into an object the menu no longer reads. Track WHICH object
    -- was written to and start over whenever it is a different one. Same lesson as the FixNames
    -- crash: nothing on this menu survives a close.
    local addr = nil
    pcall(function() addr = state:GetAddress() end)
    if addr ~= ACF_lastStateAddr then
        ACF_lastStateAddr = addr
        ACF_namesApplied = {}
    end

    local ok, map = pcall(function() return state.Mgs3UniformCobraUiKeyMap end)
    if not ok or map == nil then return end

    for _, id in ipairs(ACF_SLOT_IDS) do
        local m = meta[id]
        if m ~= nil and m.Name ~= nil and m.Name ~= "" and not ACF_namesApplied[id] then
            local key = ACF_CobraKeyFor(id)
            local okA = pcall(function() map:Add(key, ACF_NS .. m.Name) end)
            if okA then
                ACF_namesApplied[id] = true
                print(string.format("[ACF] slot %d named '%s'", id, m.Name))
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Automatic Collection Viewer unlock for ACF's slots (61-64)
-- ---------------------------------------------------------------------------------------------
--
-- The equip menu (Survival Viewer) is handled in C++ and is already automatic. The Camouflage
-- Collection under Main Menu > Extras is a SEPARATE system and was not - it needed uacwrite by
-- hand, and did not survive a reboot because nothing re-applied it.
--
-- This is the uacwrite recipe, narrowed to ACF's four slots and run on a timer:
--   * UnlockCamouflageMap is TMap<ECamouflageType, EGsrExtraAcquiredStatus> - an ENUM, not a bool.
--     Passing `true` is meaningless and is why early attempts silently did nothing.
--   * Write to EVERY live UserProfileSaveGame. FindFirstOf returns an arbitrary instance, and the
--     menu and in-game contexts use different ones - that is why this once looked like it only
--     worked from the main menu.
--   * Grow CamouflageList one element at a time; bulk TArray ops are unsafe on this build.
--
-- Runs in the GAME thread (reflection is not safe off it) and only logs when it changes something.
local ACF_AUTO_SLOTS = { 61, 62, 63, 64 }
local ACF_acquiredValue = nil

local function ACF_ResolveAcquired()
    if ACF_acquiredValue ~= nil then return ACF_acquiredValue end
    local e = StaticFindObject("/Script/Gsr.EGsrExtraAcquiredStatus")
    if e == nil or not e:IsValid() then e = StaticFindObject("/Script/MGS3.EGsrExtraAcquiredStatus") end
    if e ~= nil and e:IsValid() then
        for v = 0, 8 do
            local ok, nm = pcall(function() return e:GetNameByValue(v):ToString() end)
            if ok and nm ~= nil and nm:find("NewAcquired") then ACF_acquiredValue = v break end
        end
    end
    if ACF_acquiredValue == nil then ACF_acquiredValue = 2 end   -- Unaquired|Acquired|NewAcquired
    return ACF_acquiredValue
end

local ACF_autoReported = false

local function ACF_AutoCollectionUnlock()
    local saves = FindAllOf("UserProfileSaveGame")
    if saves == nil then return end
    local acquired = ACF_ResolveAcquired()
    local changed, seen = 0, 0

    for _, s in ipairs(saves) do
        if s ~= nil and s:IsValid() then
            seen = seen + 1
            local ok, map = pcall(function() return s.UnlockCamouflageMap end)
            if ok and map ~= nil then
                for _, id in ipairs(ACF_AUTO_SLOTS) do
                    local have = nil
                    local ok2, v = pcall(function() return map:Find(id) end)
                    if ok2 and v ~= nil then
                        local ok3, uv = pcall(function() return v:get() end)
                        if ok3 then have = uv end
                    end
                    -- Write unless it is ALREADY the acquired value.
                    --
                    -- The first version only wrote when the entry was missing. It never wrote
                    -- anything: the map ships pre-populated with ~67 entries that are mostly
                    -- Unaquired, so every slot "existed" and was skipped - and because nothing
                    -- changed, it logged nothing either, which looked like the timer was dead.
                    if have ~= acquired then
                        local ok4 = pcall(function() map:Add(id, acquired) end)
                        if ok4 then changed = changed + 1 end
                    end
                end
            end
            -- CamouflageList must be long enough for the slot index to exist at all.
            local okL, cl = pcall(function() return s.CamouflageList end)
            if okL and cl ~= nil then
                local guard = 0
                while #cl < 65 and guard < 80 do
                    local okA = pcall(function() cl[#cl + 1] = true end)
                    if not okA then break end
                    guard = guard + 1
                    changed = changed + 1
                end
            end
        end
    end

    -- Report the first pass unconditionally. "changed 0" and "the timer never ran" produced
    -- identical silence last time, which made a simple logic bug look like a dead timer.
    if not ACF_autoReported and seen > 0 then
        ACF_autoReported = true
        print(string.format("[ACF] Collection Viewer auto: %d profile(s), acquired=%d, %d written.",
              seen, acquired, changed))
    elseif changed > 0 then
        print("[ACF] Collection Viewer: applied " .. changed .. " entries for slots 61-64.")
    end
end

LoopInGameThreadWithDelay(5000, function()
    pcall(ACF_AutoCollectionUnlock)
    pcall(ACF_ApplySlotNames)
end)

-- acfslots - show what metadata ACF found, and re-apply it.
--
-- Prints every slot whether or not a file was found, so "no metadata" and "never looked" cannot
-- look the same - a failure mode that cost real time earlier in this project.
RegisterConsoleCommandHandler("acfslots", function(FullCommand, Parameters, Ar)
    ACF_metaText = nil                -- force a reparse so edits are picked up without a restart
    ACF_namesApplied = {}
    local meta = ACF_LoadSlotMeta()
    print("[ACF] --- slot metadata ---")
    for _, id in ipairs(ACF_SLOT_IDS) do
        local m = meta[id]
        if m == nil then
            print(string.format("[ACF]   slot %d (ACF Mod %d): no ACF_Slot%d.txt - using default name",
                  id, id - 60, id))
        else
            print(string.format("[ACF]   slot %d (ACF Mod %d): Name='%s'  Description='%s'  BaseCamo='%s'",
                  id, id - 60, tostring(m.Name), tostring(m.Description), tostring(m.BaseCamo)))
        end
    end

    -- Per-terrain values, published by the C++ side after it parses them. Reported here because a
    -- line with a typo parses as "absent", which otherwise looks identical to leaving that surface
    -- alone - the author would have no way to tell.
    local counts, errors = {}, {}
    local tf = io.open("ACF Logs\\acf_terrain_resolved.txt", "r")
    if tf ~= nil then
        for line in tf:lines() do
            local id, kind, rest = line:match("^(%d+)|([%w_]+)|(.*)$")
            if id ~= nil then
                id = tonumber(id)
                if kind == "count" then
                    counts[id] = tonumber(rest) or 0
                elseif kind == "error" then
                    errors[id] = errors[id] or {}
                    errors[id][#errors[id] + 1] = rest
                end
            end
        end
        tf:close()

        print("[ACF] --- per-terrain values ---")
        for _, id in ipairs(ACF_SLOT_IDS) do
            local n = counts[id] or 0
            if n > 0 then
                print(string.format("[ACF]   slot %d: %d surface(s) set", id, n))
            else
                print(string.format("[ACF]   slot %d: none - uses BaseCamo everywhere", id))
            end
            for _, e in ipairs(errors[id] or {}) do
                print(string.format("[ACF]     COULD NOT READ  %s", e))
            end
        end
    end

    ACF_ApplySlotNames()
    print("[ACF] Reopen the Survival Viewer to see any changes.")
    return true
end)

-- svrec - dump the whole 0x50-byte record for given camo ids from the real ownership store.
--
-- Only offset 0 of each record is mapped ("owned"). The new-item dot beside ACF rows is very
-- likely another field in the same record. Setting it there would be authoritative and persist,
-- unlike UniformCheckFlagMap, which is derived - the game rebuilt it 71 -> 14 on save, so writing
-- that would have to be re-applied forever.
--
--   svrec          compare camo 0 (long owned) against 61 (fresh ACF slot)
--   svrec 0 61 62  specific ids
RegisterConsoleCommandHandler("svrec", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil then
        for _, v in ipairs(Parameters) do arg = arg .. " " .. tostring(v) end
    end
    if ACF_SvRequest("rec" .. arg) then
        print("[ACF] svrec: dumping records - see UE4SS.log.")
    end
    return true
end)

-- camotable - dump the game's own per-camo table.
--
-- From FUN_147A9D010: entry = &DAT_1545218E0 + uniformId * 3 (0x18 bytes each), entry[1] points at
-- per-background bytes, and the byte at entry+0x16 is a flat bonus added whatever the environment
-- is. That flat byte is what an author's Camo= value should be.
--
-- Verify before writing: id 0 should read 10 (Olive Drab), 1 -> 30, 11 -> 0 (Naked), 60 -> 20
-- (Crocodile). Gold is NOT here - id 59 is special-cased to -1000 in code.
-- ufaddr <ObjectPath> - where a UFunction's native code lives, as a Ghidra address.
--
-- A UE4SS hook on a UFunction only fires for Blueprint and Lua callers, never the game's own
-- native calls, so reflection cannot INTERCEPT native work. It can still LOCATE it, which turns
-- "find this function in Ghidra" into a lookup by name.
--
--   ufaddr /Script/Gsr.GsrEquipController:ReduceStockedAmmoCount
RegisterConsoleCommandHandler("ufaddr", function(FullCommand, Parameters, Ar)
    local path = ""
    if Parameters ~= nil and #Parameters > 0 then path = table.concat(Parameters, " ") end
    if path == "" then
        print("[ACF] Usage: ufaddr /Script/Pkg.Class:FunctionName")
        print("[ACF]   e.g. ufaddr /Script/Gsr.GsrEquipController:ReduceStockedAmmoCount")
        return true
    end
    if ACF_SvRequest("ufaddr " .. path) then
        print("[ACF] ufaddr: see UE4SS.log")
    end
    return true
end)

-- ammowatch - does infinite ammo suppress the consume, or undo it?
--
-- Those two look identical in the HUD but are different mechanisms, and which one it is decides
-- whether ACF would have to intercept a call or could just write a value. Logs the equipped
-- weapon's stock and loaded counts with the change each time either moves.
--
-- Test: throw one WITHOUT Grenade Camo, then equip it and throw again.
--   stock never changes            -> the consume is skipped
--   stock drops then comes back    -> it is refilled after the fact
RegisterConsoleCommandHandler("ammowatch", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("ammowatch") then
        print("[ACF] ammowatch: watching. Throw a grenade, then swap camo and throw again.")
    end
    return true
end)

-- supdump - check the suppressor durability addresses.
--
-- Read-only, and it verifies itself. The addresses came from RMLSNK's Cheat Engine table for
-- patch 1.1.2, converted with this project's text/data deltas, so supdump first confirms the two
-- AOB signatures really sit at the computed code addresses. If those say MATCH, the data
-- addresses are trustworthy; if not, the arithmetic or the game build is wrong and nothing below
-- them means anything.
--
-- Equip a weapon with a suppressor first, then compare the printed numbers with the suppressor
-- count shown in game.
RegisterConsoleCommandHandler("supdump", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("supdump") then
        print("[ACF] supdump: see UE4SS.log - compare the numbers with the in-game suppressor count.")
    end
    return true
end)

-- camoref [id] - every instruction that reads the worn-uniform byte.
--
-- Three abilities are known to hang off a hardcoded comparison on that byte: Grenade Camo
-- (32) for infinite ammo, camo 25 for unlimited suppressor durability, and camo 56 for
-- silent footsteps. This finds the sites so the comparison beside them can be read.
--
-- The byte lives at PTR_DAT_14c532038 + 0x7AE, and 0x7AE can only be encoded as a disp32,
-- so AE 07 00 00 appears literally in every instruction that touches it.
--
-- Read-only. Defaults to id 56; pass another to hunt it instead (camoref 32).
RegisterConsoleCommandHandler("camoref", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil and #Parameters > 0 then arg = " " .. table.concat(Parameters, " ") end
    if ACF_SvRequest("camoref" .. arg) then
        print("[ACF] camoref: see UE4SS.log")
    end
    return true
end)

-- wepdump [weaponId] - print a weapon's whole 0x58-byte inventory entry.
--
-- Only two fields are mapped: +0x00 stock and +0x04 loaded. Everything else is unnamed, and the
-- suppressor durability is expected to be in there. Each dword is printed as raw bytes, int32,
-- two int16s and a float, so a value like 100 or 1.0 stands out.
--
-- Defaults to the equipped weapon. Safe and instant - it only reads.
RegisterConsoleCommandHandler("wepdump", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil and #Parameters > 0 then arg = " " .. table.concat(Parameters, " ") end
    if ACF_SvRequest("wepdump" .. arg) then
        print("[ACF] wepdump: dumped to UE4SS.log.")
    end
    return true
end)

-- wepwatch [weaponId|off] - report every byte of a weapon entry that changes.
--
-- This is how the suppressor durability field gets named. Unlike ammotrap it does NOT guard a
-- page or single-step, so it costs nothing and cannot destabilise the game - it just samples the
-- entry each tick and prints what moved.
--
-- The test:
--   1. wepwatch          (equip a suppressed weapon first)
--   2. fire a few shots, note which offset counts down
--   3. equip the camo that gives unlimited suppressor durability
--   4. fire again - the offset that STOPS moving is the field
--
-- The worn camo and facepaint ids are printed on every line, so step 3 records itself.
RegisterConsoleCommandHandler("wepwatch", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil and #Parameters > 0 then arg = " " .. table.concat(Parameters, " ") end
    if ACF_SvRequest("wepwatch" .. arg) then
        print("[ACF] wepwatch: armed. Fire a suppressed weapon, then check UE4SS.log.")
    end
    return true
end)

-- ammotrap [weaponId] - who writes a weapon's ammo, and who called them.
--
-- SLOW while armed - it guards a page and single-steps every write to it. Arm it, do the one
-- thing you want to catch, and it disarms itself once the budget is spent.
--
-- Defaults to the equipped weapon. Throw ONE grenade WITHOUT Grenade Camo; the caller chain is
-- printed as Ghidra addresses.
RegisterConsoleCommandHandler("ammotrap", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil and #Parameters > 0 then arg = " " .. table.concat(Parameters, " ") end
    if ACF_SvRequest("ammotrap" .. arg) then
        print("[ACF] ammotrap: arming - throw ONE grenade, then check UE4SS.log.")
    end
    return true
end)

-- ammohook - is ReduceStockedAmmoCount even CALLED when infinite ammo is active?
--
-- ammotrap showed no write to the ammo bytes with Grenade Camo on, but a write-watch cannot tell
-- "the function ran and took a different branch" from "the function was never called" - and those
-- need different fixes. This settles it.
--
-- A UE4SS hook on a UFunction only fires for Blueprint and Lua callers. That normally makes it
-- useless for native work (see the caption-getter test), but ammotrap's stack showed the exec thunk
-- 0x145a586f7 with engine frames either side, so this one IS invoked from Blueprint - which makes
-- the hook fire for the real thing.
--
--   fires with Grenade Camo    -> called, but decides internally not to decrement
--   silent with Grenade Camo   -> never called; the decision is in the Blueprint that calls it
local ACF_ammoHooked = false
RegisterConsoleCommandHandler("ammohook", function(FullCommand, Parameters, Ar)
    if ACF_ammoHooked then
        print("[ACF] ammohook: already active - throw a grenade and watch the log.")
        return true
    end
    local ok, err = pcall(function()
        RegisterHook("/Script/Gsr.GsrEquipController:ReduceStockedAmmoCount",
            function(self, EquipId)
                local id = "?"
                local okp, v = pcall(function() return EquipId:get() end)
                if okp then id = tostring(v) end

                -- Every NPC owns one of these, so without the owner a guard reloading looks
                -- exactly like Snake throwing - which is how the first run's fires were read.
                local who = "?"
                local oko, o = pcall(function() return self:get():GetFullName() end)
                if oko then who = tostring(o) end
                local mine = (who:find("BP_Player", 1, true) ~= nil
                           or who:find("PlayerPawn", 1, true) ~= nil)

                print(string.format("[ACF][ammohook] %s EquipId=%s  on %s",
                      mine and ">>> PLAYER" or "(npc)", id, who))
            end)
    end)
    if not ok then
        print("[ACF] ammohook: RegisterHook failed - " .. tostring(err))
        return true
    end
    ACF_ammoHooked = true
    print("[ACF] ammohook: active. Throw one WITHOUT Grenade Camo, then one WITH it.")
    return true
end)

-- reduceammo <equipId> [loaded] - call the game's own ammo-consume directly.
--
-- Calls UGsrEquipController::ReduceStockedAmmoCount, or ReduceLoadedAmmoCount with "loaded".
-- EGsrEquipId shares numbering with EWeaponName, so WP_StunGrenade is 21, WP_Grenade 19,
-- WP_Rpg 17, WP_EasyGun 7.
--
-- Worth trying WITH Grenade Camo on: the game skips this call entirely under infinite ammo, so
-- calling it by hand asks whether the function itself would still refuse. If ammo drops anyway,
-- the protection is purely in the caller and nothing inside the function defends it.
--
-- Run ammowatch first if you want the before/after printed for you.
RegisterConsoleCommandHandler("reduceammo", function(FullCommand, Parameters, Ar)
    local id, wantLoaded = nil, false
    if Parameters ~= nil then
        for _, p in ipairs(Parameters) do
            local n = tonumber(p)
            if n ~= nil then id = n
            elseif tostring(p):lower():find("load", 1, true) then wantLoaded = true end
        end
    end
    if id == nil then
        print("[ACF] Usage: reduceammo <equipId> [loaded]")
        print("[ACF]   e.g. reduceammo 21          stun grenades, stocked")
        print("[ACF]        reduceammo 21 loaded   the loaded count instead")
        return true
    end

    -- FindFirstOf returns whichever instance the object array happens to hold first, and that was
    -- an ENEMY's controller (GsrEnemy_01.BP_GsrEquipController_C). Every NPC owns one, so the
    -- player's has to be picked out by its outer rather than taken on faith.
    local ctrl = nil
    local all = FindAllOf("GsrEquipController")
    if all ~= nil then
        for i = 1, #all do
            local c = all[i]
            if c ~= nil and c:IsValid() then
                local n = c:GetFullName()
                if n:find("BP_Player", 1, true) ~= nil or n:find("PlayerPawn", 1, true) ~= nil then
                    ctrl = c
                    break
                end
            end
        end
        if ctrl == nil then
            print(string.format("[ACF] Found %d GsrEquipController(s) but none owned by the player:", #all))
            for i = 1, #all do
                if all[i] ~= nil and all[i]:IsValid() then
                    print("[ACF]   " .. all[i]:GetFullName())
                end
            end
            return true
        end
    end
    if ctrl == nil or not ctrl:IsValid() then
        print("[ACF] No GsrEquipController live - load a save first.")
        return true
    end

    local which = wantLoaded and "ReduceLoadedAmmoCount" or "ReduceStockedAmmoCount"
    local ok, err = pcall(function()
        if wantLoaded then ctrl:ReduceLoadedAmmoCount(id) else ctrl:ReduceStockedAmmoCount(id) end
    end)
    if ok then
        print(string.format("[ACF] %s(%d) called on %s", which, id, ctrl:GetFullName()))
    else
        print(string.format("[ACF] %s(%d) failed: %s", which, id, tostring(err)))
    end
    return true
end)

-- plstatus [id] - ask the game which EPlayerStatus flags are set right now.
--
-- Built to test a NAME, not to trust one. PL_F_HAND_BLUR (45) sits beside the aim statuses so it
-- looks like the shaking-hands mechanic Animals camo removes, but "hand blur" could just as easily
-- be a render effect. Reading the live flag settles it instead of building on the guess.
--
--   plstatus         sweep every status and list the ones currently true
--   plstatus 45      watch one, printing only when it changes
--
-- Test for the aim shake: run  plstatus 45,  aim and hold still WITHOUT Animals camo, then equip
-- Animals camo and aim again. If 45 tracks the shake it is the right flag; if it never moves, or
-- moves when merely aiming, the name is misleading us.
local ACF_statusWatch = nil
local ACF_statusLast  = nil

local function ACF_SnakeStatus()
    local all = FindAllOf("BP_SnakeStatus_C")
    if all == nil then all = FindAllOf("SnakeStatusComponent") end
    if all == nil then return nil end
    for i = 1, #all do
        local c = all[i]
        if c ~= nil and c:IsValid() then
            local n = c:GetFullName()
            if n:find("BP_Player", 1, true) ~= nil or n:find("PlayerPawn", 1, true) ~= nil then
                return c
            end
        end
    end
    -- Fall back to the first, but say so - an NPC's status would answer a different question.
    for i = 1, #all do
        if all[i] ~= nil and all[i]:IsValid() then
            print("[ACF] plstatus: no player-owned status found, using " .. all[i]:GetFullName())
            return all[i]
        end
    end
    return nil
end

-- QueryPlayerStatus(Status, CheckPulse, bool& Result, bool& JustModified) has TWO out params, and
-- out params are exactly what defeated GetDataTableRowNames earlier: UE4SS may return them, or
-- write into tables passed in. Try both, and report rather than returning nil quietly - a call that
-- never works must not look like "the flag never changed".
local ACF_statusErr = nil

local function ACF_QueryStatus(comp, id)
    -- Form 1: out params come back as return values.
    local ok, a, b = pcall(function() return comp:QueryPlayerStatus(id, false) end)
    if ok then
        if type(a) == "boolean" then return a end
        if type(a) == "table"   then return a.Result or a[1] end
        if a ~= nil then ACF_statusErr = "unexpected return: " .. type(a) .. " " .. tostring(a) end
    else
        ACF_statusErr = "call failed: " .. tostring(a)
    end

    -- Form 2: UE4SS writes into tables handed in, as GetDataTableRowNames does.
    local outResult, outJust = {}, {}
    local ok2, err2 = pcall(function() comp:QueryPlayerStatus(id, false, outResult, outJust) end)
    if ok2 then
        if type(outResult.Result) == "boolean" then ACF_statusErr = nil; return outResult.Result end
        if type(outResult[1])     == "boolean" then ACF_statusErr = nil; return outResult[1] end
        ACF_statusErr = "4-arg form returned nothing usable"
    else
        ACF_statusErr = (ACF_statusErr or "") .. " | 4-arg failed: " .. tostring(err2)
    end
    return nil
end

RegisterConsoleCommandHandler("plstatus", function(FullCommand, Parameters, Ar)
    local id = nil
    if Parameters ~= nil and #Parameters > 0 then id = tonumber(Parameters[1]) end

    local comp = ACF_SnakeStatus()
    if comp == nil then
        print("[ACF] plstatus: no SnakeStatus component live - load a save first.")
        return true
    end

    -- Watching one flag at a time cannot answer "does 45 differ from 44", because the two are
    -- observed during different aims. Accept a list so one aim exercises all of them.
    local ids = {}
    if Parameters ~= nil then
        for _, p in ipairs(Parameters) do
            local n = tonumber(p)
            if n ~= nil then ids[#ids + 1] = n end
        end
    end
    if #ids > 1 then
        ACF_statusWatch = table.concat(ids, ",")
        local token = ACF_statusWatch
        local last = {}
        ACF_statusErr = nil
        local line = ""
        for _, s in ipairs(ids) do
            local v = ACF_QueryStatus(comp, s)
            last[s] = v
            line = line .. string.format("%d=%s  ", s, tostring(v))
        end
        print("[ACF] plstatus: watching " .. token .. " -> " .. line)
        if ACF_statusErr ~= nil then
            print("[ACF] plstatus: query problem - " .. tostring(ACF_statusErr))
            return true
        end
        LoopAsync(50, function()
            if ACF_statusWatch ~= token then return true end
            local c = ACF_SnakeStatus()
            if c == nil then return false end
            for _, s in ipairs(ids) do
                local v = ACF_QueryStatus(c, s)
                if v ~= last[s] then
                    last[s] = v
                    print(string.format("[ACF][plstatus] %d -> %s", s, tostring(v)))
                end
            end
            return false
        end)
        return true
    end

    if id ~= nil then
        ACF_statusWatch = id
        ACF_statusLast  = nil
        -- Read once up front. Without this a query that never works is indistinguishable from a
        -- flag that never changes, because the first comparison is nil against nil.
        ACF_statusErr = nil
        local first = ACF_QueryStatus(comp, id)
        print(string.format("[ACF] plstatus: watching status %d, currently %s", id, tostring(first)))
        if first == nil then
            print("[ACF] plstatus: the query is NOT answering, so silence below means nothing.")
            print("[ACF]   " .. tostring(ACF_statusErr))
            print("[ACF]   component: " .. comp:GetFullName())
            return true
        end
        ACF_statusLast = first

        -- Polled rather than hooked: the flag is queried, not broadcast, so there is nothing to
        -- hook. 100ms is fast enough to see aiming start and stop without flooding the log, and
        -- only changes are printed.
        LoopAsync(100, function()
            if ACF_statusWatch ~= id then return true end   -- superseded by a later plstatus
            local c = ACF_SnakeStatus()
            if c == nil then return false end
            local v = ACF_QueryStatus(c, id)
            if v ~= ACF_statusLast then
                ACF_statusLast = v
                print(string.format("[ACF][plstatus] %d -> %s", id, tostring(v)))
            end
            return false
        end)
        return true
    end

    print("[ACF] --- EPlayerStatus flags currently true ---")
    ACF_statusErr = nil
    local shown, answered = 0, 0
    for s = 0, 120 do
        local v = ACF_QueryStatus(comp, s)
        if v ~= nil then answered = answered + 1 end
        if v == true then
            shown = shown + 1
            print(string.format("[ACF]   %d", s))
        end
    end
    -- "nothing is true" and "nothing answered" look the same in a list of zero lines, so separate
    -- them explicitly rather than letting a broken query read as a result.
    if answered == 0 then
        print("[ACF] the query answered for NOTHING - this is a broken call, not an empty result.")
        print("[ACF]   " .. tostring(ACF_statusErr))
        print("[ACF]   component: " .. comp:GetFullName())
    elseif shown == 0 then
        print(string.format("[ACF] none true (%d statuses answered, so the query works)", answered))
    else
        print(string.format("[ACF] %d true of %d answered", shown, answered))
    end
    return true
end)

-- speedwatch - measure top running speed, to compare camos.
--
-- Gold is said to grant a slight movement bonus. Finding that in code means hunting reads of
-- LegacyStandParallelMoveSpeedMax at +0x2E4, an offset far too common to search cleanly - but the
-- effect is observable, so measure it instead. Run a straight line in one camo, then another, and
-- compare the peaks.
--
-- Reports the highest horizontal speed seen in each window rather than the instantaneous value,
-- because acceleration means most samples are below top speed and an average would hide the
-- difference we are looking for.
local ACF_speedOn = false
RegisterConsoleCommandHandler("speedwatch", function(FullCommand, Parameters, Ar)
    if ACF_speedOn then
        ACF_speedOn = false
        print("[ACF] speedwatch: off")
        return true
    end

    local pawn = FindFirstOf("BP_Player_C")
    if pawn == nil or not pawn:IsValid() then
        print("[ACF] speedwatch: player pawn not found - load a save first.")
        return true
    end

    ACF_speedOn = true
    print("[ACF] speedwatch: on. Run in a straight line for a few seconds, then swap camo and")
    print("[ACF]   repeat. Compare the peak numbers, not single samples.")

    local peak, ticks = 0.0, 0
    LoopAsync(50, function()
        if not ACF_speedOn then return true end
        local p = FindFirstOf("BP_Player_C")
        if p == nil or not p:IsValid() then return false end

        local ok, sp = pcall(function()
            local v = p:GetVelocity()
            return math.sqrt((v.X * v.X) + (v.Y * v.Y))   -- horizontal only; falling is not running
        end)
        if not ok then
            print("[ACF] speedwatch: could not read velocity - " .. tostring(sp))
            ACF_speedOn = false
            return true
        end

        if sp > peak then peak = sp end
        ticks = ticks + 1
        if ticks >= 40 then      -- ~2 seconds
            ticks = 0
            if peak > 1.0 then
                print(string.format("[ACF][speed] peak %.1f", peak))
            end
            peak = 0.0
        end
        return false
    end)
    return true
end)

-- getf / setf <Class> <Field> [value] - read or write a reflected float on a live object.
--
-- Written because "this field's name says movement speed" is not evidence that writing it does
-- anything. Poking it and watching with speedwatch settles in seconds what reading headers cannot:
-- some of these are tuning constants read once at init, and writing those achieves nothing.
--
--   getf GsrPlayerBasicAction LegacyStandParallelMoveSpeedMax
--   setf GsrPlayerBasicAction LegacyStandParallelMoveSpeedMax 448.5
--   setf GsrPlayerSubjectiveCamera amplitudeAmplifierStand 0
--
-- Skips Default__ objects - a class-default has already produced one wrong answer in this project.
local function ACF_FindLive(className)
    local all = FindAllOf(className)
    if all == nil then return nil, 0 end
    local n = 0
    local first = nil
    for i = 1, #all do
        local o = all[i]
        if o ~= nil and o:IsValid() and o:GetFullName():find("Default__", 1, true) == nil then
            n = n + 1
            if first == nil then first = o end
        end
    end
    return first, n
end

local function ACF_FloatCmd(Parameters, doWrite)
    local cls, field, val = nil, nil, nil
    if Parameters ~= nil then
        for _, p in ipairs(Parameters) do
            local n = tonumber(p)
            if n ~= nil and cls ~= nil and field ~= nil then val = n
            elseif cls == nil then cls = tostring(p)
            elseif field == nil then field = tostring(p) end
        end
    end
    if cls == nil or field == nil or (doWrite and val == nil) then
        print("[ACF] Usage: " .. (doWrite and "setf <Class> <Field> <value>" or "getf <Class> <Field>"))
        print("[ACF]   e.g. setf GsrPlayerBasicAction LegacyStandParallelMoveSpeedMax 448.5")
        return true
    end

    local obj, count = ACF_FindLive(cls)
    if obj == nil then
        print(string.format("[ACF] no live '%s' found (Default__ objects are skipped)", cls))
        return true
    end
    if count > 1 then
        print(string.format("[ACF] note: %d live '%s' - using %s", count, cls, obj:GetFullName()))
    end

    local ok, cur = pcall(function() return obj[field] end)
    if not ok or cur == nil then
        print(string.format("[ACF] '%s' has no readable field '%s'", cls, field))
        return true
    end

    if not doWrite then
        print(string.format("[ACF] %s.%s = %s", cls, field, tostring(cur)))
        return true
    end

    local okw = pcall(function() obj[field] = val end)
    local after = nil
    pcall(function() after = obj[field] end)
    -- Report what it reads back as, not what we asked for: a field the engine recomputes will
    -- revert, and that is exactly the case worth knowing about.
    print(string.format("[ACF] %s.%s  %s -> %s  (wrote %s%s)",
          cls, field, tostring(cur), tostring(after), tostring(val),
          okw and "" or ", WRITE FAILED"))
    return true
end

RegisterConsoleCommandHandler("getf", function(FullCommand, Parameters, Ar)
    return ACF_FloatCmd(Parameters, false)
end)
RegisterConsoleCommandHandler("setf", function(FullCommand, Parameters, Ar)
    return ACF_FloatCmd(Parameters, true)
end)

-- slotpatch [max] / slotpatch off - EXPERIMENTAL: raise the Survival Viewer's camo ceiling.
--
-- Two things cap the list, both compiled into sv_uniform.c's list loop:
--   cmp ebx,0x41 / je   id 65 is explicitly skipped - which is why granting it never listed
--   cmp ebx,0x42 / jl   the loop covers ids 0..65 only
--
-- ExpandCamouflageMax did not help because it raises the ENUM, and this loop does not consult it.
--
-- Clamped to 70: the uniform value table holds exactly 70 entries and the address right after it
-- is a live global, so a higher bound would corrupt memory rather than add slots.
--
-- Verifies the bytes before writing and aborts if they differ, so a game update fails cleanly
-- instead of corrupting code. 'slotpatch off' puts the originals back.
--
-- SHIP AN ASSET for any id you intend to EQUIP - granting an id with no Camouf_<id>_asset was a
-- hard crash on selection when it was tried with 52/53.
RegisterConsoleCommandHandler("slotprobe", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("slotprobe") then
        print("[ACF] slotprobe: see UE4SS.log - which camo ids have a live resource entry.")
    end
    return true
end)

RegisterConsoleCommandHandler("slotpatch", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil and #Parameters > 0 then arg = " " .. table.concat(Parameters, " ") end
    if ACF_SvRequest("slotpatch" .. arg) then
        print("[ACF] slotpatch: see UE4SS.log, then svunlock the ids you want and open the viewer.")
    end
    return true
end)

-- svkeys - list every CobraUI key in DT_Mgs3UniformToCobraUIKey.
--
-- Slot names are applied by writing Mgs3UniformCobraUiKeyMap under the row's CobraUI key. For
-- 61-64 that key is ADDITIONAL2..5, derived as "ADDITIONAL" .. (id - 59). Slot 65 is the DOWNLOAD
-- slot, so that formula produces ADDITIONAL6, which is a guess and evidently wrong - its name
-- stays "UNLOCKED".
--
-- Rather than guess again, read the table: its row names ARE the keys.
RegisterConsoleCommandHandler("svkeys", function(FullCommand, Parameters, Ar)
    local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    if lib == nil or not lib:IsValid() then
        print("[ACF] DataTableFunctionLibrary CDO not found")
        return true
    end
    local dt = StaticFindObject("/CobraUI/Data/SV/DT_Mgs3UniformToCobraUIKey.DT_Mgs3UniformToCobraUIKey")
    if dt == nil or not dt:IsValid() then
        print("[ACF] DT_Mgs3UniformToCobraUIKey not loaded - open the Survival Viewer once first.")
        return true
    end

    -- Out params are written into the table handed in; the return value is nil. Learned the hard
    -- way when GetDataTableRowNames looked like it was returning empty tables.
    local names = {}
    local ok = pcall(function() lib:GetDataTableRowNames(dt, names) end)
    if not ok then
        print("[ACF] GetDataTableRowNames raised an error")
        return true
    end

    local shown = 0
    print("[ACF] --- CobraUI keys (row names) ---")
    ACF_EachArray(names, function(i, s)
        shown = shown + 1
        print(string.format("[ACF]   %3d  %s", i, s))
    end)
    if shown == 0 then
        print("[ACF] nothing came back - shape: " .. ACF_Shape(names))
    else
        print(string.format("[ACF] %d keys", shown))
    end
    return true
end)

-- trykey <key> - write a recognisable name into Mgs3UniformCobraUiKeyMap under any key.
--
-- Slot 65's key is not known. Rather than rebuild DT_Mgs3UniformToCobraUIKey once per guess, guess
-- at runtime: this writes "ACF TRYKEY" under whatever key you name, so a wrong guess costs one
-- console line instead of a pak build. Open the Survival Viewer, run it, and look at the row.
--
--   trykey UNLOCKED     the current best guess - the uniform's own name
--   trykey DOWNLOAD     GM_CAMOUF_DOWNLOAD is what the enum calls slot 65
--   trykey ADDITIONAL6  ruled out by svkeys, kept so the negative is reproducible
RegisterConsoleCommandHandler("trykey", function(FullCommand, Parameters, Ar)
    local key = Parameters and Parameters[1] and tostring(Parameters[1]) or nil
    if key == nil or key == "" then
        print("[ACF] trykey <key>   e.g. 'trykey UNLOCKED'. Open the Survival Viewer first.")
        return true
    end

    local state = FindFirstOf("CCamouflageMenuState")
    if state == nil or not state:IsValid() then
        print("[ACF] No live CCamouflageMenuState - open the Survival Viewer first.")
        return true
    end
    local ok, map = pcall(function() return state.Mgs3UniformCobraUiKeyMap end)
    if not ok or map == nil then
        print("[ACF] Could not read Mgs3UniformCobraUiKeyMap: " .. tostring(map))
        return true
    end

    -- Report whether the key already existed. "Nothing changed" means something different when
    -- the key was absent than when it was present and simply is not read.
    local had = "absent"
    local ok2, v = pcall(function() return map:Find(key) end)
    if ok2 and v ~= nil then had = "already present" end

    local okA = pcall(function() map:Add(key, ACF_NS .. "ACF TRYKEY") end)
    if not okA then
        print("[ACF] trykey: Add failed for '" .. key .. "'")
        return true
    end
    print(string.format("[ACF] trykey: wrote 'ACF TRYKEY' under '%s' (was %s).", key, had))
    print("[ACF] Close and reopen the Survival Viewer. If a row now reads ACF TRYKEY, that is the key.")
    return true
end)

-- svicons - list the numeric camouflage thumbnail textures the game has loaded.
--
-- A row's icon field is a numeric TEXTURE NAME, not an index: the badges live under
-- /CobraUI/textures/sv/camouflage/ as textures literally called "9279063", "3184223" and so on.
-- Slots 61-64 are pointed at four of these by hand. Slot 65 needs a fifth that nothing else uses,
-- and guessing at the number is how the 0x10000 sequence got mistaken for real art before.
--
-- So enumerate them instead. Anything listed here exists; cross-reference against the icon column
-- of svrows to see which are already spoken for.
--
-- Textures load on demand, so open the Survival Viewer and the Camouflage Collection once before
-- running this or the list will be short.
RegisterConsoleCommandHandler("svicons", function(FullCommand, Parameters, Ar)
    local seen, count = {}, 0
    print("[ACF] --- camouflage thumbnail textures currently loaded ---")
    local ok = pcall(function()
        ForEachUObject(function(obj)
            if obj == nil or not obj:IsValid() then return end
            local full = obj:GetFullName()
            if full == nil then return end
            if not full:find("sv/camouflage", 1, true) then return end
            -- The numeric name is the last path component.
            local name = full:match("([^%./]+)$")
            if name == nil or seen[name] then return end
            seen[name] = true
            count = count + 1
            print(string.format("[ACF]   %s", full))
        end)
    end)
    if not ok then
        print("[ACF] svicons: ForEachUObject is unavailable in this UE4SS build.")
        return true
    end
    if count == 0 then
        print("[ACF] nothing loaded - open the Survival Viewer and the Camouflage Collection, then retry.")
    else
        print(string.format("[ACF] %d object(s) under sv/camouflage", count))
    end
    return true
end)

-- camocol - which of the five per-terrain columns the game is reading right now.
--
-- The value block is 27 terrains x 5 columns, and the columns are picked by player state. This
-- logs the chosen index whenever it changes, so standing/crouching/prone/wall-press can be mapped
-- to real column numbers instead of inferred from the code.
RegisterConsoleCommandHandler("camocol", function(FullCommand, Parameters, Ar)
    if ACF_SvRequest("camocol") then
        print("[ACF] camocol: watching. Stand, crouch, go prone, then press against a wall.")
    end
    return true
end)

--   camotable         summary of every entry
--   camotable <ids>   the per-background row for those camos, e.g. "camotable 1" for Tiger Stripe
RegisterConsoleCommandHandler("camotable", function(FullCommand, Parameters, Ar)
    local arg = ""
    if Parameters ~= nil then
        for _, v in ipairs(Parameters) do arg = arg .. " " .. tostring(v) end
    end
    if ACF_SvRequest("camotable" .. arg) then
        print("[ACF] camotable: dumping - see UE4SS.log.")
    end
    return true
end)

-- dttables - list every loaded DataTable by name.
--
-- The concealment value is a 2D lookup, uniform x background: EGsrMgs3CamoufType has 27 entries
-- (water, moss, grass, soil, the room variants) and nothing in the SDK references it, so the table
-- is reached by native code. Before hunting it in Ghidra with no anchor, check the cheap
-- possibility that it also exists as a cooked DataTable under a name we have not looked for.
--
-- Uses UE4SS's own object enumeration, not a memory sweep.
--   dttables         only names containing camo/uniform/prop
--   dttables all     every DataTable
RegisterConsoleCommandHandler("dttables", function(FullCommand, Parameters, Ar)
    local showAll = (Parameters ~= nil and Parameters[1] ~= nil
                     and tostring(Parameters[1]):lower() == "all")

    -- FindAllOf returns a plain array, matching how every other command here uses it.
    local tables = FindAllOf("DataTable") or {}
    local found, shown = #tables, 0

    for i = 1, found do
        local o = tables[i]
        if o ~= nil and o:IsValid() then
            local okName, name = pcall(function() return o:GetFullName() end)
            if okName and type(name) == "string" then
                local low = string.lower(name)
                if showAll
                   or low:find("camo") or low:find("uniform") or low:find("prop") then
                    shown = shown + 1
                    print("[ACF][dt] " .. name)
                end
            end
        end
    end
    print(string.format("[ACF] %d DataTables loaded, %d shown.%s",
          found, shown, showAll and "" or "  Use 'dttables all' for the rest."))
    return true
end)

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
        -- Do not guess at the unwrap API. Report what each attempt actually does, including the
        -- error, so a failure is diagnosable instead of silently falling through to tostring()
        -- and printing a pointer - which is what the first two attempts did.
        local shown = "nil"
        if ok2 and v ~= nil then
            local attempts = {
                { "v:ToString()",         function() return v:ToString() end },
                { "v:get():ToString()",   function() return v:get():ToString() end },
                { "v:get()",              function() return v:get() end },
            }
            local parts = { "type=" .. type(v) }
            for _, a in ipairs(attempts) do
                local ok3, r = pcall(a[2])
                if ok3 and type(r) == "string" then
                    shown = r
                    parts[#parts+1] = a[1] .. "=OK"
                    break
                end
                parts[#parts+1] = a[1] .. (ok3 and ("=" .. type(r)) or ("=ERR " .. tostring(r):sub(1,40)))
            end
            if shown == "nil" then shown = "<unread> " .. table.concat(parts, " | ") end
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
    -- Forward every mode the C++ side understands. This used to whitelist only "off" and "rows",
    -- so "svwatch map" and "svwatch gauge" silently fell through to the plain legacy-state watch
    -- and produced legacy-state offsets - results that looked like real answers to a question
    -- that had never been asked.
    local known = { off = true, rows = true, map = true, gauge = true, read = true, base = true }
    local p = (Parameters ~= nil and Parameters[1] ~= nil) and tostring(Parameters[1]):lower() or ""
    local arg = known[p] and ("watch " .. p) or "watch"
    if p ~= "" and not known[p] then
        print("[ACF] svwatch: unknown mode '" .. p .. "' - using the legacy state watch.")
        print("[ACF] Modes: off | rows | map | gauge | read")
    end
    local f, err = io.open("ACF Logs\\ACF_svunlock.txt", "w")
    if f == nil then
        print("[ACF] Could not write request file: " .. tostring(err))
        return false
    end
    f:write(arg)
    f:close()
    if arg == "watch off" then
        print("[ACF] svwatch: disarming.")
    elseif arg == "watch gauge" then
        print("[ACF] svwatch: arming on the HUD gauge queue. Now MOVE so the percentage changes.")
    elseif arg == "watch map" then
        print("[ACF] svwatch: arming on the row map header. Now CLOSE and REOPEN the viewer.")
    elseif arg == "watch rows" then
        print("[ACF] svwatch: arming on the row buffer. Now CLOSE and REOPEN the viewer.")
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

-- Every registered command belongs here. The old table listed 14 mostly-exploratory commands and
-- omitted acfslots, svrows and camotable - the three worth asking a bug reporter to run - so
-- 'acfhelp' was least useful to the people most likely to type it.
local ACF_COMMANDS = {
    { "-- if something looks wrong, run these --" },
    { "acfslots",               "what ACF found in each ACF_Slot<ID>.txt, and re-apply it" },
    { "svrows",                 "what the Survival Viewer is drawing each row from (read-only)" },
    { "camotable",              "the game's per-camo value table, including ACF's entries" },

    { "-- camo / equip --" },
    { "camotest <camo>",        "forcecamo + asset-cache before/after diff; says if the game even asked" },
    { "camodesc",               "raw DescryptionText for every row, plus the rich-text tags allowed" },
    { "whichtext [text|all]",   "names the widget drawing a string; \"all\" lists every text widget" },
    { "ufaddr <ObjectPath>",    "Ghidra address of a UFunction's native code, looked up by name" },
    { "ammowatch",              "logs the equipped weapon's ammo as it changes, with deltas" },
    { "ammotrap [id]",          "SLOW: traps writes to a weapon's ammo and names the caller chain" },
    { "camoref [id]",           "every instruction reading the worn-uniform byte (finds hardcoded camo checks)" },
    { "supdump",               "verifies + reads the suppressor durability addresses (read-only)" },
    { "wepdump [id]",           "prints a weapon's whole 0x58-byte entry, four readings per dword" },
    { "wepwatch [id|off]",      "reports every byte of a weapon entry that changes - finds suppressor wear" },
    { "ammohook",               "logs whether ReduceStockedAmmoCount is called at all" },
    { "reduceammo <id> [loaded]","calls the game's own ammo-consume directly, to see if it refuses" },
    { "plstatus [ids]",         "which EPlayerStatus flags are set; with ids, watches them live" },
    { "speedwatch",             "peak running speed, for comparing camos - run, swap, compare" },
    { "getf <Class> <Field>",   "read a reflected float on a live object" },
    { "setf <Class> <Field> <v>","write one, and report what it reads back as" },
    { "camodiag <camo>",        "enum name, asset resident?, LoadDataAsset result, unlock state" },
    { "forcecamo <fp> <camo>",  "preview-only camo swap; REVERTS on pause/area change" },
    { "swapthumb <row> <tex>",  "patch a row's Thumbnail live, to test a texture before packing it" },

    { "-- unlocking (ACF does this automatically; these are for testing) --" },
    { "svunlock [ids]",         "own camos in the legacy store - what the Survival Viewer reads" },
    { "slotpatch [max]|off",    "EXPERIMENTAL: raise the SV camo ceiling past 64" },
    { "svlock [ids]",           "the reverse, for testing what an uninstall looks like" },
    { "uacwrite [max]",         "unlock every camo in the Collection Viewer (memory only)" },
    { "uacgame [write]",        "unlock camos in the Survival Viewer via UniformCheckFlagMap" },
    { "unlockall [max]",        "every unlock mechanism, every id 0..max (default 65)" },

    { "-- inspection --" },
    { "svrec <ids>",            "dump the 0x50-byte ownership record for given camo ids" },
    { "svkeymap [set]",         "read or patch the live row-name key map" },
    { "svkeys",                 "list every CobraUI key in DT_Mgs3UniformToCobraUIKey" },
    { "svicons",                "list the numeric thumbnail textures under sv/camouflage" },
    { "trykey <key>",           "test a CobraUI key for slot 65 without rebuilding a pak" },
    { "dttables [all]",         "list loaded DataTables (filtered to camo/uniform by default)" },
    { "dumpcamolist",           "dump the camo list the menu is working from" },
    { "assetmgr",               "inspect the AssetManager registry entry for a camo asset" },
    { "findallcamouflageassets","list loaded CamouflageAssetType assets (Camouf_<id>_asset)" },
    { "loadasset <name>",       "call DataAssetHelper:LoadDataAsset" },
    { "dumpusmap",              "generate Mappings.usmap so DataTables can be edited offline" },

    { "-- SLOW: page traps. These stutter the game badly. 'svwatch off' stops them --" },
    { "svwatch <mode>",         "trap writes: off | rows | map | gauge | base | (no arg = legacy state)" },
    { "svread",                 "trap READS of the camo ownership table" },
    { "svsnap",                 "snapshot the legacy state block" },
    { "svdiff",                 "diff it against the snapshot" },
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
