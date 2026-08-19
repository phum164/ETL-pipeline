$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = 'C:\ProgramData\RM\data-engineering\etl.env'
$logRoot = 'C:\ProgramData\RM\data-engineering\logs'

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
Get-ChildItem -LiteralPath $logRoot -Filter '*.log' -File -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force -ErrorAction SilentlyContinue

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logRoot "incremental-$stamp.log"

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    "[$(Get-Date -Format o)] ETL env file not found: $envFile" |
        Tee-Object -FilePath $logPath
    exit 1
}

$previousEnvFile = [Environment]::GetEnvironmentVariable('ETL_ENV_FILE', 'Process')
$env:ETL_ENV_FILE = $envFile

try {
    "[$(Get-Date -Format o)] starting RM data-engineering incremental batch" |
        Tee-Object -FilePath $logPath
    & docker compose --project-directory $repoRoot --env-file $envFile `
        -f (Join-Path $repoRoot 'compose.yaml') run --rm rm-dw-etl incremental *>&1 |
        Tee-Object -FilePath $logPath -Append
    $exitCode = $LASTEXITCODE
    "[$(Get-Date -Format o)] finished with exit code $exitCode" |
        Tee-Object -FilePath $logPath -Append
}
catch {
    "[$(Get-Date -Format o)] launcher failure: $_" |
        Tee-Object -FilePath $logPath -Append
    $exitCode = 1
}
finally {
    if ($null -eq $previousEnvFile) {
        Remove-Item Env:ETL_ENV_FILE -ErrorAction SilentlyContinue
    }
    else {
        $env:ETL_ENV_FILE = $previousEnvFile
    }
}

exit $exitCode
