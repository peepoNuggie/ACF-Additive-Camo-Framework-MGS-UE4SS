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
#include <Unreal/Engine/UDataTable.hpp>
#include <Unreal/FProperty.hpp>
#include <Unreal/FString.hpp>
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
        // PROVEN BEHAVIOUR we are exploiting (from the live log):
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
        static constexpr int ACFCamoIds[] = { 61, 62, 63, 64, 65, 66, 72 };

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
            // changes vanilla behaviour for ids that are not ours. Only ids we actually ship a
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

    using namespace RC;
    using namespace Unreal;

    // One entry per camo to add. Adding a camo should be a matter of adding a line here.
    struct ACFCamoDef
    {
        const wchar_t* ItemName;     // EItemName / EGsrItemId entry name
        const wchar_t* RowName;      // DataTable row key and ECamouflageType entry name
        int32_t        CamoValue;    // ECamouflageType numeric value (vanilla uses 0-70)
        const wchar_t* DisplayName;  // shown in the Collection Viewer
    };

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
        auto on_dll_load(std::wstring_view dll_name) -> void override {}
        auto on_unreal_init() -> void override {}

        auto on_update() -> void override
        {
            if (m_registered) { return; }

            // Wait until the game has actually loaded the collection table.
            auto* dataTable = FindTable(STR("/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection.DT_CamouflageCollection"));
            if (dataTable == nullptr) { return; }

            m_registered = true;

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
            // Still OBSERVE-ONLY: it logs and forwards to the original, changing no behaviour.
            constexpr bool kEnableAssetLookupDetour = true;
            if constexpr (kEnableAssetLookupDetour)
            {
                AssetLookupDetour::Install();
            }

            // Raise the camo ceiling BEFORE registering anything, so IDs above 65 are inside
            // the valid range by the time the rest of the system sees them.
            ExpandCamouflageMax(100);

            // Re-test an assumption everything else rests on: are TMap READS actually broken?
            //
            // The "reads are broken" note at the top of this file came from FindRowUnchecked
            // returning null for "IT_EqNaked" - but that is NOT a real row name in this table,
            // as the FModel dump later showed. A lookup for a row that does not exist returning
            // null is correct behaviour, not a bug. So the evidence never supported the claim.
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
                { STR("IT_EqACFSlot61"), STR("IT_EqACFSlot61"), 61, L"ACF Mod 1" },
                { STR("IT_EqACFSlot62"), STR("IT_EqACFSlot62"), 62, L"ACF Mod 2" },
                { STR("IT_EqACFSlot63"), STR("IT_EqACFSlot63"), 63, L"ACF Mod 3" },
                { STR("IT_EqACFSlot64"), STR("IT_EqACFSlot64"), 64, L"ACF Mod 4" },
                { STR("IT_EqACFSlot65"), STR("IT_EqACFSlot65"), 65, L"ACF Mod 5" },
                // 66 has no ECamouflageType NAME at all, but it renders fine - CamouflageType is
                // written as a raw byte, and the detour resolves the asset. Proof that the enum
                // is not the ceiling we long assumed it was.
                { STR("IT_EqACFSlot66"), STR("IT_EqACFSlot66"), 66, L"ACF Mod 6" },
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
            SetStringField(rowStruct, buffer.data(), STR("DisplayName"), def.DisplayName);
            // Vanilla uses a loc key here (ユニフォーム説明リソース = "uniform description
            // resource"), but since DisplayName turned out to accept plain text, this very likely
            // does too - it has not been tested separately. Left borrowing NAKED's key because it
            // displays correctly and nothing depends on changing it.
            SetStringField(rowStruct, buffer.data(), STR("DescryptionText"), L"ユニフォーム説明リソース-NAKED");
            SetStringField(rowStruct, buffer.data(), STR("LockDescryptionText"), STR(""));
            SetStringField(rowStruct, buffer.data(), STR("LightName"), STR(""));

            // Thumbnail is a hard object pointer, so we can only set it if the texture happens
            // to be loaded. Borrow a vanilla one - a placeholder image beats a null.
            auto* thumbnail = UObjectGlobals::StaticFindObject<UObject*>(nullptr, nullptr, STR("/CobraUI/textures/sv/camouflage/669275.669275"));
            if (thumbnail != nullptr)
            {
                SetObjectField(rowStruct, buffer.data(), STR("Thumbnail"), thumbnail);
                Output::send<LogLevel::Warning>(STR("[ACF]:   thumbnail set.\n"));
            }
            else
            {
                Output::send<LogLevel::Warning>(STR("[ACF]:   thumbnail texture not loaded - leaving null.\n"));
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
