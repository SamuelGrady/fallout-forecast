$ErrorActionPreference = 'Stop'
$recorderPath = Join-Path $PSScriptRoot 'recorder.py'
$logDirectory = Join-Path $env:LOCALAPPDATA 'FalloutForecastPlaytest'
New-Item -ItemType Directory -Force $logDirectory | Out-Null
try {
    $uvPath = (Get-Command uv -ErrorAction Stop).Source
    # PowerShell 5.1 wraps native stderr as ErrorRecords, including uv's
    # successful first-run download notices. Inspect the process exit code.
    $ErrorActionPreference = 'Continue'
    & $uvPath run --no-project --python 3.13 --with 'faster-whisper==1.2.1' --with 'av==16.0.1' --with 'imageio-ffmpeg==0.6.0' --with 'windows-capture==2.0.1' python $recorderPath *> (Join-Path $logDirectory 'launcher.log')
    $recorderExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($recorderExitCode -ne 0) { throw "Recorder exited with code $recorderExitCode. See $logDirectory/launcher.log" }
} catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Playtest recorder') | Out-Null
}
