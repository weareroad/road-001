@echo off
setlocal

sjasmplus main-loader.asm
if errorlevel 1 exit /b %errorlevel%

echo Built loader-test.sna
