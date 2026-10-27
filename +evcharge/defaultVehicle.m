function vehicle = defaultVehicle()
%DEFAULTVEHICLE Return nominal EV parameters for the Finland demo.
%
%   VEHICLE = DEFAULTVEHICLE returns a structure used by the readable
%   energy model and charging optimizer.

vehicle.Name = "Nominal long-range EV";
vehicle.BatteryCapacityKWh = 77;
vehicle.UsableBatteryCapacityKWh = 74;
vehicle.VehicleMassKg = 2100;
vehicle.BaseConsumptionKWhPerKm = 0.168;
vehicle.ReferenceSpeedKmh = 90;
vehicle.HighSpeedPenaltyPerKmh = 0.0032;
vehicle.LowSpeedPenaltyPerKmh = 0.0010;
vehicle.ClimbEfficiency = 0.86;
vehicle.RegenerationEfficiency = 0.42;
vehicle.DrivetrainEfficiency = 0.90;
vehicle.RegenerativePowerLimitKW = 70;
vehicle.DragCoefficientAreaM2 = 0.68;
vehicle.RollingResistanceCoefficient = 0.010;
vehicle.AirDensityKgPerM3 = 1.225;
vehicle.BaseAccessoryPowerKW = 0.7;
vehicle.HeatPumpPowerKW = 1.2;
vehicle.ResistiveHeaterPowerKW = 3.2;
vehicle.CoolingPowerKW = 1.0;
vehicle.ColdEfficiencyPenaltyPerDegC = 0.006;
vehicle.WarmEfficiencyPenaltyPerDegC = 0.002;
vehicle.ComfortTemperatureLowC = 16;
vehicle.ComfortTemperatureHighC = 24;
vehicle.MaximumChargePowerKW = 170;
vehicle.ChargeStopOverheadMinutes = 5;
vehicle.FastChargeTaperStartSoCPercent = 55;
vehicle.FastChargeTaperEndSoCPercent = 90;
vehicle.TargetChargeSoCPercent = 82;
vehicle.MaximumChargeSoCPercent = 92;
vehicle.ChargeTaperEfficiency = 0.86;
end
