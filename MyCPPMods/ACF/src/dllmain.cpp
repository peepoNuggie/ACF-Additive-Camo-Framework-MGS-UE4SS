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
#include <vector>

namespace MyMods
{
    using namespace RC;
    using namespace Unreal;

    // One entry per camo to add. Adding a camo should be a matter of adding a line here.
    struct ACFCamoDef
    {
        const wchar_t* ItemName;   // EItemName / EGsrItemId entry name
        const wchar_t* RowName;    // DataTable row key and ECamouflageType entry name
        int32_t        CamoValue;  // ECamouflageType numeric value (vanilla uses 0-70)
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

            // The sort table drives display ORDER in the viewer. It is optional: a missing
            // sort entry must never block the main registration (it silently did once).
            auto* sortTable = FindTable(STR("/CobraUI/Data/SV/DT_UniformSortDelta.DT_UniformSortDelta"));
            if (sortTable == nullptr)
            {
                Output::send<LogLevel::Warning>(STR("[ACF]: DT_UniformSortDelta not loaded - skipping sort registration.\n"));
            }

            // EXPERIMENT (ordering is deliberate, do not shuffle without reading this):
            //
            // Last test registered 72 then 73 and only ONE new row appeared. Camo 72 was both
            // FIRST in the list and the ONLY one with a packaged Camouf_<id>_asset .pak, so two
            // different explanations predicted the same result:
            //     (a) only the first registration actually takes effect, or
            //     (b) only camos that have a matching .pak asset get rendered.
            //
            // Putting 72 LAST separates them:
            //     only 72 visible      -> (b), the .pak asset is required
            //     only 73 visible      -> (a), only the first registration works
            //     all three visible    -> neither; the earlier count was simply wrong
            static const ACFCamoDef camos[] = {
                { STR("IT_EqACFTest3"), STR("IT_EqACFTest3"), 73 },  // no .pak
                { STR("IT_EqACFTest4"), STR("IT_EqACFTest4"), 74 },  // no .pak
                { STR("IT_EqACFTest2"), STR("IT_EqACFTest2"), 72 },  // has ACF_Sneaking72_P.pak
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

        static auto FindTable(const wchar_t* path) -> UDataTable*
        {
            return UObjectGlobals::StaticFindObject<UDataTable*>(nullptr, nullptr, path);
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

            camoEnum->InsertIntoNames(TPair<FName, int64>{ FName(def.RowName, FNAME_Add), def.CamoValue }, camoEnum->NumEnums(), false);
            itemEnum->InsertIntoNames(TPair<FName, int64>{ FName(def.ItemName, FNAME_Add), itemIndex }, itemIndex, false);
            gsrItemEnum->InsertIntoNames(TPair<FName, int64>{ FName(def.ItemName, FNAME_Add), gsrItemEnum->NumEnums() }, gsrItemEnum->NumEnums(), false);

            auto rowStruct = dataTable->GetRowStruct();
            const auto rowSize = rowStruct->GetPropertiesSize();
            std::vector<uint8_t> buffer(rowSize, 0);

            // Ideally we would clone a real row here so the new one inherits Thumbnail,
            // DisplayName, AssetID, ModelAsset and FaceOption. That does not work: TMap reads
            // are broken on this build, so FindRowUnchecked returns null for every row name we
            // try, including ones we can see in the shipped table. The row therefore goes in
            // as an all-zero blank plus the few fields set below.
            //
            // A blank row is still enough to produce a visible Collection Viewer entry (it
            // reads as an unacquired "No Data" slot), but it will never display properly until
            // we can populate those fields. Doing that means constructing FString/FText/soft
            // object references by hand rather than copying them - see the project notes.
            SetByteField(rowStruct, buffer.data(), STR("CamouflageType"), static_cast<uint8_t>(def.CamoValue));
            SetByteField(rowStruct, buffer.data(), STR("ItemType"), static_cast<uint8_t>(itemIndex));
            SetByteField(rowStruct, buffer.data(), STR("IsShowLockDescryptionText"), 0);  // sic - typo is the game's
            SetByteField(rowStruct, buffer.data(), STR("IsHiddenItem"), 0);
            SetByteField(rowStruct, buffer.data(), STR("IsAdditionalItem"), 0);

            dataTable->AddRow(FName(def.RowName, FNAME_Add), buffer.data(), rowStruct);

            Output::send<LogLevel::Warning>(STR("[ACF]:   added collection row (ItemType {}).\n"), itemIndex);
            return true;
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
