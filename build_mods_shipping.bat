@echo off
REM No -G on purpose - CMake picks the newest Visual Studio it finds. Naming a
REM version you do not have fails outright ("could not find any instance of
REM Visual Studio"). This used to hardcode "Visual Studio 17 2022", which fails
REM on a machine with VS 2026; it went unnoticed because there was no errorlevel
REM check, so the build line below still ran against an existing build folder.
REM
REM -T v143 pins the toolset RE-UE4SS c838a8ac builds against.
REM
REM Changing Visual Studio versions? DELETE the build folder first - CMake will
REM not reconfigure an existing cache under a different generator.

cmake -B build -T v143 .
if errorlevel 1 goto :failed

cmake --build build --config Game__Shipping__Win64
if errorlevel 1 goto :failed

echo.
echo Built: build\MyCPPMods\ACF\Game__Shipping__Win64\ACF.dll
echo Copy it over ue4ss\Mods\ACF-CPP\dlls\main.dll with the game CLOSED.
pause
exit /b 0

:failed
echo.
echo BUILD FAILED - see the output above.
pause
exit /b 1