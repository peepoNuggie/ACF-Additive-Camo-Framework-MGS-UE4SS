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

    class ACF : public RC::CppUserModBase {
    public:
        bool m_registered = false;

        ACF() {
            ModVersion = STR("0.1");
            ModName = STR("ACF");
            ModAuthors = STR("UE4SS");
            ModDescription = STR("Additive Camo Framework");
            Output::send<LogLevel::Warning>(STR("[ACF]: Init.\n"));
        }

        ~ACF() override {
        }

        auto on_program_start() -> void override {}
        auto on_dll_load(std::wstring_view dll_name) -> void override {}
        auto on_unreal_init() -> void override {}

        auto RegisterCamo(const wchar_t* itemName, const wchar_t* rowName, int32_t camoValue, UDataTable* dataTable, const wchar_t* sourceRowName) -> void
{
    auto camoEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/MGS3.ECamouflageType"));
    auto itemEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/MGS3.EItemName"));
    auto gsrItemEnum = UObjectGlobals::StaticFindObject<UEnum*>(nullptr, nullptr, STR("/Script/Gsr.EGsrItemId"));

    if (camoEnum == nullptr || itemEnum == nullptr || gsrItemEnum == nullptr)
    {
        Output::send<LogLevel::Warning>(STR("[ACF]: One or more enums not found.\n"));
        return;
    }

    auto camoIndex = camoEnum->NumEnums();
    auto itemIndex = itemEnum->NumEnums();
    auto gsrIndex = gsrItemEnum->NumEnums();

    camoEnum->InsertIntoNames(TPair<FName, int64>{FName(rowName, FNAME_Add), camoValue}, camoIndex, false);
    itemEnum->InsertIntoNames(TPair<FName, int64>{FName(itemName, FNAME_Add), itemIndex}, itemIndex, false);
    gsrItemEnum->InsertIntoNames(TPair<FName, int64>{FName(itemName, FNAME_Add), gsrIndex}, gsrIndex, false);

    auto rowStruct = dataTable->GetRowStruct();
    auto rowSize = rowStruct->GetPropertiesSize();

    // Start from a REAL existing row's data instead of zeros
    auto sourceRow = dataTable->FindRowUnchecked(FName(sourceRowName, FNAME_Find));
    std::vector<uint8_t> buffer(rowSize, 0);
    if (sourceRow != nullptr)
    {
        memcpy(buffer.data(), sourceRow, rowSize);
        Output::send<LogLevel::Warning>(STR("[ACF]: Copied data from existing row {}.\n"), sourceRowName);
    }
    else
    {
        Output::send<LogLevel::Warning>(STR("[ACF]: Source row {} not found, using blank buffer.\n"), sourceRowName);
    }

    // Now override just the CamouflageType to our new value
    auto camoProp = rowStruct->GetPropertyByNameInChain(STR("CamouflageType"));
    if (camoProp != nullptr)
    {
        auto valuePtr = camoProp->ContainerPtrToValuePtr<uint8_t>(buffer.data());
        *valuePtr = static_cast<uint8_t>(camoValue);
    }

    // ItemType links this row back to the EItemName entry we just registered.
    // Leaving this at 0 likely files the row under the wrong item category,
    // which would explain it not showing up in the camo menu at all.
    auto itemTypeProp = rowStruct->GetPropertyByNameInChain(STR("ItemType"));
    if (itemTypeProp != nullptr)
    {
        auto valuePtr = itemTypeProp->ContainerPtrToValuePtr<uint8_t>(buffer.data());
        *valuePtr = static_cast<uint8_t>(itemIndex);
        Output::send<LogLevel::Warning>(STR("[ACF]: Set ItemType to {}.\n"), itemIndex);
    }
    else
    {
        Output::send<LogLevel::Warning>(STR("[ACF]: ItemType field not found!\n"));
    }

    auto SetBoolField = [&](const wchar_t* fieldName, bool value)
    {
        auto prop = rowStruct->GetPropertyByNameInChain(fieldName);
        if (prop != nullptr)
        {
            auto ptr = prop->ContainerPtrToValuePtr<uint8_t>(buffer.data());
            *ptr = value ? 1 : 0;
            Output::send<LogLevel::Warning>(STR("[ACF]: Set {} successfully.\n"), fieldName);
        }
        else
        {
            Output::send<LogLevel::Warning>(STR("[ACF]: Field {} not found!\n"), fieldName);
        }
    };

    SetBoolField(STR("IsShowLockDescryptionText"), false);
    SetBoolField(STR("IsHiddenItem"), false);
    SetBoolField(STR("IsAdditionalItem"), false);

    dataTable->AddRow(FName(rowName, FNAME_Add), buffer.data(), rowStruct);

    Output::send<LogLevel::Warning>(STR("[ACF]: RegisterCamo complete.\n"));
}

        auto on_update() -> void override
        {
            if (m_registered) { return; }

            auto dataTable = UObjectGlobals::StaticFindObject<UDataTable*>(nullptr, nullptr, STR("/CobraUI/Data/Collection/Camouflage/DT_CamouflageCollection.DT_CamouflageCollection"));
            if (dataTable == nullptr)
            {
                return;
            }

            m_registered = true;
            RegisterCamo(STR("IT_EqACFTest2"), STR("IT_EqACFTest2"), 72, dataTable, STR("IT_EqNaked"));
        }
    };//class
}

#define MOD_EXPORT __declspec(dllexport)
extern "C" {
    MOD_EXPORT RC::CppUserModBase* start_mod() { return new MyMods::ACF(); }
    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}