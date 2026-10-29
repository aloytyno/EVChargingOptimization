# Start the EV assistant API on http://127.0.0.1:8765
#
# Options (environment variables):
#   EV_LIVE_DATA=0         use cached Finland routes only
#   EV_SPEECH=0            no microphone / speech output
#   EV_MATLAB_SESSION=name connect to a MATLAB that ran matlab.engine.shareEngine("name")
#
# Without EV_MATLAB_SESSION, an already shared MATLAB session is used if one
# exists; otherwise a new MATLAB engine is started (slower).

$ErrorActionPreference = "Stop"
$backend = $PSScriptRoot
$venv = Join-Path $backend ".venv"

if (-not (Test-Path (Join-Path $venv "Scripts\python.exe"))) {
    python -m venv $venv
    & (Join-Path $venv "Scripts\python.exe") -m pip install -r (Join-Path $backend "requirements.txt")
}

Push-Location $backend
try {
    & (Join-Path $venv "Scripts\python.exe") -m uvicorn evbackend.app:app --host 127.0.0.1 --port 8765
}
finally {
    Pop-Location
}
