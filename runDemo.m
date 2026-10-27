function result = runDemo(initialSocPercent, marginSocPercent)
%RUNDEMO Run the Finland EV charging optimization demo.
%
%   RESULT = RUNDEMO runs the default Helsinki-to-Oulu demo using cached
%   Finnish route and charging-station data.
%
%   RESULT = RUNDEMO(INITIALSOCPERCENT, MARGINSOCPERCENT) overrides the
%   default initial state of charge and required arrival margin.

arguments
    initialSocPercent (1,1) double = 72
    marginSocPercent (1,1) double = 10
end

addProjectPaths
config = evchargeSimConfig();

result = evcharge.runChargingOptimization( ...
    "InitialSoCPercent", initialSocPercent, ...
    "MarginSoCPercent", marginSocPercent, ...
    "StartAddress", config.StartAddress, ...
    "DestinationAddress", config.DestinationAddress, ...
    "Scenario", config.Scenario, ...
    "UseLiveData", config.UseLiveData);

assignin("base", "evChargingResult", result);
socProfileTimeseries = timeseries( ...
    result.SoCProfile.SoCPercent, result.SoCProfile.DistanceKm);
assignin("base", "socProfileTimeseries", socProfileTimeseries);

fprintf("Route: %s to %s\n", result.StartAddress, result.DestinationAddress);
fprintf("Status: %s\n", result.Status);
fprintf("Total route distance: %.1f km\n", result.TotalDistanceKm);
fprintf("Estimated route energy: %.1f kWh\n", result.TotalEnergyKWh);
fprintf("Charging stops: %d\n", height(result.Stops));
fprintf("Final SoC: %.1f %%\n", result.FinalSoCPercent);

if ~isempty(result.Stops)
    disp(result.Stops(:, ["StationName", "DistanceKm", ...
        "PowerKW", "ArrivalSoCPercent", "DepartureSoCPercent", ...
        "ChargeTimeMinutes"]));
end

modelName = "EVChargingSimulation";
if exist(modelName + ".slx", "file") == 2
    open_system(modelName);
end
end
