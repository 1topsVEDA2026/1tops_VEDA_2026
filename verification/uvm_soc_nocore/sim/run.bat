@echo off
REM ==============================================================================
REM run.bat - One-click Windows Batch execution script for QuestaSim
REM ==============================================================================
echo Launching QuestaSim SoC No-Core UVM Verification Environment...
cd /d "%~dp0"
vsim -do run_questa.do
pause
