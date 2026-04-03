@echo off
setlocal

pushd "%~dp0.."

echo Formatting...
call dart format lib
if errorlevel 1 goto :fail

echo Analyzing...
call flutter analyze
if errorlevel 1 goto :fail

echo Building Windows (debug)...
call flutter build windows --debug
if errorlevel 1 goto :fail

echo Done
popd
exit /b 0

:fail
set "exit_code=%errorlevel%"
popd
exit /b %exit_code%
