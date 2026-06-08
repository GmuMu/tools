@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Android 签名证书生成工具

echo ============================================
echo        Android 签名证书生成工具
echo ============================================
echo.

REM ---------- 1. 检查 keytool 是否可用 ----------
where keytool >nul 2>nul
if errorlevel 1 (
    echo [错误] 未检测到 keytool 命令。
    echo        请先安装 JDK 并将 JDK 的 bin 目录加入系统 PATH。
    echo.
    pause
    exit /b 1
)

REM ---------- 2. 输入证书别名 ----------
:input_alias
set "ALIAS="
set /p "ALIAS=请输入证书别名（例如 blzhyqApp）: "
if "!ALIAS!"=="" (
    echo [提示] 别名不能为空,请重新输入。
    goto input_alias
)

REM ---------- 3. 输入密码 ----------
:input_password
set "PASSWORD="
set /p "PASSWORD=请输入密码（至少 6 位）: "
if "!PASSWORD!"=="" (
    echo [提示] 密码不能为空,请重新输入。
    goto input_password
)
set "PWLEN=0"
for /l %%i in (0,1,128) do (
    if not "!PASSWORD:~%%i,1!"=="" set /a PWLEN=%%i+1
)
if !PWLEN! lss 6 (
    echo [提示] 密码长度必须不少于 6 位,当前长度 !PWLEN! 位,请重新输入。
    goto input_password
)

REM ---------- 3.5 选择签名算法 / 密钥长度 ----------
:input_mode
echo.
echo --------------------------------------------
echo 请选择签名方案:
echo   [1] keysize 1024 + SHA1WithRSA   （兼容老项目 / 微信、支付宝老 SDK,与原命令一致）
echo   [2] keysize 2048 + SHA256WithRSA （现代推荐,Google Play 上架要求）
echo --------------------------------------------
set "MODE="
set /p "MODE=请输入 1 或 2 (回车默认 1): "
if "!MODE!"=="" set "MODE=1"

if "!MODE!"=="1" (
    set "KEYSIZE=1024"
    set "SIGALG=SHA1WithRSA"
    set "MODE_DESC=keysize 1024 + SHA1WithRSA （兼容老项目）"
) else if "!MODE!"=="2" (
    set "KEYSIZE=2048"
    set "SIGALG=SHA256WithRSA"
    set "MODE_DESC=keysize 2048 + SHA256WithRSA （现代推荐）"
) else (
    echo [提示] 无效输入,请输入 1 或 2。
    goto input_mode
)
echo 已选择: !MODE_DESC!

REM ---------- 3.6 是否在指纹 txt 中保存明文密码 ----------
echo.
echo --------------------------------------------
echo 是否在指纹信息 txt 中保存密码（明文）?
echo   注意: 密码明文存盘有泄露风险,建议仅在私人环境下使用。
echo --------------------------------------------
set "INCLUDE_PWD="
set /p "INCLUDE_PWD=输入 y 表示保存密码,其他任意键不保存 (回车默认不保存): "
if /i "!INCLUDE_PWD!"=="y" (
    set "PWD_DESC=是"
) else (
    set "INCLUDE_PWD=n"
    set "PWD_DESC=否"
)
echo 已选择: !PWD_DESC!保存密码

REM ---------- 4. 弹出文件夹选择对话框 ----------
echo.
echo 请在弹出的窗口中选择证书保存目录...
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = 'Select keystore save directory'; $f.ShowNewFolderButton = $true; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $f.SelectedPath }"`) do set "SAVEDIR=%%i"

if "!SAVEDIR!"=="" (
    echo [错误] 未选择保存目录,操作已取消。
    pause
    exit /b 1
)

REM 去掉末尾可能的反斜杠
if "!SAVEDIR:~-1!"=="\" set "SAVEDIR=!SAVEDIR:~0,-1!"

set "KEYSTORE_FILE=!SAVEDIR!\!ALIAS!.keystore"
set "FINGERPRINT_FILE=!SAVEDIR!\!ALIAS!_证书指纹信息.txt"

