function buildEVChargingDemo()
%BUILDEVCHARGINGDEMO Generate the Simulink and System Composer demo models.
%
%   BUILDEVCHARGINGDEMO creates EVChargingSimulation.slx and
%   EVChargingArchitecture.slx in the current folder. Existing generated
%   models with those names are replaced so the script is repeatable.

addProjectPaths
buildSimulationModel();
buildArchitectureModel();
fprintf("Generated EVChargingSimulation.slx and EVChargingArchitecture.slx.\n");
end

function buildSimulationModel()
modelName = "EVChargingSimulation";
replaceModelFile(modelName);

new_system(modelName);
open_system(modelName);
set_param(modelName, ...
    "StopTime", "0", ...
    "Solver", "FixedStepDiscrete", ...
    "SystemTargetFile", "grt.tlc");

add_block("simulink/Sources/Constant", modelName + "/InitialSoCPercent", ...
    "Value", "72", "Position", [60 80 150 115]);
add_block("simulink/Sources/Constant", modelName + "/MarginSoCPercent", ...
    "Value", "10", "Position", [60 150 150 185]);

functionBlock = modelName + "/ChargingOptimization";
add_block("simulink/User-Defined Functions/MATLAB Function", functionBlock, ...
    "Position", [245 80 430 190]);
setMatlabFunctionScript(functionBlock);

displayNames = ["FinalSoCPercent", "MinimumSoCPercent", ...
    "ChargeTimeMinutes", "NumberOfStops", "StatusCode"];
for k = 1:numel(displayNames)
    top = 45 + 55*k;
    add_block("simulink/Sinks/Display", modelName + "/" + displayNames(k), ...
        "Position", [520 top 650 top+30]);
    add_line(modelName, "ChargingOptimization/" + k, ...
        displayNames(k) + "/1", "autorouting", "on");
end

add_line(modelName, "InitialSoCPercent/1", ...
    "ChargingOptimization/1", "autorouting", "on");
add_line(modelName, "MarginSoCPercent/1", ...
    "ChargingOptimization/2", "autorouting", "on");

add_block("simulink/Sources/From Workspace", modelName + "/SoCProfileFromRunDemo", ...
    "VariableName", "socProfileTimeseries", ...
    "Position", [60 270 205 305]);
add_block("simulink/Sinks/Scope", modelName + "/SoCOverDistance", ...
    "Position", [285 255 420 320]);
add_line(modelName, "SoCProfileFromRunDemo/1", ...
    "SoCOverDistance/1", "autorouting", "on");

save_system(modelName);
end

function setMatlabFunctionScript(blockPath)
root = sfroot;
chart = root.find("-isa", "Stateflow.EMChart", "Path", blockPath);
scriptLines = [
    "function [finalSocPercent, minSocPercent, totalChargeTimeMinutes, numStops, statusCode] = fcn(initialSocPercent, marginSocPercent)"
    "%#codegen"
    "coder.extrinsic('evcharge.simulinkEntryPoint');"
    "finalSocPercent = 0;"
    "minSocPercent = 0;"
    "totalChargeTimeMinutes = 0;"
    "numStops = 0;"
    "statusCode = -1;"
    "[finalSocPercent, minSocPercent, totalChargeTimeMinutes, numStops, statusCode] = evcharge.simulinkEntryPoint(initialSocPercent, marginSocPercent);"
    "end"];
chart.Script = char(strjoin(scriptLines, newline));
end

function buildArchitectureModel()
modelName = "EVChargingArchitecture";
replaceModelFile(modelName);

model = systemcomposer.createModel(modelName);
arch = model.Architecture;

journey = arch.addComponent("Journey_Input");
route = arch.addComponent("Finland_Route_Data_Access");
vehicle = arch.addComponent("Vehicle");
battery = vehicle.Architecture.addComponent("Battery");
soc = vehicle.Architecture.addComponent("SoC_Estimation");
energy = arch.addComponent("Energy_Consumption");
stations = arch.addComponent("Charging_Station_Data");
optimizer = arch.addComponent("Charging_Optimization");
display = arch.addComponent("Driver_Display");

setComponentPositions(journey, route, vehicle, battery, soc, ...
    energy, stations, optimizer, display);

journeyRequest = journey.Architecture.addPort("Journey_Request", "out");
routeRequest = route.Architecture.addPort("Journey_Request", "in");
routeProfile = route.Architecture.addPort("Route_Profile", "out");
energyRoute = energy.Architecture.addPort("Route_Profile", "in");

vehicleState = vehicle.Architecture.addPort("Vehicle_State", "out");
energyVehicle = energy.Architecture.addPort("Vehicle_State", "in");
energyDemand = energy.Architecture.addPort("Energy_Demand", "out");

stationQuery = stations.Architecture.addPort("Route_Profile", "in");
stationList = stations.Architecture.addPort("Station_List", "out");
optimizerEnergy = optimizer.Architecture.addPort("Energy_Demand", "in");
optimizerStations = optimizer.Architecture.addPort("Station_List", "in");
chargingPlan = optimizer.Architecture.addPort("Charging_Plan", "out");
displayPlan = display.Architecture.addPort("Charging_Plan", "in");

arch.connect(journeyRequest, routeRequest);
arch.connect(routeProfile, energyRoute);
arch.connect(routeProfile, stationQuery);
arch.connect(vehicleState, energyVehicle);
arch.connect(energyDemand, optimizerEnergy);
arch.connect(stationList, optimizerStations);
arch.connect(chargingPlan, displayPlan);

batterySoC = battery.Architecture.addPort("Battery_SoC", "out");
socBattery = soc.Architecture.addPort("Battery_SoC", "in");
socEstimate = soc.Architecture.addPort("Estimated_SoC", "out");
vehicleSoC = vehicle.Architecture.addPort("Estimated_SoC", "out");
vehicle.Architecture.connect(batterySoC, socBattery);
vehicle.Architecture.connect(socEstimate, vehicleSoC);

save_system(modelName);
end

function setComponentPositions(journey, route, vehicle, battery, soc, ...
    energy, stations, optimizer, display)
journey.Position = [60 110 180 170];
route.Position = [250 90 430 190];
vehicle.Position = [250 245 430 360];
battery.Position = [40 45 150 95];
soc.Position = [205 45 330 95];
energy.Position = [505 130 685 230];
stations.Position = [505 285 685 365];
optimizer.Position = [760 180 960 300];
display.Position = [1030 210 1190 270];
end

function replaceModelFile(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

modelFile = modelName + ".slx";
if exist(modelFile, "file") == 2
    delete(modelFile);
end
end
