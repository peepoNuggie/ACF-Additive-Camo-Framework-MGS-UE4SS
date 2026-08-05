// ACF - Additive Camo Framework (MGS Delta / UE4SS)
//
// Registers additional camouflage entries with the game at runtime.
//
// WHAT THIS CURRENTLY ACHIEVES (confirmed by A/B test with the mod disabled):
//   A registered camo shows up as a new row in the COLLECTION VIEWER (the gallery under
//   Extras that displays camos on a posed model). Disabling this mod makes the row vanish.
//
// WHAT IT DOES NOT YET ACHIEVE:
//   The in-game TAB equip menu is a completely separate system. It does not read
//   DT_CamouflageCollection at all - it reads native FPropData TMaps living on a
//   CSVTabViewWidget instance (+0x748 button->propdata, +0x798 index->button), which are
//   populated by native C++ that UE4SS's reflection cannot see or hook. Getting entries in
//   there is an open problem - see the project notes.
//
// KNOWN UE4SS LIMITATIONS ON THIS BUILD (learned the hard way):
//   * TMap READS are broken. DataTable::FindRowUnchecked returns null even for row names we
//     know exist, so copying an existing row as a template does not work.
//   * TMap ITERATION is worse - range-for over GetRowMap() HARD CRASHES the game. Never do it.
//   * TMap WRITES are fine. DataTable::AddRow works, which is why registration succeeds.
//   * UClass function/property ENUMERATION is unreliable for the same reason. Look functions
//     up directly with StaticFindObject("/Script/Pkg.Class:FuncName") instead of enumerating.

#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UEnum.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>   // UFunction, for the caption-getter probe
#include <Unreal/Engine/UDataTable.hpp>
#include <Unreal/FProperty.hpp>
#include <Unreal/FString.hpp>
#include <Unreal/FText.hpp>
#include <Unreal/Hooks.hpp>                        // ProcessEvent callback, for the gauge trace
#include <Unreal/Core/HAL/UnrealMemory.hpp>
// WIN32_LEAN_AND_MEAN / NOMINMAX keep Windows.h from dragging in winsock and from defining
// min/max macros, both of which break UE4SS headers.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <polyhook2/Detour/x64Detour.hpp>
#include <new>
#include <vector>
#include <memory>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <fstream>
#include <filesystem>
#include <string>

namespace MyMods
{
    // Hoisted above the detour so it can use FName/StringType too. These are repeated further
    // down for the original code; a duplicate using-directive is harmless.
    using namespace RC;
    using namespace RC::Unreal;

    // ---------------------------------------------------------------------------------------
    // Native detour on the asset-registry lookup
    // ---------------------------------------------------------------------------------------
    //
    // WHY THIS EXISTS
    //
    // Ghidra traced the camo asset path to:
    //     DataAssetHelper::LoadDataAsset   FUN_145052ca0
    //       -> UAssetManager::GetPrimaryAssetData   FUN_143bee420   <-- we hook THIS
    //
    // GetPrimaryAssetData walks a two-level TMap (PrimaryAssetType -> asset FName) built at
    // startup from AssetRegistry.bin. Assets that were not in that cooked registry - i.e. every
    // camo we add - are absent, so it returns 0 and nothing renders. Confirmed by dumping the
    // registry: it lists Camouf_1..51 and 54..60 and nothing else.
    //
    // UE4SS's RegisterHook cannot touch this: it only intercepts calls dispatched through
    // Unreal's VM, and the shipped game calls this natively. A machine-code detour is the only
    // way in, hence PolyHook.
    //
    // OBSERVE-ONLY FOR NOW. It logs calls and forwards to the original, changing nothing. That
    // proves (a) the address is right, (b) the detour holds without crashing, and (c) what the
    // game actually asks for and when. Only once that is confirmed should we consider returning
    // a synthesised entry for unregistered names.
    //
    // ADDRESS SAFETY: 0x143bee420 is absolute for THIS build, with image base 0x140000000. It
    // must be applied as an offset from the real module base, never hardcoded - ASLR moves the
    // module, and any game patch moves the function. If the bytes at that offset do not look
    // like a function prologue we refuse to hook rather than corrupt random code.
    namespace AssetLookupDetour
    {
        // Signature per the decompile: (AssetManager* self, uint64* assetId, char bAllowRedirect)
        using GetPrimaryAssetDataFn = uint64_t* (*)(int64_t*, uint64_t*, char);

        static uint64_t                        g_trampoline = 0;
        static std::unique_ptr<PLH::x64Detour> g_detour;
        static uint64_t                        g_callCount = 0;
        static uint64_t                        g_missCount = 0;

        // Ghidra address minus the assumed image base.
        constexpr uintptr_t kGhidraAddress = 0x143bee420;
        constexpr uintptr_t kGhidraImageBase = 0x140000000;
        constexpr uintptr_t kOffsetFromBase = kGhidraAddress - kGhidraImageBase;

        // Set true to rescue failed camo lookups by substituting a registered camo's entry.
        //
        // PROVEN BEHAVIOR we are exploiting (from the live log):
        //     name='Camouf_61_asset' -> MISS      (not in the cooked registry)
        //     name='Camouf_60_asset' -> HIT       (is in the cooked registry)
        //
        // When an unregistered camo is asked for, we re-ask for camo 60 and return THAT entry.
        // The engine then loads Camouf_60_asset, so camo 61 renders camo 60's content.
        //
        // Be clear about what this is: a PROOF that we can defeat the registry miss from inside
        // the lookup. It is not yet additive - every rescued id shows the same asset, because
        // the entry we hand back still points at camo 60's package. Making each id load its OWN
        // package means synthesising an entry whose path points elsewhere, which needs the
        // FPrimaryAssetData layout. This step establishes control; that step adds content.
        // OFF by design. The rescue works - it was confirmed making unregistered camo ids render
        // camo 60's content - but while it is on, EVERY id we rescue looks identical to camo 60,
        // which masks whether an id genuinely resolved its own asset. Leaving it off means a
        // camo reverting to 0 is honest evidence that the id has nothing, which is what makes
        // testing readable.
        //
        // Turn back on only once a rescued id can load its OWN package (see the note above about
        // synthesising an FPrimaryAssetData whose path points elsewhere). Until then it proves a
        // capability rather than adding content.
        // TEMPORARILY OFF - the rescue WORKS but is not yet stable.
        //
        // Confirmed working 2026-07-29: camos 60-65 each rendered their own distinct custom
        // uniform, on ids the game never registered, with no vanilla camo replaced.
        //
        // Confirmed CRASH: after cycling through the slots, re-selecting camo 61 crashed the
        // game. The log ends exactly at "RESCUE #46: 'Camouf_61_asset'". A preceding camotest on
        // an already-current 61 also reported "cache did NOT change", so the trigger looks like
        // re-requesting an id that was already rescued.
        //
        // Likely cause: the original returns a pointer INTO the game's live TMap, and the engine
        // may write through it or treat it as owned storage. We hand back a static buffer
        // instead, so repeated use drifts from what the engine expects.
        //
        // The proper fix is to stop returning fake memory and instead insert a real entry into
        // AssetTypeMap so the lookup succeeds on its own - no synthesis, no lifetime problem.
        static bool g_rescueEnabled = true;
        static uint64_t g_rescueCount = 0;

        // The camo ids ACF actually ships a Camouf_<id>_asset for, in ACF_CamoSlots_P.
        // Keep this in sync with the pak - rescuing an id we do not ship would make a
        // non-existent camo silently render someone else's content.
        // 66 is included as a TEST. It is GM_CAMOUF_MAX - the enum's upper bound, not a normal
        // slot - so it may be rejected by range checks that have nothing to do with the asset
        // registry. Worth testing precisely because it is a DIFFERENT mechanism from the
        // registration problem the rescue solves: an earlier sweep found 66-75 all dead, but that
        // was before the rescue existed, when 61-65 were equally dead. So that result says
        // nothing about 66 any more.
        //
        // If 66 works, the usable band grows past the five reserved ids. If it does not, the enum
        // is the real ceiling and 61-65 is the hard limit.
        // 67 is GM_CAMOUF_EQ_CBOX_A - a cardboard box slot. Included as an EXPERIMENT.
        //
        // Vanilla has no Camouf_67_asset at all (the registry holds 1-51 and 54-60), so shipping
        // one ADDS a package rather than overriding the box's own asset. The real unknown is
        // whether equipping camo value 67 triggers box-specific behavior somewhere in native
        // code. If the cardboard box misbehaves, remove 67 from this list and drop the pak.
        // 61-64 only: the four reserved uniform slots (ADDITIONAL_UNIFORM_2..5) are the whole
        // usable capacity. 65 (DOWNLOAD), 66 (the old MAX sentinel), 67-69 (cardboard boxes) and
        // 72 can render via forcecamo but can never be equipped, so rescuing their assets only
        // costs work on lookups that lead nowhere.
        static constexpr int ACFCamoIds[] = { 61, 62, 63, 64 };

        static auto IsACFCamoAsset(const StringType& name) -> bool
        {
            // Expect exactly "Camouf_<id>_asset".
            constexpr auto prefix = STR("Camouf_");
            constexpr auto suffix = STR("_asset");
            if (name.rfind(prefix, 0) != 0) { return false; }
            const auto suffixPos = name.rfind(suffix);
            if (suffixPos == StringType::npos) { return false; }

            const auto digitsStart = std::char_traits<StringType::value_type>::length(prefix);
            if (suffixPos <= digitsStart) { return false; }

            int id = 0;
            for (auto i = digitsStart; i < suffixPos; ++i)
            {
                const auto c = name[i];
                if (c < STR('0') || c > STR('9')) { return false; }
                id = id * 10 + (c - STR('0'));
            }

            for (const int ours : ACFCamoIds)
            {
                if (ours == id) { return true; }
            }
            return false;
        }

        // Offsets of the two (package path, asset name) FName pairs inside FPrimaryAssetData,
        // taken from a live hex dump of a working camo entry.
        constexpr size_t kEntrySize      = 0x88;
        constexpr size_t kPkgNameOffsetA = 0x08;
        constexpr size_t kAssetNameOffA  = 0x10;
        constexpr size_t kPkgNameOffsetB = 0x28;
        constexpr size_t kAssetNameOffB  = 0x30;

        struct CachedEntry
        {
            StringType name;
            uint8_t    bytes[kEntrySize];
            bool       valid = false;
        };
        static CachedEntry g_entries[8];

        // Pack an FName the way the engine stores it here: low 32 bits = comparison index,
        // high 32 bits = number (0 for all of ours, matching the dump).
        //
        // FNAME_FIND ONLY - never FNAME_Add from in here.
        //
        // This is the suspected cause of the intermittent rescue crash. GetPrimaryAssetData can
        // be called from the ASYNC LOADING THREAD (an earlier crash in this project was literally
        // "Crash in runnable thread FAsyncLoadingThread"), and FNAME_Add MUTATES the global name
        // table. Doing that off the game thread is a race, which fits the symptoms: intermittent,
        // and tied to repeated rescues rather than to any one action.
        //
        // Prime() below adds the names once, up front, on the game thread. By the time the detour
        // runs they already exist, so a Find is enough and nothing is mutated in a hot path.
        static auto PackName(const StringType& text) -> uint64_t
        {
            auto n = FName(text.c_str(), FNAME_Find);
            if (n == FName()) { return 0; }  // not primed - caller must handle
            return static_cast<uint64_t>(n.GetComparisonIndex().ToUnstableInt());
        }

        // Called ONCE from on_update (game thread) to put every name the detour might need into
        // the global name table, so the detour itself never has to add one.
        static auto Prime() -> void
        {
            for (const int id : ACFCamoIds)
            {
                wchar_t asset[64];
                wchar_t pkg[160];
                swprintf_s(asset, STR("Camouf_%d_asset"), id);
                swprintf_s(pkg, STR("/Game/Maps/AssetCamouflage/Camouf_%d_asset"), id);
                // FNAME_Add here is safe: we are on the game thread during on_update.
                FName(asset, FNAME_Add);
                FName(pkg, FNAME_Add);
            }
            FName(STR("Camouf_60_asset"), FNAME_Add);  // the donor
            Output::send<LogLevel::Warning>(STR("[ACF][detour] primed FNames for all ACF camo ids.\n"));
        }

        // Build (once) a copy of the donor entry repointed at `assetName`'s own package.
        static auto GetOrBuildEntry(const StringType& assetName, const uint64_t* donor) -> uint8_t*
        {
            for (auto& e : g_entries)
            {
                if (e.valid && e.name == assetName) { return e.bytes; }
            }
            for (auto& e : g_entries)
            {
                if (e.valid) { continue; }

                std::memcpy(e.bytes, donor, kEntrySize);

                // CRITICAL: clear the loaded-object region (+0x40..+0x7f).
                //
                // The caller in FUN_145052ca0 does:
                //     ptr = *(void**)(entry + 0x68);
                //     if (ptr == 0 || ...) { ptr = *(void**)(entry + 0x48); base = entry + 0x48; }
                //     rc = *(long**)(base + 8);
                //     if (rc) { LOCK(); *(int*)(rc + 1) += 1; UNLOCK(); }     <-- REFCOUNT BUMP
                //
                // So it increments a refcount through a pointer stored INSIDE the entry. Copying
                // the donor wholesale means that once camo 60 is loaded those fields hold live
                // pointers to ITS object, and every rescue bumps camo 60's refcount through our
                // fake struct - corrupting it. That matches the crash appearing only after
                // cycling camos, not on first use.
                //
                // A freshly-dumped entry had +0x40..+0x7f all zero (the "not loaded yet" state).
                // Zeroing it makes the engine take the load path and fetch OUR package from the
                // name fields below, touching no other camo's refcount.
                std::memset(e.bytes + 0x40, 0, 0x40);

                const StringType pkgPath = StringType(STR("/Game/Maps/AssetCamouflage/")) + assetName;
                const uint64_t pkgPacked   = PackName(pkgPath);
                const uint64_t assetPacked = PackName(assetName);

                // If Prime() did not cover this name we must NOT fall back to FNAME_Add here -
                // that is the thread-safety hazard we are trying to remove. Bail instead; the
                // caller falls back to the donor entry, which is merely wrong-looking, not unsafe.
                if (pkgPacked == 0 || assetPacked == 0)
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][detour]   '{}' not primed - refusing to add names off-thread.\n"), assetName);
                    return nullptr;
                }

                std::memcpy(e.bytes + kPkgNameOffsetA, &pkgPacked,   sizeof(pkgPacked));
                std::memcpy(e.bytes + kAssetNameOffA,  &assetPacked, sizeof(assetPacked));
                std::memcpy(e.bytes + kPkgNameOffsetB, &pkgPacked,   sizeof(pkgPacked));
                std::memcpy(e.bytes + kAssetNameOffB,  &assetPacked, sizeof(assetPacked));

