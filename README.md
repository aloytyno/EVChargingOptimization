# EV Charging Optimization Demo

This folder contains a MATLAB/Simulink demo scaffold for optimizing EV
charging stops on Finnish routes. The demo is Finland-first and runs from
cached data by default, so it is repeatable without internet access.

## Quick Start

Run this from MATLAB in the project folder:

```matlab
addProjectPaths
buildEVChargingDemo
result = runDemo
```

For the live-data workflow and car-style UI, store the API keys in MATLAB
Vault and launch the app:

```matlab
setSecret("Google.Maps.APIKey")
setSecret("OpenChargeMap")
launchEVChargingPlannerApp
```

FMI Open Data does not require an API key.

## Speech-Driven Assistant (mockup)

`launchEVAssistantApp` opens a voice-first planner for non-technical
drivers. Tap the big button, say where you want to go ("Take me to Oulu"),
and the assistant answers aloud: whether you can make it, where to charge
and for how long, and the battery left on arrival. It also takes care of
battery care, such as warming a cold battery before fast charging and
telling you how full to charge at home before a trip.

How it works:

- Speech-to-text: Audio Toolbox Whisper (local), with a small fix-up for
  misheard Finnish place names (`evcharge.assistant.correctPlaceNames`).
- Language model: a local Ollama model with tool calling. The
  conversation uses `messageHistory` from the
  [LLMs with MATLAB](https://github.com/matlab-deep-learning/llms-with-matlab)
  add-on; requests go straight to Ollama's `/api/chat` with thinking
  turned off (`evcharge.assistant.ollamaGenerator`), which is much faster
  for reasoning models such as qwen3.
- Tools (`evcharge.assistant.tools`): `get_vehicle_state`, `plan_trip`
  (wraps `evcharge.runChargingOptimization`), `get_battery_advice`
  (rule-based, `evcharge.assistant.batteryAdvice`), and
  `start_preconditioning`. These are plain MATLAB functions, so they can
  also be published as an MCP server later.
- Text-to-speech: Audio Toolbox HiFi-GAN (local).
- The "Simulated car" panel stands in for the vehicle's battery level,
  location, battery temperature, and model (Kia EV6 by default), plus the
  battery you want left on arrival. The outside temperature comes from the
  FMI forecast for the selected location.

One-time setup:

```powershell
winget install Ollama.Ollama
ollama pull qwen3:8b
```

Then download and unzip the
[Whisper small model](https://ssd.mathworks.com/supportfiles/audio/whisper-small.zip)
so that `%USERPROFILE%\MATLAB\Whisper\whisper-small\whisper-small` contains
`model.safetensors`. The model name, Whisper folder, and other settings are
in `+evcharge/+assistant/config.m`.

```matlab
launchEVAssistantApp

% Or without the UI:
a = evcharge.assistant.Assistant();
r = a.ask("Can I make it to Oulu without charging?")
```

The build script creates:

- `EVChargingSimulation.slx`: Simulink-facing demo model.
- `EVChargingArchitecture.slx`: System Composer architecture model.

The MATLAB package in `+evcharge` contains the cached route data, vehicle
energy model, charging-stop optimizer, and optional live-data adapter hooks.
The live adapter uses Google Routes, Google Elevation, FMI weather, and Open
Charge Map, then falls back to cached Finland data if a live service is not
available.

## Demo Defaults

- Country: Finland.
- Cached route: Helsinki to Oulu.
- Cached charging data: plausible high-power charging stops along the route.
- Initial SoC: 72%.
- Required arrival margin: 10%.
- Vehicle model: readable route-segment energy model using distance, speed
  limit, elevation change, vehicle mass, and regenerative recovery.

## Tests

Run:

```matlab
results = runtests("tests")
table(results)
```

The tests cover no-charge, one/multiple-charge, infeasible-margin, and
Simulink entry-point scenarios using cached Finland data.

`tests/tAssistantTools.m` and `tests/tAssistantLoop.m` cover the assistant
tool layer and tool-calling loop offline, using a scripted fake LLM, so they
need neither Ollama nor a microphone.
