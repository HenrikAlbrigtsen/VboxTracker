@echo off
title VBoxTracker
echo  ___  ___          _____               _
echo  \  \/  /         |_   _|             | |
echo   \    /  _ __     | |_ __ __ _  ___ | | _____ _ __
echo   /    \ ^| '_ \    | | '__/ _` |/ __|| |/ / _ \ '__|
echo  /  /\  \^| |_) ^|   | | ^| ^| (_^| ^| (__ ^|   <  __/ ^|
echo  \_^|  ^|_/^| .__/    \_/_^|  \__,_^|\___^||_^|\_\___^|_^|
echo           ^| ^|
echo           ^|_^|
echo.
echo  Starting VirtualBox session tracker...
echo  Dashboard: open dashboard.html in your browser
echo.
echo  Press Ctrl+C to stop tracking.
echo.

PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VBoxTracker.ps1"
pause
