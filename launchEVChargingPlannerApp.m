function launchEVChargingPlannerApp()
%LAUNCHEVCHARGINGPLANNERAPP Open the EV charging planner demo UI.
%
%   LAUNCHEVCHARGINGPLANNERAPP opens a programmatic uifigure app that uses
%   the +evcharge optimization pipeline. Live data is requested first; the
%   package falls back to cached Finland data if an API is unavailable.

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

app.Figure = uifigure( ...
    Name="EV Charging Planner", ...
    Position=[80 80 1500 820], ...
    Color=colors.bg);

root = uigridlayout(app.Figure, [1 3]);
root.RowHeight = {"1x"};
root.ColumnWidth = {340, 520, "1.25x"};
root.Padding = [18 18 18 18];
root.ColumnSpacing = 14;
root.BackgroundColor = colors.bg;

controls = uipanel(root, ...
    Title="Journey", ...
    ForegroundColor=colors.text, ...
    BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
controls.Layout.Column = 1;

controlGrid = uigridlayout(controls, [19 2]);
controlGrid.RowHeight = {28, 34, 28, 34, 28, 34, 28, 34, 28, 34, ...
    28, 34, 28, 34, 28, 34, 18, 44, "1x"};
controlGrid.ColumnWidth = {120, "1x"};
controlGrid.Padding = [16 14 16 14];
controlGrid.BackgroundColor = colors.panel;

uilabel(controlGrid, Text="Start", FontColor=colors.muted);
app.Start = uieditfield(controlGrid, "text", ...
    Value="Helsinki, Finland", BackgroundColor=colors.midGray, ...
    FontColor=colors.text);

uilabel(controlGrid, Text="Destination", FontColor=colors.muted);
app.Destination = uieditfield(controlGrid, "text", ...
    Value="Oulu, Finland", BackgroundColor=colors.midGray, ...
    FontColor=colors.text);

uilabel(controlGrid, Text="Initial SoC (%)", FontColor=colors.muted);
app.InitialSoc = uispinner(controlGrid, ...
    Limits=[5 100], Value=72, Step=1, ...
    BackgroundColor=colors.midGray, FontColor=colors.text);

uilabel(controlGrid, Text="SoC margin (%)", FontColor=colors.muted);
app.MarginSoc = uispinner(controlGrid, ...
    Limits=[3 45], Value=10, Step=1, ...
    BackgroundColor=colors.midGray, FontColor=colors.text);

uilabel(controlGrid, Text="Destination SoC (%)", FontColor=colors.muted);
app.TargetSoc = uispinner(controlGrid, ...
    Limits=[0 90], Value=10, Step=1, ...
    BackgroundColor=colors.midGray, FontColor=colors.text);

uilabel(controlGrid, Text="Vehicle", FontColor=colors.muted);
profiles = evcharge.vehicleProfiles();
app.Vehicle = uidropdown(controlGrid, ...
    Items=string({profiles.Name}), ...
    ItemsData=string({profiles.ID}), ...
    Value=profiles(1).ID, ...
    BackgroundColor=colors.midGray, ...
    FontColor=colors.text);

uilabel(controlGrid, Text="Max stops", FontColor=colors.muted);
app.MaxStops = uispinner(controlGrid, ...
    Limits=[0 12], Value=5, Step=1, ...
    BackgroundColor=colors.midGray, FontColor=colors.text);

uilabel(controlGrid, Text="Objective", FontColor=colors.muted);
app.Objective = uidropdown(controlGrid, ...
    Items=["Fastest trip", "Fewest stops", "Lowest risk"], ...
    ItemsData=["FastestTrip", "FewestStops", "LowestRisk"], ...
    Value="FastestTrip", BackgroundColor=colors.midGray, ...
    FontColor=colors.text);

app.PlanButton = uibutton(controlGrid, ...
    Text="Plan route", ...
    FontWeight="bold", ...
    BackgroundColor=colors.accent, ...
    FontColor=[0.02 0.05 0.04], ...
    ButtonPushedFcn=@planRoute);
app.PlanButton.Layout.Row = 18;
app.PlanButton.Layout.Column = [1 2];

app.Status = uilabel(controlGrid, ...
    Text="Ready", ...
    FontColor=colors.muted, ...
    WordWrap="on");
app.Status.Layout.Row = 19;
app.Status.Layout.Column = [1 2];

center = uigridlayout(root, [5 1]);
center.Layout.Column = 2;
center.RowHeight = {120, "1.15x", "1x", "1x", "0.85x"};
center.Padding = [0 0 0 0];
center.RowSpacing = 12;
center.BackgroundColor = colors.bg;

summary = uipanel(center, ...
    BorderColor=colors.panel2, ...
    BackgroundColor=colors.panel);
summary.Layout.Row = 1;
summaryGrid = uigridlayout(summary, [2 5]);
summaryGrid.RowHeight = {32, "1x"};
summaryGrid.ColumnWidth = repmat({"1x"}, 1, 5);
summaryGrid.Padding = [14 12 14 12];
summaryGrid.BackgroundColor = colors.panel;

titles = ["Status", "Distance", "Energy", "Trip time", "Final SoC"];
for k = 1:numel(titles)
    uilabel(summaryGrid, Text=titles(k), FontColor=colors.muted, ...
        HorizontalAlignment="center");
end
app.StatusValue = makeSummaryValue(summaryGrid, "Ready", colors);
app.DistanceValue = makeSummaryValue(summaryGrid, "-", colors);
app.EnergyValue = makeSummaryValue(summaryGrid, "-", colors);
app.TimeValue = makeSummaryValue(summaryGrid, "-", colors);
app.FinalSocValue = makeSummaryValue(summaryGrid, "-", colors);

app.StopTable = uitable(center, ...
    BackgroundColor=[colors.midGray; colors.midGrayAlt], ...
    ForegroundColor=colors.text);
app.StopTable.Layout.Row = 2;
app.StopTable.ColumnName = ["Stop", "Power", "Arrive", "Depart", "Charge"];

app.SocAxes = uiaxes(center, BackgroundColor=colors.midGrayAlt, ...
    XColor=colors.muted, YColor=colors.muted, ...
    GridColor=[0.25 0.31 0.29]);
app.SocAxes.Layout.Row = 3;
title(app.SocAxes, "SoC over route", Color=colors.text)
xlabel(app.SocAxes, "Distance (km)")
ylabel(app.SocAxes, "SoC (%)")

app.ProfileAxes = uiaxes(center, BackgroundColor=colors.midGrayAlt, ...
    XColor=colors.muted, YColor=colors.muted, ...
    GridColor=[0.25 0.31 0.29]);
app.ProfileAxes.Layout.Row = 4;
title(app.ProfileAxes, "Elevation and temperature", Color=colors.text)
xlabel(app.ProfileAxes, "Distance (km)")

app.EnergyAxes = uiaxes(center, BackgroundColor=colors.midGrayAlt, ...
    XColor=colors.muted, YColor=colors.muted, ...
    GridColor=[0.25 0.31 0.29]);
app.EnergyAxes.Layout.Row = 5;
title(app.EnergyAxes, "Energy by segment", Color=colors.text)
xlabel(app.EnergyAxes, "Distance (km)")
ylabel(app.EnergyAxes, "kWh")

mapPanel = uipanel(root, BackgroundColor=colors.panel, ...
    BorderColor=colors.panel2);
mapPanel.Layout.Column = 3;
mapGrid = uigridlayout(mapPanel, [2 1]);
mapGrid.RowHeight = {"1x", 32};
mapGrid.Padding = [8 8 8 8];
mapGrid.BackgroundColor = colors.panel;
app.MapAxes = geoaxes(mapGrid, Basemap="streets-dark");
app.MapAxes.Layout.Row = 1;
app.MapAxes.Color = colors.midGrayAlt;
title(app.MapAxes, "Route map", Color=colors.text)
app.MapHoverLabel = uilabel(mapGrid, ...
    Text="Hover over a charging stop", ...
    FontColor=colors.text, ...
    BackgroundColor=colors.midGray, ...
    HorizontalAlignment="center");
app.MapStopData = table();
app.Figure.WindowButtonMotionFcn = @updateMapHover;

    function planRoute(~, ~)
        app.PlanButton.Enable = "off";
        app.Status.Text = "Fetching route, elevation, weather, and chargers...";
        drawnow

        try
            result = evcharge.runChargingOptimization( ...
                StartAddress=string(app.Start.Value), ...
                DestinationAddress=string(app.Destination.Value), ...
                InitialSoCPercent=app.InitialSoc.Value, ...
                MarginSoCPercent=app.MarginSoc.Value, ...
                DestinationSoCPercent=app.TargetSoc.Value, ...
                VehicleID=string(app.Vehicle.Value), ...
                MaxStops=app.MaxStops.Value, ...
                Objective=string(app.Objective.Value), ...
                DepartureTime=datetime("now", TimeZone="UTC"), ...
                UseLiveData=true);
            updateUi(result);
            statusText = "Plan complete. Data source: " + result.DataSource;
            if isfield(result, "Warnings") && ~isempty(result.Warnings)
                statusText = statusText + newline + strjoin(result.Warnings, newline);
            end
            app.Status.Text = statusText;
        catch ME
            app.Status.Text = "Planning failed: " + string(ME.message);
        end

        app.PlanButton.Enable = "on";
    end

    function updateUi(result)
        app.StatusValue.Text = result.Status;
        app.DistanceValue.Text = sprintf("%.0f km", result.TotalDistanceKm);
        app.EnergyValue.Text = sprintf("%.0f kWh", result.TotalEnergyKWh);
        app.TimeValue.Text = sprintf("%.0f min", result.TotalTripTimeMinutes);
        app.FinalSocValue.Text = sprintf("%.0f %%", result.FinalSoCPercent);

        if isempty(result.Stops)
            app.StopTable.Data = table("No charging needed", "-", "-", "-", "-", ...
                VariableNames=["Stop", "Power", "Arrive", "Depart", "Charge"]);
        else
            app.StopTable.Data = table( ...
                result.Stops.StationName, ...
                compose("%.0f kW", result.Stops.PowerKW), ...
                compose("%.0f %%", result.Stops.ArrivalSoCPercent), ...
                compose("%.0f %%", result.Stops.DepartureSoCPercent), ...
                compose("%.0f min", result.Stops.ChargeTimeMinutes), ...
                VariableNames=["Stop", "Power", "Arrive", "Depart", "Charge"]);
        end

        plotSoc(result);
        plotMap(result);
        plotProfile(result);
        plotEnergy(result);
    end

    function plotSoc(result)
        evcharge.ui.plotSocProfile(app.SocAxes, result, colors)
    end

    function plotProfile(result)
        cla(app.ProfileAxes)
        yyaxis(app.ProfileAxes, "left")
        plot(app.ProfileAxes, result.RouteEnergy.EndKm, ...
            cumsum(result.RouteEnergy.ElevationDeltaM), ...
            LineWidth=1.8, Color=[0.47 0.78 0.96])
        ylabel(app.ProfileAxes, "Relative elevation (m)")
        yyaxis(app.ProfileAxes, "right")
        plot(app.ProfileAxes, result.RouteEnergy.EndKm, ...
            result.RouteEnergy.TemperatureC, ...
            LineWidth=1.8, Color=[0.95 0.62 0.18])
        ylabel(app.ProfileAxes, "Temperature (C)")
        grid(app.ProfileAxes, "on")
    end

    function plotEnergy(result)
        cla(app.EnergyAxes)
        bar(app.EnergyAxes, result.RouteEnergy.EndKm, ...
            result.RouteEnergy.EnergyKWh, ...
            FaceColor=colors.accent, EdgeColor="none")
        grid(app.EnergyAxes, "on")
    end

    function plotMap(result)
        app.MapStopData = evcharge.ui.plotRouteMap(app.MapAxes, result, colors);
        app.MapHoverLabel.Text = "Hover over a charging stop";
    end

    function updateMapHover(~, ~)
        if isempty(app.MapStopData) || ~isvalid(app.MapAxes)
            return
        end

        currentPoint = app.MapAxes.CurrentPoint;
        lat = currentPoint(1, 1);
        lon = currentPoint(1, 2);
        [latLimits, lonLimits] = geolimits(app.MapAxes);
        if lon < lonLimits(1) || lon > lonLimits(2) ...
                || lat < latLimits(1) || lat > latLimits(2)
            return
        end

        normalizedDistance = hypot( ...
            (app.MapStopData.Longitude - lon) ./ diff(lonLimits), ...
            (app.MapStopData.Latitude - lat) ./ diff(latLimits));
        [nearestDistance, nearestIndex] = min(normalizedDistance);
        if nearestDistance < 0.035
            app.MapHoverLabel.Text = sprintf("%s  |  %.4f, %.4f  |  %.0f kW", ...
                app.MapStopData.StationName(nearestIndex), ...
                app.MapStopData.Latitude(nearestIndex), ...
                app.MapStopData.Longitude(nearestIndex), ...
                app.MapStopData.PowerKW(nearestIndex));
        else
            app.MapHoverLabel.Text = "Hover over a charging stop";
        end
    end
end

function label = makeSummaryValue(parent, textValue, colors)
label = uilabel(parent, ...
    Text=textValue, ...
    FontSize=22, ...
    FontWeight="bold", ...
    FontColor=colors.text, ...
    HorizontalAlignment="center");
end
