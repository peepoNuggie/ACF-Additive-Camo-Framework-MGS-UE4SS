cmake_minimum_required(VERSION 3.22)

set(TARGET ACF)
project(${TARGET})

add_library(${TARGET} SHARED "src/dllmain.cpp")
target_include_directories(${TARGET} PRIVATE .)

# PolyHook_2 is already a UE4SS dependency (it uses it for IAT hooks), so we get it for free.
#
# We need it because the camo asset lookup is native-to-native: UE4SS's RegisterHook only
# intercepts calls dispatched through Unreal's VM, and the shipped game calls
# UAssetManager::GetPrimaryAssetData (FUN_143bee420) directly. A machine-code detour is the
# only way to observe or alter that call.
target_link_libraries(${TARGET} PRIVATE UE4SS PolyHook_2)
