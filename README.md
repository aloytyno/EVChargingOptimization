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
