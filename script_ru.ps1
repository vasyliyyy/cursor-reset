$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

Write-Host "$GREEN[Информация]$NC Закрытие Cursor перед началом работы..."
Get-Process -Name "cursor" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Ошибка]$NC Пожалуйста, запустите скрипт от имени администратора"
    Write-Host "Нажмите правой кнопкой мыши на скрипт и выберите 'Запуск от имени администратора'"
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

Clear-Host
Write-Host @"

    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN   Инструмент изменения ID устройства Cursor          $NC"
Write-Host "$BLUE================================$NC"
Write-Host ""

function Get-CursorVersion {
    try {
        $packagePath = "$env:LOCALAPPDATA\Programs\cursor\resources\app\package.json"
        
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Информация]$NC Текущая версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        $altPath = "$env:LOCALAPPDATA\cursor\resources\app\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Информация]$NC Текущая версия Cursor: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "$YELLOW[Предупреждение]$NC Невозможно определить версию Cursor"
        Write-Host "$YELLOW[Подсказка]$NC Убедитесь, что Cursor установлен правильно"
        return $null
    }
    catch {
        Write-Host "$RED[Ошибка]$NC Не удалось получить версию Cursor: $_"
        return $null
    }
}

$cursorVersion = Get-CursorVersion
Write-Host ""

Write-Host "$YELLOW[Важное примечание]$NC Последняя версия 0.47.x (поддерживается)"
Write-Host ""

Write-Host "$GREEN[Информация]$NC Проверка процессов Cursor..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[Отладка]$NC Получение подробной информации о процессе $processName:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" | 
        Select-Object ProcessId, ExecutablePath, CommandLine | 
        Format-List
}

$MAX_RETRIES = 5
$WAIT_TIME = 1

function Close-CursorProcess {
    param($processName)
    
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[Предупреждение]$NC Обнаружен запущенный процесс $processName"
        Get-ProcessDetails $processName
        
        Write-Host "$YELLOW[Предупреждение]$NC Попытка закрыть $processName..."
        Stop-Process -Name $processName -Force
        
        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }
            
            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[Ошибка]$NC Не удалось закрыть $processName после $MAX_RETRIES попыток"
                Get-ProcessDetails $processName
                Write-Host "$RED[Ошибка]$NC Пожалуйста, закройте процесс вручную и попробуйте снова"
                Read-Host "Нажмите Enter для выхода"
                exit 1
            }
            Write-Host "$YELLOW[Предупреждение]$NC Ожидание закрытия процесса, попытка $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[Информация]$NC $processName успешно закрыт"
    }
}

Close-CursorProcess "Cursor"
Close-CursorProcess "cursor"

if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

if (Test-Path $STORAGE_FILE) {
    Write-Host "$GREEN[Информация]$NC Создание резервной копии конфигурационного файла..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

Write-Host "$GREEN[Информация]$NC Генерация нового ID..."

function Get-RandomHex {
    param (
        [int]$length
    )
    
    $bytes = New-Object byte[] ($length)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    $hexString = [System.BitConverter]::ToString($bytes) -replace '-',''
    $rng.Dispose()
    return $hexString
}

function New-StandardMachineId {
    $template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    $result = $template -replace '[xy]', {
        param($match)
        $r = [Random]::new().Next(16)
        $v = if ($match.Value -eq "x") { $r } else { ($r -band 0x3) -bor 0x8 }
        return $v.ToString("x")
    }
    return $result
}

$MAC_MACHINE_ID = New-StandardMachineId
$UUID = [System.Guid]::NewGuid().ToString()
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
$prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
$randomPart = Get-RandomHex -length 32
$MACHINE_ID = "$prefixHex$randomPart"
$SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "$RED[Ошибка]$NC Пожалуйста, запустите скрипт от имени администратора"
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Update-MachineGuid {
    try {
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW[Предупреждение]$NC Путь реестра не существует: $registryPath, создание..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN[Информация]$NC Путь реестра успешно создан"
        }

        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN[Информация]$NC Текущее значение реестра:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography" 
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW[Предупреждение]$NC Значение MachineGuid не существует, будет создано новое"
            }
        } catch {
            Write-Host "$YELLOW[Предупреждение]$NC Не удалось получить MachineGuid: $($_.Exception.Message)"
        }

        if (-not (Test-Path $BACKUP_DIR)) {
            New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        }

        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru
            
            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Информация]$NC Резервная копия реестра создана: $backupFile"
            } else {
                Write-Host "$YELLOW[Предупреждение]$NC Не удалось создать резервную копию, продолжаем..."
            }
        }

        $newGuid = [System.Guid]::NewGuid().ToString()

        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop
        
        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Ошибка проверки реестра: обновленное значение ($verifyGuid) не соответствует ожидаемому ($newGuid)"
        }

        Write-Host "$GREEN[Информация]$NC Реестр успешно обновлен:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED[Ошибка]$NC Операция с реестром не удалась: $($_.Exception.Message)"
        
        if (($backupFile -ne $null) -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW[Восстановление]$NC Восстановление из резервной копии..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru
            
            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Восстановление успешно]$NC Оригинальное значение реестра восстановлено"
            } else {
                Write-Host "$RED[Ошибка]$NC Восстановление не удалось, импортируйте резервную копию вручную: $backupFile"
            }
        } else {
            Write-Host "$YELLOW[Предупреждение]$NC Резервная копия не найдена или не создана, автоматическое восстановление невозможно"
        }
        return $false
    }
}