echo.
echo 保存目录: !SAVEDIR!
echo 证书文件: !KEYSTORE_FILE!
echo 指纹文件: !FINGERPRINT_FILE!
echo.

REM ---------- 5. 文件已存在则确认覆盖 ----------
if exist "!KEYSTORE_FILE!" (
    set "OVERWRITE="
    set /p "OVERWRITE=证书文件已存在,是否覆盖? (y/n): "
    if /i not "!OVERWRITE!"=="y" (
        echo 已取消。
        pause
        exit /b 0
    )
    del /q "!KEYSTORE_FILE!" 2>nul
)

echo.
echo ============================================
echo  [1/2] 正在生成证书 ...
echo ============================================

REM ---------- 6. 生成证书（永久 = 36500 天 / 约 100 年）----------
keytool -genkeypair ^
    -alias "!ALIAS!" ^
    -keyalg RSA ^
    -sigalg !SIGALG! ^
    -keysize !KEYSIZE! ^
    -validity 36500 ^
    -keystore "!KEYSTORE_FILE!" ^
    -storepass "!PASSWORD!" ^
    -keypass "!PASSWORD!" ^
    -dname "CN=!ALIAS!, OU=Android, O=Android, L=Beijing, ST=Beijing, C=CN" ^
    -v

if errorlevel 1 (
    echo.
    echo [错误] 证书生成失败,请检查上方错误信息。
    pause
    exit /b 1
)

echo.
echo ============================================
echo  [2/2] 正在提取证书指纹（MD5 / SHA1 / SHA256）...
echo ============================================

REM ---------- 7. 写指纹 txt（UTF-8 BOM）----------
REM 步骤: 头部 (UTF-8) 与 keytool 输出 (GBK) 分别写到两个临时文件,
REM 然后用 PowerShell 分别按对应编码读入,合并后整体写出 UTF-8 BOM。
set "TMP_HDR=%TEMP%\_ks_hdr_%RANDOM%.txt"
set "TMP_KT=%TEMP%\_ks_kt_%RANDOM%.txt"

(
    echo ============================================
    echo  Android 签名证书指纹信息
    echo ============================================
    echo  别名       : !ALIAS!
    echo  证书文件   : !KEYSTORE_FILE!
    echo  有效期     : 36500 天（约 100 年）
    echo  签名算法   : !SIGALG!
    echo  密钥长度   : !KEYSIZE!
    if /i "!INCLUDE_PWD!"=="y" echo  密码       : !PASSWORD!
    echo  生成时间   : %DATE% %TIME%
    echo ============================================
    echo.
) > "!TMP_HDR!"

keytool -list -v -keystore "!KEYSTORE_FILE!" -storepass "!PASSWORD!" -alias "!ALIAS!" > "!TMP_KT!" 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$h = [IO.File]::ReadAllText('!TMP_HDR!', (New-Object System.Text.UTF8Encoding $false));" ^
  "$k = [IO.File]::ReadAllText('!TMP_KT!', [System.Text.Encoding]::GetEncoding(936));" ^
  "[IO.File]::WriteAllText('!FINGERPRINT_FILE!', $h + $k, (New-Object System.Text.UTF8Encoding $true))"

if errorlevel 1 (
    echo [警告] 指纹信息保存失败,请检查 !FINGERPRINT_FILE!
) else (
    echo 指纹信息已保存（UTF-8 with BOM）。
)

del "!TMP_HDR!" 2>nul
del "!TMP_KT!" 2>nul

echo.
echo ============================================
echo                生成成功！
echo ============================================
echo  证书文件: !KEYSTORE_FILE!
echo  指纹文件: !FINGERPRINT_FILE!
echo ============================================
echo.

REM ---------- 8. 询问是否打开保存目录 ----------
set "OPENDIR="
set /p "OPENDIR=是否打开保存目录? (y/n): "
if /i "!OPENDIR!"=="y" (
    explorer "!SAVEDIR!"
)

echo.
pause
endlocal
exit /b 0
