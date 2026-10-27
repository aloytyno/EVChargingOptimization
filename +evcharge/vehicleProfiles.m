function profiles = vehicleProfiles()
%VEHICLEPROFILES Return selectable EV profiles for the planner.
%
%   PROFILES = VEHICLEPROFILES returns a struct array. Each profile extends
%   the nominal vehicle parameters with battery capacity and DC fast-charging
%   curves digitized from user-provided reference plots.

profiles = [teslaModelYPerformance(), kiaEv6LongRange()];
end

function vehicle = baseVehicle()
vehicle = evcharge.defaultVehicle();
end

function vehicle = teslaModelYPerformance()
vehicle = baseVehicle();
vehicle.ID = "tesla-model-y-performance";
vehicle.Name = "Tesla Model Y Performance";
vehicle.BatteryCapacityKWh = 85;
vehicle.UsableBatteryCapacityKWh = 81;
vehicle.VehicleMassKg = 2050;
vehicle.DragCoefficientAreaM2 = 0.66;
vehicle.ReferenceCruisePower90KphKW = 14.1;
vehicle.MaximumChargePowerKW = 250;
vehicle.TargetChargeSoCPercent = 82;
vehicle.MaximumChargeSoCPercent = 92;
vehicle.ChargeCurveSocPercent = [ ...
    0 2 5 6 8 9 10 12 14 16 18 20 22 24 25 26 27 29 31 33 ...
    35 36 38 40 42 44 46 48 50 52 55 58 60 62 65 66 67 69 ...
    70 72 74 76 78 80 82 84 86 88 90 92 94 95 96 97 98 99 100];
vehicle.ChargeCurvePowerKW = [ ...
    100 108 108 230 240 245 226 230 229 222 215 202 193 185 ...
    181 168 172 177 170 162 150 140 132 125 116 112 108 105 ...
    100 97 91 84 80 81 79 72 74 66 64 59 56 54 52 50 48 45 ...
    44 41 39 35 29 28 24 18 14 8 8];
end

function vehicle = kiaEv6LongRange()
vehicle = baseVehicle();
vehicle.ID = "kia-ev6-long-range-2wd";
vehicle.Name = "Kia EV6 Long Range 2WD";
vehicle.BatteryCapacityKWh = 77;
vehicle.UsableBatteryCapacityKWh = 74;
vehicle.VehicleMassKg = 2000;
vehicle.DragCoefficientAreaM2 = 0.70;
vehicle.ReferenceCruisePower90KphKW = 17.5;
vehicle.MaximumChargePowerKW = 258;
vehicle.TargetChargeSoCPercent = 82;
vehicle.MaximumChargeSoCPercent = 92;
vehicle.ChargeCurveSocPercent = [ ...
    0 1 2 4 6 8 10 12 14 16 18 20 22 25 26 28 30 33 36 39 ...
    42 45 48 50 51 54 57 58 60 62 63 65 67 68 69 70 72 74 ...
    75 76 77 78 79 80 82 84 86 88 90 91 92 94 96 98 100];
vehicle.ChargeCurvePowerKW = [ ...
    50 205 213 216 219 220 222 223 224 222 224 224 224 225 ...
    247 248 250 250 251 251 253 253 255 257 204 205 205 207 ...
    195 195 160 161 162 118 119 118 119 119 99 90 82 73 66 ...
    58 48 40 34 32 32 30 25 20 14 9 8];
end