Write-Host "$GREEN[Информация]$NC Обновление конфигурации..."

try {
    if (-not (Test-Path $STORAGE_FILE)) {
        Write-Host "$RED[Ошибка]$NC Конфигурационный файл не найден: $STORAGE_FILE"
        Write-Host "$YELLOW[Подсказка]$NC Пожалуйста, сначала установите и запустите Cursor, затем используйте этот скрипт"
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }

    try {
        $originalContent = Get-Content $STORAGE_FILE -Raw -Encoding UTF8
        $config = $originalContent | ConvertFrom-Json 

        $oldValues = @{
            'machineId' = $config.'telemetry.machineId'
            'macMachineId' = $config.'telemetry.macMachineId'
            'devDeviceId' = $config.'telemetry.devDeviceId'
            'sqmId' = $config.'telemetry.sqmId'
        }

        $config.'telemetry.machineId' = $MACHINE_ID
        $config.'telemetry.macMachineId' = $MAC_MACHINE_ID
        $config.'telemetry.devDeviceId' = $UUID
        $config.'telemetry.sqmId' = $SQM_ID

        $updatedJson = $config | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($STORAGE_FILE), 
            $updatedJson, 
            [System.Text.Encoding]::UTF8
        )
        Write-Host "$GREEN[Информация]$NC Конфигурационный файл успешно обновлен"
    } catch {
        if ($originalContent) {
            [System.IO.File]::WriteAllText(
                [System.IO.Path]::GetFullPath($STORAGE_FILE), 
                $originalContent, 
                [System.Text.Encoding]::UTF8
            )
        }
        throw "Ошибка обработки JSON: $_"
    }

    Update-MachineGuid

    Write-Host ""
    Write-Host "$GREEN[Информация]$NC Конфигурация обновлена:"
    Write-Host "$BLUE[Отладка]$NC machineId: $MACHINE_ID"
    Write-Host "$BLUE[Отладка]$NC macMachineId: $MAC_MACHINE_ID"
    Write-Host "$BLUE[Отладка]$NC devDeviceId: $UUID"
    Write-Host "$BLUE[Отладка]$NC sqmId: $SQM_ID"

    Write-Host ""
    Write-Host "$GREEN[Информация]$NC Структура файлов:"
    Write-Host "$BLUE$env:APPDATA\Cursor\User$NC"
    Write-Host "├── globalStorage"
    Write-Host "│   ├── storage.json (изменен)"
    Write-Host "│   └── backups"

    $backupFiles = Get-ChildItem "$BACKUP_DIR\*" -ErrorAction SilentlyContinue
    if ($backupFiles) {
        foreach ($file in $backupFiles) {
            Write-Host "│       └── $($file.Name)"
        }
    } else {
        Write-Host "│       └── (пусто)"
    }

    Write-Host ""
    Write-Host "$GREEN================================$NC"
    Write-Host "$YELLOW  Подпишитесь на канал 【煎饼果子卷AI】 для обсуждения приемов работы с Cursor и знаний об AI (скрипт бесплатный, подписывайтесь на канал для вступления в группу)  $NC"
    Write-Host "$GREEN================================$NC"
    Write-Host ""
    Write-Host "$GREEN[Информация]$NC Пожалуйста, перезапустите Cursor для применения новой конфигурации"
    Write-Host ""

    Write-Host ""
    Write-Host "$YELLOW[Вопрос]$NC Хотите отключить автоматическое обновление Cursor?"
    Write-Host "0) Нет - оставить настройки по умолчанию (нажмите Enter)"
    Write-Host "1) Да - отключить автоматическое обновление"
    $choice = Read-Host "Выберите опцию (0)"

    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "$GREEN[Информация]$NC Обработка автоматического обновления..."
        $updaterPath = "$env:LOCALAPPDATA\cursor-updater"

        function Show-ManualGuide {
            Write-Host ""
            Write-Host "$YELLOW[Предупреждение]$NC Автоматическая настройка не удалась, попробуйте выполнить вручную:"
            Write-Host "$YELLOWШаги для отключения обновлений вручную:$NC"
            Write-Host "1. Откройте PowerShell от имени администратора"
            Write-Host "2. Скопируйте и вставьте следующие команды:"
            Write-Host "$BLUEКоманда 1 - Удалить существующую директорию (если есть):$NC"
            Write-Host "Remove-Item -Path `"$updaterPath`" -Force -Recurse -ErrorAction SilentlyContinue"
            Write-Host ""
            Write-Host "$BLUEКоманда 2 - Создать блокирующий файл:$NC"
            Write-Host "New-Item -Path `"$updaterPath`" -ItemType File -Force | Out-Null"
            Write-Host ""
            Write-Host "$BLUEКоманда 3 - Установить атрибут только для чтения:$NC"
            Write-Host "Set-ItemProperty -Path `"$updaterPath`" -Name IsReadOnly -Value `$true"
            Write-Host ""
            Write-Host "$BLUEКоманда 4 - Установить разрешения (опционально):$NC"
            Write-Host "icacls `"$updaterPath`" /inheritance:r /grant:r `"`$($env:USERNAME):(R)`""
            Write-Host ""
            Write-Host "$YELLOWМетод проверки:$NC"
            Write-Host "1. Выполните команду: Get-ItemProperty `"$updaterPath`""
            Write-Host "2. Убедитесь, что IsReadOnly имеет значение True"
            Write-Host "3. Выполните команду: icacls `"$updaterPath`""
            Write-Host "4. Убедитесь, что есть только права на чтение"
            Write-Host ""
            Write-Host "$YELLOW[Подсказка]$NC После завершения перезапустите Cursor"
        }

        try {
            if (Test-Path $updaterPath) {
                if ((Get-Item $updaterPath) -is [System.IO.FileInfo]) {
                    Write-Host "$GREEN[Информация]$NC Файл блокировки обновлений уже создан"
                    return
                }
                else {
                    try {
                        Remove-Item -Path $updaterPath -Force -Recurse -ErrorAction Stop
                        Write-Host "$GREEN[Информация]$NC Директория cursor-updater успешно удалена"
                    }
                    catch {
                        Write-Host "$RED[Ошибка]$NC Не удалось удалить директорию cursor-updater"
                        Show-ManualGuide
                        return
                    }
                }
            }

            try {
                New-Item -Path $updaterPath -ItemType File -Force -ErrorAction Stop | Out-Null
                Write-Host "$GREEN[Информация]$NC Файл блокировки успешно создан"
            }
            catch {
                Write-Host "$RED[Ошибка]$NC Не удалось создать файл блокировки"
                Show-ManualGuide
                return
            }

            try {
                Set-ItemProperty -Path $updaterPath -Name IsReadOnly -Value $true -ErrorAction Stop
                
                $result = Start-Process "icacls.exe" -ArgumentList "`"$updaterPath`" /inheritance:r /grant:r `"$($env:USERNAME):(R)`"" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -ne 0) {
                    throw "Команда icacls не выполнена"
                }
                
                Write-Host "$GREEN[Информация]$NC Разрешения файла успешно установлены"
            }
            catch {
                Write-Host "$RED[Ошибка]$NC Не удалось установить разрешения файла"
                Show-ManualGuide
                return
            }

            try {
                $fileInfo = Get-ItemProperty $updaterPath
                if (-not $fileInfo.IsReadOnly) {
                    Write-Host "$RED[Ошибка]$NC Проверка не удалась: настройки разрешений могли не примениться"
                    Show-ManualGuide
                    return
                }
            }
            catch {
                Write-Host "$RED[Ошибка]$NC Проверка настроек не удалась"
                Show-ManualGuide
                return
            }

            Write-Host "$GREEN[Информация]$NC Автоматическое обновление успешно отключено"
        }
        catch {
            Write-Host "$RED[Ошибка]$NC Произошла неизвестная ошибка: $_"
            Show-ManualGuide
        }
    }
    else {
        Write-Host "$GREEN[Информация]$NC Сохранены настройки по умолчанию"
    }

    Update-MachineGuid

} catch {
    Write-Host "$RED[Ошибка]$NC Основная операция не удалась: $_"
    Write-Host "$YELLOW[Попытка]$NC Использование альтернативного метода..."
    
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $config | ConvertTo-Json | Set-Content -Path $tempFile -Encoding UTF8
        Copy-Item -Path $tempFile -Destination $STORAGE_FILE -Force
        Remove-Item -Path $tempFile
        Write-Host "$GREEN[Информация]$NC Конфигурация успешно записана альтернативным методом"
    } catch {
        Write-Host "$RED[Ошибка]$NC Все попытки не удались"
        Write-Host "Подробности ошибки: $_"
        Write-Host "Целевой файл: $STORAGE_FILE"
        Write-Host "Убедитесь, что у вас достаточно прав для доступа к файлу"
        Read-Host "Нажмите Enter для выхода"
        exit 1
    }
}

Write-Host ""
Read-Host "Нажмите Enter для выхода"
exit 0

function Write-ConfigFile {
    param($config, $filePath)
    
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $jsonContent = $config | ConvertTo-Json -Depth 10
        
        $jsonContent = $jsonContent.Replace("`r`n", "`n")
        
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($filePath),
            $jsonContent,
            $utf8NoBom
        )
        
        Write-Host "$GREEN[Информация]$NC Конфигурационный файл успешно записан (UTF8 без BOM)"
    }
    catch {
        throw "Не удалось записать конфигурационный файл: $_"
    }
}

$cursorVersion = Get-CursorVersion
Write-Host ""
if ($cursorVersion) {
    Write-Host "$GREEN[Информация]$NC Обнаружена версия Cursor: $cursorVersion, продолжаем..."
} else {
    Write-Host "$YELLOW[Предупреждение]$NC Не удалось определить версию, продолжаем..."
} 