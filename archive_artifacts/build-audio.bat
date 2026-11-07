@echo off
setlocal

sjasmplus main-audio.asm
if errorlevel 1 exit /b %errorlevel%

echo Built pt3-audio.sna
