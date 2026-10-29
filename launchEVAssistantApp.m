function launchEVAssistantApp()
%LAUNCHEVASSISTANTAPP Open the speech-driven EV trip assistant mockup.
%
%   LAUNCHEVASSISTANTAPP opens a uifigure app where the driver presses the
%   talk button and says where they want to go. A local LLM (Ollama via
%   llms-with-matlab) calls the +evcharge planning tools, speaks a short
%   answer, and shows the next charging stop, SoC profile, and route map.
%   The "Simulated car" panel stands in for the real vehicle's signals.
%
%   Setup: install Ollama and run "ollama pull qwen3:8b" (see
%   evcharge.assistant.config to change the model).

addProjectPaths

colors.bg = [0.05 0.07 0.08];
colors.panel = [0.09 0.12 0.13];
colors.panel2 = [0.12 0.16 0.16];
colors.midGray = [0.38 0.40 0.40];
colors.midGrayAlt = [0.32 0.34 0.34];
colors.text = [0.90 0.94 0.91];
colors.muted = [0.58 0.66 0.62];
colors.accent = [0.00 0.73 0.62];
colors.warn = [0.95 0.62 0.18];
colors.listen = [0.86 0.24 0.24];

cfg = evcharge.assistant.config();
state = evcharge.assistant.VehicleState();
assistant = evcharge.assistant.Assistant(State=state, Config=cfg);
speech = evcharge.assistant.SpeechIO(cfg);
assistant.ToolStartFcn = @onToolStart;
isBusy = false;
lastPlan = [];

app.Figure = uifigure(Name="EV Assistant", Position=[60 60 1440 840], ...
    Color=colors.bg, CloseRequestFcn=@closeApp);

root = uigridlayout(app.Figure, [1 3]);
root.ColumnWidth = {400, "1x", 460};
root.Padding = [18 18 18 18];
root.ColumnSpacing = 14;
root.BackgroundColor = colors.bg;

%% Left column: talk button, conversation, simulated car
% Simulated car panel layout: the slider row is taller so its tick labels
% fit, and the panel height is derived from the rows so nothing is clipped.
carRowHeights = {52, 34, 34, 34, 34, 34};
carRowSpacing = 14;
carPadding = [16 14 16 14];
carPanelHeight = sum([carRowHeights{:}]) ...
    + carRowSpacing * (numel(carRowHeights) - 1) ...
    + carPadding(2) + carPadding(4) + 4;

left = uigridlayout(root, [6 1]);
left.RowHeight = {130, 30, "1x", 36, 34, carPanelHeight};
left.Padding = [0 0 0 0];
left.RowSpacing = 10;
left.BackgroundColor = colors.bg;

app.TalkButton = uibutton(left, Text="Tap and tell me where to go", ...
    FontSize=22, FontWeight="bold", WordWrap="on", ...
    BackgroundColor=colors.accent, FontColor=[0.02 0.05 0.04], ...
    ButtonPushedFcn=@onTalk);

app.Status = uilabel(left, Text="Starting...", FontColor=colors.muted, ...
    WordWrap="on");

app.Transcript = uitextarea(left, Editable="off", FontSize=15, ...
    BackgroundColor=colors.panel, FontColor=colors.text, Value="");

typeRow = uigridlayout(left, [1 2]);
typeRow.ColumnWidth = {"1x", 70};
typeRow.Padding = [0 0 0 0];
typeRow.BackgroundColor = colors.bg;
app.TypeField = uieditfield(typeRow, "text", ...
    Placeholder="Or type here, e.g. 'Take me to Oulu'", ...
    BackgroundColor=colors.midGray, FontColor=colors.text, ...
    ValueChangedFcn=@onTyped);
uibutton(typeRow, Text="Send", BackgroundColor=colors.panel2, ...
    FontColor=colors.text, ButtonPushedFcn=@onTyped);

app.CarToggle = uibutton(left, "state", Text="Simulated car ▾", Value=true, ...
    BackgroundColor=colors.panel2, FontColor=colors.muted, ...
    ValueChangedFcn=@onToggleCar);