                e.name = assetName;
                e.valid = true;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][detour]   built entry for '{}': pkg='{}' (0x{:x}) asset=0x{:x}\n"),
                    assetName, pkgPath, pkgPacked, assetPacked);
                return e.bytes;
            }
            return nullptr;  // cache full
        }

        static auto Detour(int64_t* self, uint64_t* assetId, char bAllowRedirect) -> uint64_t*
        {
            auto original = reinterpret_cast<GetPrimaryAssetDataFn>(g_trampoline);
            uint64_t* result = original(self, assetId, bAllowRedirect);

            ++g_callCount;
            if (result == nullptr) { ++g_missCount; }

            // One-shot layout dump of a SUCCESSFUL camo entry.
            //
            // To make a rescued id load its OWN package we have to hand back an entry whose path
            // points at Camouf_<id>_asset instead of the donor's. That means knowing where the
            // package name sits inside FPrimaryAssetData. The map's element stride is 0x98 with
            // the key at +0 and the next-index at +0x90, so the value is ~0x88 bytes.
            //
            // Read-only: we print the donor's bytes and look for the packed FName of
            // "Camouf_60_asset" inside them. Whatever offset that turns up at is the field to
            // patch in a copy.
            static bool s_dumpedEntry = false;
            if (!s_dumpedEntry && result != nullptr && assetId != nullptr)
            {
                const auto hitName = FName(static_cast<int64_t>(assetId[1])).ToString();
                if (hitName.find(STR("Camouf_")) != StringType::npos)
                {
                    s_dumpedEntry = true;
                    const auto* raw = reinterpret_cast<const uint8_t*>(result);
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][detour] --- FPrimaryAssetData layout for '{}' ---\n"), hitName);
                    for (int row = 0; row < 0x88; row += 16)
                    {
                        StringType line;
                        for (int i = 0; i < 16; ++i)
                        {
                            wchar_t buf[8];
                            swprintf_s(buf, STR("%02x "), raw[row + i]);
                            line += buf;
                        }
                        Output::send<LogLevel::Warning>(STR("[ACF][detour]   +0x{:02x}: {}\n"), row, line);
                    }
                    // Where does the requested FName appear inside the value?
                    const uint64_t wanted = assetId[1];
                    for (int off = 0; off + 8 <= 0x88; off += 4)
                    {
                        uint64_t v = 0;
                        std::memcpy(&v, raw + off, sizeof(v));
                        if (v == wanted || (v & 0xFFFFFFFF) == (wanted & 0xFFFFFFFF))
                        {
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][detour]   >>> asset FName found at +0x{:02x}\n"), off);
                        }
                    }
                }
            }

            // Rescue path: a miss on a camo asset WE SHIP that was never registered.
            //
            // Deliberately narrow. A blanket "rescue anything named Camouf_*" made EVERY
            // non-existent camo render camo 60 instead of falling back to the default, which
            // changes vanilla behavior for ids that are not ours. Only ids we actually ship a
            // Camouf_<id>_asset for get rescued; everything else is left alone to fall back
            // exactly as it always did.
            if (g_rescueEnabled && result == nullptr && assetId != nullptr)
            {
                const auto missedName = FName(static_cast<int64_t>(assetId[1])).ToString();
                if (IsACFCamoAsset(missedName))
                {
                    // FNAME_Find, not FNAME_Add: camo 60 is definitely already in the name table
                    // (the game just looked it up), and we must not pollute name state from
                    // inside a hot engine call.
                    auto donor = FName(STR("Camouf_60_asset"), FNAME_Find);
                    if (donor != FName())
                    {
                        const uint64_t donorPacked =
                            static_cast<uint64_t>(donor.GetComparisonIndex().ToUnstableInt());
                        uint64_t substitute[2] = { assetId[0], donorPacked };
                        uint64_t* rescued = original(self, substitute, bAllowRedirect);
                        if (rescued != nullptr)
                        {
                            // Copy the donor entry and REPOINT it at our own package, so the id
                            // loads ITS asset rather than mirroring camo 60.
                            //
                            // Layout confirmed from a live dump of a working entry:
                            //   +0x08  FName  package path   ("/Game/Maps/AssetCamouflage/Camouf_N_asset")
                            //   +0x10  FName  asset name     ("Camouf_N_asset")
                            //   +0x28  FName  package path   (same pair repeated)
                            //   +0x30  FName  asset name
                            //
                            // Cached per name: building it once avoids touching the name table on
                            // every call, and the returned pointer must stay valid after we return.
                            auto* patched = GetOrBuildEntry(missedName, rescued);
                            if (patched != nullptr)
                            {
                                ++g_rescueCount;
                                Output::send<LogLevel::Warning>(
                                    STR("[ACF][detour] RESCUE #{}: '{}' -> synthesised entry pointing at its own package\n"),
                                    g_rescueCount, missedName);
                                return reinterpret_cast<uint64_t*>(patched);
                            }
                            // Fall back to the donor entry unmodified rather than returning null.
                            ++g_rescueCount;
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][detour] RESCUE #{}: '{}' -> donor entry (synthesis unavailable)\n"),
                                g_rescueCount, missedName);
                            return rescued;
                        }
                    }
                }
            }

            // Resolve the raw FName ints to readable text. An FPrimaryAssetId is two packed
            // FNames: [0] = PrimaryAssetType, [1] = the asset's name. Raw indices told us
            // nothing; the strings tell us exactly which lookups are ours.
            //
            // FName(int64) here builds the wrapper WITHOUT a name-table lookup - it just splits
            // the packed value - so it is safe to construct from engine-supplied ints.
            StringType typeStr, nameStr;
            if (assetId != nullptr)
            {
                auto typeName = FName(static_cast<int64_t>(assetId[0]));
                auto assetName = FName(static_cast<int64_t>(assetId[1]));
                typeStr = typeName.ToString();
                nameStr = assetName.ToString();
            }

            // Always log anything that looks like one of ours, however many calls in - these are
            // rare and are the whole point. Everything else is sampled so the log stays usable.
            const bool isCamo = nameStr.find(STR("Camouf_")) != StringType::npos;
            if (isCamo || g_callCount <= 20 || (g_callCount % 500) == 0)
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF][detour] #{} type='{}' name='{}' redirect={} -> {}\n"),
                    g_callCount,
                    typeStr.empty() ? STR("?") : typeStr,
                    nameStr.empty() ? STR("?") : nameStr,
                    static_cast<int>(bAllowRedirect),
                    result != nullptr ? STR("HIT") : STR("MISS"));
            }
            return result;
        }

        // Log where we THINK the function is, and what bytes are there, WITHOUT touching memory.
        //
        // Completely safe - reads only. Run this first: if the reported bytes do not look like a
        // function prologue, the offset is wrong for this build and hooking it would corrupt
        // unrelated code. UE4SS logs real runtime addresses (e.g. "AActor::BeginPlay address
        // 0x..."), so those can be used to sanity-check the module base independently.
        //
        // A normal x64 prologue usually starts with one of:
        //   48 89 5C 24 ..   mov [rsp+..], rbx
        //   40 53 / 40 55    push rbx / push rbp (with REX)
        //   48 83 EC ..      sub rsp, imm8
        //   4C 8B DC         mov r11, rsp
        static auto Probe() -> void
        {
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0)
            {
                Output::send<LogLevel::Warning>(STR("[ACF][detour] could not get module base.\n"));
                return;
            }
            const uintptr_t target = moduleBase + kOffsetFromBase;
            const auto* b = reinterpret_cast<const uint8_t*>(target);

            Output::send<LogLevel::Warning>(
                STR("[ACF][detour] module base = 0x{:x}\n"), moduleBase);
            Output::send<LogLevel::Warning>(
                STR("[ACF][detour] ghidra 0x{:x} - base 0x{:x} = offset 0x{:x}\n"),
                kGhidraAddress, kGhidraImageBase, kOffsetFromBase);
            Output::send<LogLevel::Warning>(
                STR("[ACF][detour] computed target = 0x{:x}\n"), target);
            Output::send<LogLevel::Warning>(
                STR("[ACF][detour] bytes: {:02x} {:02x} {:02x} {:02x} {:02x} {:02x} {:02x} {:02x}\n"),
                b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]);

            const bool looksLikePrologue =
                (b[0] == 0x48 && b[1] == 0x89) ||   // mov [rsp+x], reg
                (b[0] == 0x40 && (b[1] == 0x53 || b[1] == 0x55 || b[1] == 0x57)) ||
                (b[0] == 0x48 && b[1] == 0x83) ||   // sub rsp, imm8
                (b[0] == 0x4C && b[1] == 0x8B) ||   // mov r11, rsp
                (b[0] == 0x53 || b[0] == 0x55 || b[0] == 0x57);
            Output::send<LogLevel::Warning>(
                STR("[ACF][detour] looks like a function prologue: {}\n"),
                looksLikePrologue ? STR("YES - safe to try hooking") : STR("NO - DO NOT HOOK"));
        }

        static auto Install() -> void
        {
            if (g_detour != nullptr) { return; }

            Probe();

            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }
            const uintptr_t target = moduleBase + kOffsetFromBase;

            g_detour = std::make_unique<PLH::x64Detour>(
                static_cast<uint64_t>(target),
                reinterpret_cast<uint64_t>(&Detour),
                &g_trampoline);

            if (!g_detour->hook())
            {
                Output::send<LogLevel::Warning>(STR("[ACF][detour] hook() FAILED - leaving the game untouched.\n"));
                g_detour.reset();
                return;
            }
            Output::send<LogLevel::Warning>(STR("[ACF][detour] installed on GetPrimaryAssetData (observe-only).\n"));
        }
    }

    // ---------------------------------------------------------------------------------------
    // Per-slot metadata supplied by the mod author
    // ---------------------------------------------------------------------------------------
    //
    // A camo mod ships Content/Paks/mods/ACF_Slot<ID>.txt next to its pak:
    //
    //     Name=Ocelot's Uniform
    //     Description=Worn by the young Ocelot.
    //     Camo=-25
    //
    // The Lua side reads the same file to rename the Survival Viewer row. This copy exists
    // because the COLLECTION VIEWER row is written here, at registration, from the DataTable's
    // DisplayName field - Lua's runtime write does not touch it. Both menus have to agree, so
    // both sides read the same file rather than one telling the other.
    //
    // Relative path on purpose: Lua and this code share the process working directory
    // (Binaries/Win64), the same reasoning as the svunlock bridge file.
    namespace SlotMeta
    {
        // Find ACF_Slot<ID>.txt ANYWHERE under Content/Paks, not just directly in mods/.
        //
        // Authors will organize their downloads into subfolders - Content/Paks/mods/MyCamo/ and
        // similar - and with a single fixed path that silently fell back to the default name with
        // no error, which is the worst possible failure for something optional.
        //
        // Searching is done ONCE here and the result handed to Lua through a resolved file, so
        // there is only one implementation of the lookup rather than one per language.
        static auto Find(int slotId) -> StringType
        {
            wchar_t want[64]{};
            swprintf_s(want, L"ACF_Slot%d.txt", slotId);

            std::error_code ec;
            const std::filesystem::path root = L"..\\..\\Content\\Paks";
            if (!std::filesystem::exists(root, ec)) { return StringType(); }

            StringType found;
            int matches = 0;
            for (auto it = std::filesystem::recursive_directory_iterator(
                     root, std::filesystem::directory_options::skip_permission_denied, ec);
                 it != std::filesystem::recursive_directory_iterator(); it.increment(ec))
            {
                if (ec) { break; }
                if (it->is_directory(ec)) { continue; }
                if (_wcsicmp(it->path().filename().c_str(), want) != 0) { continue; }
                if (matches++ == 0) { found = it->path().wstring(); }
            }

            // Two mods claiming the same slot is the collision case, and it is silent otherwise.
            if (matches > 1)
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF]: WARNING - {} files named ACF_Slot{}.txt found. Two mods may be ")
                    STR("claiming the same slot; using '{}'\n"), matches, slotId, found);
            }
            return found;
        }

        // Returns the value for 'key', or an empty string if the file or key is absent.
        static auto Read(int slotId, const wchar_t* key) -> StringType
        {
            const StringType path = Find(slotId);
            if (path.empty()) { return StringType(); }

            std::ifstream in(path);
            if (!in.is_open()) { return StringType(); }

            // The file is plain ASCII/UTF-8 Key=Value. Read narrow and widen: authors write these
            // in Notepad and non-ASCII names are a later problem, not a v1.1 one.
            std::string line;
            const std::string want = [&]{
                std::string s; for (const wchar_t* p = key; *p; ++p) { s += static_cast<char>(*p); } return s;
            }();

            while (std::getline(in, line))
            {
                if (line.empty() || line[0] == ';' || line[0] == '#') { continue; }
                const auto eq = line.find('=');
                if (eq == std::string::npos) { continue; }
                auto trim = [](std::string s) {
                    const auto b = s.find_first_not_of(" \t\r\n");
                    const auto e = s.find_last_not_of(" \t\r\n");
                    return (b == std::string::npos) ? std::string() : s.substr(b, e - b + 1);
                };
                if (trim(line.substr(0, eq)) != want) { continue; }
                const std::string val = trim(line.substr(eq + 1));
                return StringType(val.begin(), val.end());
            }
            return StringType();
        }

        // The description the menus actually show, assembled from the author's colored lines.
        //
        // The game's description widget is a rich text block, so a style tag in the string is
        // honoured - <Ability>text</> renders orange, and note the close is </>, not </Ability>.
        // Rather than make authors learn that, each color gets its own key and ACF wraps it.
        //
        // Only four styles exist. They come from the game's own style table
        // (/CobraUI/Data/RichText/RichTextStyleRowTemplate) which cannot have rows added, so HTML
        // like <span color="#FF0000"> does nothing.
        //
        // Description= still works, for files written before the colored keys existed.
        static auto ReadDescription(int slotId) -> StringType
        {
            struct Part { const wchar_t* key; const wchar_t* style; };
            static const Part kParts[] = {
                { L"PlainDesc",         nullptr     },   // plain
                { L"AbilityDescOrange", L"Ability"  },   // orange
                { L"WarningDesc",       L"Warning"  },   // red
                { L"SpecialDesc",       L"Special"  },   // yellow
            };

            StringType out;
            for (const Part& part : kParts)
            {
                const StringType value = Read(slotId, part.key);
                if (value.empty()) { continue; }

                if (!out.empty()) { out += STR("\n"); }
                if (part.style == nullptr)
                {
                    out += value;
                }
                else
                {
                    out += STR("<");
                    for (const wchar_t* p = part.style; *p != L'\0'; ++p)
                    {
                        out += static_cast<StringType::value_type>(*p);
                    }
                    out += STR(">");
                    out += value;
                    out += STR("</>");
                }
            }

            if (!out.empty()) { return out; }
            return Read(slotId, STR("Description"));
        }

        // Publish what was found so the Lua side does not have to repeat the search.
        // Written to ACF Logs, which already exists and is where our other output goes.
        static auto WriteResolved(const int* ids, size_t count) -> void
        {
            std::error_code ec;
            std::filesystem::create_directories(L"ACF Logs", ec);
            std::wofstream out(L"ACF Logs\\acf_slots_resolved.txt", std::ios::trunc);
            if (!out.is_open()) { return; }
            out << L"; Generated by ACF. Lists the per-slot metadata found under Content/Paks.\n";
            out << L"; Edit ACF_Slot<ID>.txt next to your pak instead - this file is overwritten.\n";
            for (size_t i = 0; i < count; ++i)
            {
                const int id = ids[i];
                const StringType src = Find(id);
                if (src.empty()) { out << L"; slot " << id << L": no ACF_Slot" << id << L".txt found\n"; continue; }
                out << id << L"|Name|"        << Read(id, STR("Name"))        << L"\n";
                out << id << L"|Description|" << ReadDescription(id) << L"\n";
                out << id << L"|BaseCamo|"    << Read(id, STR("BaseCamo"))    << L"\n";
                out << L"; slot " << id << L" from " << src << L"\n";
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // The REAL ownership store
    // ---------------------------------------------------------------------------------------
    //
    // Everything we wrote before today's last step was downstream of the truth. The chain is:
    //
    //     param_1 (real state)  ->  PTR_DAT_14c532038  ->  PTR_DAT_14c532020  ->  save file
    //
    // FUN_147a7cf60(param_1) rebuilds the ...038 block from param_1, and runs when the Survival
    // Viewer opens - which is why our flag never survived to be displayed.
    //
    // Its second loop flattens the source into the packed table we had been reading:
    //     dst 0x25c + 4k     <- *(ushort*)(param_1 + 0x2e94 + 0xA0*k)
    //     dst 0x25c + 4k + 2 <- *(ushort*)(param_1 + 0x2ee4 + 0xA0*k)
    //
    // Camo id maps to dst 0x2C2 + 2*id, so working both cases back:
    //     id 0 -> param_1 + 0x2ee4 + 0xA0*25 = param_1 + 0x3E84
    //     id 1 -> param_1 + 0x2e94 + 0xA0*26 = param_1 + 0x3ED4
    //     id 2 -> param_1 + 0x2ee4 + 0xA0*26 = param_1 + 0x3F24
    //     id 3 -> param_1 + 0x2e94 + 0xA0*27 = param_1 + 0x3F74
    //
    // Every step is +0x50. It is not interleaved at all - that was just the compiler unrolling
    // two entries per iteration. One array, stride 0x50, base param_1 + 0x3E84.
    //
    // param_1 cannot be read out of Ghidra: the only reference is LEA R9,[FUN_147a7cf60], so it
    // is registered as a callback and the pointer only exists at run time. Hence this detour,
    // which does nothing but record it.
    namespace LiveStore
    {
        using RefreshFn = void (*)(int64_t);

        constexpr uintptr_t kGhidraAddress   = 0x147a7cf60;
        constexpr uintptr_t kGhidraImageBase = 0x140000000;
        constexpr uintptr_t kOffsetFromBase  = kGhidraAddress - kGhidraImageBase;
        constexpr size_t    kCamoBase        = 0x3E84;
        constexpr size_t    kCamoStride      = 0x50;
        constexpr int       kMaxCamoId       = 80;

        static std::unique_ptr<PLH::x64Detour> g_detour;
        static uint64_t  g_trampoline = 0;
        static int64_t   g_state      = 0;
        static bool      g_logged     = false;

        // The hook is not reliable - FUN_147a7cf60 does not fire on every Survival Viewer open,
        // so ACF's camos failed to auto-unlock on a fresh save and needed the command by hand.
        //
        // It turns out we never needed it. The captured param_1 (0x7ff7a8767b90) minus the module
        // base (0x7ff7951b0000, from the state pointer at base+0xC532038) is 0x135B7B90 - i.e.
        // Ghidra 0x1535B7B90, right next to DAT_1535bd868 which FUN_147a7cf60 itself references.
        // param_1 is a STATIC GLOBAL, not a heap object, so it can be computed directly.
        //
        // Validated before use: a real table has ids 0 and 11 owned and every entry 0 or 1.
        constexpr uintptr_t kGhidraStateObj  = 0x1535B7B90;
        constexpr uintptr_t kStateObjOffset  = kGhidraStateObj - kGhidraImageBase;

        static auto Flag(int id) -> uint16_t*
        {
            if (g_state == 0 || id < 0 || id >= kMaxCamoId) { return nullptr; }
            return reinterpret_cast<uint16_t*>(g_state + kCamoBase + kCamoStride * static_cast<size_t>(id));
        }

        // Anything requested before the pointer existed. Without this the command only works if
        // you open the Survival Viewer first, run it, then reopen - an awful interface, and the
        // ordering is not something a user should have to know.
        static std::vector<int> g_pending;
        static uint16_t         g_pendingValue = 1;
        static int              g_appliedCount = 0;
        static int              g_autoCount    = 0;

        // One call stack from inside the Survival Viewer refresh.
        //
        // The row's camouflage number is taken from the map while the list is being built, so no
        // write from on_update can ever be early enough - proven by trying it every tick. The
        // builder has no name to search for and does not call GetCaptionText, so there is nothing
        // to cross-reference. This detour already fires during the viewer open, which means its
        // return addresses ARE the build path. Captured once and logged from on_update.
        static void* g_frames[10]{};
        static uint16_t g_frameCount = 0;
        static bool     g_framesLogged = false;

        static void Detour(int64_t param_1)
        {
            g_state = param_1;

            if (g_frameCount == 0)
            {
                g_frameCount = RtlCaptureStackBackTrace(0, 10, g_frames, nullptr);
            }

            // ACF's own camos are unlocked automatically, every refresh. The console command was
            // never meant to be part of the user experience - a player installing a camo mod
            // should not have to know a command exists, let alone the order to run it in.
            // Only 61-64 (ADDITIONAL_UNIFORM_2..5) are usable: 60 is the real Crocodile Suit, 65
            // is DOWNLOAD and never lists, 66 was the MAX sentinel, 67-69 are cardboard boxes.
            for (int id = 61; id <= 64; ++id)
            {
                auto* f = reinterpret_cast<uint16_t*>(
                    param_1 + kCamoBase + kCamoStride * static_cast<size_t>(id));
                if (*f != 1) { *f = 1; ++g_autoCount; }
            }

            // Apply BEFORE the original runs, so the refresh and the list it feeds both see the
            // new flags. Writing after would need yet another menu open to show up.
            if (!g_pending.empty())
            {
                int changed = 0;
                for (int id : g_pending)
                {
                    if (id < 0 || id >= kMaxCamoId) { continue; }
                    auto* f = reinterpret_cast<uint16_t*>(
                        param_1 + kCamoBase + kCamoStride * static_cast<size_t>(id));
                    if (*f == g_pendingValue) { continue; }
                    *f = g_pendingValue;
                    ++changed;
                }
                g_pending.clear();
                g_appliedCount = changed;   // logged from on_update, never in here
            }

            reinterpret_cast<RefreshFn>(g_trampoline)(param_1);
        }

        static auto Install() -> void
        {
            if (g_detour != nullptr) { return; }
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }

            g_detour = std::make_unique<PLH::x64Detour>(
                static_cast<uint64_t>(moduleBase + kOffsetFromBase),
                reinterpret_cast<uint64_t>(&Detour),
                &g_trampoline);

            if (!g_detour->hook())
            {
                Output::send<LogLevel::Warning>(STR("[ACF][live] hook on FUN_147a7cf60 FAILED.\n"));
                g_detour.reset();
                return;
            }
            Output::send<LogLevel::Warning>(STR("[ACF][live] watching FUN_147a7cf60 for the real state pointer.\n"));
        }

        // Keep ACF's camos flagged every tick once the pointer is known.
        //
        // Doing it only inside the hook was not enough: the hook fires on the Survival Viewer
        // refresh, by which point the list for THAT open has already been built, so the camos
        // only appeared on the next open - which is exactly the "had to run svunlock manually"
        // behavior. Re-applying continuously means any menu open after the first sees them.
        // Four uint16 compares per tick; the writes almost never fire.
        // Compute the state pointer directly instead of waiting for the hook.
        static auto ResolveStatic() -> void
        {
            if (g_state != 0) { return; }
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }

            const auto candidate = static_cast<int64_t>(moduleBase + kStateObjOffset);
            auto* table = reinterpret_cast<uint16_t*>(candidate + kCamoBase);

            int owned = 0;
            for (int id = 0; id < kMaxCamoId; ++id)
            {
                const uint16_t v = table[id * (kCamoStride / 2)];
                if (v > 1) { return; }        // not a flag array - do not touch it
                owned += v;
            }
            if (owned < 8) { return; }
            if (table[0] != 1 || table[11 * (kCamoStride / 2)] != 1) { return; }

            g_state = candidate;
            Output::send<LogLevel::Warning>(
                STR("[ACF][live] state resolved statically at 0x{:x} (no hook needed).\n"),
                static_cast<uint64_t>(g_state));
        }

        static auto KeepApplied() -> void
        {
            ResolveStatic();
            if (g_state == 0) { return; }
            for (int id = 61; id <= 64; ++id)
            {
                auto* f = Flag(id);
                if (f != nullptr && *f != 1) { *f = 1; ++g_autoCount; }
            }
        }

        // Dump whole 0x50-byte records so fields other than "owned" can be identified.
        //
        // Ownership is offset 0 of the record; the rest is unmapped. The new-item dot beside ACF
        // rows is almost certainly another field in here - "check status" in the UE-side
        // AllInvCheckStatusStruct is a DERIVED copy (the game rebuilt it 71 -> 14 on save), so
        // writing that map would have to be re-applied forever. Setting the real field instead
        // is one line next to the ownership write.
        //
        // Compare a camo that shows the dot (e.g. 61) against one that does not (e.g. 0).
        static auto DumpRecords(const int* ids, size_t count) -> void
        {
            if (g_state == 0) { Output::send<LogLevel::Warning>(STR("[ACF][rec] no state yet.\n")); return; }
            for (size_t k = 0; k < count; ++k)
            {
                const int id = ids[k];
                if (id < 0 || id >= kMaxCamoId) { continue; }
                auto* p = reinterpret_cast<uint8_t*>(g_state + kCamoBase + kCamoStride * static_cast<size_t>(id));
                for (size_t row = 0; row < kCamoStride; row += 16)
                {
                    StringType hex;
                    for (size_t i = row; i < row + 16 && i < kCamoStride; ++i)
                    {
                        wchar_t b[8]{}; swprintf_s(b, L"%02X ", p[i]); hex += b;
                    }
                    Output::send<LogLevel::Warning>(STR("[ACF][rec] id {:>3} +0x{:02x}  {}\n"), id, row, hex);
                }
            }
        }

        // Guarded 32-bit read. Separate and object-free so SEH is legal here.
        static auto ReadInt32(const void* p, int32_t* out) -> bool
        {
            __try
            {
                *out = *static_cast<const int32_t*>(p);
                return true;
            }
            __except (EXCEPTION_EXECUTE_HANDLER)
            {
                return false;
            }
        }

        // Guarded single-byte read. Kept separate and object-free so SEH is legal here.
        static auto ReadByte(const void* p, uint8_t* out) -> bool
        {
            __try
            {
                *out = *static_cast<const uint8_t*>(p);
                return true;
            }
            __except (EXCEPTION_EXECUTE_HANDLER)
            {
                return false;
            }
        }


        // One bounded pass over the game's own mapped image, looking for the camo base table.
        //
        // Why this and not Ghidra: the legacy Mgs3 data is loaded at RUNTIME into memory that has
        // no contents in the file on disk. That is why svarena's strings show as "??" in Ghidra,
        // and why searching the executable for the known values finds nothing. The table only
        // exists once the game is running.
        //
        // This is not the kind of scan that got this project into trouble before. That was a
        // repeated sweep of all process memory on a timer, which froze the game. This walks the
        // single mapped region of the game image once, on command, and stops.
        //
        // The signature is six consecutive camo base values whose ids are proven from the
        // description switch and whose values were read out of the live rows by svrows:
        //     id 55 BattleDressPW  5
        //     id 56 SneakingPW    15
        //     id 57 NakedWoodland 45
        //     id 58 NakedBeltlink  0
        //     id 59 Gold        -100
        //     id 60 Crocodile    20
        // All four widths are tried, because nothing yet says how wide an entry is.
        // Set once findcamo has located and verified the table.
        static const int32_t* g_camoTable = nullptr;


        // The camouflage index, found via the MGS3-Delta-Trainer's AOB for "calcuateCamoIndexOffset"
        // (48 83 EC 30 0F 29 74 24 20 48 8B F9 48 63 F2 E8), which lands at Ghidra 0x147ACEC10 -
        // in the legacy layer, next to the data dispatcher and the ownership refresh.
        //
        //     iVar2 = FUN_147a9d010( (int)*(short*)(param_1 + 0x2f88) + *(int*)(param_1 + 0x820c), f );
        //     (&DAT_1535c2064)[playerIndex * 0x58] = iVar2;     // live index, percentage x10
        //
        // param_1 is the same state object LiveStore already resolves - it reads the camo
        // ownership array at param_1 + 0x3E84 - so +0x2F88 and +0x820C are already reachable.
        //
        // Read-only. Verify the numbers track the HUD before believing any of it: everything that
        // "looked right" tonight turned out to be a copy.
        constexpr uintptr_t kGhidraCamoIndex = 0x1535C2064;
        constexpr size_t    kBaseOffset      = 0x2F88;   // int16
        constexpr size_t    kModifierOffset  = 0x820C;   // int32

        static bool g_watchBase = false;
        static int  g_baseTick  = 0;
        static int  g_baseLines = 0;


        // Logged from on_update, never inside the hook.
        static auto DrainApplied() -> void
        {
            if (g_frameCount != 0 && !g_framesLogged)
            {
                g_framesLogged = true;
                const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
                Output::send<LogLevel::Warning>(STR("[ACF][stack] Survival Viewer refresh call stack:\n"));
                for (uint16_t f = 0; f < g_frameCount; ++f)
                {
                    const auto addr = reinterpret_cast<uintptr_t>(g_frames[f]);
                    if (addr < moduleBase) { continue; }   // outside the game image
                    Output::send<LogLevel::Warning>(STR("[ACF][stack]   #{} ghidra 0x{:X}\n"),
                        f, static_cast<uint64_t>(addr - moduleBase + 0x140000000ull));
                }
            }

            if (g_autoCount != 0)
            {
                const int a = g_autoCount;
                g_autoCount = 0;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][live] auto-unlocked {} ACF camo(s) (61-64).\n"), a);
            }
            if (g_appliedCount == 0) { return; }
            const int n = g_appliedCount;
            g_appliedCount = 0;
            Output::send<LogLevel::Warning>(
                STR("[ACF][live] applied {} queued unlock(s) as the Survival Viewer opened.\n"), n);
        }

        // Called from on_update so logging never happens inside the hook.
        static auto ReportOnce() -> void
        {
            if (g_state == 0 || g_logged) { return; }
            g_logged = true;
            StringType owned;
            int count = 0;
            for (int id = 0; id < kMaxCamoId; ++id)
            {
                auto* f = Flag(id);
                if (f == nullptr || *f == 0) { continue; }
                if (count++) { owned += STR(","); }
                owned += std::to_wstring(id);
            }
            Output::send<LogLevel::Warning>(
                STR("[ACF][live] real state = 0x{:x}, camo array @ 0x{:x} stride 0x50 - {} owned: {}\n"),
                static_cast<uint64_t>(g_state),
                static_cast<uint64_t>(g_state + kCamoBase), count, owned);
        }
    }

    using namespace RC;
    using namespace Unreal;

    // ---------------------------------------------------------------------------------------
    // Survival Viewer row contents (name / icon)
    // ---------------------------------------------------------------------------------------
    //
    // The menu renders rows from FPropData structs held in a TMap on CSVTabViewWidget. Ghidra
    // (FUN_1453c7f40, FindPropDataForSelectIndex) gave the container layout, and the SDK dump
    // gave the struct:
    //
    //     widget + 0x748  -> elements pointer      element stride 0x98
    //     widget + 0x750  -> element count         key at +0, FPropData at +8, next at +0x90
    //
    //     FPropData: +0x10 FString Name    <- what the row displays
    //                +0x30 int32   Icon    <- thumbnail id
    //                +0x34 int32   Camouf  <- which camo the row is for
    //                +0x60 FString Explain
    //
    // So ACF's rows showing "-IT_EqAdditionalUniform2-2" is not an unreachable loc table - it is
    // an unresolved key sitting in an FString we can see. READ-ONLY for now: dump what is there
    // and confirm the layout before writing anything into the game's containers.
    namespace PropRows
    {
        constexpr size_t kElemsOff   = 0x748;
        constexpr size_t kCountOff   = 0x750;
        constexpr size_t kElemStride = 0x98;
        constexpr size_t kDataOff    = 0x08;   // FPropData within an element
        constexpr size_t kNameOff    = 0x10;
        constexpr size_t kSNameOff   = 0x20;   // what the LIST ROW shows; Name is the detail caption
        constexpr size_t kExplainOff = 0x60;   // the description under the caption
        constexpr size_t kIconOff    = 0x30;
        constexpr size_t kCamoufOff  = 0x34;

        // UE FString is a TArray<TCHAR>: { TCHAR* Data; int32 Num; int32 Max; }
        struct RawString { wchar_t* Data; int32_t Num; int32_t Max; };

        static auto Walk(uint8_t* elems, int32_t count) -> void
        {
            for (int32_t i = 0; i < count; ++i)
            {
                auto* pd     = elems + kElemStride * static_cast<size_t>(i) + kDataOff;
                const auto camouf = *reinterpret_cast<int32_t*>(pd + kCamoufOff);
                const auto icon   = *reinterpret_cast<int32_t*>(pd + kIconOff);
                const auto& name  = *reinterpret_cast<RawString*>(pd + kNameOff);
                const auto& sname = *reinterpret_cast<RawString*>(pd + kSNameOff);

                StringType text, stext;
                if (name.Data != nullptr && name.Num > 0 && name.Num < 512)
                {
                    text.assign(name.Data, static_cast<size_t>(name.Num - 1));
                }
                if (sname.Data != nullptr && sname.Num > 0 && sname.Num < 512)
                {
                    stext.assign(sname.Data, static_cast<size_t>(sname.Num - 1));
                }
                const auto& expl = *reinterpret_cast<RawString*>(pd + kExplainOff);
                Output::send<LogLevel::Warning>(
                    STR("[ACF][rows]   [{}] camouf={} icon={} Name {}/{} '{}' | SName {}/{} '{}' | Explain {}/{}\n"),
                    i, camouf, icon, name.Num, name.Max, text,
                    sname.Num, sname.Max, stext, expl.Num, expl.Max);
            }
        }

        // What each ACF slot should be called. Slots 61-64 are the vanilla reserved
        // ADDITIONAL_UNIFORM_2..5 entries, whose loc keys do not resolve - the game renders its
        // own missing-key marker, "Ã£â€šÂ¢Ã£â€šÂ¤Ã£Æ’â€ Ã£Æ’Â Ã¥ÂÂÃ¥Â®Å¡Ã§Â¾Â©-IT_EqAdditionalUniform2-2".
        // Names are per-SLOT, not per-mod. The third-party camos in use here are test fixtures;
        // anyone installing ACF will drop different mods into these slots, so naming a slot after
        // whatever happens to occupy it locally would be wrong. Matches the Collection Viewer,
        // which already labels them ACF Mod 1-7.
        // Icon is a NUMERIC TEXTURE NAME, not a table index. The thumbnails already used by the
        // Collection Viewer are textures literally called "9279063", "5115826" etc. under
        // /CobraUI/textures/sv/camouflage/, and vanilla rows carry values in the same range
        // (16684634 for NAKED, 3184223 for OLIVE DRAB). ACF's rows come through as 9200220,
        // 9265756, 9331292, 9396828 - each exactly 0x10000 apart, i.e. a generated sequence
        // rather than a real texture, which is why they render as "U.H"/"U.I" letter badges.
        //
        // Point them at textures that actually exist. Reusing the same numbers the Collection
        // Viewer rows already use, so each slot gets a distinct, real thumbnail.
        // Descriptions are per-slot too, for the same reason the names are: the slot does not
        // know which mod fills it. Kept short deliberately - these are written IN PLACE into the
        // existing buffer, and the placeholder they replace may not be long. Anything that does
        // not fit is skipped and reported rather than truncated.
        struct NameFix
        {
            const wchar_t* keyFragment;
            const wchar_t* display;
            const wchar_t* desc;
            int32_t        icon;
        };
        static const NameFix kNameFixes[] = {
            { STR("AdditionalUniform2"), STR("ACF Mod 1"), STR("Uniform slot 1, added by ACF."),  9279063 },  // 61
            { STR("AdditionalUniform3"), STR("ACF Mod 2"), STR("Uniform slot 2, added by ACF."),  5115826 },  // 62
            { STR("AdditionalUniform4"), STR("ACF Mod 3"), STR("Uniform slot 3, added by ACF."),  6002287 },  // 63
            { STR("AdditionalUniform5"), STR("ACF Mod 4"), STR("Uniform slot 4, added by ACF."), 11310703 },  // 64
        };

        // Overwrite IN PLACE only. An FString is { TCHAR* Data; int32 Num; int32 Max; } and the
        // buffer belongs to the game's allocator - reallocating it from here is what hard-crashed
        // the DataTable work earlier. Every replacement is shorter than the placeholder it
        // replaces (Max was 40 for the longest), so the existing buffer is reused and only Num
        // changes. If a replacement would not fit, it is skipped rather than forced.
        // Overwrite one FString in place if the replacement fits. Returns true if it wrote.
        static auto SetInPlace(RawString& s, const wchar_t* text) -> bool
        {
            if (s.Data == nullptr || s.Max <= 0) { return false; }
            const size_t len = std::wcslen(text);
            if (static_cast<int32_t>(len) + 1 > s.Max) { return false; }
            std::wmemcpy(s.Data, text, len);
            s.Data[len] = L'\0';
            s.Num = static_cast<int32_t>(len) + 1;
            return true;
        }

        // Writing Name alone was not enough: the detail panel at the bottom-left picked up
        // "ACF Mod 1" correctly while the list row kept showing the placeholder. The two come
        // from different fields - Name (+0x10) feeds the detail caption, SName (+0x20) is what
        // the row itself displays. Write both.
        static auto FixNames(uint8_t* elems, int32_t count, bool verbose) -> int
        {
            int fixed = 0;
            for (int32_t i = 0; i < count; ++i)
            {
                auto* pd = elems + kElemStride * static_cast<size_t>(i) + kDataOff;
                auto& name  = *reinterpret_cast<RawString*>(pd + kNameOff);
                auto& sname = *reinterpret_cast<RawString*>(pd + kSNameOff);

                // Match on either field - whichever still holds the unresolved key.
                StringType current;
                if (name.Data != nullptr && name.Num > 0 && name.Num < 512)
                {
                    current.assign(name.Data, static_cast<size_t>(name.Num - 1));
                }
                if (sname.Data != nullptr && sname.Num > 0 && sname.Num < 512)
                {
                    current += StringType(sname.Data, static_cast<size_t>(sname.Num - 1));
                }
                if (current.empty()) { continue; }

                for (const auto& fix : kNameFixes)
                {
                    if (current.find(fix.keyFragment) == StringType::npos) { continue; }

                    auto& explain = *reinterpret_cast<RawString*>(pd + kExplainOff);
                    const bool wroteName  = SetInPlace(name, fix.display);
                    const bool wroteSName = SetInPlace(sname, fix.display);
                    const bool wroteDesc  = SetInPlace(explain, fix.desc);
                    *reinterpret_cast<int32_t*>(pd + kIconOff) = fix.icon;
                    if (wroteName || wroteSName) { ++fixed; }

                    if (verbose)
                    {
                        Output::send<LogLevel::Warning>(
                            STR("[ACF][rows]   row {} -> '{}' (Name {}, SName {}, Explain {} max {}) icon {}\n"),
                            i, fix.display,
                            wroteName  ? STR("ok") : STR("no room"),
                            wroteSName ? STR("ok") : STR("no room"),
                            wroteDesc  ? STR("ok") : STR("no room"),
                            explain.Max, fix.icon);
                    }
                    break;
                }
            }
            return fixed;
        }

        // Applied continuously, not once.
        //
        // svrows fix wrote the names successfully - the dump showed rows 14-17 reading
        // "ACF Mod 1".."ACF Mod 4" - and the menu still displayed the placeholders. The list is
        // rebuilt every time the viewer opens, which regenerates the unresolved key and discards
        // our edit. Fixing after the fact is always too late; it has to be in place before the
        // rows are read.
        //
        // The element pointer is cached, so the common case is a handful of compares. Re-finding
        // only happens when the cache goes stale.
        static uint8_t* g_elems  = nullptr;
        static int32_t  g_count  = 0;
        static uint8_t* g_widget = nullptr;
        static int      g_findTick = 0;

        static auto Tick() -> void
        {
            if (g_elems != nullptr)
            {
                if (g_count > 0 && g_count <= 512) { FixNames(g_elems, g_count, false); return; }
                g_elems = nullptr;   // stale
            }

            if (++g_findTick < 30) { return; }
            g_findTick = 0;

            std::vector<UObject*> found;
            UObjectGlobals::FindAllOf(STR("CSVTabViewWidget"), found);
            for (auto* obj : found)
            {
                if (obj == nullptr) { continue; }
                auto* base = reinterpret_cast<uint8_t*>(obj);
                auto* elems = *reinterpret_cast<uint8_t**>(base + kElemsOff);
                const int32_t count = *reinterpret_cast<int32_t*>(base + kCountOff);
                if (elems == nullptr || count <= 0 || count > 512) { continue; }
                g_elems = elems;
                g_count = count;
                FixNames(g_elems, g_count, false);
                return;
            }
        }

        // The first attempt used FindFirstOf("CSVTabViewWidget") and got elements=0, count=0 -
        // either a class-default object or the wrong owner entirely. Our own Ghidra notes had
        // already warned that param_1 in FindPropDataForSelectIndex is probably NOT the menu
        // widget, and I used it anyway.
        //
        // So stop asserting an owner. Check every live instance of the plausible classes, skip
        // class-defaults, and report which ones hold something map-shaped at +0x748/+0x750.
        // ---------------------------------------------------------------------------------
        // Intercept the READ instead of racing the write
        // ---------------------------------------------------------------------------------
        //
        // Writing into the map cannot work: FUN_1453d0c20 is the map's destructor - it walks
        // elements at stride 0x98 freeing four FStrings each at +0x18/+0x28/+0x50/+0x68, which
        // after the +8 element header are exactly Name/SName/Weight/Explain. The whole map is
        // torn down and rebuilt every time the viewer opens, so any edit we make is discarded.
        //
        // FindPropDataForSelectIndex is what the menu calls to READ a row:
        //     bool FUN_1453c7f40(void* self, int index, FPropData* out)
        // Patch its output and every consumer sees our values, with nothing to race.
        namespace ReadHook
        {
            using FindFn = bool (*)(void*, int32_t, uint8_t*);

            constexpr uintptr_t kGhidraAddress   = 0x1453c7f40;
            constexpr uintptr_t kGhidraImageBase = 0x140000000;

            static std::unique_ptr<PLH::x64Detour> g_detour;
            static uint64_t g_trampoline = 0;

            // The camouflage value the author asked for, matched to the row by the name they also
            // supplied. Matching on text rather than on an id because FPropData's own ID field is
            // not yet known to be the camo id - the same read that applies this logs it, so the
            // next pass can key off the id directly if that turns out to be sound.
            struct SlotCamo
            {
                StringType name;
                int32_t    value = 0;
                bool       has   = false;
            };
            static SlotCamo g_slotCamo[4];

            static auto LoadSlotCamo() -> void
            {
                for (int id = 61; id <= 64; ++id)
                {
                    auto& s = g_slotCamo[id - 61];
                    s.name = SlotMeta::Read(id, STR("Name"));
                    const StringType camo = SlotMeta::Read(id, STR("BaseCamo"));
                    if (s.name.empty() || camo.empty()) { continue; }

                    wchar_t* end = nullptr;
                    const long v = std::wcstol(camo.c_str(), &end, 10);
                    if (end == camo.c_str()) { continue; }   // not a number - ignore, do not guess
                    s.value = static_cast<int32_t>(v);
                    s.has   = true;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][camo] slot {} '{}' wants camouflage {}\n"), id, s.name, s.value);
                }
            }

            // One line per distinct row index, capped. This runs on every row read while the
            // viewer is open, so it must not grow without bound.
            static bool g_logged[128]{};

            static bool Detour(void* self, int32_t index, uint8_t* out)
            {
                const bool ok = reinterpret_cast<FindFn>(g_trampoline)(self, index, out);
                if (!ok || out == nullptr) { return ok; }

                auto& name  = *reinterpret_cast<RawString*>(out + kNameOff);
                auto& sname = *reinterpret_cast<RawString*>(out + kSNameOff);

                StringType current;
                if (name.Data != nullptr && name.Num > 0 && name.Num < 512)
                {
                    current.assign(name.Data, static_cast<size_t>(name.Num - 1));
                }
                if (sname.Data != nullptr && sname.Num > 0 && sname.Num < 512)
                {
                    current += StringType(sname.Data, static_cast<size_t>(sname.Num - 1));
                }
                if (current.empty()) { return ok; }

                for (const auto& fix : kNameFixes)
                {
                    if (current.find(fix.keyFragment) == StringType::npos) { continue; }
                    SetInPlace(name, fix.display);
                    SetInPlace(sname, fix.display);
                    *reinterpret_cast<int32_t*>(out + kIconOff) = fix.icon;
                    break;
                }

                auto* camouf = reinterpret_cast<int32_t*>(out + kCamoufOff);

                // Identify the row. FPropData carries Index at +0x00 and ID at +0x04; whether ID
                // is the camo id or an EItemName is unknown, so log it beside the text we can
                // already recognize and let the next pass use it if it holds up.
                const int32_t rowId = *reinterpret_cast<int32_t*>(out + 0x04);
                if (rowId >= 61 && rowId <= 64
                    && index >= 0 && index < static_cast<int32_t>(std::size(g_logged)) && !g_logged[index])
                {
                    g_logged[index] = true;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][camo] row {:>3}  Index={} ID={} Origin={} camouf={}  '{}'\n"),
                        index,
                        *reinterpret_cast<int32_t*>(out + 0x00),
                        *reinterpret_cast<int32_t*>(out + 0x04),
                        *reinterpret_cast<int32_t*>(out + 0x08),
                        *camouf, current);
                }

                // What this buffer is and is NOT good for, both established by experiment:
                //
                //  * NAME/SName are not drawn from here. Forcing SName to a marker for ids 61-64
                //    left the rows showing the author's name, so the list draws its text from
                //    somewhere else - which is why row names come from ACF_Names_P and the
                //    localisation fallback rather than from this hook.
                //
                //  * CAMOUF *IS* consumed from here. FUN_1452894f0 calls this very function and
                //    returns nothing but the +0x34 field out of the buffer it fills:
                //        FindPropDataForSelectIndex(list, index, &out);
                //        return ok ? out.Camouf : 0;
                //    and FUN_145289460 hands that straight to the gauge as
                //    UCCamoufGaugeWidget::SetCamouflagePreview(gauge, value, ...).
                //
                // Note what the caller does with the third argument: the gauge is told to show
                // the value only when SelectIndex != the hovered index, so this drives the
                // PREVIEW percentage for a row being hovered, not the equipped one.
                // DELIBERATELY NOT WRITTEN. Setting Camouf here does work - hovering an ACF slot
                // showed the author's value in the gauge - but it changes the PREVIEW only. The
                // percentage while the camo is actually worn stays 0, because gameplay reads a
                // base value from a source this does not reach.
                //
                // The result was a menu promising 50% and a game delivering 0%. That is worse than
                // showing nothing: it is the HUD telling the player something untrue. Restore this
                // only together with the gameplay value, never on its own.
                //
                // Everything needed to switch it back on is still here - g_slotCamo holds the
                // author's number and ID at +0x04 is the camo id.
                (void)camouf;
                return ok;
            }

            static auto Install() -> void
            {
                if (g_detour != nullptr) { return; }
                const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
                if (moduleBase == 0) { return; }

                g_detour = std::make_unique<PLH::x64Detour>(
                    static_cast<uint64_t>(moduleBase + (kGhidraAddress - kGhidraImageBase)),
                    reinterpret_cast<uint64_t>(&Detour),
                    &g_trampoline);

                if (!g_detour->hook())
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][rows] hook on FindPropDataForSelectIndex FAILED.\n"));
                    g_detour.reset();
                    return;
                }
                LoadSlotCamo();
                Output::send<LogLevel::Warning>(
                    STR("[ACF][rows] hooked FindPropDataForSelectIndex - row text patched on read.\n"));
            }
        }

        static auto Dump(bool applyNames = false) -> void
        {
            static const wchar_t* kCandidates[] = {
                STR("CSVTabViewWidget"),
                STR("SurvivalViewerStateSubsystem"),
                STR("CCamouflageMenuState"),
                STR("CPropMenuBaseState"),
                STR("CSVMenuStateBase"),
            };

            int examined = 0;
            for (const wchar_t* cls : kCandidates)
            {
                std::vector<UObject*> found;
                UObjectGlobals::FindAllOf(cls, found);
                if (found.empty())
                {
                    Output::send<LogLevel::Warning>(STR("[ACF][rows] {}: no live instances\n"), cls);
                    continue;
                }

                for (auto* obj : found)
                {
                    if (obj == nullptr) { continue; }
                    const auto full = obj->GetFullName();
                    if (full.find(STR("Default__")) != StringType::npos) { continue; }   // CDO

                    auto* base = reinterpret_cast<uint8_t*>(obj);
                    auto* elems = *reinterpret_cast<uint8_t**>(base + kElemsOff);
                    const int32_t count = *reinterpret_cast<int32_t*>(base + kCountOff);
                    ++examined;

                    const bool sane = elems != nullptr && count > 0 && count <= 512;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][rows] {} 0x{:x}  +0x748=0x{:x}  +0x750={}  {}\n"),
                        cls, reinterpret_cast<uintptr_t>(base),
                        reinterpret_cast<uintptr_t>(elems), count,
                        sane ? STR("<- looks like the map") : STR(""));

                    if (!sane) { continue; }
                    if (applyNames)
                    {
                        const int n = FixNames(elems, count, true);
                        Output::send<LogLevel::Warning>(STR("[ACF][rows] renamed {} row(s).\n"), n);
                    }
                    Walk(elems, count);
                }
            }
            if (examined == 0)
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF][rows] nothing live - open the Survival Viewer, then run this.\n"));
            }
        }

        // Write the author's camouflage value into the row map itself.
        //
        // The list row and the gauge are TWO DIFFERENT DISPLAYS and only the gauge was fixed by
        // patching FindPropDataForSelectIndex's output: that function returns a COPY, which the
        // hover path reads and the gauge shows, while the row draws its own number from the
        // ItemButtonDataMap entry at widget+0x748. Hence a slot reading "00" in the list while the
        // gauge correctly previews 50%.
        //
        // Two rules learned the hard way, both obeyed here:
        //  * Re-find the widget every time. The old FixNames cached the element pointer and the
        //    map is destroyed and rebuilt on every viewer open, so the next tick read freed
        //    memory - that is the crash that shipped in v1.0.
        //  * Only write, never allocate. Camouf is a plain int32 in memory the game owns.
        static auto ApplyCamo() -> void
        {
            // EVERY tick, deliberately. Throttling to every 15 lost a race: the map is filled
            // when the viewer opens and the list widgets take their number from it as they are
            // created, so a write a quarter of a second later is always too late and the row
            // keeps the 0 it was built with - which is exactly what "svrows shows 50 but the row
            // shows 00" means. UMG lists populate entries over following frames, so running each
            // tick is the only way a post-fill write can land before the button reads it.
            //
            // If this still loses, the value has to come from the source the builder reads, not
            // from here.

            static const wchar_t* kCandidates[] = {
                STR("CSVTabViewWidget"),
                STR("CCamouflageMenuState"),
            };

            for (const wchar_t* cls : kCandidates)
            {
                std::vector<UObject*> found;
                UObjectGlobals::FindAllOf(cls, found);
                for (auto* obj : found)
                {
                    if (obj == nullptr) { continue; }
                    if (obj->GetFullName().find(STR("Default__")) != StringType::npos) { continue; }

                    auto* base  = reinterpret_cast<uint8_t*>(obj);
                    auto* elems = *reinterpret_cast<uint8_t**>(base + kElemsOff);
                    const int32_t count = *reinterpret_cast<int32_t*>(base + kCountOff);
                    if (elems == nullptr || count <= 0 || count > 512) { continue; }

                    // Publish for 'svwatch rows'. That command traps writes to this buffer to
                    // catch whoever populates it, and its pointer used to come from PropRows::Tick
                    // which was removed after the v1.0 crash - so it had nothing to arm. This is
                    // re-found every tick rather than cached across frames, which is what made
                    // the old cache unsafe.
                    g_elems  = elems;
                    g_count  = count;
                    g_widget = base;   // for 'svwatch map' - the map header lives at base+0x748

                    for (int32_t i = 0; i < count; ++i)
                    {
                        auto* entry = elems + kElemStride * static_cast<size_t>(i);
                        auto* pd    = entry + kDataOff;
                        const int32_t id = *reinterpret_cast<int32_t*>(pd + 0x04);
                        if (id < 61 || id > 64) { continue; }

                        // WRITE DISABLED, along with the one in ReadHook. Writing Camouf changed
                        // the gauge preview and nothing else, leaving the menu promising a number
                        // the game does not honour when the camo is worn.
                        //
                        // Kept for the record, because two things learned here are easy to lose:
                        //  * The number in the LIST is recomputed every frame as a delta - what
                        //    the camo index would become if you switched, terrain and stance
                        //    included, relative to what is worn. Wearing Gold (-100) makes every
                        //    row read about 165 higher. It is not this field.
                        //  * Do not "fix" the list by writing its text either. A fixed string in a
                        //    column that recomputes per frame is wrong the moment the player moves.
                        (void)pd; (void)entry;
                        break;
                    }
                }
            }
        }
    }

    // One entry per camo to add. Adding a camo should be a matter of adding a line here.
    struct ACFCamoDef
    {
        const wchar_t* ItemName;     // EItemName / EGsrItemId entry name
        const wchar_t* RowName;      // DataTable row key and ECamouflageType entry name
        int32_t        CamoValue;    // ECamouflageType numeric value (vanilla uses 0-70)
        const wchar_t* DisplayName;  // shown in the Collection Viewer - PLAIN TEXT is fine
        // Thumbnail texture, as a bare name under /CobraUI/textures/sv/camouflage/.
        //
        // Must be a texture the engine ALREADY HAS IN MEMORY - the row's Thumbnail is a hard
        // UObject pointer, not a path, so we cannot make the engine go and fetch one. Vanilla
        // camo thumbnails are all preloaded (verified: two picked at random were both already
        // resident without anything asking for them), which is why they work here.
        //
        // A custom texture shipped in a pak is NOT preloaded and cannot currently be loaded on
        // demand - ACFT01 was built correctly and still never appears in memory. Getting custom
        // art in needs the texture referenced from an asset that does load. Until then, each row
        // at least gets its OWN vanilla thumbnail instead of all six showing Naked.
        const wchar_t* ThumbnailName;
    };

    // A row whose thumbnail texture was not in memory when the row was registered.
    //
    // Vanilla thumbnails are preloaded so they resolve immediately. A CUSTOM texture shipped in a
    // pak is not - it only enters memory once something that loads REFERENCES it. We added
    // ACFT01 to Camouf_67_asset's import table for exactly that reason, so it arrives when that
    // camo asset loads, which is long after registration.
    //
    // So the row is registered with a null Thumbnail and revisited each tick until the texture
    // shows up. This works because TMap reads are fine (FindRowUnchecked with FNAME_Find), which
    // means we can find the row again and patch the field in place.
    struct PendingThumb
    {
        StringType rowName;
        StringType thumbName;
        bool       done = false;
    };

    // ---------------------------------------------------------------------------------------
    // Legacy MGS3 save state - camo ownership
    // ---------------------------------------------------------------------------------------
    //
    // The Survival Viewer / equip menu does NOT read the same data as the Collection Viewer.
    // It reflects what the player actually OWNS, and ownership lives in the legacy MGS3 game
    // state - the "Mgs3GameData" blob in the .sav (19188 raw bytes wrapping the original
    // game's save structure, which MGS Delta carries forward wholesale).
    //
    // HOW THE LAYOUT WAS FOUND (differential analysis, 2026-07-29):
    //   Two saves were compared that differed by exactly six camos - CHOCO_CHIP(4),
    //   RAIN_STROKE(6), WATER(8), SCIENTIST(13), HORNET_STRIPE(17), ANIMAL(29). Six bytes in
    //   the blob went 0 -> 1, at deltas of 4, 4, 10, 8, 24. The ID deltas are 2, 2, 5, 4, 12 -
    //   exactly half. So: one uint16 per ECamouflageType value, base = blob + 0x2C2.
    //   Decoding a 14-camo save with that layout reproduced the player's camo list exactly.
    //
    // WHY WE PATCH MEMORY AND NOT THE FILE:
    //   Writing those flags straight into the .sav makes the game reject it outright
    //   ("failed to load save data") - the blob carries some integrity field we have not
    //   identified, and no standard digest (CRC32/32C/BE, Adler, FNV, XOR, sums) of it is
    //   stored anywhere in the file. Setting the flags in the LIVE blob sidesteps that
    //   completely: the game recomputes whatever it needs when it next writes a save, exactly
    //   as it does when you pick an item up during play.
    namespace LegacySave
    {
        constexpr size_t kTableOff  = 0x2C2;   // camo table, relative to the blob head

        // WHERE THE LIVE STATE IS (Ghidra, 2026-07-29)
        //
        // Saving assembles Mgs3GameData in FUN_147ab0db0:
        //     memset(&DAT_15451cae0, 0, 0x4af4);              // 19188-byte staging buffer
        //     memcpy(&DAT_15451cae0, FUN_147ad16d0(), 0x32f0); // chunk 1
        //     memcpy(&DAT_15451fdd0, FUN_147ad18a0(), 0x1800); // chunk 2 (blob + 0x32f0)
        //     _DAT_15451cac0 = &DAT_15451cae0;                 // TArray.Data
        //     _DAT_15451cac8 = 0x4af4;                         // TArray.Num
        //
        // So DAT_15451cae0 is only a STAGING COPY - zeroed and rebuilt on every save. Writing
        // there would be wiped, and that is exactly why UniformCheckFlagMap went 71 -> 14 when
        // we wrote it earlier: the game was not ignoring us, it was rebuilding from source.
        //
        // The camo table is at blob + 0x2C2, and 0x2C2 < 0x32F0, so it lives in chunk 1 - whose
        // source is FUN_147ad16d0(), which is just:  return PTR_DAT_14c532020;
        //
        // Hence the live table is  (*(uint8_t**)(moduleBase + 0xC532020)) + 0x2C2.
        // WHICH POINTER IS THE LIVE ONE (Ghidra, 2026-07-29)
        //
        // There are two copies of this structure, and we spent a long time on the wrong one.
        //
        //     FUN_147ad1bb0(dst, size):
        //         memcpy(PTR_DAT_14c532020 + (dst - PTR_DAT_14c532038),   // destination
        //                dst,                                            // source
        //                size);
        //
        // Source is the ...038 block, destination is the ...020 block. So ...038 is the LIVE
        // game state and ...020 is a save-time MIRROR. FUN_147ad16d0 returns ...020, which is
        // why every address derived from it pointed at the mirror.
        //
        // That explains the whole dead end: writing the mirror never changed the Survival
        // Viewer (it reads the live state), the mirror is only written at save time by the sync
        // in FUN_147aaf2d0, and its contents matched the player's camos exactly only because it
        // had been synced during the last save.
        //
        // The mirror is unusable in both directions - the viewer ignores it, and the sync
        // overwrites anything we put there moments before serialization.
        //
        // Layouts are identical: the sync maps dst = 020 + (src - 038), preserving offsets, so
        // 0x2C2 (measured from the save file, i.e. the mirror) applies unchanged to the live block.
        constexpr uintptr_t kGhidraImageBase   = 0x140000000;
        constexpr uintptr_t kGhidraStatePtr    = 0x14c532038;   // PTR_DAT_14c532038 - LIVE state
        constexpr uintptr_t kStatePtrOffset    = kGhidraStatePtr - kGhidraImageBase;

        static uint8_t* g_table = nullptr;

        // How far the flag array actually runs. Checked against a real save: entries 0..97 are
        // all 0 or 1, but 98 onwards hold counts (10, 10, 5, 25...) belonging to whatever field
        // follows. An earlier version validated 128 entries, hit those counts, and rejected a
        // perfectly good pointer. Stop well short of the boundary.
        constexpr int kFlagArrayIds = 80;

        // Cheap sanity check. This is not a search - we already know the address - it only
        // guards against reading before a save is loaded, when the pointer may be null or the
        // state not yet populated.
        static auto LooksValid(uint8_t* table) -> bool
        {
            int owned = 0;
            for (int id = 0; id < kFlagArrayIds; ++id)
            {
                const uint16_t v = *reinterpret_cast<uint16_t*>(table + 2 * id);
                if (v > 1) { return false; }        // strictly a flag array
                owned += v;
            }
            // Olive Drab and Naked can never be un-owned in a real save.
            return owned >= 8
                && *reinterpret_cast<uint16_t*>(table + 2 * 0)  == 1
                && *reinterpret_cast<uint16_t*>(table + 2 * 11) == 1;
        }

        static auto Resolve() -> uint8_t*
        {
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return nullptr; }

            auto* slot = reinterpret_cast<uint8_t**>(moduleBase + kStatePtrOffset);
            uint8_t* state = *slot;
            Output::send<LogLevel::Warning>(STR("[ACF]: legacy state ptr @ 0x{:x} -> {}\n"),
                                            moduleBase + kStatePtrOffset, static_cast<void*>(state));
            if (state == nullptr) { return nullptr; }

            uint8_t* table = state + kTableOff;
            if (!LooksValid(table))
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: state present but table at +0x2C2 does not look like ")
                                                STR("a flag array - load a save first.\n"));
                return nullptr;
            }
            return table;
        }

        static auto Entry(uint8_t* table, int id) -> uint16_t*
        {
            return reinterpret_cast<uint16_t*>(table + 2 * static_cast<size_t>(id));
        }

        // -----------------------------------------------------------------------------------
        // Write watch - make the game tell us who grants a camo
        // -----------------------------------------------------------------------------------
        //
        // Setting the ownership flag ourselves is NOT enough: the write lands (confirmed live -
        // the table reads back correctly) but the Survival Viewer does not change, while
        // picking a camo up off the ground updates it instantly with no save involved. So the
        // pickup path does more than set this byte, and we need that code.
        //
        // Rather than hunt for it, trap it. Mark the page read-only; any write raises an access
        // violation; the handler records the faulting instruction, lets the write through via a
        // single-step, then re-arms. Pick a camo up and the pickup handler names itself.
        //
        // The handler does NO logging or allocation - that risks deadlocking inside an exception
        // on an arbitrary thread. It only fills a fixed slot; on_update drains and prints.
        // Watch the WHOLE of chunk 1, not just the camo table. Camo pickups are rare in the
        // world, so gating the test on finding one is a bad instrument; items are everywhere.
        // Acquiring anything should land in this block, and camo acquisition is very likely the
        // same routine with a different table.
        constexpr size_t kChunk1Size = 0x32F0;   // from FUN_147ab0db0's first memcpy

        // The first run caught writes but nothing usable: the faulting instruction was
        // 0x7fffac39bc5b - outside the game module (0x7ff7a...), i.e. a memcpy in a system DLL -
        // and it filled ids 0,1,2,3... sequentially from that one instruction. That is a bulk
        // copy of the whole table, not a per-camo grant. So also record the CALLER: the first
        // return address on the stack that lands inside the game exe. And keep only DISTINCT
        // writers, so one memcpy loop cannot burn every slot.
        // Several callers, not one. The first attempt recorded only the first return address
        // inside the game module and landed on FUN_1415cab30 - the game's own TLS pooled
        // ALLOCATOR, whose memcpy was just growing the buffer. The code we actually want is
        // further up the stack, past the allocator frames.
        constexpr int kCallerDepth = 5;
        struct WatchHit
        {
            uintptr_t rip;
            uintptr_t callers[kCallerDepth];
            size_t    offset;
            bool      isRead;
        };

        static void*     g_veh         = nullptr;
        static uint8_t*  g_stateBase   = nullptr;   // offsets are always reported against this
        static uint8_t*  g_watchStart  = nullptr;
        static uint8_t*  g_watchEnd    = nullptr;
        static uint8_t*  g_pageStart   = nullptr;
        static size_t    g_pageSize    = 0;
        static uintptr_t g_moduleBase  = 0;
        static uintptr_t g_moduleEnd   = 0;
        static bool      g_armed       = false;
        static WatchHit  g_hits[64]{};
        // These two must reset on every Arm(). As function-statics inside DrainHits they did
        // not, so the second watch session printed only hits past the first session's count -
        // 10 of 11 hits from a real camo pickup were captured and never shown.
        static LONG      g_reported     = 0;
        static bool      g_saidDisarmed = false;
        // Read mode: guard with PAGE_NOACCESS so READS fault too. Used to answer a different
        // question - not "who grants a camo" but "does the Survival Viewer even consult this
        // table?" If it never reads it, no amount of writing here will ever work.
        static bool      g_watchReads   = false;
        // When the trap is pointed at the FPropData row buffer, the camo-table offset range is
        // meaningless - it mislabeled a row write as "CAMO id 7" and disarmed after 3 hits.
        static bool      g_camoRange    = true;
        static volatile LONG g_hitCount   = 0;   // writes that landed IN the table
        static volatile LONG g_faultCount = 0;   // all writes to the page, for runaway control
        static constexpr LONG kMaxHits   = 24;
        // Budget of page faults before the watch shuts itself off, so a runaway cannot make the
        // game unplayable. Per-arm, because it depends entirely on how hot the page is: the camo
        // base at player+0x2F88 shares its page with fields written about 7000 times a second, so
        // the old fixed 200000 was spent in twenty seconds - before the camo change we were
        // waiting for. Page protection is page-granular; there is no way to watch only the two
        // bytes we care about short of a hardware watchpoint.
        static constexpr LONG kDefaultMaxFaults = 200000;
        static LONG           g_maxFaults       = kDefaultMaxFaults;
        static volatile LONG  g_budgetSpent     = 0;   // set when the watch shut itself off

        static auto Disarm() -> void
        {
            if (!g_armed) { return; }
            g_armed = false;
            DWORD old = 0;
            VirtualProtect(g_pageStart, g_pageSize, PAGE_READWRITE, &old);
        }

        static LONG CALLBACK WatchHandler(EXCEPTION_POINTERS* info)
        {
            const DWORD code = info->ExceptionRecord->ExceptionCode;

            // Second half of the trap: the faulting write has now executed, so put the guard back.
            if (code == EXCEPTION_SINGLE_STEP && g_pageStart != nullptr)
            {
                if (g_armed)
                {
                    DWORD old = 0;
                    VirtualProtect(g_pageStart, g_pageSize,
                                   g_watchReads ? PAGE_NOACCESS : PAGE_READONLY, &old);
                }
                return EXCEPTION_CONTINUE_EXECUTION;
            }

            if (code != EXCEPTION_ACCESS_VIOLATION || !g_armed) { return EXCEPTION_CONTINUE_SEARCH; }
            if (info->ExceptionRecord->NumberParameters < 2) { return EXCEPTION_CONTINUE_SEARCH; }
            // 0 = read, 1 = write. In read mode we want both; otherwise writes only.
            const ULONG_PTR access = info->ExceptionRecord->ExceptionInformation[0];
            if (!g_watchReads && access != 1) { return EXCEPTION_CONTINUE_SEARCH; }
            if (access != 0 && access != 1) { return EXCEPTION_CONTINUE_SEARCH; }

            auto* addr = reinterpret_cast<uint8_t*>(info->ExceptionRecord->ExceptionInformation[1]);
            if (addr < g_pageStart || addr >= g_pageStart + g_pageSize) { return EXCEPTION_CONTINUE_SEARCH; }

            if (addr >= g_watchStart && addr < g_watchEnd)
            {
                const auto rip = static_cast<uintptr_t>(info->ContextRecord->Rip);

                // Walk the stack for the first return address inside the game module. When the
                // write comes from a CRT memcpy this is the only way to reach the game code that
                // asked for it.
                uintptr_t callers[kCallerDepth]{};
                int nCallers = 0;
                auto* sp = reinterpret_cast<uintptr_t*>(info->ContextRecord->Rsp);
                for (int i = 0; i < 256 && nCallers < kCallerDepth; ++i)
                {
                    const uintptr_t v = sp[i];
                    if (v < g_moduleBase || v >= g_moduleEnd) { continue; }
                    // Skip near-duplicates from the same call site being spilled twice.
                    if (nCallers > 0 && v == callers[nCallers - 1]) { continue; }
                    callers[nCallers++] = v;
                }
                const uintptr_t caller = callers[0];

                // Always relative to the state base, so read mode (which narrows g_watchStart to
                // the table) still reports comparable offsets.
                const size_t off = static_cast<size_t>(addr - g_stateBase);
                const bool inCamoTable = g_camoRange
                                      && off >= kTableOff && off < kTableOff + 2 * kFlagArrayIds;

                // Dedupe on the CALLER, not the instruction. This block is live game state and
                // is written constantly, so without this the slots fill with unrelated churn
                // before the pickup ever happens.
                bool seen = false;
                const LONG have = g_hitCount;
                for (LONG i = 0; i < have && i < static_cast<LONG>(std::size(g_hits)); ++i)
                {
                    const bool same = (caller != 0) ? (g_hits[i].callers[0] == caller)
                                                    : (g_hits[i].rip == rip);
                    // Always keep a camo-table write even if that caller was seen elsewhere.
                    if (same && !inCamoTable) { seen = true; break; }
                    if (same && g_hits[i].offset == off) { seen = true; break; }
                }

                if (!seen)
                {
                    const LONG slot = InterlockedIncrement(&g_hitCount) - 1;
                    if (slot < static_cast<LONG>(std::size(g_hits)))
                    {
                        g_hits[slot].rip    = rip;
                        g_hits[slot].offset = off;
                        g_hits[slot].isRead = (access == 0);
                        for (int c = 0; c < kCallerDepth; ++c) { g_hits[slot].callers[c] = callers[c]; }
                    }
                    // Write mode: stop as soon as we get what we came for - a write to the camo
                    // table. Do NOT stop merely on writer count; on live state that would disarm
                    // long before the player picks anything up.
                    // Read mode: every hit is in the table by construction, so stopping on the
                    // first would tell us nothing. Collect until the slots fill.
                    const bool done = g_watchReads
                        ? (slot + 1 >= static_cast<LONG>(std::size(g_hits)))
                        : (inCamoTable || slot + 1 >= static_cast<LONG>(std::size(g_hits)));
                    if (done) { g_armed = false; }
                }
            }

            if (InterlockedIncrement(&g_faultCount) >= g_maxFaults) { g_armed = false; g_budgetSpent = true; }

            // Let the write through, then re-arm on the single-step that follows.
            DWORD old = 0;
            VirtualProtect(g_pageStart, g_pageSize, PAGE_READWRITE, &old);
            info->ContextRecord->EFlags |= 0x100;   // TF - trap after the next instruction
            return EXCEPTION_CONTINUE_EXECUTION;
        }

        // Core: guard [start, end) and report anything that touches it.
        static auto ArmRange(uint8_t* base, uint8_t* start, uint8_t* end, bool watchReads) -> bool
        {
            Disarm();
            g_watchReads = watchReads;
            auto* mod = GetModuleHandleW(nullptr);
            g_moduleBase = reinterpret_cast<uintptr_t>(mod);
            g_moduleEnd  = g_moduleBase;
            if (mod != nullptr)
            {
                auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(mod);
                auto* nt  = reinterpret_cast<IMAGE_NT_HEADERS*>(
                                reinterpret_cast<uint8_t*>(mod) + dos->e_lfanew);
                g_moduleEnd = g_moduleBase + nt->OptionalHeader.SizeOfImage;
            }
            g_stateBase  = base;
            g_watchStart = start;
            g_watchEnd   = end;
            g_camoRange  = true;   // callers that are not the legacy state clear this
            g_hitCount   = 0;
            g_faultCount  = 0;
            g_budgetSpent = 0;
            g_maxFaults   = kDefaultMaxFaults;   // callers raise it after arming if their page is hot
            g_reported   = 0;   // must reset, or a second session prints almost nothing
            g_saidDisarmed = false;

            SYSTEM_INFO si{};
            GetSystemInfo(&si);
            const uintptr_t mask = ~static_cast<uintptr_t>(si.dwPageSize - 1);
            g_pageStart = reinterpret_cast<uint8_t*>(reinterpret_cast<uintptr_t>(g_watchStart) & mask);
            auto* endPage = reinterpret_cast<uint8_t*>(
                (reinterpret_cast<uintptr_t>(g_watchEnd) + si.dwPageSize - 1) & mask);
            g_pageSize = static_cast<size_t>(endPage - g_pageStart);

            if (g_veh == nullptr) { g_veh = AddVectoredExceptionHandler(1, WatchHandler); }
            if (g_veh == nullptr) { return false; }

            DWORD old = 0;
            if (!VirtualProtect(g_pageStart, g_pageSize,
                                watchReads ? PAGE_NOACCESS : PAGE_READONLY, &old)) { return false; }
            g_armed = true;
            return true;
        }

        // 'state' is the chunk-1 base, NOT the camo table. watchReads narrows to the camo table
        // and guards with PAGE_NOACCESS - reads are far noisier, and answer a narrower question.
        static auto Arm(uint8_t* state, bool watchReads = false) -> bool
        {
            return watchReads
                ? ArmRange(state, state + kTableOff, state + kTableOff + 2 * kFlagArrayIds, true)
                : ArmRange(state, state, state + kChunk1Size, false);
        }

        // Called from on_update so logging happens on a normal thread, never inside the handler.
        static auto DrainHits() -> void
        {
            LONG& reported = g_reported;
            const LONG have = g_hitCount;
            while (reported < have && reported < static_cast<LONG>(std::size(g_hits)))
            {
                const auto& h = g_hits[reported];
                const bool inCamoTable = h.offset >= kTableOff
                                      && h.offset <  kTableOff + 2 * kFlagArrayIds;
                const bool ripInGame = h.rip >= g_moduleBase && h.rip < g_moduleEnd;

                StringType what = inCamoTable
                    ? (StringType(h.isRead ? STR("READ CAMO id ") : STR("CAMO id "))
                       + std::to_wstring((h.offset - kTableOff) / 2))
                    : StringType(h.isRead ? STR("READ state") : STR("state"));

                // Only translate to a Ghidra address when the address really is in the game
                // module - otherwise the subtraction produces a meaningless number, which is
                // exactly what the first run printed.
                StringType chain;
                for (int c = 0; c < kCallerDepth; ++c)
                {
                    if (h.callers[c] == 0) { break; }
                    if (c) { chain += STR(" <- "); }
                    wchar_t b[24]{};
                    swprintf_s(b, L"0x%llx",
                               static_cast<unsigned long long>(h.callers[c] - g_moduleBase + kGhidraImageBase));
                    chain += b;
                }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][watch] {} +0x{:x} {} GHIDRA stack: {}\n"),
                    what, h.offset,
                    ripInGame ? STR("(direct)") : STR("(via memcpy)"),
                    chain.empty() ? StringType(STR("<none>")) : chain);
                ++reported;
            }
            // Heartbeat while armed. Without this, "nothing wrote to the table" and "the guard
            // is not firing at all" produce identical logs - which is exactly the ambiguity that
            // stalled the first two attempts. g_faultCount counts EVERY write to the page, so a
            // non-zero value proves the trap is live even when no camo write lands.
            if (g_armed)
            {
                static int tick = 0;
                if (++tick >= 200)
                {
                    tick = 0;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][watch] armed - {} page writes trapped, {} of them in the camo table\n"),
                        static_cast<long>(g_faultCount), static_cast<long>(g_hitCount));
                }
            }

            // Say so when the budget runs out. Previously this shut off in silence unless it had
            // caught something, so a watch that expired before the event we were waiting for
            // looked exactly like a watch that saw nothing - which is how a base-value trap was
            // read as "nothing wrote it" when it had actually stopped two minutes earlier.
            if (g_budgetSpent != 0)
            {
                g_budgetSpent = 0;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][watch] BUDGET SPENT after {} page writes - watch is OFF. ")
                    STR("Re-arm and do the thing you are watching for straight away.\n"),
                    static_cast<long>(g_faultCount));
            }

            // Same trap as g_reported: a function-static 'said' would fire once per process and
            // stay silent for every later session.
            if (!g_armed && reported > 0 && reported == have && !g_saidDisarmed)
            {
                g_saidDisarmed = true;
                Output::send<LogLevel::Warning>(STR("[ACF][watch] disarmed after {} hits.\n"), have);
            }
        }

        // -----------------------------------------------------------------------------------
        // Snapshot / diff
        // -----------------------------------------------------------------------------------
        //
        // Setting the ownership flag is provably not enough: a hand-written flag reads back
        // correctly and the Survival Viewer ignores it, while a real Rain Drop pickup sets the
        // SAME byte in the SAME block and the viewer updates instantly. So a grant touches more
        // than one field, and guessing which is a waste of time.
        //
        // Take a full copy of the live block, let the player acquire a camo, then diff. That
        // reports every byte a genuine grant changes - no searching, no rare-instruction hunt.
        static std::vector<uint8_t> g_snapshot;

        static auto Snap(uint8_t* state) -> void
        {
            g_snapshot.assign(state, state + kChunk1Size);
            Output::send<LogLevel::Warning>(
                STR("[ACF][snap] captured {} bytes of live state. Now acquire a camo, then run svdiff.\n"),
                static_cast<int>(g_snapshot.size()));
        }

        static auto Diff(uint8_t* state) -> void
        {
            if (g_snapshot.size() != kChunk1Size)
            {
                Output::send<LogLevel::Warning>(STR("[ACF][diff] no snapshot yet - run svsnap first.\n"));
                return;
            }

            int changed = 0;
            for (size_t i = 0; i < kChunk1Size; )
            {
                if (state[i] == g_snapshot[i]) { ++i; continue; }

                // Group contiguous changes so a multi-byte field reads as one line.
                const size_t start = i;
                while (i < kChunk1Size && state[i] != g_snapshot[i]) { ++i; }
                const size_t len = i - start;

                StringType before, after;
                for (size_t k = start; k < start + len && k < start + 12; ++k)
                {
                    wchar_t buf[8]{};
                    swprintf_s(buf, L"%02X ", g_snapshot[k]); before += buf;
                    swprintf_s(buf, L"%02X ", state[k]);      after  += buf;
                }

                const bool inCamoTable = start >= kTableOff && start < kTableOff + 2 * kFlagArrayIds;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][diff] {}+0x{:x} ({} bytes)  {} -> {}\n"),
                    inCamoTable ? STR("*CAMO* ") : STR(""), start, static_cast<int>(len), before, after);

                if (++changed >= 100)
                {
                    Output::send<LogLevel::Warning>(STR("[ACF][diff] ...stopping at 100 changed regions.\n"));
                    break;
                }
            }
            if (changed == 0) { Output::send<LogLevel::Warning>(STR("[ACF][diff] no changes.\n")); }
            else { Output::send<LogLevel::Warning>(STR("[ACF][diff] {} changed regions.\n"), changed); }
        }

        static auto Report(uint8_t* table) -> void
        {
            StringType owned;
            int count = 0;
            for (int id = 0; id < kFlagArrayIds; ++id)
            {
                if (*Entry(table, id) == 0) { continue; }
                if (count++) { owned += STR(","); }
                owned += std::to_wstring(id);
            }
            Output::send<LogLevel::Warning>(STR("[ACF]: legacy camo table @ {} - {} owned: {}\n"),
                                            static_cast<void*>(table), count, owned);
        }

        // value = 1 to grant, 0 to revoke. Revoking matters: ids 52 (BONSAI) and 53 (USMX) are
        // enum entries with no asset behind them, and selecting one is a hard crash, so anything
        // that sets them needs a way to unset them.
        // Returns how many entries actually changed, so a no-op is distinguishable from a hit.
        static auto Unlock(const int* ids, size_t count, uint16_t value = 1) -> int
        {
            // Write the REAL store when we have it. The table this namespace resolves is a
            // mirror that FUN_147a7cf60 rebuilds from that store whenever the Survival Viewer
            // opens, so writing the mirror is always undone.
            if (LiveStore::g_state != 0)
            {
                LiveStore::ReportOnce();
                int changed = 0;
                for (size_t k = 0; k < count; ++k)
                {
                    auto* f = LiveStore::Flag(ids[k]);
                    if (f == nullptr || *f == value) { continue; }
                    *f = value;
                    ++changed;
                    Output::send<LogLevel::Warning>(STR("[ACF][live]   camo id {} -> {}\n"), ids[k], value);
                }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][live] {} changed in the REAL store. Open the Survival Viewer.\n"), changed);
                return changed;
            }

            // Not captured yet: queue it. The hook applies it the moment the Survival Viewer
            // opens, BEFORE the refresh runs, so one command plus one menu open is enough. The
            // old behavior - "open the viewer, run it, reopen" - was a bad interface and the
            // ordering is not something anyone should have to know.
            LiveStore::g_pending.assign(ids, ids + count);
            LiveStore::g_pendingValue = value;
            Output::send<LogLevel::Warning>(
                STR("[ACF]: queued {} camo(s) - they will be applied when you open the Survival Viewer.\n"),
                static_cast<int>(count));
            return 0;

            // Resolved every time rather than cached: the pointer is only valid once a save is
            // loaded, and it can move between loads.
            g_table = Resolve();
            if (g_table == nullptr) { return -1; }
            Report(g_table);

            int changed = 0;
            for (size_t k = 0; k < count; ++k)
            {
                const int id = ids[k];
                if (id < 0 || id >= kFlagArrayIds) { continue; }
                if (*Entry(g_table, id) == value) { continue; }
                *Entry(g_table, id) = value;
                ++changed;
                Output::send<LogLevel::Warning>(STR("[ACF]:   unlocked camo id {}\n"), id);
            }
            Output::send<LogLevel::Warning>(STR("[ACF]: {} newly unlocked. Open the Survival Viewer, then SAVE to persist.\n"), changed);
            return changed;
        }
    }


    // -----------------------------------------------------------------------------------------
    // The camouflage index itself - contributing a base the way a real camo does
    // -----------------------------------------------------------------------------------------
    //
    // Found from the MGS3-Delta-Trainer's "calcuateCamoIndexOffset" signature. FUN_147ACEC00, in
    // the legacy layer beside the data dispatcher:
    //
    //     iVar2 = FUN_147a9d010(*(short*)(param_1+0x2f88) + *(int*)(param_1+0x820c), f);
    //     (&DAT_1535c2064)[player * 0x58] = iVar2;
    //
    // DAT_1535C2064 is CONFIRMED to be the live index, not another copy: it reads -1000 while
    // wearing Gold (-100%) and moves with stance, terrain and grass exactly as the HUD does.
    // Values are percentage x10. param_1 is the player object, NOT the save state ACF already
    // owns - the base at +0x2F88 reads 0 through that pointer.
    //
    // The point of detouring rather than writing the value on a timer: the original runs first and
    // computes everything normally, then the author's base is ADDED to the result. Every modifier
    // the game applies still applies. That is the difference between giving a slot a real camo
    // value and pinning a number on the HUD that gameplay does not honour.
    namespace CamoIndex
    {

        constexpr int       kFirstSlot    = 61;
        constexpr int       kLastSlot     = 64;

        static int32_t   g_want[4]{};
        static bool      g_has[4]{};


        // The game's own per-camo table, from FUN_147A9D010:
        //
        //     entry = &DAT_1545218e0 + uniformId * 3;        // 3 qwords, 0x18 bytes per entry
        //     values = entry[1];                             // -> per-background bytes, 5 per type
        //     index += *(char*)(values + backgroundType * 5) * 10;
        //     index += *(char*)((char*)entry + 0x16) * 10;   // flat, environment-independent
        //
        // The byte at +0x16 is a per-camo bonus applied whatever the background is, which is
        // exactly what an author's Camo= value means. Writing it would put the value in the
        // game's own data instead of adding to the result afterwards.
        //
        // Gold is NOT in this table - FUN_147A9D010 special-cases id 59 ("';'") to -1000 in code,
        // which is why every search for -100 as table data came up empty.
        //
        // Equipped ids live at PTR_DAT_14c532038[0x7AE] (uniform) and [0x7AF] (facepaint).
        constexpr uintptr_t kGhidraUniformTable = 0x1545218E0;
        constexpr size_t    kEntryStride        = 0x18;
        constexpr size_t    kFlatByteOffset     = 0x16;

        // The 27 background types, in EGsrMgs3CamoufType order. This is the INNER index of a
        // camo's value block - what you are standing against, not what you are wearing.
        static const wchar_t* kBackgrounds[] = {
            STR("NO_CAMOUFLAGE"), STR("ROOM_NO_CAMOUFLAGE"), STR("WATER"), STR("MOSS"),
            STR("BLACK"), STR("GRAY"), STR("SOIL_BROWN"), STR("WOOD"), STR("OBJ_BROWN"),
            STR("OBJ_RED"), STR("OBJ_OLIVEGREEN"), STR("GRASS"), STR("LEAF"), STR("SOIL_BEIGE"),
            STR("OBJ_BEIGE"), STR("WOOD_GREEN"), STR("WHITE"), STR("ROOM_GRAY"), STR("ROOM_WOOD"),
            STR("ROOM_BLACK"), STR("ROOM_BROWN"), STR("ROOM_RED"), STR("ROOM_ORANGE"),
            STR("ROOM_OLIVE"), STR("ROOM_BEIGE"), STR("ROOM_WHITE"), STR("ROOM_BLUE"),
        };
        constexpr int kBackgroundCount = 27;
        constexpr int kVariantsPerBackground = 5;   // stance/state; already handled by the game

        // Per-terrain values.
        //
        // The metadata key for each of the 27 terrains, in EGsrMgs3CamoufType order. The two
        // "no camouflage" entries are deliberately null: they are the game's "nothing matches
        // here" defaults and are not something an author should be setting.
        static const wchar_t* kTerrainKeys[kBackgroundCount] = {
            nullptr,                    // 0  NO_CAMOUFLAGE
            nullptr,                    // 1  ROOM_NO_CAMOUFLAGE
            STR("CamoWater"),           // 2
            STR("CamoMoss"),            // 3
            STR("CamoBlack"),           // 4
            STR("CamoGray"),            // 5
            STR("CamoSoilBrown"),       // 6
            STR("CamoWood"),            // 7
            STR("CamoObjBrown"),        // 8
            STR("CamoObjRed"),          // 9
            STR("CamoObjOliveGreen"),   // 10
            STR("CamoGrass"),           // 11
            STR("CamoLeaf"),            // 12
            STR("CamoSoilBeige"),       // 13
            STR("CamoObjBeige"),        // 14
            STR("CamoWoodGreen"),       // 15
            STR("CamoWhite"),           // 16
            STR("CamoRoomGray"),        // 17
            STR("CamoRoomWood"),        // 18
            STR("CamoRoomBlack"),       // 19
            STR("CamoRoomBrown"),       // 20
            STR("CamoRoomRed"),         // 21
            STR("CamoRoomOrange"),      // 22
            STR("CamoRoomOlive"),       // 23
            STR("CamoRoomBeige"),       // 24
            STR("CamoRoomWhite"),       // 25
            STR("CamoRoomBlue"),        // 26
        };

        constexpr size_t kValuesPtrOffset = 8;                                    // entry[1]
        constexpr size_t kBlockSize = kBackgroundCount * kVariantsPerBackground;  // 27 * 5 = 135

        // STATIC storage, one block per slot, never freed. The game will hold a pointer to this
        // for the rest of the session, so it must outlive everything - a heap allocation we could
        // lose track of, or anything with a destructor, would be a dangling pointer waiting to
        // happen. 540 bytes total is not worth being clever about.
        static int8_t g_block[4][kBlockSize];
        static bool   g_hasBlock[4];
        static int    g_terrainCount[4];
        static std::vector<StringType> g_terrainErrors[4];

        // Parse "35, 50, 80, 55, 60" or a single "35". Returns how many values were read, or 0 if
        // the line is not usable. A single value fills all five columns.
        static auto ParseTerrainLine(const StringType& text, int8_t out[kVariantsPerBackground]) -> int
        {
            int count = 0;
            const wchar_t* p = text.c_str();
            while (*p != L'\0' && count < kVariantsPerBackground)
            {
                while (*p == L' ' || *p == L'\t' || *p == L',') { ++p; }
                if (*p == L'\0') { break; }

                wchar_t* end = nullptr;
                const long v = std::wcstol(p, &end, 10);
                if (end == p) { return 0; }                       // not a number - reject the line
                if (v < -128 || v > 127) { return -1; }           // out of signed-byte range
                out[count++] = static_cast<int8_t>(v);
                p = end;
            }
            if (count == 0) { return 0; }
            if (count == 1)
            {
                // Single value: same in every stance. Simpler for the author, but it means going
                // prone gains nothing on that surface, which the template warns about.
                for (int i = 1; i < kVariantsPerBackground; ++i) { out[i] = out[0]; }
                count = kVariantsPerBackground;
            }
            return count;
        }

        // Build each slot's block from its metadata file. Called once, at install.
        static auto LoadTerrainValues() -> void
        {
            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                const int slot = id - kFirstSlot;
                int terrainsSet = 0;

                for (int t = 0; t < kBackgroundCount; ++t)
                {
                    if (kTerrainKeys[t] == nullptr) { continue; }
                    const StringType line = SlotMeta::Read(id, kTerrainKeys[t]);
                    if (line.empty()) { continue; }

                    int8_t v[kVariantsPerBackground]{};
                    const int n = ParseTerrainLine(line, v);
                    if (n <= 0)
                    {
                        // Say so rather than silently ignoring it - a typo in one line should not
                        // look identical to deliberately leaving the surface alone.
                        const StringType why = (n == 0)
                            ? StringType(STR("expected 1 or 5 numbers"))
                            : StringType(STR("value outside -128..127"));
                        Output::send<LogLevel::Warning>(
                            STR("[ACF][terrain] slot {} '{}' could not be read ('{}') - {}\n"),
                            id, kTerrainKeys[t], line, why);
                        g_terrainErrors[slot].push_back(StringType(kTerrainKeys[t]) + STR(": ") + why);
                        continue;
                    }

                    for (int c = 0; c < kVariantsPerBackground; ++c)
                    {
                        g_block[slot][t * kVariantsPerBackground + c] = v[c];
                    }
                    ++terrainsSet;
                }

                g_hasBlock[slot] = (terrainsSet > 0);
                g_terrainCount[slot] = terrainsSet;
                if (terrainsSet > 0)
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][terrain] slot {} has values for {} surface(s)\n"), id, terrainsSet);
                }
            }

            // Publish for acfslots. A separate file rather than appending to the resolved-slots
            // one, because that is written elsewhere and truncates - relying on which runs first
            // is the kind of ordering assumption that already bit this project once.
            std::wofstream out(L"ACF Logs\\acf_terrain_resolved.txt", std::ios::trunc);
            if (!out.is_open()) { return; }
            out << L"; Generated by ACF. Per-terrain values found per slot, and any lines that\n"
                << L"; could not be read. Edit ACF_Slot<ID>.txt instead - this file is overwritten.\n";
            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                const int slot = id - kFirstSlot;
                out << id << L"|count|" << g_terrainCount[slot] << L"\n";
                for (const auto& e : g_terrainErrors[slot]) { out << id << L"|error|" << e << L"\n"; }
            }
        }

        // Put the author's value into the game's own table.
        //
        // The dump showed ACF's ids 61-64 are not missing from the table - they are ALIASED to the
        // same value block as id 58, which is the all-zero one, which is exactly why they conceal
        // like Naked. Every vanilla camo has flat=0 at entry+0x16, so that byte is unused and the
        // calculator adds it unconditionally: index += *(char*)(entry + 0x16) * 10.
        //
        // Writing one signed byte per slot therefore expresses the author's value as game data
        // rather than as an adjustment bolted onto the result. It is also the only version that
        // could correct the Survival Viewer's row number, since that column is derived from the
        // game's own figures.
        //
        // Re-applied on a timer: cheap (four byte compares) and survives the table being
        // reinitialized on load.
        static auto ApplyTable() -> void
        {
            static int tick = 0;
            if (++tick < 30) { return; }
            tick = 0;

            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            auto* table = reinterpret_cast<uint8_t*>(
                moduleBase + (kGhidraUniformTable - 0x140000000ull));

            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                const int slot = id - kFirstSlot;
                auto* entry = table + kEntryStride * static_cast<size_t>(id);

                // BaseCamo -> the flat byte, added whatever the terrain.
                if (g_has[slot])
                {
                    const auto wanted = static_cast<int8_t>(g_want[slot]);
                    auto* flat = entry + kFlatByteOffset;
                    uint8_t current = 0;
                    if (LiveStore::ReadByte(flat, &current) && static_cast<int8_t>(current) != wanted)
                    {
                        DWORD old = 0;
                        if (VirtualProtect(flat, 1, PAGE_READWRITE, &old) != 0)
                        {
                            *flat = static_cast<uint8_t>(wanted);
                            VirtualProtect(flat, 1, old, &old);

                            static bool announced[4]{};
                            if (!announced[slot])
                            {
                                announced[slot] = true;
                                Output::send<LogLevel::Warning>(
                                    STR("[ACF][table] camo {} flat value set to {}\n"), id, wanted);
                            }
                        }
                    }
                }

                // Per-terrain values -> point entry[1] at our own block.
                //
                // ACF's slots ship ALIASED to id 58's all-zero block, so this displaces nothing of
                // the game's - we are giving the slot the row it never had. Handled separately
                // from the flat byte because a file may set terrain values and no BaseCamo, or the
                // other way round.
                if (g_hasBlock[slot])
                {
                    auto* ptrField = entry + kValuesPtrOffset;
                    uint64_t current = 0;
                    bool ok = true;
                    for (int b = 0; b < 8 && ok; ++b)
                    {
                        uint8_t v = 0;
                        ok = LiveStore::ReadByte(ptrField + b, &v);
                        current |= static_cast<uint64_t>(v) << (8 * b);
                    }
                    const auto wanted = reinterpret_cast<uint64_t>(&g_block[slot][0]);
                    if (ok && current != wanted)
                    {
                        DWORD old = 0;
                        if (VirtualProtect(ptrField, sizeof(uint64_t), PAGE_READWRITE, &old) != 0)
                        {
                            *reinterpret_cast<uint64_t*>(ptrField) = wanted;
                            VirtualProtect(ptrField, sizeof(uint64_t), old, &old);

                            static bool announcedBlock[4]{};
                            if (!announcedBlock[slot])
                            {
                                announcedBlock[slot] = true;
                                Output::send<LogLevel::Warning>(
                                    STR("[ACF][table] camo {} now uses ACF's own per-terrain block\n"), id);
                            }
                        }
                    }
                }
            }
        }


        // Dump ONE camo's value block, the row behind a camo in the grid.
        //
        // FUN_147A9D010 reads it as *(char*)(entry[1] + backgroundType * 5), so the block should be
        // 27 * 5 = 135 signed bytes. Printing all five variants per background rather than assuming
        // which is which: if the five differ, that is the stance spread; if a background's five are
        // identical, the game does not vary it by stance there.
        //
        // Verification, not decoration - Tiger Stripe (id 1) should read positive on GRASS, LEAF,
        // WOOD and the SOILs and negative on WHITE and the ROOM_* set, matching its own in-game
        // description. If the shape is wrong, the layout assumption is wrong.
        // Which of the five per-terrain columns the game is currently reading.
        //
        // FUN_147A9D010 stores the chosen index here right after picking it:
        //     group A (state 0x3b clear): col 2 if state 3 and not 0xa9, else state 2 ? 1 : 0
        //     group B (state 0x3b set)  : state 2 ? 4 : 3
        // The same state (2) splits both pairs, which is why 0/1 and 3/4 look like the same
        // posture distinction with and without something else applied.
        //
        // Logging it while the player changes posture maps each column to a real stance, so the
        // modder template can say what a value actually means instead of guessing.
        constexpr uintptr_t kGhidraColumnIndex = 0x1535BFBB0;

        static bool g_watchColumn = false;
        static int  g_columnTick  = 0;
        static int  g_columnLines = 0;

        // Everything FUN_147A9D010 uses, read live, so the arithmetic can be watched rather than
        // reasoned about. All of these are globals it writes as it goes:
        //     0x1535BFB84  the terrain index actually in use (0-26, after FUN_147a9db30 maps the
        //                  raw surface id to a background type)
        //     0x1535BFBB0  the stance column (0-4)
        //     0x1535BFB70  the finished camouflage index, percentage x10
        // and the equipped uniform id is PTR_DAT_14c532038[0x7AE].
        //
        // Printing the raw table byte for [terrain][column] beside the final number shows how the
        // game composes them - which settles whether an author's per-terrain value should add to
        // BaseCamo or replace it, by observation instead of preference.
        constexpr uintptr_t kGhidraTerrainIdx = 0x1535BFB84;
        constexpr uintptr_t kGhidraFinalIndex = 0x1535BFB70;
        constexpr uintptr_t kGhidraStatePtr   = 0x14C532038;
        constexpr size_t    kEquippedUniform  = 0x7AE;

        // --- ammowatch -------------------------------------------------------------------------
        //
        // Infinite ammo could work two ways that look identical in the HUD: the consume never runs,
        // or it runs and something puts the round back. Static reading cannot tell them apart -
        // watching the number can, and that decides whether ACF would need to suppress a call or
        // simply write a value.
        //
        // The legacy weapon array, from FUN_147A7C530 (inventory.c):
        //     DAT_1535B7D20, stride 0x58, ids 0..0x82, +0x00 stock, +0x04 loaded
        // Current weapon id is mirrored for the HUD at PTR_DAT_14c532038 + 0x704, so the watch
        // follows whatever is equipped instead of needing an id up front.
        //
        // Sampled every tick, NOT throttled like the camo poll: a refill that happens in the same
        // frame as the decrement is exactly the case worth catching, and a slow sample would miss
        // it and look like "the ammo never moved".
        constexpr uintptr_t kGhidraWeaponArray = 0x1535B7D20;
        constexpr size_t    kWeaponStride      = 0x58;
        constexpr size_t    kCurWeaponIdMirror = 0x704;

        static bool g_watchAmmo  = false;
        static int  g_ammoLines  = 0;

        static auto ReadInt16(const void* addr, int16_t* out) -> bool
        {
            uint8_t lo = 0, hi = 0;
            if (!LiveStore::ReadByte(addr, &lo)) { return false; }
            if (!LiveStore::ReadByte(static_cast<const uint8_t*>(addr) + 1, &hi)) { return false; }
            *out = static_cast<int16_t>(static_cast<uint16_t>(lo) | (static_cast<uint16_t>(hi) << 8));
            return true;
        }

        static auto PollAmmo() -> void
        {
            if (!g_watchAmmo) { return; }
            if (g_ammoLines >= 400) { g_watchAmmo = false; return; }

            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            const auto at = [&](uintptr_t ghidra) { return moduleBase + (ghidra - 0x140000000ull); };

            auto* statePtr = *reinterpret_cast<uint8_t**>(at(kGhidraStatePtr));
            if (statePtr == nullptr) { return; }

            int16_t weaponId = 0;
            if (!ReadInt16(statePtr + kCurWeaponIdMirror, &weaponId)) { return; }
            if (weaponId < 0 || weaponId > 0x82) { return; }

            auto* entry = reinterpret_cast<uint8_t*>(at(kGhidraWeaponArray))
                        + kWeaponStride * static_cast<size_t>(weaponId);

            int16_t stock = 0, loaded = 0;
            if (!ReadInt16(entry, &stock)) { return; }
            if (!ReadInt16(entry + 4, &loaded)) { return; }

            uint8_t camoRaw = 0, faceRaw = 0;
            LiveStore::ReadByte(statePtr + kEquippedUniform, &camoRaw);
            LiveStore::ReadByte(statePtr + kEquippedUniform + 1, &faceRaw);

            static int16_t lastW = -1, lastS = -1, lastL = -1;
            static uint8_t lastC = 0xFF, lastF = 0xFF;
            if (weaponId == lastW && stock == lastS && loaded == lastL
                && camoRaw == lastC && faceRaw == lastF)
            {
                return;
            }

            // Show the delta, because "went 8 -> 7 -> 8 within a few frames" is a refill and
            // "stayed at 8" is a suppressed consume, and only the sign of the change separates them.
            const int dStock  = (lastW == weaponId && lastS >= 0) ? (stock  - lastS) : 0;
            const int dLoaded = (lastW == weaponId && lastL >= 0) ? (loaded - lastL) : 0;

            lastW = weaponId; lastS = stock; lastL = loaded; lastC = camoRaw; lastF = faceRaw;
            ++g_ammoLines;

            Output::send<LogLevel::Warning>(
                STR("[ACF][ammo] weapon {:>3}  stock {:>4} ({:+d})  loaded {:>4} ({:+d})   camo {}  face {}\n"),
                static_cast<int>(weaponId),
                static_cast<int>(stock), dStock,
                static_cast<int>(loaded), dLoaded,
                static_cast<int>(static_cast<int8_t>(camoRaw)),
                static_cast<int>(static_cast<int8_t>(faceRaw)));
        }

        static auto PollLive() -> void
        {
            if (!g_watchColumn) { return; }
            if (++g_columnTick < 15) { return; }
            g_columnTick = 0;
            if (g_columnLines >= 200) { g_watchColumn = false; return; }

            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            const auto at = [&](uintptr_t ghidra) { return moduleBase + (ghidra - 0x140000000ull); };

            int32_t terrain = 0, column = 0, final = 0;
            if (!LiveStore::ReadInt32(reinterpret_cast<const void*>(at(kGhidraTerrainIdx)), &terrain)) { return; }
            if (!LiveStore::ReadInt32(reinterpret_cast<const void*>(at(kGhidraColumnIndex)), &column)) { return; }
            if (!LiveStore::ReadInt32(reinterpret_cast<const void*>(at(kGhidraFinalIndex)), &final)) { return; }

            // Equipped uniform, straight out of the legacy state - no UObject search on this path.
            int32_t camo = -1;
            auto* statePtr = *reinterpret_cast<uint8_t**>(at(kGhidraStatePtr));
            if (statePtr != nullptr)
            {
                uint8_t raw = 0;
                if (LiveStore::ReadByte(statePtr + kEquippedUniform, &raw)) { camo = static_cast<int8_t>(raw); }
            }

            // Only report when the situation changes, not every tick.
            static int32_t lastT = -999, lastC = -999, lastCamo = -999;
            if (terrain == lastT && column == lastC && camo == lastCamo) { return; }
            lastT = terrain; lastC = column; lastCamo = camo;
            ++g_columnLines;

            // The table cell the game just read, and the flat byte, so the sum is visible.
            int cell = 0, flat = 0;
            if (camo >= 0 && camo <= 69 && terrain >= 0 && terrain < kBackgroundCount && column >= 0 && column < 5)
            {
                auto* entry = reinterpret_cast<uint8_t*>(at(kGhidraUniformTable)) + kEntryStride * static_cast<size_t>(camo);
                uint64_t valuesPtr = 0;
                bool ok = true;
                for (int b = 0; b < 8 && ok; ++b)
                {
                    uint8_t v = 0;
                    ok = LiveStore::ReadByte(entry + 8 + b, &v);
                    valuesPtr |= static_cast<uint64_t>(v) << (8 * b);
                }
                uint8_t fb = 0;
                if (ok && LiveStore::ReadByte(entry + kFlatByteOffset, &fb)) { flat = static_cast<int8_t>(fb); }
                if (ok && valuesPtr != 0)
                {
                    uint8_t raw = 0;
                    if (LiveStore::ReadByte(reinterpret_cast<const uint8_t*>(valuesPtr) + terrain * 5 + column, &raw))
                    {
                        cell = static_cast<int8_t>(raw);
                    }
                }
            }

            const wchar_t* tname = (terrain >= 0 && terrain < kBackgroundCount) ? kBackgrounds[terrain] : STR("?");
            Output::send<LogLevel::Warning>(
                STR("[ACF][live] camo {:>2} terrain {:>2} {:<18} col {}  cell {:>4} (x10 = {:>5})  flat {:>4}  FINAL {:>5} ({}%)\n"),
                camo, terrain, tname, column, cell, cell * 10, flat, final, final / 10);
        }

        static auto PollColumn() -> void
        {
            if (!g_watchColumn) { return; }
            if (++g_columnTick < 15) { return; }   // a few times a second
            g_columnTick = 0;
            if (g_columnLines >= 120) { g_watchColumn = false; return; }

            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            int32_t col = 0;
            if (!LiveStore::ReadInt32(
                    reinterpret_cast<const void*>(moduleBase + (kGhidraColumnIndex - 0x140000000ull)),
                    &col))
            {
                g_watchColumn = false;
                return;
            }

            // Only report changes - holding a stance would otherwise flood the log.
            static int32_t last = -999;
            if (col == last) { return; }
            last = col;
            ++g_columnLines;

            static const wchar_t* kGuess[] = {
                STR("standing?"), STR("crouching?"), STR("prone?"),
                STR("wall, standing?"), STR("wall, crouching?"),
            };
            const wchar_t* guess = (col >= 0 && col < 5) ? kGuess[col] : STR("?");
            Output::send<LogLevel::Warning>(
                STR("[ACF][col] column {}  ({})\n"), col, guess);
        }

        static auto DumpCamoRow(int id) -> void
        {
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            auto* entry = reinterpret_cast<uint8_t*>(
                moduleBase + (kGhidraUniformTable - 0x140000000ull)) + kEntryStride * static_cast<size_t>(id);

            uint64_t valuesPtr = 0;
            for (int b = 0; b < 8; ++b)
            {
                uint8_t v = 0;
                if (!LiveStore::ReadByte(entry + 8 + b, &v)) { return; }
                valuesPtr |= static_cast<uint64_t>(v) << (8 * b);
            }
            uint8_t flat = 0;
            LiveStore::ReadByte(entry + kFlatByteOffset, &flat);

            Output::send<LogLevel::Warning>(
                STR("[ACF][row] camo {} - values at 0x{:X}, flat {}\n"),
                id, valuesPtr, static_cast<int>(static_cast<int8_t>(flat)));

            // The whole 0x18-byte entry, because only +0x08 and +0x16 have ever been identified.
            // If per-uniform stats live as data anywhere, the unexamined bytes next to the values
            // pointer are the first place to look - that is how the value block itself was found.
            // Compare a camo with an ability (18 Spider, 12 Sneaking) against one without (1).
            {
                uint8_t raw[kEntryStride]{};
                bool ok = true;
                for (size_t b = 0; b < kEntryStride && ok; ++b)
                {
                    ok = LiveStore::ReadByte(entry + b, &raw[b]);
                }
                if (ok)
                {
                    StringType hex;
                    for (size_t b = 0; b < kEntryStride; ++b)
                    {
                        if (b != 0 && (b % 8) == 0) { hex += STR(" |"); }
                        wchar_t byteText[8]{};
                        std::swprintf(byteText, 8, L" %02X", static_cast<unsigned>(raw[b]));
                        for (const wchar_t* p = byteText; *p != L'\0'; ++p)
                        {
                            hex += static_cast<StringType::value_type>(*p);
                        }
                    }
                    Output::send<LogLevel::Warning>(STR("[ACF][row]   bytes:{}\n"), hex);

                    uint64_t word0 = 0;
                    for (int b = 7; b >= 0; --b) { word0 = (word0 << 8) | raw[b]; }
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][row]   +0x00 = 0x{:X}{}\n"),
                        word0,
                        (word0 > 0x10000 && word0 < 0x7FFFFFFFFFFFull)
                            ? STR("  (looks like a pointer)") : STR(""));

                    // Spacing between entries is uneven (~19-25 bytes), which is the shape of
                    // packed strings rather than a fixed-stride struct. Read it as text to settle
                    // that, instead of concluding it from the arithmetic.
                    if (word0 > 0x10000 && word0 < 0x7FFFFFFFFFFFull)
                    {
                        StringType text;
                        bool printable = true;
                        auto* p = reinterpret_cast<const uint8_t*>(word0);
                        for (int b = 0; b < 40; ++b)
                        {
                            uint8_t c = 0;
                            if (!LiveStore::ReadByte(p + b, &c)) { break; }
                            if (c == 0) { break; }
                            if (c < 0x20 || c > 0x7E) { printable = false; break; }
                            text += static_cast<StringType::value_type>(c);
                        }
                        if (printable && !text.empty())
                        {
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][row]   +0x00 reads as text: \"{}\"\n"), text);
                        }
                        else
                        {
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][row]   +0x00 is not a string - points at binary data\n"));
                        }
                    }
                }
            }

            if (valuesPtr == 0)
            {
                Output::send<LogLevel::Warning>(STR("[ACF][row]   no value block (null pointer)\n"));
                return;
            }

            auto* values = reinterpret_cast<const uint8_t*>(valuesPtr);
            for (int bg = 0; bg < kBackgroundCount; ++bg)
            {
                int8_t v[kVariantsPerBackground]{};
                bool ok = true;
                for (int s = 0; s < kVariantsPerBackground && ok; ++s)
                {
                    uint8_t raw = 0;
                    ok = LiveStore::ReadByte(values + bg * kVariantsPerBackground + s, &raw);
                    v[s] = static_cast<int8_t>(raw);
                }
                if (!ok)
                {
                    Output::send<LogLevel::Warning>(STR("[ACF][row]   unreadable at background {}\n"), bg);
                    return;
                }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][row]   {:>2} {:<20} {:>4} {:>4} {:>4} {:>4} {:>4}\n"),
                    bg, kBackgrounds[bg], v[0], v[1], v[2], v[3], v[4]);
            }
        }

        static auto DumpTable() -> void
        {
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            auto* table = reinterpret_cast<uint8_t*>(
                moduleBase + (kGhidraUniformTable - 0x140000000ull));

            Output::send<LogLevel::Warning>(
                STR("[ACF][table] uniform table at 0x{:X} (ghidra 0x{:X})\n"),
                reinterpret_cast<uint64_t>(table),
                static_cast<uint64_t>(kGhidraUniformTable));

            // Checked against values known from elsewhere before anything is written: Olive Drab
            // 10, Tiger Stripe 30, Naked 0, Crocodile 20, Naked Woodland 45. If those line up the
            // table is real; if they do not, this is another copy and it gets abandoned.
            for (int id = 0; id <= 70; ++id)
            {
                auto* entry = table + kEntryStride * static_cast<size_t>(id);
                uint64_t values = 0;
                uint8_t flat = 0;
                bool ok = true;
                for (int b = 0; b < 8 && ok; ++b)
                {
                    uint8_t v = 0;
                    ok = LiveStore::ReadByte(entry + 8 + b, &v);
                    values |= static_cast<uint64_t>(v) << (8 * b);
                }
                if (!ok || !LiveStore::ReadByte(entry + kFlatByteOffset, &flat)) { continue; }

                // Only print entries that have something in them, so the list stays readable.
                if (values == 0 && flat == 0) { continue; }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][table]   id {:>2}  values=0x{:X}  flat={}\n"),
                    id, values, static_cast<int>(static_cast<int8_t>(flat)));
            }
        }

        static auto Install() -> void
        {
            static bool tried = false;
            if (tried) { return; }
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }
            tried = true;

            int have = 0;
            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                // BaseCamo, not Camo. The modder template names the flat value BaseCamo to keep it
                // distinct from the per-terrain CamoWater/CamoGrass/CamoRoomBlue family it also
                // lists. There is deliberately NO fallback to the old key: a silent mismatch here
                // is exactly the failure the rename is meant to prevent.
                const StringType camo = SlotMeta::Read(id, STR("BaseCamo"));
                if (camo.empty()) { continue; }
                wchar_t* end = nullptr;
                const long v = std::wcstol(camo.c_str(), &end, 10);
                if (end == camo.c_str()) { continue; }
                g_want[id - kFirstSlot] = static_cast<int32_t>(v);
                g_has[id - kFirstSlot]  = true;
                ++have;
            }
            // Per-terrain values are independent of BaseCamo - a file may set either, both or
            // neither - so this runs regardless of what the loop above found.
            LoadTerrainValues();
            int haveBlocks = 0;
            for (bool b : g_hasBlock) { if (b) { ++haveBlocks; } }

            if (have == 0 && haveBlocks == 0)
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF][index] no slot supplied camouflage values - leaving concealment alone.\n"));
                return;
            }

            // The detour on FUN_147ACEC00 that used to add the value here is retired and archived
            // in docs/retired_cpp_diagnostics.txt. ApplyTable writes the value into the game's own
            // per-camo table instead, which is better data AND keeps ACF out of the per-frame
            // camouflage update entirely.

            Output::send<LogLevel::Warning>(
                STR("[ACF][index] applying camouflage values - {} slot(s) with BaseCamo, {} with per-terrain\n"),
                have, haveBlocks);
        }


    }

    // -----------------------------------------------------------------------------------------
    // Survival Viewer descriptions for ACF's slots
    // -----------------------------------------------------------------------------------------
    //
    // The viewer's description comes from FUN_145289f40, a free function:
    //
    //     FString* GetCaptionExplainText(FString* out, char tabType, int index)
    //
    // For tabType 1 (Uniform) it does NOT look the text up by data. It builds a localisation key
    // from the id with a hardcoded switch - namespace "ユニフォーム説明リソース" plus a suffix -
    // and resolves it with an EMPTY fallback:
    //
    //     id 0x3C (60) -> "-AdditionalUniform1"   (Crocodile Suit, the last vanilla one)
    //     id 0x3D (61) -> "-AdditionalUniform2"   ACF slot 1
    //     id 0x3E (62) -> "-AdditionalUniform3"   ACF slot 2
    //     id 0x3F (63) -> "-AdditionalUniform4"   ACF slot 3
    //     id 0x40 (64) -> "-AdditionalUniform5"   ACF slot 4
    //
    // Those four keys are well-formed but have no entry in the loc data, which is why the viewer
    // shows nothing. It also explains why ids 34-51 all share one description: they collapse onto
    // a single "-Download" key.
    //
    // The trick that solved row NAMES cannot work here. That one relies on writing the key
    // ourselves into Mgs3UniformCobraUiKeyMap; this key is built by the game from a constant.
    // Adding the missing loc entries is blocked by the usual limitation - a new row needs a new
    // FName in a zen package's local name map, which retoc cannot add.
    //
    // So answer the call instead. For ACF's four ids with a Description in the author's metadata,
    // return that text and never consult localisation; everything else goes to the original.
    //
    // Detoured rather than hooked through UE4SS: a UE4SS hook on the UFunction fires only for
    // calls made from Lua and never once while the menu draws, proving the widget reaches the
    // native function directly. See the ACF_Str/svcap probes in main.lua for that experiment.
    // Infinite ammo for an ACF slot, through the game's own path.
    //
    // FUN_147AD5960(equipId) is the whole mechanism: it picks how much a shot costs, then calls the
    // decrement with that amount. Both vanilla sources are hardcoded id tests in one switch -
    //     PTR_DAT_14c532038[0x7AE] == 32   Grenade Camo, for grenade ids 0x13-0x17
    //     PTR_DAT_14c532038[0x7AF] == 13   Infinity Face Paint, for everything else
    // plus EZ Gun (7) and the Patriot (9), which are always free.
    //
    // An ACF slot can never satisfy the vanilla test - the equipped uniform byte would have to read
    // 32, which would make it the Grenade Camo - so this detours the function and returns without
    // consuming when an ACF slot asks for it.
    //
    // Returning early rather than forcing amount=0 is deliberate and measured, not a shortcut:
    // ammotrap recorded ZERO writes to the ammo bytes while Grenade Camo was worn, so the vanilla
    // "amount 0" path writes nothing either. Skipping produces the same observable result.
    //
    // Config, per slot. The two keys are INDEPENDENT - either one alone turns it on:
    //     INFAmmoFlag=1            every weapon is free, like the Infinity Facepaint
    //     INFAmmoWeapon=Grenades   these weapons are free, like Grenade Camo
    // Setting both is simply the union. Names are EGsrEquipId without the WP_ prefix,
    // case-insensitive; raw numbers work too, and "Grenades" expands to all five throwables.
    namespace InfAmmo
    {
        constexpr uintptr_t kGhidraAddress   = 0x147AD5960;
        constexpr uintptr_t kGhidraImageBase = 0x140000000;
        constexpr uintptr_t kOffsetFromBase  = kGhidraAddress - kGhidraImageBase;
        constexpr uintptr_t kGhidraStatePtr  = 0x14C532038;
        constexpr size_t    kEquippedUniform = 0x7AE;

        constexpr int kFirstSlot = 61;
        constexpr int kLastSlot  = 64;

        using DecideAmountFn = void (*)(int);

        static uint64_t                        g_trampoline = 0;
        static std::unique_ptr<PLH::x64Detour> g_detour;
        static bool                            g_installTried = false;

        static bool             g_allWeapons[kLastSlot - kFirstSlot + 1]{};   // INFAmmoFlag
        static std::vector<int> g_only[kLastSlot - kFirstSlot + 1];           // INFAmmoWeapon
        static long             g_suppressed = 0;

        struct EquipName { const wchar_t* name; int id; };
        static const EquipName kEquipNames[] = {
            { L"knife",         1  }, { L"fork",          2  }, { L"cigarpistol",  3  },
            { L"handkerchief",  4  }, { L"mk22",          5  }, { L"gove",         6  },
            { L"easygun",       7  }, { L"ezgun",         7  }, { L"saarmy",       8  },
            { L"patriot",       9  }, { L"patriotpostol", 9  }, { L"scorpion",     10 },
            { L"m16a1",         11 }, { L"akm",           12 }, { L"m63",          13 },
            { L"ithaca",        14 }, { L"dragnov",       15 }, { L"mosinnagant",  16 },
            { L"rpg",           17 }, { L"torch",         18 }, { L"grenade",      19 },
            { L"firegrenade",   20 }, { L"stungrenade",   21 }, { L"chaffgrenade", 22 },
            { L"smokegrenade",  23 }, { L"magazine",      24 }, { L"tnt",          25 },
            { L"c3",            26 },
        };

        static auto Lower(const StringType& s) -> StringType
        {
            StringType out;
            for (auto c : s)
            {
                out += (c >= L'A' && c <= L'Z')
                     ? static_cast<StringType::value_type>(c - L'A' + L'a') : c;
            }
            return out;
        }

        // Reports what it could not understand. A typo here would otherwise read as "restricted to
        // nothing", which looks identical to the flag simply not working.
        static auto ParseEquipList(const StringType& raw, int slotId, std::vector<int>& out) -> void
        {
            StringType token;
            auto flush = [&]() {
                StringType t;
                for (auto c : token) { if (c != L' ' && c != L'\t') { t += c; } }
                token.clear();
                if (t.empty()) { return; }

                const StringType low = Lower(t);
                if (low == STR("grenades") || low == STR("allgrenades"))
                {
                    for (int id = 19; id <= 23; ++id) { out.push_back(id); }
                    return;
                }
                if (low[0] >= L'0' && low[0] <= L'9')
                {
                    int v = 0;
                    for (auto c : low) { if (c >= L'0' && c <= L'9') { v = v * 10 + (c - L'0'); } }
                    out.push_back(v);
                    return;
                }
                for (const auto& e : kEquipNames)
                {
                    if (low == StringType(e.name)) { out.push_back(e.id); return; }
                }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][infammo] slot {}: COULD NOT READ equipment name '{}' - ignored\n"),
                    slotId, t);
            };

            for (auto c : raw)
            {
                if (c == L',' || c == L';') { flush(); } else { token += c; }
            }
            flush();
        }

        static auto LoadConfig() -> int
        {
            int have = 0;
            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                const int i = id - kFirstSlot;
                g_allWeapons[i] = false;
                g_only[i].clear();

                // The two keys stand alone: INFAmmoWeapon works with INFAmmoFlag absent or 0.
                const StringType flag = SlotMeta::Read(id, STR("INFAmmoFlag"));
                for (auto c : flag) { if (c >= L'1' && c <= L'9') { g_allWeapons[i] = true; break; } }

                const StringType list = SlotMeta::Read(id, STR("INFAmmoWeapon"));
                if (!list.empty()) { ParseEquipList(list, id, g_only[i]); }

                if (!g_allWeapons[i] && g_only[i].empty()) { continue; }
                ++have;

                if (g_allWeapons[i])
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][infammo] slot {}: infinite ammo for EVERY weapon\n"), id);
                }
                if (!g_only[i].empty())
                {
                    StringType ids;
                    for (size_t n = 0; n < g_only[i].size(); ++n)
                    {
                        if (n) { ids += STR(", "); }
                        ids += std::to_wstring(g_only[i][n]);
                    }
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][infammo] slot {}: infinite ammo for equip id(s) {}{}\n"),
                        id, ids,
                        g_allWeapons[i] ? STR("  (already covered by INFAmmoFlag=1)") : STR(""));
                }
            }
            return have;
        }

        static auto Detour(int equipId) -> void
        {
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            auto** statePP = reinterpret_cast<uint8_t**>(
                moduleBase + (kGhidraStatePtr - kGhidraImageBase));

            if (statePP != nullptr && *statePP != nullptr)
            {
                uint8_t worn = 0;
                if (LiveStore::ReadByte(*statePP + kEquippedUniform, &worn))
                {
                    const int uniform = static_cast<int8_t>(worn);
                    if (uniform >= kFirstSlot && uniform <= kLastSlot)
                    {
                        const int i = uniform - kFirstSlot;
                        bool applies = g_allWeapons[i];
                        if (!applies)
                        {
                            for (int id : g_only[i]) { if (id == equipId) { applies = true; break; } }
                        }
                        if (applies)
                        {
                            ++g_suppressed;
                            return;   // consume nothing, exactly as the vanilla amount-0 path does
                        }
                    }
                }
            }
            reinterpret_cast<DecideAmountFn>(g_trampoline)(equipId);
        }

        static auto Install() -> void
        {
            if (g_installTried) { return; }
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }
            g_installTried = true;

            if (LoadConfig() == 0)
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF][infammo] no slot sets INFAmmoFlag or INFAmmoWeapon - not detouring.\n"));
                return;
            }

            g_detour = std::make_unique<PLH::x64Detour>(
                static_cast<uint64_t>(moduleBase + kOffsetFromBase),
                reinterpret_cast<uint64_t>(&Detour),
                &g_trampoline);

            if (!g_detour->hook())
            {
                Output::send<LogLevel::Warning>(STR("[ACF][infammo] detour FAILED to install\n"));
                g_detour.reset();
                return;
            }
            Output::send<LogLevel::Warning>(
                STR("[ACF][infammo] detoured the consume-amount function at ghidra 0x{:X}\n"),
                static_cast<uint64_t>(kGhidraAddress));
        }
    }

    namespace ExplainText
    {
        using GetExplainFn = void* (*)(void* out, char tabType, int index);

        constexpr uintptr_t kGhidraAddress   = 0x145289f40;
        constexpr uintptr_t kGhidraImageBase = 0x140000000;
        constexpr uintptr_t kOffsetFromBase  = kGhidraAddress - kGhidraImageBase;

        constexpr char kTabUniform = 1;
        constexpr int  kFirstSlot  = 61;
        constexpr int  kLastSlot   = 64;

        static std::unique_ptr<PLH::x64Detour> g_detour;
        static uint64_t g_trampoline   = 0;
        static int      g_answered     = 0;
        static int      g_reported     = 0;
        static bool     g_installTried = false;

        // Descriptions are cached at install time, NOT read on demand.
        //
        // SlotMeta::Read walks all of Content/Paks recursively and then opens a file. This detour
        // runs once per row while the viewer is drawing, so calling it from in here would put a
        // recursive directory scan in the middle of a menu build. Four strings, read once.
        static StringType g_desc[kLastSlot - kFirstSlot + 1];

        // An FString is a TArray<TCHAR>: pointer, then count and capacity as two int32.
        // The caller treats `out` as uninitialized - the original's failure path writes two zeroed
        // qwords into it - so every field has to be set, and the buffer has to come from the
        // game's allocator because the game is what frees it.
        struct FStringLayout
        {
            wchar_t* Data;
            int32_t  Num;
            int32_t  Max;
        };

        static auto WriteFString(void* out, const wchar_t* text) -> bool
        {
            const size_t len = std::wcslen(text);
            const size_t withNull = len + 1;
            auto* buffer = static_cast<wchar_t*>(FMemory::Malloc(withNull * sizeof(wchar_t)));
            if (buffer == nullptr) { return false; }

            std::memcpy(buffer, text, withNull * sizeof(wchar_t));

            auto* str = static_cast<FStringLayout*>(out);
            str->Data = buffer;
            str->Num  = static_cast<int32_t>(withNull);   // FString length INCLUDES the terminator
            str->Max  = static_cast<int32_t>(withNull);
            return true;
        }

        // The builder's call stack, captured from a detour we already know fires during the build.
        //
        // Every page trap failed for one reason: opening the viewer allocates the row buffer, the
        // map header and the widget itself fresh, so there is nothing stable to arm in advance.
        // This detour needs nothing stable - four descriptions are requested within 600ms of the
        // viewer opening, which is the build asking, not the player hovering. Whoever calls this
        // is therefore the builder, and the builder is what reads the master camouflage value.
        static void*    g_frames[12]{};
        static uint16_t g_frameCount = 0;
        static bool     g_framesLogged = false;

        static auto Detour(void* out, char tabType, int index) -> void*
        {
            if (g_frameCount == 0)
            {
                g_frameCount = RtlCaptureStackBackTrace(0, 12, g_frames, nullptr);
            }

            if (tabType == kTabUniform && index >= kFirstSlot && index <= kLastSlot && out != nullptr)
            {
                const StringType& desc = g_desc[index - kFirstSlot];
                if (!desc.empty() && WriteFString(out, desc.c_str()))
                {
                    ++g_answered;
                    return out;
                }
            }
            return reinterpret_cast<GetExplainFn>(g_trampoline)(out, tabType, index);
        }

        static auto Install() -> void
        {
            if (g_installTried) { return; }
            const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            if (moduleBase == 0) { return; }
            g_installTried = true;

            int have = 0;
            for (int id = kFirstSlot; id <= kLastSlot; ++id)
            {
                g_desc[id - kFirstSlot] = SlotMeta::ReadDescription(id);
                if (!g_desc[id - kFirstSlot].empty()) { ++have; }
            }

            // Nothing to say is a normal state - no author has supplied a description. Leave the
            // game's code alone rather than detouring it to do nothing; ids 61-64 then keep the
            // empty description they already have, which the game ships for other rows too
            // (Usmx and WhiteTuxedo both display none).
            if (have == 0)
            {
                Output::send<LogLevel::Warning>(STR("[ACF][explain] no slot supplied a Description - leaving the game's own text alone.\n"));
                return;
            }

            g_detour = std::make_unique<PLH::x64Detour>(
                static_cast<uint64_t>(moduleBase + kOffsetFromBase),
                reinterpret_cast<uint64_t>(&Detour),
                &g_trampoline);

            if (!g_detour->hook())
            {
                Output::send<LogLevel::Warning>(STR("[ACF][explain] hook on FUN_145289f40 FAILED - descriptions unchanged.\n"));
                g_detour.reset();
                return;
            }
            Output::send<LogLevel::Warning>(STR("[ACF][explain] answering Survival Viewer descriptions for {} slot(s).\n"), have);
        }

        // Logged from on_update, never from inside the detour - that runs while the menu is
        // building and logging there would be both noisy and a bad place to block.
        static auto ReportProgress() -> void
        {
            if (g_frameCount != 0 && !g_framesLogged)
            {
                g_framesLogged = true;
                const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
                Output::send<LogLevel::Warning>(STR("[ACF][explain] caller stack (the row builder):\n"));
                for (uint16_t f = 0; f < g_frameCount; ++f)
                {
                    const auto addr = reinterpret_cast<uintptr_t>(g_frames[f]);
                    if (addr < moduleBase) { continue; }
                    Output::send<LogLevel::Warning>(STR("[ACF][explain]   #{} ghidra 0x{:X}\n"),
                        f, static_cast<uint64_t>(addr - moduleBase + 0x140000000ull));
                }
            }

            if (g_answered == g_reported) { return; }
            g_reported = g_answered;
            Output::send<LogLevel::Warning>(STR("[ACF][explain] supplied {} description(s) so far.\n"), g_answered);
        }
    }

    class ACF : public RC::CppUserModBase
    {
    public:
        ACF()
        {
            ModVersion = STR("0.1");
            ModName = STR("ACF");
            ModAuthors = STR("UE4SS");
            ModDescription = STR("Additive Camo Framework");
            Output::send<LogLevel::Warning>(STR("[ACF]: Init.\n"));
        }

        ~ACF() override = default;

        auto on_program_start() -> void override {}

        // Console-command bridge.
        //
        // The unlock has to run in C++ (it walks process memory, which Lua cannot do), but the
        // console commands all live in main.lua. So the Lua command writes a one-line request
        // file and we pick it up here, on the game thread. Polled a few times a second rather
        // than every tick - it is a file open on the hot path otherwise.
        auto PollUnlockRequest() -> void
        {
            if (++m_pollTick < 15) { return; }
            m_pollTick = 0;

            // Deliberately RELATIVE. The first attempt used GetTempPathW on this side and
            // os.getenv("TEMP") on the Lua side, which looked equivalent but is not: the game
            // process resolves a different temp directory than a normal shell does, so the
            // request file was written somewhere this code never looked and nothing ever ran.
            // Lua and this code live in the SAME process, so a relative path is guaranteed to
            // resolve to the same file for both. It lands in Binaries\Win64\ACF Logs.
            const wchar_t* file = L"ACF Logs\\ACF_svunlock.txt";

            if (!m_loggedBridgePath)
            {
                m_loggedBridgePath = true;
                wchar_t abs[MAX_PATH]{};
                if (GetFullPathNameW(file, MAX_PATH, abs, nullptr) != 0)
                {
                    Output::send<LogLevel::Warning>(STR("[ACF]: svunlock bridge watching {}\n"), abs);
                }
            }

            HANDLE h = CreateFileW(file, GENERIC_READ,
                                   FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                   nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (h == INVALID_HANDLE_VALUE) { return; }
            char buf[512]{};
            DWORD read = 0;
            ReadFile(h, buf, sizeof(buf) - 1, &read, nullptr);
            CloseHandle(h);
            DeleteFileW(file);   // consume it, so one write means one unlock
            if (read == 0) { return; }

            // ufaddr <ObjectPath> - the Ghidra address of a UFunction's native code.
            //
            // A UE4SS hook on a UFunction only fires for Blueprint and Lua callers, never for the
            // game's own native calls - the caption-getter control test proved that (12 fires from
            // a manual call, 0 while the menu drew). So reflection cannot intercept native work.
            //
            // It can still LOCATE it. The UFunction carries a pointer to its native code, which
            // turns "find this function in Ghidra" into a lookup by name, and survives a game
            // update in a way a hardcoded offset does not.
            //
            //     ufaddr /Script/Gsr.GsrEquipController:ReduceStockedAmmoCount
            if (const char* argp = std::strstr(buf, "ufaddr"); argp != nullptr)
            {
                argp += 6;
                while (*argp == ' ' || *argp == '\t') { ++argp; }

                StringType path;
                while (*argp != '\0' && *argp != '\r' && *argp != '\n')
                {
                    path += static_cast<StringType::value_type>(*argp);
                    ++argp;
                }
                while (!path.empty() && (path.back() == ' ' || path.back() == '\t')) { path.pop_back(); }

                if (path.empty())
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][ufaddr] usage: ufaddr /Script/Pkg.Class:FunctionName\n"));
                    return;
                }

                auto* fn = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr, path.c_str());
                if (fn == nullptr)
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][ufaddr] not found: {}\n"), path);
                    return;
                }

                const auto native = reinterpret_cast<uintptr_t>(fn->GetFunc());
                const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
                if (native == 0 || moduleBase == 0)
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][ufaddr] {} has no native function pointer (script-only)\n"), path);
                    return;
                }

                Output::send<LogLevel::Warning>(
                    STR("[ACF][ufaddr] {}\n"), path);
                Output::send<LogLevel::Warning>(
                    STR("[ACF][ufaddr]   live 0x{:X}   ghidra 0x{:X}\n"),
                    static_cast<uint64_t>(native),
                    static_cast<uint64_t>(0x140000000ull + (native - moduleBase)));
                Output::send<LogLevel::Warning>(
                    STR("[ACF][ufaddr]   NOTE: this is usually the exec thunk. Open it in Ghidra -\n")
                    STR("[ACF][ufaddr]   it unpacks parameters and calls the real implementation.\n"));
                return;
            }

            // ammotrap [weaponId] - who actually writes a weapon's ammo?
            //
            // Two consume functions are known and neither is guarded, so we still do not know
            // which one runs for a given weapon, nor what decides to skip it. A write-watch on the
            // four bytes names the instruction and its callers instead of guessing.
            //
            // The weapon array is a good trap target where earlier ones failed: it is a static
            // global that is not reallocated, and ammo changes rarely, so the fault budget is not
            // burned by unrelated traffic the way the Survival Viewer's buffers burned it.
            //
            // Arm it, throw one grenade WITHOUT Grenade Camo, and read the caller chain.
            if (std::strstr(buf, "ammotrap") != nullptr)
            {
                const auto moduleBase = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
                const auto at = [&](uintptr_t g) { return moduleBase + (g - 0x140000000ull); };

                int id = -1;
                for (const char* p = buf; *p != '\0'; ++p)
                {
                    if (*p >= '0' && *p <= '9')
                    {
                        id = 0;
                        while (*p >= '0' && *p <= '9') { id = id * 10 + (*p++ - '0'); }
                        break;
                    }
                }

                if (id < 0)   // no id given - use whatever is equipped
                {
                    auto* statePtr = *reinterpret_cast<uint8_t**>(at(CamoIndex::kGhidraStatePtr));
                    int16_t cur = 0;
                    if (statePtr != nullptr
                        && CamoIndex::ReadInt16(statePtr + CamoIndex::kCurWeaponIdMirror, &cur))
                    {
                        id = cur;
                    }
                }
                if (id < 0 || id > 0x82)
                {
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][ammotrap] no valid weapon id (equip one, or pass it: ammotrap 21)\n"));
                    return;
                }

                auto* entry = reinterpret_cast<uint8_t*>(at(CamoIndex::kGhidraWeaponArray))
                            + CamoIndex::kWeaponStride * static_cast<size_t>(id);

                // Offsets in the report are relative to the entry, so +0x0 is stock and +0x4 loaded.
                LegacySave::g_camoRange = false;
                if (!LegacySave::ArmRange(entry, entry, entry + 8, false))
                {
                    Output::send<LogLevel::Warning>(STR("[ACF][ammotrap] could not arm\n"));
                    return;
                }
                Output::send<LogLevel::Warning>(
                    STR("[ACF][ammotrap] armed on weapon {} at 0x{:X} (+0x0 stock, +0x4 loaded).\n")
                    STR("[ACF][ammotrap] Throw ONE without Grenade Camo, then read the stack.\n"),
                    id, static_cast<uint64_t>(0x140000000ull
                        + (reinterpret_cast<uintptr_t>(entry) - moduleBase)));
                return;
            }

            if (std::strstr(buf, "ammowatch") != nullptr)
            {
                CamoIndex::g_watchAmmo = true;
                CamoIndex::g_ammoLines = 0;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][ammo] watching the equipped weapon's ammo. Throw one, note the delta.\n"));
                return;
            }

            if (std::strstr(buf, "camocol") != nullptr)
            {
                CamoIndex::g_watchColumn = true;
                CamoIndex::g_columnLines = 0;
                Output::send<LogLevel::Warning>(
                    STR("[ACF][col] watching the stance column - stand, crouch, go prone, hug a wall.\n"));
                return;
            }

            if (std::strstr(buf, "camotable") != nullptr)
            {
                // With ids, dump each one's per-background row; without, the summary of all entries.
                std::vector<int> ids;
                for (const char* p = buf; *p != '\0'; )
                {
                    if (*p < '0' || *p > '9') { ++p; continue; }
                    int v = 0;
                    while (*p >= '0' && *p <= '9') { v = v * 10 + (*p++ - '0'); }
                    ids.push_back(v);
                }
                if (ids.empty()) { CamoIndex::DumpTable(); return; }
                for (int id : ids)
                {
                    if (id < 0 || id > 69) { continue; }   // the table is 70 entries
                    CamoIndex::DumpCamoRow(id);
                }
                return;
            }

            // "watch rows" also contains "rows", so the dump must not claim it first.
            if (std::strstr(buf, "rec") != nullptr && std::strstr(buf, "rows") == nullptr)
            {
                std::vector<int> ids;
                for (const char* p = buf; *p != '\0'; )
                {
                    if (*p < '0' || *p > '9') { ++p; continue; }
                    int v = 0;
                    while (*p >= '0' && *p <= '9') { v = v * 10 + (*p++ - '0'); }
                    ids.push_back(v);
                }
                if (ids.empty()) { ids = { 0, 61 }; }   // a known-old camo vs a fresh ACF slot
                LiveStore::DumpRecords(ids.data(), ids.size());
                return;
            }

            if (std::strstr(buf, "rows") != nullptr && std::strstr(buf, "watch") == nullptr)
            {
                PropRows::Dump(std::strstr(buf, "fix") != nullptr);
                return;
            }

            if (std::strstr(buf, "snap") != nullptr || std::strstr(buf, "diff") != nullptr)
            {
                uint8_t* table = LegacySave::Resolve();
                if (table == nullptr) { return; }
                uint8_t* state = table - LegacySave::kTableOff;
                if (std::strstr(buf, "snap") != nullptr) { LegacySave::Snap(state); }
                else                                     { LegacySave::Diff(state); }
                return;
            }

            // "watch" arms the write trap instead of writing anything.
            if (std::strstr(buf, "watch") != nullptr)
            {
                if (std::strstr(buf, "off") != nullptr)
                {
                    LegacySave::Disarm();
                    Output::send<LogLevel::Warning>(STR("[ACF][watch] disarmed.\n"));
                    return;
                }
                // "watch rows" traps the FPropData element buffer instead of the legacy state.
                // Per-tick writing cannot win: the map is regenerated and the rows rebuilt in
                // the same frame the viewer opens, so our edit always lands after the row has
                // already been built. Catching whoever populates the buffer gives us a place to
                // hook where the write happens BEFORE the rows read it.
                // "watch gauge" traps the HUD camo gauge's update queue.
                //
                // This is the only trap so far aimed at memory that survives. Every Survival
                // Viewer attempt failed because opening the viewer allocates the rows, the map
                // header and the widget itself fresh, leaving nothing to arm in advance. The HUD
                // gauge widget lives for the whole session and its queue buffer is reused.
                //
                // FUN_145330460 drains that queue: the array is at widget+0x7a0, entries are 0x40
                // bytes, and the live percentage is the int32 at entry+0x04 with the formatted
                // text at +0x10. The value therefore arrives ALREADY COMPUTED, so whoever writes
                // into this buffer is the code that computes the true camouflage percentage -
                // which is what we need, rather than another display to overwrite.
                if (std::strstr(buf, "gauge") != nullptr)
                {
                    // The live object is a Blueprint subclass, so search the BP names too, and
                    // report every candidate with its array state rather than failing silently -
                    // "not found" and "found but the queue is empty" need different fixes.
                    static const wchar_t* kGaugeClasses[] = {
                        STR("CCamoufGaugeWidget"),
                        STR("CamoufGaugeBP_C"),
                        STR("New_CamoufGaugeBP_C"),
                        STR("HUDCustomCamoufGauge_C"),
                        STR("HUDCustomCamoufGauge_New_C"),
                    };

                    int seen = 0;
                    for (const wchar_t* cls : kGaugeClasses)
                    {
                        std::vector<UObject*> found;
                        UObjectGlobals::FindAllOf(cls, found);
                        for (auto* obj : found)
                        {
                            if (obj == nullptr) { continue; }
                            if (obj->GetFullName().find(STR("Default__")) != StringType::npos) { continue; }

                            auto* w    = reinterpret_cast<uint8_t*>(obj);
                            auto* data = *reinterpret_cast<uint8_t**>(w + 0x7A0);
                            const int32_t num = *reinterpret_cast<int32_t*>(w + 0x7A8);
                            const int32_t max = *reinterpret_cast<int32_t*>(w + 0x7AC);
                            ++seen;
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][watch] {} 0x{:x}  queue data=0x{:x} num={} max={}\n"),
                                cls, reinterpret_cast<uintptr_t>(w),
                                reinterpret_cast<uintptr_t>(data), num, max);

                            const int32_t slots = (max > num) ? max : num;
                            if (data == nullptr || slots <= 0 || slots > 256) { continue; }

                            auto* end = data + static_cast<size_t>(slots) * 0x40;
                            const bool ok = LegacySave::ArmRange(data, data, end, false);
                            LegacySave::g_camoRange = false;
                            Output::send<LogLevel::Warning>(
                                STR("[ACF][watch] {} on the gauge queue at 0x{:x} ({} slots). ")
                                STR("Now MOVE so the percentage changes.\n"),
                                ok ? STR("ARMED") : STR("FAILED to arm"),
                                reinterpret_cast<uintptr_t>(data), slots);
                            return;
                        }
                    }
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][watch] {} gauge widget(s) seen, none with a usable queue.\n"), seen);
                    return;
                }

                // "watch map" traps the widget's MAP HEADER instead of the element buffer.
                //
                // Trapping the elements themselves cannot catch the build: reopening the viewer
                // allocates a fresh buffer, so the writes land where nothing is armed - confirmed,
                // 12 faults on the old page and not one inside the rows, including across sort
                // changes, which turn out to reorder a separate index rather than rewrite entries.
                //
                // The header at widget+0x748 does not move while the widget lives, and the builder
                // has to store the new pointer and count there. Catching that write gives us the
                // builder, which has just read the master camouflage value.
                if (std::strstr(buf, "map") != nullptr)
                {
                    if (PropRows::g_widget == nullptr)
                    {
                        Output::send<LogLevel::Warning>(
                            STR("[ACF][watch] no widget yet - open the Survival Viewer first.\n"));
                        return;
                    }
                    auto* start = PropRows::g_widget + PropRows::kElemsOff;
                    auto* end   = start + 0x18;   // element pointer, count, capacity
                    const bool ok = LegacySave::ArmRange(start, start, end, false);
                    LegacySave::g_camoRange = false;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][watch] {} on the map header at 0x{:x}. Now CLOSE and REOPEN the viewer.\n"),
                        ok ? STR("ARMED") : STR("FAILED to arm"),
                        reinterpret_cast<uintptr_t>(start));
                    return;
                }

                if (std::strstr(buf, "rows") != nullptr)
                {
                    if (PropRows::g_elems == nullptr || PropRows::g_count <= 0)
                    {
                        Output::send<LogLevel::Warning>(
                            STR("[ACF][watch] no PropData buffer yet - open the Survival Viewer first.\n"));
                        return;
                    }
                    auto* start = PropRows::g_elems;
                    auto* end   = start + static_cast<size_t>(PropRows::g_count) * PropRows::kElemStride;
                    const bool ok = LegacySave::ArmRange(start, start, end, false);
                    LegacySave::g_camoRange = false;   // offsets here are rows, not camo ids
                    Output::send<LogLevel::Warning>(
                        STR("[ACF][watch] {} on PropData buffer 0x{:x} ({} rows). Reopen the viewer.\n"),
                        ok ? STR("ARMED") : STR("FAILED to arm"),
                        reinterpret_cast<uintptr_t>(start), PropRows::g_count);
                    return;
                }

                uint8_t* table = LegacySave::Resolve();
                if (table == nullptr) { return; }
                uint8_t* state = table - LegacySave::kTableOff;   // back to the chunk-1 base
                const bool reads = (std::strstr(buf, "read") != nullptr);
                const bool ok = LegacySave::Arm(state, reads);
                Output::send<LogLevel::Warning>(
                    STR("[ACF][watch] {} on legacy state 0x{:x}, mode={}. {}\n"),
                    ok ? STR("ARMED") : STR("FAILED to arm"),
                    reinterpret_cast<uintptr_t>(state),
                    reads ? STR("READS of the camo table") : STR("WRITES to the whole block"),
                    reads ? STR("Now OPEN the Survival Viewer.") : STR("Pick up ANY item."));
                return;
            }

            // "clear" revokes instead of granting.
            const uint16_t value = (std::strstr(buf, "clear") != nullptr) ? 0 : 1;

            std::vector<int> ids;
            if (std::strstr(buf, "all") != nullptr)
            {
                // NOT simply 0..60. Ids 52 (GM_CAMOUF_BONSAI) and 53 (GM_CAMOUF_USMX) are enum
                // entries with no asset - the cooked registry has Camouf_1..51 and 54..60 and
                // nothing for those two. Granting them puts unselectable rows in the menu that
                // HARD CRASH the game when clicked. Confirmed the hard way.
                for (int i = 0; i <= 60; ++i)
                {
                    if (i == 52 || i == 53) { continue; }
                    ids.push_back(i);
                }
            }
            else
            {
                for (const char* p = buf; *p != '\0'; )
                {
                    if (*p < '0' || *p > '9') { ++p; continue; }
                    int v = 0;
                    while (*p >= '0' && *p <= '9') { v = v * 10 + (*p++ - '0'); }
                    ids.push_back(v);
                }
            }
            if (ids.empty()) { return; }
            LegacySave::Unlock(ids.data(), ids.size(), value);
        }
        auto on_dll_load(std::wstring_view dll_name) -> void override {}
        auto on_unreal_init() -> void override {}


        auto on_update() -> void override
        {
            // Runs regardless of registration state - the unlock is independent of it.
            PollUnlockRequest();
            LegacySave::DrainHits();
            LiveStore::ReportOnce();
            LiveStore::KeepApplied();
            CamoIndex::Install();
            CamoIndex::ApplyTable();
            CamoIndex::PollLive();
            CamoIndex::PollAmmo();
            // LiveStore::ApplyCamoTable() is NOT called. What findcamo locates is a fourth copy:
            // all four writes landed and no displayed number changed. Left compiled as a
            // diagnostic, but nothing should write to memory whose owner we cannot name.
            LiveStore::DrainApplied();
            ExplainText::Install();
            InfAmmo::Install();
            ExplainText::ReportProgress();

            // The P3 investigation diagnostics are NO LONGER RUN. They answered their questions and
            // every one of them cost something to leave switched on:
            //
            //   GaugeTrace  - registered a GLOBAL ProcessEvent pre-callback with UE4SS. Prime
            //                 suspect for the hot-reload crash that appeared recently: reloading
            //                 Lua mods rebuilds UE4SS's hook machinery while our callback is still
            //                 registered against it. Unproven, but it is dead code either way.
            //   LegacyData  - a live detour on FUN_147a5bcc0, the legacy layer's data dispatcher,
            //                 which every data query in the game passes through.
            //   CamoSource  - walked a vtable chain once a second to read a struct that turned out
            //                 to be a debug mirror the shipping build never fills.
            //   PollCamoBase, CamoIndex::Report/ReportBase, ReportCaptionFuncs - logging that only
            //                 meant anything while the FUN_147ACEC00 detour was installed, and it
            //                 is not any more.
            //
            // The code is kept and still compiles. Re-enable a single line here if a question
            // needs it again; do not switch them all back on by habit.
            PropRows::ApplyCamo();

            // PropRows::Tick() used to run here and has been REMOVED - it crashed the game.
            //
            // Crash dump crash_2026_07_30_03_36_52 faulted at main.dll+0x186DB =
            // PropRows::FixNames+0x7B, reading freed memory. FixNames caches the FPropData
            // element pointer, but that map is destroyed and rebuilt every time the Survival
            // Viewer opens (FUN_1453d0c20 is its destructor), so the cached pointer goes stale
            // and the next tick reads through it.
            //
            // It was also pointless: the runtime name writes never reached the row, which is why
            // row names moved to the ACF_Names_P pak. Dead code that could take the game down.
            //
            // svrows (PropRows::Dump) is still available as a manual diagnostic - it re-finds the
            // widget each time instead of trusting a cached pointer.

            // Once registration is done, keep trying to attach any thumbnail that was not
            // available at the time. See RetryPendingThumbnails for why this is needed.
            if (m_registered) { RetryPendingThumbnails(); return; }

            // Wait until the game has actually loaded the collection table.
            auto* dataTable = FindTable(STR("/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection.DT_CamouflageCollection"));
            if (dataTable == nullptr) { return; }

            m_registered = true;
            m_collectionTable = dataTable;   // kept so late thumbnails can find their row again

            // Flip to true to install the native detour on UAssetManager::GetPrimaryAssetData.
            //
            // OFF by default deliberately. This writes machine code into the running game at an
            // address derived from a Ghidra offset; if that offset is wrong for the current
            // build it will corrupt unrelated instructions and crash unpredictably. Everything
            // is written and compiled - enabling is a one-line change once we want the data.
            //
            // To revert after a bad run: copy the previous ACF.dll back over
            // ue4ss/Mods/ACF-CPP/dlls/main.dll. Nothing else is affected.
            // Probe is READ-ONLY and always safe - it just reports where we think the function
            // is and what bytes live there, so we can confirm the address before ever writing.
            AssetLookupDetour::Probe();

            // Add every FName the detour could need, HERE on the game thread, so the detour
            // itself only ever does lookups. See the note on PackName: adding names from inside
            // the detour races the async loading thread and is the suspected crash cause.
            AssetLookupDetour::Prime();

            // ENABLED 2026-07-29 after the probe validated the address:
            //   module base 0x7ff7aea30000 + offset 0x3bee420 = 0x7ff7b261e420
            //   bytes there: 48 89 5c 24 10 48 89 6c
            //     = mov [rsp+10h], rbx ; mov [rsp+18h], rbp   -> textbook x64 prologue
            // Still OBSERVE-ONLY: it logs and forwards to the original, changing no behavior.
            constexpr bool kEnableAssetLookupDetour = true;
            if constexpr (kEnableAssetLookupDetour)
            {
                AssetLookupDetour::Install();
            }

            // Captures the real ownership state pointer the first time the Survival Viewer
            // refreshes. Observe-only: it records param_1 and forwards.
            LiveStore::Install();

            // Patches ACF row text/icon as the menu reads each row. The map itself is rebuilt
            // every open, so intercepting the read is the only place an edit survives.
            PropRows::ReadHook::Install();

            // Raise the camo ceiling BEFORE registering anything, so IDs above 65 are inside
            // the valid range by the time the rest of the system sees them.
            ExpandCamouflageMax(100);

            // Publish the per-slot metadata we found, so the Lua side reads one resolved list
            // instead of repeating the directory search in a second language.
            {
                static const int kSlots[] = { 61, 62, 63, 64 };
                SlotMeta::WriteResolved(kSlots, std::size(kSlots));
            }

            // Re-test an assumption everything else rests on: are TMap READS actually broken?
            //
            // The "reads are broken" note at the top of this file came from FindRowUnchecked
            // returning null for "IT_EqNaked" - but that is NOT a real row name in this table,
            // as the FModel dump later showed. A lookup for a row that does not exist returning
            // null is correct behavior, not a bug. So the evidence never supported the claim.
            //
            // This matters a lot. If reads work:
            //   * we can CLONE a real row instead of writing a blank one, which is what would
            //     finally populate Thumbnail/DisplayName/AssetID properly
            //   * and the one-row-per-session limit is NOT AddRow's internal remove
            //     false-matching, it is TSet growth in AddRowInternal - a different fix
            //
            // FindRowUnchecked is a single TMap::Find, no iteration, so this is safe (unlike
            // range-for over GetRowMap(), which hard-crashes the game - never do that).
            ProbeRowReads(dataTable);

            // The sort table drives display ORDER in the viewer. It is optional: a missing
            // sort entry must never block the main registration (it silently did once).
            auto* sortTable = FindTable(STR("/CobraUI/Data/SV/DT_UniformSortDelta.DT_UniformSortDelta"));
            if (sortTable == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: DT_UniformSortDelta not loaded - skipping sort registration.\n"));
            }

            // EXPERIMENT: is a DT_CamouflageCollection row REQUIRED for a camo to render?
            //
            // Established by testing forcecamo across 60-65 with Camouf_<id>_asset shipped for
            // every one of them:
            //     camo 60 renders   - has a vanilla row (IT_EqAdditionalUniform2) + sort entry
            //     camo 61-65 dead   - enum entry and asset present, but NO row, NO sort entry
            //
            // The asset alone is therefore not enough. The row is the only difference between
            // the slot that works and the five that do not.
            //
            // We can add exactly ONE row per session (UE4SS cannot grow the game's TMap beyond
            // that - see the AddRow note below), so we spend it on camo 61 and check whether
            // `forcecamo 0 61` starts rendering:
            //     61 renders     -> the row is the requirement, and shipping a modified
            //                       DT_CamouflageCollection.uasset in a pak unlocks 61-65 too
            //     61 still dead  -> something beyond the row is needed and the pak route would
            //                       have been wasted work
            //
            // Deliberately targeting a RESERVED slot rather than 72: IDs above 65 are confirmed
            // dead in native code, so testing there could not distinguish "row missing" from
            // "ID out of range". 72 stays supported in the code path, just unused for now.
            //
            // DisplayName TAKES PLAIN TEXT. Confirmed in game 2026-07-29: the row below gold
            // reads "ACF Mod 1" exactly as written here.
            //
            // CORRECTION of a note that stood in this file for weeks. It claimed "DisplayName is
            // NOT display text - vanilla rows hold a LOCALISATION KEY... a plain-English value
            // here cannot resolve." That was wrong, for a reason worth remembering: an early
            // plain-text attempt showed NO DATA and we blamed the string. But NO DATA is the
            // VANILLA state for this row and has nothing to do with DisplayName. Two unrelated
            // things were conflated, the conclusion was written down as fact, and it sent us into
            // .locres byte-patching (which renamed the row, then crashed the game) to solve a
            // problem that never existed.
            //
            // Vanilla rows do use loc keys and those still work - they are simply not required.
            // RE-TESTING THE ONE-ROW LIMIT.
            //
            // Previously measured: 95 -> 96, then 96 -> 96, then 96 -> 96. Only the first AddRow
            // ever landed. The explanation at the time was "AddRow calls RemoveRowInternal first,
            // and TMap lookups are broken on this build, so it false-matches and deletes the row
            // we just added."
            //
            // That explanation is now DEAD: TMap reads work fine - they only appeared broken
            // because we built the FName with FNAME_Add instead of FNAME_Find. So RemoveRowInternal
            // correctly removes nothing for a new name, and the real cause must be something else
            // (most likely TSet growth in AddRowInternal).
            //
            // Distinct names and distinct camo ids, so nothing can collide. Watch the log:
            //     95 -> 96 -> 97 -> 98   the limit is gone, we can add rows freely
            //     95 -> 96 -> 96 -> 96   confirmed as growth, and the pak route is the fix
            // 61-65 is the full usable band: these ECamouflageType values already exist, so no
            // InsertIntoNames is needed and rows add freely (see the note above).
            //
            // 60 is deliberately NOT here. It is GM_CAMOUF_ADDITIONAL_UNIFORM_1, which vanilla
            // ships as the CROCODILE SUIT - a real DLC uniform with its own row
            // (IT_EqAdditionalUniform2). Using it would REPLACE player content, which is the one
            // thing ACF exists to avoid.
            static const ACFCamoDef camos[] = {
                // Thumbnails point at each slot's OWN placeholder texture - the same four that
                // ACF_SvThumb_P overrides with the ACF logo, so both menus show identical art and
                // no extra pak is needed.
                //
                // These used to point at real vanilla camo thumbnails (Moss, Animal, Hebi,
                // Spirit). That looked fine but was a trap: overriding those to brand the rows
                // would have changed the thumbnails of the actual vanilla camos too. The
                // reserved-slot placeholders below are used by nothing except these slots.
                { STR("IT_EqACFSlot61"), STR("IT_EqACFSlot61"), 61, L"ACF Mod 1", STR("9200220") },
                { STR("IT_EqACFSlot62"), STR("IT_EqACFSlot62"), 62, L"ACF Mod 2", STR("9265756") },
                { STR("IT_EqACFSlot63"), STR("IT_EqACFSlot63"), 63, L"ACF Mod 3", STR("9331292") },
                { STR("IT_EqACFSlot64"), STR("IT_EqACFSlot64"), 64, L"ACF Mod 4", STR("9396828") },

                // STOPS AT 64 ON PURPOSE. Slots 65-67 used to be registered here, and they render
                // via forcecamo, but they can never be equipped, so a Collection Viewer row for
                // them just advertises content the player cannot reach:
                //   65 = GM_CAMOUF_DOWNLOAD  - written successfully, never appears in the list
                //   66 = was GM_CAMOUF_MAX   - a sentinel, never a real uniform
                //   67 = GM_CAMOUF_EQ_CBOX_A - a cardboard box, and already owned from the start
                // The equip menu's four reserved slots (ADDITIONAL_UNIFORM_2..5 = 61-64) are the
                // real capacity of the framework. See the slot table in README.md.
            };

            for (const auto& def : camos)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: Registering {} (camo id {}).\n"), def.RowName, def.CamoValue);

                if (RegisterCamo(def, dataTable) && sortTable != nullptr)
                {
                    RegisterUniformSort(def, sortTable);
                }
            }

            Output::send<LogLevel::Warning>(STR("[ACF]: Registration pass complete.\n"));
        }

    private:
        bool m_registered = false;
        bool m_dumpedLayout = false;
        int  m_pollTick = 0;            // throttles the console-command bridge
        bool m_loggedBridgePath = false;
        std::vector<PendingThumb> m_pendingThumbs;
        UDataTable* m_collectionTable = nullptr;
        int  m_retryTicks = 0;

        // Re-attempt any thumbnail that was missing at registration time.
        //
        // Cheap: it only runs while something is still pending, and throttles to roughly once a
        // second rather than every tick.
        auto RetryPendingThumbnails() -> void
        {
            if (m_pendingThumbs.empty() || m_collectionTable == nullptr) { return; }
            if (++m_retryTicks < 60) { return; }
            m_retryTicks = 0;

            auto rowStruct = m_collectionTable->GetRowStruct();
            if (rowStruct == nullptr) { return; }

            bool anyLeft = false;
            for (auto& p : m_pendingThumbs)
            {
                if (p.done) { continue; }

                const StringType path = StringType(STR("/CobraUI/textures/sv/camouflage/"))
                                      + p.thumbName + STR(".") + p.thumbName;
                auto* tex = UObjectGlobals::StaticFindObject<UObject*>(nullptr, nullptr, path.c_str());
                if (tex == nullptr) { anyLeft = true; continue; }

                // FNAME_Find: the row name was added at registration, so it exists. Never
                // FNAME_Add from a polling path.
                const auto rowName = FName(p.rowName.c_str(), FNAME_Find);
                uint8_t* row = (rowName == FName()) ? nullptr : m_collectionTable->FindRowUnchecked(rowName);
                if (row == nullptr) { anyLeft = true; continue; }

                if (SetObjectField(rowStruct, row, STR("Thumbnail"), tex))
                {
                    p.done = true;
                    Output::send<LogLevel::Warning>(
                        STR("[ACF]: late thumbnail attached: '{}' -> {}\n"), p.rowName, p.thumbName);
                }
                else
                {
                    anyLeft = true;
                }
            }
            if (!anyLeft) { m_pendingThumbs.clear(); }
        }

        static auto FindTable(const wchar_t* path) -> UDataTable*
        {
            return UObjectGlobals::StaticFindObject<UDataTable*>(nullptr, nullptr, path);
        }

        // Logs every field of a row struct with its property type and byte offset.
        //
        // We need this because we cannot clone a template row (TMap reads are broken), so we
        // have to populate fields by hand - and to do that correctly we need to know whether
        // e.g. DisplayName is an FName, an FString or an FText. Each needs different handling;
        // writing raw bytes into the wrong one corrupts memory.
        //
        // Safe to iterate: struct fields come from the ChildProperties linked list, not a TMap.
        template<typename StructPtrT>
        static auto DumpRowStructLayout(StructPtrT rowStruct) -> void
        {
            Output::send<LogLevel::Warning>(STR("[ACF]: --- row struct layout ---\n"));
            for (FProperty* prop : rowStruct->ForEachPropertyInChain())
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   +{:#06x}  {:<24}  {}\n"),
                    prop->GetOffset_Internal(),
                    prop->GetClass().GetName(),
                    prop->GetName());
            }
            Output::send<LogLevel::Warning>(STR("[ACF]: --- end layout ---\n"));
        }

        // Writes a single byte into a struct field. Enum/bool fields in these row structs are
        // all byte-sized, so this covers everything we currently need to set.
        // Templated because GetRowStruct() hands back a TObjectPtr, not a raw pointer.
        template<typename StructPtrT>
        static auto SetByteField(StructPtrT rowStruct, uint8_t* buffer, const wchar_t* fieldName, uint8_t value) -> bool
        {
            auto* prop = rowStruct->GetPropertyByNameInChain(fieldName);
            if (prop == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   field '{}' not found.\n"), fieldName);
                return false;
            }

            *prop->ContainerPtrToValuePtr<uint8_t>(buffer) = value;
            return true;
        }

        // Constructs an FString in place inside the row buffer.
        //
        // The buffer is raw bytes we never run destructors over, so ownership works out either
        // way: if AddRow deep-copies the struct our string leaks once (a few bytes, one time
        // per camo); if it shallow-copies, the table takes ownership and nothing double-frees.
        template<typename StructPtrT>
        static auto SetStringField(StructPtrT rowStruct, uint8_t* buffer, const wchar_t* fieldName, const wchar_t* value) -> bool
        {
            auto* prop = rowStruct->GetPropertyByNameInChain(fieldName);
            if (prop == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   string field '{}' not found.\n"), fieldName);
                return false;
            }

            auto* slot = prop->ContainerPtrToValuePtr<FString>(buffer);
            new (slot) FString(value);
            return true;
        }

        // Writes a hard UObject pointer (Thumbnail is an ObjectProperty, not a soft reference,
        // so the target must already be loaded for this to be worth doing).
        template<typename StructPtrT>
        static auto SetObjectField(StructPtrT rowStruct, uint8_t* buffer, const wchar_t* fieldName, UObject* value) -> bool
        {
            auto* prop = rowStruct->GetPropertyByNameInChain(fieldName);
            if (prop == nullptr || value == nullptr) { return false; }

            *prop->ContainerPtrToValuePtr<UObject*>(buffer) = value;
            return true;
        }

        // Raises GM_CAMOUF_MAX so camo IDs above the vanilla ceiling are considered valid.
        //
        // WHY: the save's CamouflageList shipped with 66 entries, covering ECamouflageType
        // values 0-65 - and GM_CAMOUF_MAX is 66. Our test camo (72) sits outside that, which is
        // the leading explanation for why appending unlock slots past the end changed nothing:
        // the game never reads that far.
        //
        // HOW: EditValueAt changes one entry's value in place. Deliberately NOT using
        // InsertIntoNames(..., bShiftValues=true), which would renumber everything after MAX -
        // including GM_CAMOUF_EQ_CBOX_A/B/C (the cardboard boxes) - while native code still has
        // their original values compiled in. This way nothing else moves.
        //
        // CAVEAT, stated plainly: GM_CAMOUF_MAX is a C++ constant, so any native loop written as
        // `i < 66` has that baked into machine code and will not care what this enum says. This
        // only affects code that asks the enum at runtime. It may well do nothing.
        auto ExpandCamouflageMax(int64_t newMax) -> void
        {
            auto* camoEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/MGS3.ECamouflageType"));
            if (camoEnum == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: ECamouflageType not found - cannot expand MAX.\n"));
                return;
            }

            // Vanilla entries run 0-70 with index == value, so GM_CAMOUF_MAX sits at index 66.
            // Verify that before writing, rather than trusting the assumption.
            constexpr int32_t kMaxIndex = 66;
            const auto nameAtMax = camoEnum->GetNameByValue(66);

            Output::send<LogLevel::Warning>(STR("[ACF]: value 66 currently maps to '{}'\n"), nameAtMax.ToString());

            // Substring match, not equality: GetNameByValue returns the FULLY QUALIFIED name
            // ("ECamouflageType::GM_CAMOUF_MAX"), which an exact comparison silently fails.
            if (nameAtMax.ToString().find(STR("GM_CAMOUF_MAX")) == StringType::npos)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: expected GM_CAMOUF_MAX at value 66 - aborting to avoid corrupting the enum.\n"));
                return;
            }

            camoEnum->EditValueAt(kMaxIndex, newMax);

            Output::send<LogLevel::Warning>(STR("[ACF]: GM_CAMOUF_MAX 66 -> {}. Value {} now maps to '{}'.\n"),
                newMax, newMax, camoEnum->GetNameByValue(newMax).ToString());
        }

        // Adds the camo to the three enums the game uses to identify equipment, then adds a
        // matching row to DT_CamouflageCollection.
        auto RegisterCamo(const ACFCamoDef& def, UDataTable* dataTable) -> bool
        {
            auto* camoEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/MGS3.ECamouflageType"));
            auto* itemEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/MGS3.EItemName"));
            auto* gsrItemEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/Gsr.EGsrItemId"));

            if (camoEnum == nullptr || itemEnum == nullptr || gsrItemEnum == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: One or more enums not found - aborting.\n"));
                return false;
            }

            // Each enum has its own length, so each append must use its OWN NumEnums() as the
            // insert index. Reusing one index across all three corrupts them.
            const auto itemIndex = itemEnum->NumEnums();

            // NEVER insert into ECamouflageType. This is what caused the old "only one row per
            // session" limit: every multi-row attempt registered NEW enum values (72/73/74) and
            // so called InsertIntoNames per camo, after which subsequent AddRow calls silently
            // netted to zero. Targeting ids whose values already exist skipped the insert - and
            // rows then climbed 95 -> 96 -> 97 -> 98.
            //
            // We do not need it anyway: CamouflageType is written below as a raw byte value, so
            // the row works whether or not the value has a NAME in the enum. Camo 66 has no name
            // (svcheck reports "absent / None") and renders fine.
            //
            // EItemName / EGsrItemId inserts below are left in place - those were happening
            // during the successful three-row run (ItemType 161/162/163) and did not break it.
            const auto existingCamoName = camoEnum->GetNameByValue(def.CamoValue).ToString();
            Output::send<LogLevel::Warning>(STR("[ACF]:   ECamouflageType {} = '{}' (not modifying the enum).\n"),
                def.CamoValue, existingCamoName.empty() ? StringType(STR("<unnamed>")) : existingCamoName);
            itemEnum->InsertIntoNames(TPair<FName, int64>{ FName(def.ItemName, FNAME_Add), itemIndex }, itemIndex, false);
            gsrItemEnum->InsertIntoNames(TPair<FName, int64>{ FName(def.ItemName, FNAME_Add), gsrItemEnum->NumEnums() }, gsrItemEnum->NumEnums(), false);

            auto rowStruct = dataTable->GetRowStruct();
            const auto rowSize = rowStruct->GetPropertiesSize();
            std::vector<uint8_t> buffer(rowSize, 0);

            // One-shot: we need the exact field types before we can populate them by hand.
            if (!m_dumpedLayout)
            {
                m_dumpedLayout = true;
                DumpRowStructLayout(rowStruct);
            }

            // Ideally we would clone a real row here so the new one inherits Thumbnail,
            // DisplayName, AssetID, ModelAsset and FaceOption. That does not work: TMap reads
            // are broken on this build, so FindRowUnchecked returns null for every row name we
            // try, including ones we can see in the shipped table. The row therefore goes in
            // as an all-zero blank plus the few fields set below.
            //
            // A blank row is still enough to produce a visible Collection Viewer entry
            // we can populate those fields. Doing that means constructing FString/FText/soft
            // object references by hand rather than copying them - see the project notes.
            SetByteField(rowStruct, buffer.data(), STR("CamouflageType"), static_cast<uint8_t>(def.CamoValue));
            SetByteField(rowStruct, buffer.data(), STR("ItemType"), static_cast<uint8_t>(itemIndex));
            SetByteField(rowStruct, buffer.data(), STR("IsShowLockDescryptionText"), 0);  // sic - typo is the game's
            SetByteField(rowStruct, buffer.data(), STR("IsHiddenItem"), 0);
            SetByteField(rowStruct, buffer.data(), STR("IsAdditionalItem"), 0);
            SetByteField(rowStruct, buffer.data(), STR("CanCqc"), 1);

            // String fields. Every one of our rows previously had these empty, which is the
            // leading theory for why three registered rows collapsed into a single visible
            // entry - the viewer may be keying its list on one of them. Giving each camo a
            // distinct DisplayName tests that directly.
            SetStringField(rowStruct, buffer.data(), STR("AssetID"), STR("Collection_Uniform"));

            // The author's name if they shipped one, otherwise the generic "ACF Mod N".
            // The Survival Viewer row is renamed separately by the Lua side reading the same
            // file; if only one of the two were done the menus would disagree.
            const StringType authored = SlotMeta::Read(def.CamoValue, STR("Name"));
            const wchar_t* shown = authored.empty() ? def.DisplayName : authored.c_str();
            if (!authored.empty())
            {
                Output::send<LogLevel::Warning>(
                    STR("[ACF]:   slot {} named '{}' by the mod author\n"), def.CamoValue, authored);
            }
            SetStringField(rowStruct, buffer.data(), STR("DisplayName"), shown);
            // Vanilla uses a loc key here (Ã£Æ’Â¦Ã£Æ’â€¹Ã£Æ’â€¢Ã£â€šÂ©Ã£Æ’Â¼Ã£Æ’Â Ã¨ÂªÂ¬Ã¦ËœÅ½Ã£Æ’ÂªÃ£â€šÂ½Ã£Æ’Â¼Ã£â€šÂ¹ = "uniform description
            // resource"), but since DisplayName turned out to accept plain text, this very likely
            // does too - it has not been tested separately. Left borrowing NAKED's key because it
            // displays correctly and nothing depends on changing it.
            // Description: the author's text when supplied, else vanilla's NAKED loc key.
            //
            // The key is written as \u escapes, NOT as literal Japanese. This source is UTF-8
            // with no BOM, so MSVC decodes non-ASCII literals with the system codepage - the
            // literal that used to live here had already been double-mangled by an earlier save
            // and rendered in game as "\u00c3\u00a3\u00c6'\u00c2\u00a6...-NAKED". Escapes cannot rot.
            //
            // \u30E6\u30CB\u30D5\u30A9\u30FC\u30E0\u8AAC\u660E\u30EA\u30BD\u30FC\u30B9 = "uniform description resource"
            const StringType authoredDesc = SlotMeta::ReadDescription(def.CamoValue);
            SetStringField(rowStruct, buffer.data(), STR("DescryptionText"),
                authoredDesc.empty()
                    ? L"\u30E6\u30CB\u30D5\u30A9\u30FC\u30E0\u8AAC\u660E\u30EA\u30BD\u30FC\u30B9-NAKED"
                    : authoredDesc.c_str());
            SetStringField(rowStruct, buffer.data(), STR("LockDescryptionText"), STR(""));
            SetStringField(rowStruct, buffer.data(), STR("LightName"), STR(""));

            // Thumbnail is a hard object pointer, so the texture must already be in memory.
            // Vanilla camo thumbnails are all preloaded by the game, so any of them resolves.
            // Per-row now, so the six rows are visually distinct instead of all showing Naked.
            const StringType thumbPath = StringType(STR("/CobraUI/textures/sv/camouflage/"))
                                       + def.ThumbnailName + STR(".") + def.ThumbnailName;
            auto* thumbnail = UObjectGlobals::StaticFindObject<UObject*>(nullptr, nullptr, thumbPath.c_str());

            // DIAGNOSTIC: force every thumbnail down the LATE path, even vanilla ones that are
            // already resident.
            //
            // The question this answers: does the Collection Viewer re-read a row's Thumbnail
            // each time it draws, or does it cache when the row list is first built?
            //
            // Our custom texture can only ever be attached late (it arrives as an import of the
            // camo asset, well after registration). If a VANILLA texture attached late also
            // fails to appear, the viewer caches and no late patch can ever work - so the fix is
            // to get the texture loaded EARLIER, and the texture itself was never at fault.
            // If vanilla textures DO appear when attached late, then late patching is fine and
            // the blank custom thumbnail is a texture problem after all.
            //
            // Set back to false once the answer is known.
            constexpr bool kForceLateThumbnails = true;
            if constexpr (kForceLateThumbnails) { thumbnail = nullptr; }
            if (thumbnail != nullptr)
            {
                SetObjectField(rowStruct, buffer.data(), STR("Thumbnail"), thumbnail);
                Output::send<LogLevel::Warning>(STR("[ACF]:   thumbnail set.\n"));
            }
            else
            {
                // Not in memory yet. Queue it and keep retrying - a CUSTOM texture only arrives
                // once the asset referencing it loads, which is well after registration.
                m_pendingThumbs.push_back(PendingThumb{ def.RowName, def.ThumbnailName, false });
                Output::send<LogLevel::Warning>(
                    STR("[ACF]:   thumbnail '{}' not loaded yet - queued for retry.\n"), def.ThumbnailName);
            }

            // Diagnostic: if FName construction is broken, every row key we build would be the
            // SAME name - the first AddRow would insert and every later one would overwrite it.
            // That single fault would also explain why FindRowUnchecked never finds anything.
            // Log what the name actually resolves to before using it.
            auto rowFName = FName(def.RowName, FNAME_Add);
            Output::send<LogLevel::Warning>(STR("[ACF]:   FName('{}') -> '{}' (comparison index {})\n"),
                def.RowName,
                rowFName.ToString(),
                rowFName.GetComparisonIndex().ToUnstableInt());

            // KNOWN LIMITATION: only the FIRST camo registered per session actually lands.
            //
            // AddRow calls RemoveRowInternal(RowName) first ("delete the row memory even if it
            // already exists"). That remove does a TMap lookup, and TMap lookups are broken on
            // this UE4SS build - it finds a false match and deletes an existing row. So every
            // AddRow after the first nets to zero: it silently deletes the previously added row
            // and inserts the new one. Measured as 95->96, 96->96, 96->96.
            //
            // Bypassing AddRow and inserting into GetRowMap() directly (allocate + InitializeStruct
            // + CopyScriptStruct + Add) CRASHED the game. Most likely cause: adding several rows
            // forces the map to grow, and reallocating the game's container from UE4SS's side
            // mixes allocators. A single add fits in existing capacity, which is why one row has
            // always worked. Do not retry that approach without solving the allocator problem.
            //
            // Real fixes, in rough order of preference - see README:
            //   1. Call the GAME's own UDataTable::AddRow via its address (correct allocator)
            //   2. Ship a pre-modified DT_CamouflageCollection in a pak (no runtime insert at all)
            const auto rowsBefore = dataTable->GetRowMap().Num();
            dataTable->AddRow(rowFName, buffer.data(), rowStruct);
            const auto rowsAfter = dataTable->GetRowMap().Num();

            Output::send<LogLevel::Warning>(STR("[ACF]:   collection rows {} -> {} (ItemType {}).\n"),
                rowsBefore, rowsAfter, itemIndex);

            if (rowsAfter == rowsBefore)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   WARNING - row count did not increase, AddRow did nothing!\n"));
            }
            return true;
        }

        // Looks up a handful of row names and reports which resolve.
        //
        // The list deliberately mixes three kinds of name so the result is unambiguous:
        //   * names confirmed present in the shipped table (from the FModel export)
        //   * the name we historically probed and wrongly concluded was proof of a broken read
        //   * a name that certainly does not exist, as a control
        //
        // Expected if reads WORK:   real names hit, fake name misses.
        // Expected if reads BROKEN: everything misses, including the real ones.
        auto ProbeRowReads(UDataTable* dataTable) -> void
        {
            static const wchar_t* probes[] = {
                STR("IT_EqAdditionalUniform2"),  // camo 60's row - the slot that renders
                STR("IT_EqRainbow"),             // a real DLC camo row
                STR("IT_EqChamel"),              // another real DLC camo row
                STR("IT_EqNaked"),               // historically probed; believed NOT to be real
                STR("ACF_ThisRowCannotExist"),   // control - must always miss
            };

            Output::send<LogLevel::Warning>(STR("[ACF]: --- TMap read probe ({} rows in table) ---\n"),
                dataTable->GetRowMap().Num());

            int hits = 0;
            for (const auto* name : probes)
            {
                // FNAME_Find, not FNAME_Add: if the name is not already in the global name
                // table it cannot possibly be a key here, and we avoid polluting FName state.
                const auto rowName = FName(name, FNAME_Find);
                uint8_t* row = (rowName == FName()) ? nullptr : dataTable->FindRowUnchecked(rowName);
                if (row != nullptr) { ++hits; }
                Output::send<LogLevel::Warning>(STR("[ACF]:   {:<26} -> {}\n"),
                    name, row != nullptr ? STR("FOUND") : STR("miss"));
            }

            if (hits > 0)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   READS WORK ({} hit). Row cloning is possible; the one-row limit is TSet growth.\n"), hits);
            }
            else
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   all misses - reads really are broken, or these names are wrong.\n"));
            }
        }

        // Adds the camo to the viewer's sort/order table.
        auto RegisterUniformSort(const ACFCamoDef& def, UDataTable* sortTable) -> void
        {
            auto rowStruct = sortTable->GetRowStruct();
            const auto rowSize = rowStruct->GetPropertiesSize();
            std::vector<uint8_t> buffer(rowSize, 0);

            // UniformSortInfo has exactly one field: UniformType (an ECamouflageType).
            SetByteField(rowStruct, buffer.data(), STR("UniformType"), static_cast<uint8_t>(def.CamoValue));

            sortTable->AddRow(FName(def.RowName, FNAME_Add), buffer.data(), rowStruct);

            Output::send<LogLevel::Warning>(STR("[ACF]:   added sort row.\n"));
        }
    };
}

#define MOD_EXPORT __declspec(dllexport)
extern "C"
{
    MOD_EXPORT RC::CppUserModBase* start_mod() { return new MyMods::ACF(); }
    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}
