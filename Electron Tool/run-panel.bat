@echo off
setlocal
cd /d "%~dp0"

if not exist node_modules (
  echo [INFO] node_modules が見つからないため npm install を実行します...
  call npm install
  if errorlevel 1 (
    echo [ERROR] npm install に失敗しました。
    exit /b 1
  )
)

echo [INFO] UnLimiteD RR Panel を起動します...
call npm start
endlocal