app.CarPanel = uipanel(left, BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
carGrid = uigridlayout(app.CarPanel, [6 2]);
carGrid.ColumnWidth = {130, "1x"};
carGrid.RowHeight = carRowHeights;
carGrid.RowSpacing = carRowSpacing;
carGrid.ColumnSpacing = 14;
carGrid.Padding = carPadding;
carGrid.BackgroundColor = colors.panel;

app.SocLabel = uilabel(carGrid, FontColor=colors.muted);
app.SocSlider = uislider(carGrid, Limits=[5 100], Value=state.SoCPercent, ...
    FontColor=colors.muted, ValueChangedFcn=@(src, ~) setState("SoCPercent", ...
    round(src.Value)));
uilabel(carGrid, Text="Arrive with (%)", FontColor=colors.muted);
app.ArrivalSoc = uispinner(carGrid, Limits=[5 80], Step=5, ...
    Value=state.ArrivalSoCPercent, BackgroundColor=colors.midGray, ...
    FontColor=colors.text, Tooltip="Battery you want left at the destination", ...
    ValueChangedFcn=@(src, ~) setState("ArrivalSoCPercent", src.Value));
uilabel(carGrid, Text="Location", FontColor=colors.muted);
locations = evcharge.assistant.VehicleState.knownLocations();
app.Location = uidropdown(carGrid, Items=locations.Name, ...
    Value=state.LocationName, BackgroundColor=colors.midGray, ...
    FontColor=colors.text, ValueChangedFcn=@(src, ~) setState( ...
    "LocationName", string(src.Value)));
uilabel(carGrid, Text="Outside", FontColor=colors.muted);
app.OutsideTemp = uilabel(carGrid, Text="Fetching from FMI...", ...
    FontColor=colors.text, Tooltip="Forecast from FMI Open Data");
uilabel(carGrid, Text="Battery (°C)", FontColor=colors.muted);
app.BatteryTemp = uispinner(carGrid, Limits=[-30 45], ...
    Value=state.BatteryTempC, BackgroundColor=colors.midGray, ...
    FontColor=colors.text, ValueChangedFcn=@(src, ~) setState( ...
    "BatteryTempC", src.Value));
uilabel(carGrid, Text="Vehicle", FontColor=colors.muted);
profiles = evcharge.vehicleProfiles();
app.Vehicle = uidropdown(carGrid, Items=string({profiles.Name}), ...
    ItemsData=string({profiles.ID}), Value=state.VehicleID, ...
    BackgroundColor=colors.midGray, FontColor=colors.text, ...
    ValueChangedFcn=@(src, ~) setState("VehicleID", string(src.Value)));

%% Center column: next action, trip summary, SoC profile
center = uigridlayout(root, [3 1]);
center.RowHeight = {190, 110, "1x"};
center.Padding = [0 0 0 0];
center.RowSpacing = 12;
center.BackgroundColor = colors.bg;

nextPanel = uipanel(center, BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
nextGrid = uigridlayout(nextPanel, [2 1]);
nextGrid.RowHeight = {28, "1x"};
nextGrid.Padding = [20 14 20 14];
nextGrid.BackgroundColor = colors.panel;
uilabel(nextGrid, Text="NEXT", FontColor=colors.muted, FontWeight="bold");
app.NextLabel = uilabel(nextGrid, Text="Where would you like to go?", ...
    FontSize=28, FontWeight="bold", FontColor=colors.text, WordWrap="on", ...
    VerticalAlignment="top");

summaryPanel = uipanel(center, BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
summaryGrid = uigridlayout(summaryPanel, [2 4]);
summaryGrid.RowHeight = {24, "1x"};
summaryGrid.ColumnWidth = repmat({"1x"}, 1, 4);
summaryGrid.Padding = [14 10 14 10];
summaryGrid.BackgroundColor = colors.panel;
titles = ["Arrive with", "Trip time", "Charging stops", "Battery warming"];
for k = 1:numel(titles)
    uilabel(summaryGrid, Text=titles(k), FontColor=colors.muted, ...
        HorizontalAlignment="center");
end
app.ArrivalValue = makeValue(summaryGrid, "-");
app.TripValue = makeValue(summaryGrid, "-");
app.StopsValue = makeValue(summaryGrid, "-");
app.WarmValue = makeValue(summaryGrid, "Off");

app.SocAxes = uiaxes(center, BackgroundColor=colors.midGrayAlt, ...
    XColor=colors.muted, YColor=colors.muted, GridColor=[0.25 0.31 0.29]);
title(app.SocAxes, "Battery along the trip", Color=colors.text)
xlabel(app.SocAxes, "Distance (km)")
ylabel(app.SocAxes, "Battery (%)")

%% Right column: map
mapPanel = uipanel(root, BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
mapGrid = uigridlayout(mapPanel, [1 1]);
mapGrid.Padding = [8 8 8 8];
mapGrid.BackgroundColor = colors.panel;
app.MapAxes = geoaxes(mapGrid, Basemap="streets-dark");
title(app.MapAxes, "Route", Color=colors.text)
geolimits(app.MapAxes, [59.8 65.3], [21.5 29.5])
% A clean map: no latitude/longitude ticks, tick labels, or axis labels.
app.MapAxes.LatitudeAxis.Visible = "off";
app.MapAxes.LongitudeAxis.Visible = "off";
app.MapAxes.LatitudeLabel.String = "";
app.MapAxes.LongitudeLabel.String = "";

stateListener = addlistener(state, "StateChanged", @(~, ~) refreshCar());
refreshCar();
drawnow
startUp();

%% Callbacks
    function startUp()
        updateOutsideTemperature();
        [ok, message] = checkOllama(cfg);
        modelLoad = [];
        if ok
            % Load the LLM in the background while the speech models load,
            % so the first question doesn't pay for it.
            modelLoad = evcharge.assistant.preloadModel(cfg);
        end
        app.Status.Text = "Loading speech and language models...";
        drawnow
        speechOk = true;
        try
            speech.warmUp();
        catch ME
            speechOk = false;
            message = "Speech unavailable, please type. " + ME.message;
        end
        if ~isempty(modelLoad)
            wait(modelLoad);
            if ~isempty(modelLoad.Error)
                ok = false;
                message = "Could not load " + cfg.Model + ": " ...
                    + modelLoad.Error.message;
            end
        end
        if ok && speechOk
            app.Status.Text = "Ready. " + speech.RecognizerName ...
                + " + " + cfg.Model;
        else
            app.Status.Text = message;
            app.Status.FontColor = colors.warn;
        end
        greeting = "Hi! Where would you like to go?";
        addLine("Assistant", greeting);
        if speechOk
            speech.speak(greeting);
        end
    end

    function onToolStart(name, args)
        filler = evcharge.assistant.Assistant.progressMessage(name, args);
        if filler == ""
            return
        end
        app.Status.Text = filler;
        drawnow
        try
            speech.speak(filler);
        catch
            % Spoken progress is best effort.
        end
    end

    function onTalk(~, ~)
        if isBusy
            return
        end
        try
            if ~speech.IsListening
                speech.startListening();
                app.TalkButton.Text = "Listening... tap when done";
                app.TalkButton.BackgroundColor = colors.listen;
                app.Status.Text = "Listening";
            else
                resetTalkButton();
                app.Status.Text = "Recognizing speech...";
                drawnow
                heard = speech.stopListening();
                if heard == ""
                    app.Status.Text = "I didn't catch that. Tap and try again.";
                    return
                end
                handleUtterance(heard);
            end
        catch ME
            resetTalkButton();
            app.Status.Text = "Microphone problem: " + ME.message;
        end
    end

    function onTyped(~, ~)
        text = strtrim(string(app.TypeField.Value));
        if text == "" || isBusy
            return
        end
        app.TypeField.Value = "";
        handleUtterance(text);
    end

    function handleUtterance(text)
        isBusy = true;
        app.TalkButton.Enable = "off";
        addLine("You", text);
        app.Status.Text = "Thinking...";
        drawnow

        reply = assistant.ask(text);
        addLine("Assistant", reply.Text);
        if isfield(reply, "Error")
            app.Status.Text = reply.Error;
        else
            app.Status.Text = "Ready";
            if ~isempty(reply.ToolsCalled)
                app.Status.Text = "Ready · used " + strjoin(unique( ...
                    reply.ToolsCalled, "stable"), ", ");
            end
        end
        if ~isempty(reply.Plan) && ~isequal(reply.Plan, lastPlan)
            lastPlan = reply.Plan;
            showPlan(reply.Plan);
        end
        app.TalkButton.Enable = "on";
        isBusy = false;
        drawnow
        try
            % Queue behind a "Checking the route..." filler if one is playing.
            speech.speak(reply.Text, Interrupt=false);
        catch
            % Text is already on screen; speaking is best effort.
        end
    end

    function showPlan(plan)
        app.NextLabel.Text = evcharge.ui.nextActionText(plan);
        app.ArrivalValue.Text = sprintf("%.0f %%", plan.FinalSoCPercent);
        app.TripValue.Text = evcharge.ui.formatDuration(plan.TotalTripTimeMinutes);
        app.StopsValue.Text = string(height(plan.Stops));
        if plan.Status ~= "Feasible"
            app.ArrivalValue.FontColor = colors.warn;
        else
            app.ArrivalValue.FontColor = colors.text;
        end
        evcharge.ui.plotSocProfile(app.SocAxes, plan, colors);
        evcharge.ui.plotRouteMap(app.MapAxes, plan, colors);
    end

    function refreshCar()
        if ~isvalid(app.Figure)
            return
        end
        app.SocLabel.Text = sprintf("Battery %d %%", round(state.SoCPercent));
        app.SocSlider.Value = state.SoCPercent;
        app.ArrivalSoc.Value = state.ArrivalSoCPercent;
        app.Location.Value = state.LocationName;
        if isnan(state.OutsideTempC)
            app.OutsideTemp.Text = "Unavailable";
        else
            app.OutsideTemp.Text = sprintf("%.0f °C (FMI forecast)", ...
                state.OutsideTempC);
        end
        app.BatteryTemp.Value = state.BatteryTempC;
        app.Vehicle.Value = state.VehicleID;
        if state.PreconditioningOn
            app.WarmValue.Text = "On";
            app.WarmValue.FontColor = colors.warn;
            if state.PreconditioningTarget ~= ""
                app.WarmValue.Tooltip = "Warming for " + state.PreconditioningTarget;
            end
        else
            app.WarmValue.Text = "Off";
            app.WarmValue.FontColor = colors.text;
        end
    end

    function setState(name, value)
        state.(name) = value;
        if name == "LocationName"
            state.PreconditioningOn = false;
            updateOutsideTemperature();
        end
    end

    function updateOutsideTemperature()
        app.OutsideTemp.Text = "Fetching from FMI...";
        drawnow
        [ok, message] = state.updateOutsideTemperature();
        refreshCar();
        if ~ok
            app.OutsideTemp.Tooltip = message;
        end
    end

    function onToggleCar(src, ~)
        if src.Value
            left.RowHeight{6} = carPanelHeight;
            src.Text = "Simulated car ▾";
        else
            left.RowHeight{6} = 0;
            src.Text = "Simulated car ▸";
        end
    end

    function resetTalkButton()
        app.TalkButton.Text = "Tap and tell me where to go";
        app.TalkButton.BackgroundColor = colors.accent;
    end

    function addLine(who, text)
        lines = string(app.Transcript.Value);
        if isscalar(lines) && lines == ""
            lines = strings(0, 1);
        end
        app.Transcript.Value = [lines; who + ": " + text; ""];
        scroll(app.Transcript, "bottom");
    end

    function label = makeValue(parent, textValue)
        label = uilabel(parent, Text=textValue, FontSize=24, ...
            FontWeight="bold", FontColor=colors.text, ...
            HorizontalAlignment="center");
    end

    function closeApp(~, ~)
        delete(stateListener);
        delete(speech);
        delete(app.Figure);
    end
end

function [ok, message] = checkOllama(cfg)
ok = false;
try
    tags = webread("http://" + cfg.Endpoint + "/api/tags", ...
        weboptions(Timeout=3));
catch
    message = "Ollama is not running. Install it from ollama.com, then " ...
        + "run: ollama pull " + cfg.Model;
    return
end
models = tags.models;
if iscell(models)
    models = [models{:}];
end
names = strings(0, 1);
if ~isempty(models)
    names = string({models.name});
end
if any(names == cfg.Model | names == cfg.Model + ":latest")
    ok = true;
    message = "";
else
    message = "Ollama is running but the model is missing. Run: " ...
        + "ollama pull " + cfg.Model;
end
end
