@echo off
setlocal


:: 設定下載的 DLL 文件 URL
set WINDOWS_DLL_URL=https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-windows-x86_64-2.15.0.zip
set LINUX_DLL_URL=https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-2.15.0.tar.gz


:: 設定下載後的文件名
set WINDOWS_DLL_NAME=%~dp0libtensorflow-cpu-windows-x86_64-2.15.0.zip
set LINUX_DLL_NAME=%~dp0libtensorflow-cpu-linux-x86_64-2.15.0.tar.gz


:: 設定解壓縮的目錄
set LIB_DIR=%~dp0lib\tensorflow


:: 檢查 lib/tensorflow 目錄是否存在
if exist "%LIB_DIR%" (
    echo The directory %LIB_DIR% already exists. Exiting...
    pause
    exit /b
)

:: 檢查是否已存在 WINDOWS DLL 文件
if exist "%WINDOWS_DLL_NAME%" (
    echo %WINDOWS_DLL_NAME% already exists.
) else (
    echo Downloading %WINDOWS_DLL_NAME%...
    powershell -Command "Invoke-WebRequest -Uri %WINDOWS_DLL_URL% -OutFile %WINDOWS_DLL_NAME%"
    
    if exist "%WINDOWS_DLL_NAME%" (
        echo %WINDOWS_DLL_NAME% downloaded successfully.
    ) else (
        echo Failed to download %WINDOWS_DLL_NAME%.
    )
)


:: 檢查是否已存在 LINUX DLL 文件
if exist "%LINUX_DLL_NAME%" (
    echo %LINUX_DLL_NAME% already exists.
) else (
    echo Downloading %LINUX_DLL_NAME%...
    powershell -Command "Invoke-WebRequest -Uri %LINUX_DLL_URL% -OutFile %LINUX_DLL_NAME%"
    
    if exist "%LINUX_DLL_NAME%" (
        echo %LINUX_DLL_NAME% downloaded successfully.
    ) else (
        echo Failed to download %LINUX_DLL_NAME%.
    )
)



:: 檢查 lib 目錄是否存在，若不存在則創建
if not exist "%LIB_DIR%" (
    mkdir "%LIB_DIR%"
    echo Created directory: %LIB_DIR%
)


:: 解壓縮 LINUX tar 文件到 lib 目錄
echo Extracting %LINUX_DLL_NAME% to %LIB_DIR%...
powershell -Command "tar -xzf '%LINUX_DLL_NAME%' -C '%LIB_DIR%'"


:: 刪除臨時目錄
echo Cleaning up temporary files...
rmdir "%LIB_DIR%/lib" /s /q


:: 解壓縮 WINDOWS ZIP 文件到 lib 目錄
echo Extracting %WINDOWS_DLL_NAME% to %LIB_DIR%...
powershell -Command "Expand-Archive -Path '%WINDOWS_DLL_NAME%' -DestinationPath '%LIB_DIR%' -Force"


endlocal
pause
