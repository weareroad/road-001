@echo off
setlocal

sjasmplus main.asm
if errorlevel 1 exit /b %errorlevel%

echo Built road-001.sna
