@echo off
setlocal enabledelayedexpansion

if "%BPB_SCAN_CMD%"=="" (
  echo BPB_SCAN_CMD is required
  exit /b 1
)

rem Defensive validation: reject unsafe shell metacharacters in command env vars.
echo(%BPB_SCAN_CMD%| findstr /r "[&|<>]" >nul
if %ERRORLEVEL%==0 (
  echo BPB_SCAN_CMD contains unsupported shell metacharacters (^& ^| ^< ^>)
  exit /b 1
)
if not "%BPB_APPLY_CMD%"=="" (
  echo(%BPB_APPLY_CMD%| findstr /r "[&|<>]" >nul
  if %ERRORLEVEL%==0 (
    echo BPB_APPLY_CMD contains unsupported shell metacharacters (^& ^| ^< ^>)
    exit /b 1
  )
)

set "STATE_DIR=%BPB_STATE_DIR%"
if "%STATE_DIR%"=="" set "STATE_DIR=C:\bpb-automation\state"

set "LOG_DIR=%BPB_LOG_DIR%"
if "%LOG_DIR%"=="" set "LOG_DIR=C:\bpb-automation\logs"

set "HOST_LABEL=%BPB_HOST_LABEL%"
if "%HOST_LABEL%"=="" set "HOST_LABEL=windows-host"

set "UPDATE_MODE=%BPB_UPDATE_MODE%"
if "%UPDATE_MODE%"=="" set "UPDATE_MODE=command"

set "SCAN_RETRIES=%BPB_SCAN_RETRIES%"
if "%SCAN_RETRIES%"=="" set "SCAN_RETRIES=3"

set "APPLY_RETRIES=%BPB_APPLY_RETRIES%"
if "%APPLY_RETRIES%"=="" set "APPLY_RETRIES=3"

set "RETRY_DELAY_MS=%BPB_RETRY_DELAY_MS%"
if "%RETRY_DELAY_MS%"=="" set "RETRY_DELAY_MS=1000"

set "TRIGGER=%1"
if "%TRIGGER%"=="" set "TRIGGER=scheduled"

cd /d C:\bpb-automation\backend

if "%BPB_APPLY_CMD%"=="" (
  dart run bin\bpb_autoscan.dart run-once --state-dir "%STATE_DIR%" --log-dir "%LOG_DIR%" --trigger "%TRIGGER%" --host-label "%HOST_LABEL%" --update-mode "%UPDATE_MODE%" --scan-retries "%SCAN_RETRIES%" --apply-retries "%APPLY_RETRIES%" --initial-retry-delay-ms "%RETRY_DELAY_MS%" --scan-cmd "%BPB_SCAN_CMD%"
) else (
  dart run bin\bpb_autoscan.dart run-once --state-dir "%STATE_DIR%" --log-dir "%LOG_DIR%" --trigger "%TRIGGER%" --host-label "%HOST_LABEL%" --update-mode "%UPDATE_MODE%" --scan-retries "%SCAN_RETRIES%" --apply-retries "%APPLY_RETRIES%" --initial-retry-delay-ms "%RETRY_DELAY_MS%" --scan-cmd "%BPB_SCAN_CMD%" --apply --apply-cmd "%BPB_APPLY_CMD%"
)
exit /b %ERRORLEVEL%
