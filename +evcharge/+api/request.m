function responseJson = request(requestJson, generateFcn)
%REQUEST JSON command interface to the EV assistant for external UIs.
%
%   RESPONSEJSON = EVCHARGE.API.REQUEST(REQUESTJSON) runs one command and
%   returns a JSON string. The request is {"command": NAME, ...arguments}.
%   A persistent session keeps the assistant, the simulated car, and the
%   speech front end between calls, so a bridge process (e.g. Python with
%   the MATLAB Engine) only exchanges strings with MATLAB.
%
%   Commands:
%     init           {progressFile?, useLiveData?, speech?} -> health
%     health         -> {ok, model_ok, speech_ok, messages, ...}
%     getState       -> car state
%     setState       {soc_percent?, arrival_percent?, location?,
%                     battery_temp_c?, vehicle_id?} -> car state
%     listVehicles   -> [{id, name}]
%     listLocations  -> [{name, latitude, longitude}]
%     ask            {text} -> {reply, tools_called, plan, state}
%     getPlan        -> plan or null
%     startListening -> {ok}
%     stopListening  -> {transcript}
%     speak          {text, interrupt?} -> {ok}
%     stopSpeaking   -> {ok}
%     reset          -> {ok}  (forgets the conversation, keeps the car)
%
%   Failures are returned as {"error": message}; this function never
%   throws for a bad request.
%
%   RESPONSEJSON = EVCHARGE.API.REQUEST(REQUESTJSON, GENERATEFCN) is for
%   tests: on "init" it uses GENERATEFCN instead of Ollama (see
%   evcharge.assistant.Assistant).

arguments
    requestJson {mustBeTextScalar}
    generateFcn function_handle = function_handle.empty
end

persistent session

try
    req = jsondecode(char(requestJson));
    command = string(req.command);
    if command == "init"
        session = initSession(session, req, generateFcn);
        result = healthOf(session);
    else
        if isempty(session)
            error("evcharge:api:NotInitialized", ...
                "Send the init command first.");
        end
        result = runCommand(session, command, req);
    end
catch ME
    result = struct("error", string(ME.message));
end
responseJson = jsonencode(result);
end

function session = initSession(old, req, generateFcn)
if ~isempty(old) && ~isempty(old.Speech)
    delete(old.Speech);
end

cfg = evcharge.assistant.config();
cfg.UseLiveData = getField(req, "useLiveData", cfg.UseLiveData);
useSpeech = getField(req, "speech", true);

session = struct();
session.Config = cfg;
session.ProgressFile = string(getField(req, "progressFile", ""));
session.Messages = strings(1, 0);
session.State = evcharge.assistant.VehicleState();
session.Speech = [];
session.SpeechOk = false;
session.ModelOk = false;
session.RecognizerName = "";

if isempty(generateFcn)
    session.Assistant = evcharge.assistant.Assistant( ...
        State=session.State, Config=cfg);
    modelLoad = evcharge.assistant.preloadModel(cfg);
else
    session.Assistant = evcharge.assistant.Assistant( ...
        State=session.State, Config=cfg, GenerateFcn=generateFcn);
    modelLoad = [];
    session.ModelOk = true;
end

if useSpeech
    session.Speech = evcharge.assistant.SpeechIO(cfg);
    try
        session.Speech.warmUp();
        session.SpeechOk = true;
        session.RecognizerName = session.Speech.RecognizerName;
    catch ME
        session.Messages(end+1) = "Speech unavailable: " + ME.message;
    end
end

if ~isempty(modelLoad)
    wait(modelLoad);
    session.ModelOk = isempty(modelLoad.Error);
    if ~session.ModelOk
        session.Messages(end+1) = "Could not load " + cfg.Model + ": " ...
            + modelLoad.Error.message;
    end
end

if cfg.UseLiveData
    [ok, message] = session.State.updateOutsideTemperature();
    if ~ok
        session.Messages(end+1) = message;
    end
end

% Speak a filler and notify the UI when a slow tool starts.
speech = session.Speech;
progressFile = session.ProgressFile;
session.Assistant.ToolStartFcn = @(name, args) onToolStart(name, args, ...
    speech, progressFile);
end

function onToolStart(name, args, speech, progressFile)
filler = evcharge.assistant.Assistant.progressMessage(name, args);
if filler == ""
    return
end
writeProgress(progressFile, struct("type", "progress", "text", filler));
if ~isempty(speech)
    speech.speak(filler);
end
end

function writeProgress(progressFile, event)
if progressFile == ""
    return
end
fid = fopen(progressFile, "a", "n", "UTF-8");
if fid < 0
    return
