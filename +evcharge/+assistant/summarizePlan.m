function summary = summarizePlan(result)
%SUMMARIZEPLAN Condense an optimization result for a small LLM.
%
%   SUMMARY = EVCHARGE.ASSISTANT.SUMMARIZEPLAN(RESULT) converts the output
%   of evcharge.runChargingOptimization into a short struct with rounded
%   numbers, the charging stops, and the main reasons for energy use.

arguments
    result struct
end

summary.can_reach_destination = result.Status == "Feasible";
summary.status_message = result.StatusMessage;
summary.from = result.StartAddress;
summary.to = result.DestinationAddress;
summary.distance_km = round(result.TotalDistanceKm);
summary.drive_minutes = round(result.TotalDriveTimeMinutes);
summary.charging_minutes = round(result.TotalChargeTimeMinutes);
summary.total_trip_minutes = round(result.TotalTripTimeMinutes);
summary.energy_needed_kwh = round(result.TotalEnergyKWh, 1);
summary.start_battery_percent = round(result.InitialSoCPercent);
summary.arrival_battery_percent = round(result.FinalSoCPercent);
summary.lowest_battery_percent = round(result.MinimumSoCPercent);
summary.number_of_stops = height(result.Stops);
summary.stops = stopList(result);
summary.energy_factors = energyFactors(result.RouteEnergy);
summary.data_source = result.DataSource;
if ~isempty(result.Warnings)
    summary.warnings = result.Warnings(:)';
end
end

function stops = stopList(result)
stops = struct("name", {}, "km_from_start", {}, "drive_minutes_to_stop", {}, ...
    "charger_kw", {}, "arrive_percent", {}, "leave_percent", {}, ...
    "charge_minutes", {});
routeEnergy = result.RouteEnergy;
cumulativeMinutes = [0; cumsum(routeEnergy.DurationSeconds) / 60];
distanceBreakpoints = [0; routeEnergy.EndKm];
for k = 1:height(result.Stops)
    stop = result.Stops(k, :);
    driveMinutes = interp1(distanceBreakpoints, cumulativeMinutes, ...
        stop.DistanceKm, "linear", "extrap");
    previousChargeMinutes = sum(result.Stops.ChargeTimeMinutes(1:k-1));
    stops(k).name = stop.StationName;
    stops(k).km_from_start = round(stop.DistanceKm);
    stops(k).drive_minutes_to_stop = round(driveMinutes + previousChargeMinutes);
    stops(k).charger_kw = round(stop.PowerKW);
    stops(k).arrive_percent = round(stop.ArrivalSoCPercent);
    stops(k).leave_percent = round(stop.DepartureSoCPercent);
    stops(k).charge_minutes = round(stop.ChargeTimeMinutes);
end
end

function factors = energyFactors(routeEnergy)
totalKWh = sum(routeEnergy.EnergyKWh);
weightedMultiplier = sum(routeEnergy.WeatherMultiplier .* routeEnergy.DistanceKm) ...
    / sum(routeEnergy.DistanceKm);
factors.average_temperature_c = round(mean(routeEnergy.TemperatureC));
factors.cold_weather_extra_percent = round((weightedMultiplier - 1) * 100);
factors.heating_and_accessories_kwh = round(sum(routeEnergy.AccessoryEnergyKWh), 1);
factors.climbing_kwh = round(sum(routeEnergy.ClimbEnergyKWh), 1);
factors.regenerated_kwh = round(sum(routeEnergy.RegeneratedEnergyKWh), 1);
factors.average_consumption_kwh_per_100km = round( ...
    totalKWh / sum(routeEnergy.DistanceKm) * 100, 1);
end
