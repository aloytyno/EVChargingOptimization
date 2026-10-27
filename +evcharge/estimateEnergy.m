function routeEnergy = estimateEnergy(routeSegments, vehicle)
%ESTIMATEENERGY Estimate per-segment EV energy use.
%
%   ROUTEENERGY = ESTIMATEENERGY(ROUTESEGMENTS, VEHICLE) adds EnergyKWh
%   and CumulativeEnergyKWh columns to the route segment table. When the
%   route table includes live route-profile fields such as DurationSeconds
%   and TemperatureC, this function uses a physics-informed estimate based
%   on rolling resistance, aerodynamic drag, road grade, regenerative
%   braking, and HVAC/accessory loads.

arguments
    routeSegments table
    vehicle struct = evcharge.defaultVehicle()
end

distanceKm = routeSegments.DistanceKm;
elevationDeltaM = routeSegments.ElevationDeltaM;

if ismember("DurationSeconds", routeSegments.Properties.VariableNames)
    durationSeconds = max(routeSegments.DurationSeconds, 1);
else
    speedLimitKmh = routeSegments.SpeedLimitKmh;
    durationSeconds = distanceKm ./ max(speedLimitKmh, 1) * 3600;
end

if ismember("SpeedKmh", routeSegments.Properties.VariableNames)
    speedKmh = routeSegments.SpeedKmh;
else
    speedKmh = distanceKm ./ durationSeconds * 3600;
end

if ismember("TemperatureC", routeSegments.Properties.VariableNames)
    temperatureC = routeSegments.TemperatureC;
else
    temperatureC = 20 * ones(size(distanceKm));
end

durationHours = durationSeconds ./ 3600;
distanceM = distanceKm .* 1000;
speedMps = max(speedKmh ./ 3.6, 0);

rollingForceN = vehicle.VehicleMassKg .* 9.81 ...
    .* vehicle.RollingResistanceCoefficient;
rollingEnergyKWh = rollingForceN .* distanceM ./ 3.6e6 ...
    ./ vehicle.DrivetrainEfficiency;

aeroForceN = 0.5 .* vehicle.AirDensityKgPerM3 ...
    .* vehicle.DragCoefficientAreaM2 .* speedMps.^2;
aeroEnergyKWh = aeroForceN .* distanceM ./ 3.6e6 ...
    ./ vehicle.DrivetrainEfficiency;

if isfield(vehicle, "ReferenceCruisePower90KphKW")
    cruiseScale = cruiseCalibrationScale(vehicle);
    rollingEnergyKWh = rollingEnergyKWh .* cruiseScale;
    aeroEnergyKWh = aeroEnergyKWh .* cruiseScale;
end

positiveElevationM = max(elevationDeltaM, 0);
negativeElevationM = max(-elevationDeltaM, 0);
climbEnergyKWh = vehicle.VehicleMassKg .* 9.81 .* positiveElevationM ...
    ./ 3.6e6 ./ vehicle.ClimbEfficiency;
availableDownhillKWh = vehicle.VehicleMassKg .* 9.81 .* negativeElevationM ...
    ./ 3.6e6;
regenLimitKWh = vehicle.RegenerativePowerLimitKW .* durationHours;
regenEnergyKWh = min(availableDownhillKWh .* vehicle.RegenerationEfficiency, ...
    regenLimitKWh);

hvacPowerKW = hvacPower(temperatureC, vehicle);
accessoryEnergyKWh = (vehicle.BaseAccessoryPowerKW + hvacPowerKW) ...
    .* durationHours;

coldPenalty = max(vehicle.ComfortTemperatureLowC - temperatureC, 0) ...
    .* vehicle.ColdEfficiencyPenaltyPerDegC;
warmPenalty = max(temperatureC - vehicle.ComfortTemperatureHighC, 0) ...
    .* vehicle.WarmEfficiencyPenaltyPerDegC;
weatherMultiplier = 1 + coldPenalty + warmPenalty;

tractionEnergyKWh = (rollingEnergyKWh + aeroEnergyKWh + climbEnergyKWh ...
    - regenEnergyKWh) .* weatherMultiplier;

% Keep each segment positive so downhill recovery never creates a net
% energy-producing road segment in this demo model.
minimumSegmentEnergyKWh = 0.025 .* distanceKm;
energyKWh = max(tractionEnergyKWh + accessoryEnergyKWh, ...
    minimumSegmentEnergyKWh);

routeEnergy = routeSegments;
routeEnergy.SpeedKmh = speedKmh;
routeEnergy.DurationSeconds = durationSeconds;
routeEnergy.TemperatureC = temperatureC;
routeEnergy.RollingEnergyKWh = rollingEnergyKWh;
routeEnergy.AeroEnergyKWh = aeroEnergyKWh;
routeEnergy.ClimbEnergyKWh = climbEnergyKWh;
routeEnergy.RegeneratedEnergyKWh = regenEnergyKWh;
routeEnergy.AccessoryEnergyKWh = accessoryEnergyKWh;
routeEnergy.WeatherMultiplier = weatherMultiplier;
routeEnergy.EnergyKWh = energyKWh;
routeEnergy.CumulativeEnergyKWh = cumsum(energyKWh);
end

function hvacPowerKW = hvacPower(temperatureC, vehicle)
%HVACPOWER Estimate cabin climate power from route weather.

heatingNeed = max(vehicle.ComfortTemperatureLowC - temperatureC, 0);
coolingNeed = max(temperatureC - vehicle.ComfortTemperatureHighC, 0);

heatPumpShare = min(heatingNeed ./ 12, 1) .* vehicle.HeatPumpPowerKW;
resistiveShare = max(heatingNeed - 12, 0) ./ 18 ...
    .* vehicle.ResistiveHeaterPowerKW;
coolingShare = min(coolingNeed ./ 12, 1) .* vehicle.CoolingPowerKW;

hvacPowerKW = heatPumpShare + resistiveShare + coolingShare;
end

function cruiseScale = cruiseCalibrationScale(vehicle)
%CRUISECALIBRATIONSCALE Match flat-road 90 km/h power to reference data.

referenceSpeedMps = 90 / 3.6;
rollingForceN = vehicle.VehicleMassKg .* 9.81 ...
    .* vehicle.RollingResistanceCoefficient;
aeroForceN = 0.5 .* vehicle.AirDensityKgPerM3 ...
    .* vehicle.DragCoefficientAreaM2 .* referenceSpeedMps.^2;
rawTractionPowerKW = (rollingForceN + aeroForceN) ...
    .* referenceSpeedMps ./ 1000 ./ vehicle.DrivetrainEfficiency;

referenceTractionPowerKW = max(vehicle.ReferenceCruisePower90KphKW ...
    - vehicle.BaseAccessoryPowerKW, 1);
cruiseScale = referenceTractionPowerKW ./ max(rawTractionPowerKW, 1);
end
