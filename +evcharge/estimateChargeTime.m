function [chargeTimeMinutes, chargeAddedKWh] = estimateChargeTime( ...
    arrivalSocPercent, departureSocPercent, stationPowerKW, vehicle)
%ESTIMATECHARGETIME Estimate charging time from vehicle curve and station.
%
%   [MINUTES, KWH] = ESTIMATECHARGETIME(ARRIVAL, DEPARTURE, STATIONPOWER,
%   VEHICLE) numerically integrates the selected vehicle's charge curve.

arguments
    arrivalSocPercent (1,1) double
    departureSocPercent (1,1) double
    stationPowerKW (1,1) double
    vehicle struct = evcharge.defaultVehicle()
end

arrivalSocPercent = max(min(arrivalSocPercent, 100), 0);
departureSocPercent = max(min(departureSocPercent, 100), 0);
if departureSocPercent <= arrivalSocPercent
    chargeTimeMinutes = 0;
    chargeAddedKWh = 0;
    return
end

socGrid = (arrivalSocPercent:0.5:departureSocPercent)';
if socGrid(end) ~= departureSocPercent
    socGrid(end+1, 1) = departureSocPercent;
end

midSoc = (socGrid(1:end-1) + socGrid(2:end)) ./ 2;
deltaSoc = diff(socGrid);
deltaEnergyKWh = deltaSoc ./ 100 .* vehicle.UsableBatteryCapacityKWh;

if isfield(vehicle, "ChargeCurveSocPercent") ...
        && isfield(vehicle, "ChargeCurvePowerKW")
    vehiclePowerKW = interp1(vehicle.ChargeCurveSocPercent, ...
        vehicle.ChargeCurvePowerKW, midSoc, "linear", "extrap");
else
    vehiclePowerKW = vehicle.MaximumChargePowerKW ...
        .* ones(size(midSoc));
end

effectivePowerKW = min(vehiclePowerKW, stationPowerKW);
effectivePowerKW = max(effectivePowerKW .* vehicle.ChargeTaperEfficiency, 1);
chargeTimeMinutes = sum(deltaEnergyKWh ./ effectivePowerKW) * 60;
chargeAddedKWh = sum(deltaEnergyKWh);
end
