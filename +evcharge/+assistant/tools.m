function [toolDefs, runTool] = tools(options)
%TOOLS Tool definitions and dispatcher for the EV assistant.
%
%   [TOOLDEFS, RUNTOOL] = EVCHARGE.ASSISTANT.TOOLS returns an openAIFunction
%   array for ollamaChat and a handle RESULT = RUNTOOL(NAME, ARGS, STATE)
%   that executes a tool against an evcharge.assistant.VehicleState. Every
%   tool returns a struct; failures come back as struct("error", message)
%   so the language model can explain them to the driver.
%
%   The tools are thin adapters over the +evcharge algorithms, so the same
%   functions could later be published as an MCP server.

arguments
    options.UseLiveData (1,1) logical = true
end

toolDefs = [ ...
    openAIFunction("get_vehicle_state", ...
        "Get the car's current battery level, location, temperatures, " ...
        + "and the driver's target battery on arrival."), ...
    planTripDefinition(), ...
    batteryAdviceDefinition(), ...
    addParameter(openAIFunction("start_preconditioning", ...
        "Warm up the battery so the next fast charge is quicker."), ...
        "station", type="string", ...
        description="Name of the charging station, if known.", ...
        RequiredParameter=false)];

runTool = @(name, args, state) dispatch(name, args, state, options);
end

function f = planTripDefinition()
f = openAIFunction("plan_trip", ...
    "Plan a drive from the car's current location to a destination. " ...
    + "Uses the current battery level, road profile, and weather. Returns " ...
    + "whether the car can make it, the charging stops, and arrival battery.");
f = addParameter(f, "destination", type="string", ...
    description="Destination city or address in Finland, e.g. 'Oulu'.", ...
    RequiredParameter=true);
f = addParameter(f, "arrival_battery_percent", type="number", ...
    description="Battery percent wanted on arrival. Only set this if " ...
    + "the driver says it; otherwise their saved target is used.", ...
    RequiredParameter=false);
f = addParameter(f, "preference", type="string", ...
    enum=["fastest", "fewest_stops", "safest"], ...
    description="What matters most. Default fastest.", ...
    RequiredParameter=false);
end

function f = batteryAdviceDefinition()
f = openAIFunction("get_battery_advice", ...
    "Get battery care advice: how full to charge, when to charge to 100%, " ...
    + "and whether to warm the battery before fast charging.");
f = addParameter(f, "context", type="string", ...
    enum=["daily", "before_trip", "before_fast_charge"], ...
    description="The situation the driver is asking about.", ...
    RequiredParameter=true);
end

function result = dispatch(name, args, state, options)
if isempty(args) || ~isstruct(args)
    args = struct();
end
try
    switch string(name)
        case "get_vehicle_state"
            result = state.toStruct();
        case "plan_trip"
            result = planTrip(args, state, options);
        case "get_battery_advice"
            result = evcharge.assistant.batteryAdvice(state, ...
                string(getArg(args, "context", "daily")));
        case "start_preconditioning"
            result = startPreconditioning(state, ...
                string(getArg(args, "station", "")));
        otherwise
            result = struct("error", "Unknown tool '" + string(name) + "'.");
    end
catch ME
    result = struct("error", string(ME.message));
end
end

function summary = planTrip(args, state, options)
destination = strtrim(string(getArg(args, "destination", "")));
if destination == ""
    error("evcharge:assistant:NoDestination", "No destination was given.");
end
if ~contains(destination, ",")
    destination = destination + ", Finland";
end
arrivalPercent = double(getArg(args, "arrival_battery_percent", ...
    state.ArrivalSoCPercent));
objective = objectiveFromPreference(string(getArg(args, "preference", "fastest")));

scenario = cachedScenarioFor(state.LocationName, destination);
useLive = options.UseLiveData;
if ~useLive && scenario == ""
    error("evcharge:assistant:OfflineRoute", offlineMessage());
end
cachedScenario = scenario;
if cachedScenario == ""
    cachedScenario = "helsinki-to-oulu";
end

warningState = warning("off", "evcharge:LiveDataFallback");
cleanup = onCleanup(@() warning(warningState));
result = evcharge.runChargingOptimization( ...
    StartAddress=state.startAddress(), ...
    DestinationAddress=destination, ...
    Scenario=cachedScenario, ...
    UseLiveData=useLive, ...
    InitialSoCPercent=state.SoCPercent, ...
    MarginSoCPercent=min(10, arrivalPercent), ...
    DestinationSoCPercent=arrivalPercent, ...
    VehicleID=state.VehicleID, ...
    Objective=objective, ...
    OutsideTemperatureC=state.OutsideTempC);

% A failed live request silently falls back to cached data, which is only
% valid for its own route. Refuse instead of describing the wrong trip.
if result.DataSource ~= "live-public-api" && scenario == ""
    error("evcharge:assistant:OfflineRoute", offlineMessage());
end

state.ActivePlan = result;
state.PreconditioningOn = false;
state.PreconditioningTarget = "";
summary = evcharge.assistant.summarizePlan(result);
summary.preconditioning_scheduled = false;
if ~isempty(result.Stops) && state.BatteryTempC < 15
    startPreconditioning(state, result.Stops.StationName(1));
    summary.preconditioning_scheduled = true;
end
end

function result = startPreconditioning(state, station)
state.PreconditioningTarget = station;
state.PreconditioningOn = true;
result = struct("ok", true, "preconditioning_on", true, ...
    "message", "The battery will be warmed about 25 minutes before " ...
    + "arriving at the charger.");
if station ~= ""
    result.station = station;
end
end

function scenario = cachedScenarioFor(startName, destination)
scenario = "";
if ~strcmpi(startName, "Helsinki")
    return
end
if contains(destination, "Oulu", IgnoreCase=true)
    scenario = "helsinki-to-oulu";
elseif contains(destination, "Tampere", IgnoreCase=true)
    scenario = "helsinki-to-tampere";
end
end

function message = offlineMessage()
message = "Live route data is not available right now. Offline, I can " ...
    + "only plan Helsinki to Tampere or Helsinki to Oulu.";
end

function objective = objectiveFromPreference(preference)
switch lower(preference)
    case "fewest_stops"
        objective = "FewestStops";
    case "safest"
        objective = "LowestRisk";
    otherwise
        objective = "FastestTrip";
end
end

function value = getArg(args, name, defaultValue)
if isfield(args, name) && ~isempty(args.(name))
    value = args.(name);
else
    value = defaultValue;
end
end