end
closer = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", jsonencode(event));
end

function result = runCommand(session, command, req)
state = session.State;
switch command
    case "health"
        result = healthOf(session);
    case "getState"
        result = stateOf(session);
    case "setState"
        applyState(session, req);
        result = stateOf(session);
    case "listVehicles"
        profiles = evcharge.vehicleProfiles();
        result = arrayfun(@(p) struct("id", p.ID, "name", p.Name), ...
            profiles, UniformOutput=false);
    case "listLocations"
        locations = evcharge.assistant.VehicleState.knownLocations();
        result = cell(1, height(locations));
        for k = 1:height(locations)
            result{k} = struct("name", locations.Name(k), ...
                "latitude", locations.Latitude(k), ...
                "longitude", locations.Longitude(k));
        end
    case "ask"
        reply = session.Assistant.ask(string(req.text));
        result = struct();
        result.reply = reply.Text;
        result.tools_called = cellstr(reply.ToolsCalled);
        result.plan = planOrNull(state.ActivePlan);
        result.state = stateOf(session);
        if isfield(reply, "Error")
            result.llm_error = reply.Error;
        end
    case "getPlan"
        result = planOrNull(state.ActivePlan);
    case "startListening"
        requireSpeech(session);
        session.Speech.startListening();
        result = struct("ok", true);
    case "stopListening"
        requireSpeech(session);
        result = struct("transcript", session.Speech.stopListening());
    case "speak"
        requireSpeech(session);
        session.Speech.speak(string(req.text), ...
            Interrupt=getField(req, "interrupt", false));
        result = struct("ok", true);
    case "stopSpeaking"
        if ~isempty(session.Speech)
            session.Speech.stopSpeaking();
        end
        result = struct("ok", true);
    case "reset"
        session.Assistant.reset();
        result = struct("ok", true);
    otherwise
        error("evcharge:api:UnknownCommand", "Unknown command '%s'.", command);
end
end

function applyState(session, req)
state = session.State;
if isfield(req, "soc_percent")
    state.SoCPercent = min(max(req.soc_percent, 0), 100);
end
if isfield(req, "arrival_percent")
    state.ArrivalSoCPercent = min(max(req.arrival_percent, 0), 80);
end
if isfield(req, "battery_temp_c")
    state.BatteryTempC = req.battery_temp_c;
end
if isfield(req, "vehicle_id")
    evcharge.selectVehicle(string(req.vehicle_id));  % Validates the ID.
    state.VehicleID = string(req.vehicle_id);
end
if isfield(req, "location") && string(req.location) ~= state.LocationName
    locations = evcharge.assistant.VehicleState.knownLocations();
    if ~any(locations.Name == string(req.location))
        error("evcharge:api:UnknownLocation", "Unknown location '%s'.", ...
            req.location);
    end
    state.LocationName = string(req.location);
    state.PreconditioningOn = false;
    if session.Config.UseLiveData
        state.updateOutsideTemperature();
    end
end
end

function s = stateOf(session)
state = session.State;
vehicle = state.vehicle();
s = struct( ...
    "soc_percent", state.SoCPercent, ...
    "arrival_percent", state.ArrivalSoCPercent, ...
    "location", state.LocationName, ...
    "outside_temp_c", state.OutsideTempC, ...
    "battery_temp_c", state.BatteryTempC, ...
    "vehicle_id", state.VehicleID, ...
    "vehicle_name", vehicle.Name, ...
    "preconditioning_on", state.PreconditioningOn, ...
    "preconditioning_target", state.PreconditioningTarget, ...
    "has_plan", isstruct(state.ActivePlan));
end

function h = healthOf(session)
h = struct( ...
    "ok", session.ModelOk && (session.SpeechOk || isempty(session.Speech)), ...
    "model", session.Config.Model, ...
    "model_ok", session.ModelOk, ...
    "speech_ok", session.SpeechOk, ...
    "recognizer", session.RecognizerName, ...
    "live_data", session.Config.UseLiveData, ...
    "messages", {cellstr(session.Messages)});
end

function p = planOrNull(plan)
if isstruct(plan)
    p = evcharge.api.planToStruct(plan);
else
    p = [];  % jsonencode writes [] for an empty double; the UI treats it as "no plan".
end
end

function requireSpeech(session)
if isempty(session.Speech) || ~session.SpeechOk
    error("evcharge:api:NoSpeech", "Speech is not available.");
end
end

function value = getField(s, name, defaultValue)
if isfield(s, name)
    value = s.(name);
else
    value = defaultValue;
end
end
