@echo off
rem Runs ward-fix.ps1 as administrator (Windows will show a UAC prompt - press Yes).
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0ward-fix.ps1\"'"
