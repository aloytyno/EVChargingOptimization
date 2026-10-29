function result = runChargingOptimization(options)
%RUNCHARGINGOPTIMIZATION Run route energy estimation and stop planning.
%
%   RESULT = RUNCHARGINGOPTIMIZATION runs the default Finland scenario.
%
%   RESULT = RUNCHARGINGOPTIMIZATION("InitialSoCPercent", 70,
%   "MarginSoCPercent", 10) overrides the journey settings.

arguments
    options.InitialSoCPercent (1,1) double = 72
    options.MarginSoCPercent (1,1) double = 10
    options.StartAddress (1,1) string = "Helsinki, Finland"
    options.DestinationAddress (1,1) string = "Oulu, Finland"
    options.Scenario (1,1) string = "helsinki-to-oulu"
    options.UseLiveData (1,1) logical = false
    options.DepartureTime (1,1) datetime = datetime("now", TimeZone="UTC")
    options.Objective (1,1) string = "FastestTrip"
    options.VehicleID (1,1) string = "tesla-model-y-performance"
    options.MaxStops (1,1) double = Inf
    options.DestinationSoCPercent (1,1) double = NaN
    options.TargetChargeSoCPercent (1,1) double = NaN
    options.OutsideTemperatureC (1,1) double = NaN
end

vehicle = evcharge.selectVehicle(options.VehicleID);
if ~isnan(options.TargetChargeSoCPercent)
    vehicle.TargetChargeSoCPercent = options.TargetChargeSoCPercent;
end
requiredArrivalSocPercent = options.MarginSoCPercent;
if ~isnan(options.DestinationSoCPercent)
    requiredArrivalSocPercent = max(options.MarginSoCPercent, ...
        options.DestinationSoCPercent);
end
routeData = evcharge.getRouteData( ...
    "StartAddress", options.StartAddress, ...
    "DestinationAddress", options.DestinationAddress, ...
    "Scenario", options.Scenario, ...
    "UseLiveData", options.UseLiveData, ...
    "DepartureTime", options.DepartureTime);

% Cached routes carry no weather, so apply the given outside temperature
% when one is provided. Live routes keep their per-segment forecast.
if ~isnan(options.OutsideTemperatureC) && ~ismember("TemperatureC", ...
        routeData.RouteSegments.Properties.VariableNames)
    routeData.RouteSegments.TemperatureC = options.OutsideTemperatureC ...
        * ones(height(routeData.RouteSegments), 1);
end

routeEnergy = evcharge.estimateEnergy(routeData.RouteSegments, vehicle);
plan = evcharge.planChargingStops(routeEnergy, ...
    routeData.ChargingStations, options.InitialSoCPercent, ...
    options.MarginSoCPercent, vehicle, ...
    "Objective", options.Objective, ...
    "DestinationSoCPercent", requiredArrivalSocPercent, ...
    "MaxStops", options.MaxStops);

result = struct();
result.Status = plan.Status;
result.StatusMessage = plan.StatusMessage;
result.StartAddress = routeData.StartAddress;
result.DestinationAddress = routeData.DestinationAddress;
result.RouteName = routeData.Name;
result.DataSource = routeData.Source;
result.Vehicle = vehicle;
result.RouteEnergy = routeEnergy;
result.ChargingStations = routeData.ChargingStations;
result.Stops = plan.Stops;
result.SoCProfile = plan.SoCProfile;
result.TotalDistanceKm = routeEnergy.EndKm(end);
result.TotalEnergyKWh = routeEnergy.CumulativeEnergyKWh(end);
result.TotalChargeTimeMinutes = plan.TotalChargeTimeMinutes;
result.TotalDriveTimeMinutes = sum(routeEnergy.DurationSeconds) / 60;
result.TotalTripTimeMinutes = result.TotalDriveTimeMinutes ...
    + result.TotalChargeTimeMinutes;
result.InitialSoCPercent = options.InitialSoCPercent;
result.MarginSoCPercent = options.MarginSoCPercent;
result.DestinationSoCPercent = requiredArrivalSocPercent;
result.Objective = options.Objective;
result.VehicleID = vehicle.ID;
result.MaxStops = options.MaxStops;
result.DepartureTime = options.DepartureTime;
result.FinalSoCPercent = plan.FinalSoCPercent;
result.MinimumSoCPercent = plan.MinimumSoCPercent;
if isfield(routeData, "Warnings")
    result.Warnings = routeData.Warnings;
else
    result.Warnings = strings(0,1);
end
if isfield(routeData, "RoutePoints")
    result.RoutePoints = routeData.RoutePoints;
else
    result.RoutePoints = table([], [], VariableNames=["Latitude", "Longitude"]);
end
end
