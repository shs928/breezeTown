@echo off
rem Direct game launch (bypasses editor + debugger). Close the Godot editor first for best performance.
start "" "%~dp0tools\engine\Godot-4.7.2-stable\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game"
