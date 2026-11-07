@echo off
setlocal

sjasmplus main-48.asm
if errorlevel 1 exit /b %errorlevel%

echo Built demo-48.sna
