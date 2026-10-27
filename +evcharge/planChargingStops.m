function plan = planChargingStops(routeEnergy, chargingStations, ...
    initialSocPercent, marginSocPercent, vehicle, options)
%PLANCHARGINGSTOPS Select charging stops for a route.
%
%   PLAN = PLANCHARGINGSTOPS(ROUTEENERGY, STATIONS, INITIALSOC, MARGINSOC,
%   VEHICLE) greedily selects the station where arrival SoC is closest to
%   the required margin, then prefers higher charger power.

arguments
    routeEnergy table
    chargingStations table
    initialSocPercent (1,1) double
    marginSocPercent (1,1) double
    vehicle struct = evcharge.defaultVehicle()
    options.Objective (1,1) string = "FastestTrip"
    options.DestinationSoCPercent (1,1) double = marginSocPercent
    options.MaxStops (1,1) double = Inf
end

batteryCapacityKWh = vehicle.UsableBatteryCapacityKWh;
marginSoc = marginSocPercent / 100;
destinationSoc = max(options.DestinationSoCPercent, marginSocPercent) / 100;
currentSoc = initialSocPercent / 100;
currentDistanceKm = 0;
targetSoc = vehicle.TargetChargeSoCPercent / 100;
maximumChargeSoc = vehicle.MaximumChargeSoCPercent / 100;
totalDistanceKm = routeEnergy.EndKm(end);

stops = makeEmptyStopsTable();
status = "Feasible";
statusMessage = "Charging plan found.";

if strcmpi(options.Objective, "FastestTrip")
    plan = planFastestTrip(routeEnergy, chargingStations, ...
        initialSocPercent, marginSoc, destinationSoc, vehicle, ...
        options.MaxStops);
    return
end

while true
    energyToDestinationKWh = energyBetween(routeEnergy, ...
        currentDistanceKm, totalDistanceKm);
    if currentSoc - energyToDestinationKWh / batteryCapacityKWh >= destinationSoc
        finalSoc = currentSoc - energyToDestinationKWh / batteryCapacityKWh;
        break
    end

    remainingEnergyAboveMarginKWh = ...
        (currentSoc - marginSoc) * batteryCapacityKWh;
    candidateStations = chargingStations( ...
        chargingStations.DistanceKm > currentDistanceKm + 0.1 ...
        & chargingStations.DistanceKm < totalDistanceKm - 0.1, :);

    if isempty(candidateStations)
        status = "Infeasible";
        statusMessage = "No charging stations remain after the current position.";
        finalSoc = currentSoc - energyToDestinationKWh / batteryCapacityKWh;
        break
    end

    energyToStationKWh = arrayfun(@(d) energyBetween(routeEnergy, ...
        currentDistanceKm, d), candidateStations.DistanceKm);
    arrivalSoc = currentSoc - energyToStationKWh ./ batteryCapacityKWh;
    reachable = energyToStationKWh <= remainingEnergyAboveMarginKWh;

    if ~any(reachable)
        status = "Infeasible";
        statusMessage = "No reachable station satisfies the requested SoC margin.";
        finalSoc = currentSoc - energyToDestinationKWh / batteryCapacityKWh;
        break
    end

    reachableStations = candidateStations(reachable, :);
    reachableArrivalSoc = arrivalSoc(reachable);
    score = scoreReachableStations(reachableStations, reachableArrivalSoc, ...
        marginSoc, targetSoc, vehicle, options.Objective);
    score = sortrows(score, score.Properties.VariableNames(1:3));
    chosenIndex = score.OriginalIndex(1);

    station = reachableStations(chosenIndex, :);
    stationArrivalSoc = reachableArrivalSoc(chosenIndex);
    energyFromStationToDestinationKWh = energyBetween(routeEnergy, ...
        station.DistanceKm, totalDistanceKm);
    requiredDepartureForDestination = destinationSoc ...
        + energyFromStationToDestinationKWh / batteryCapacityKWh;
    if requiredDepartureForDestination <= maximumChargeSoc
        departureSoc = max(requiredDepartureForDestination, stationArrivalSoc);
    else
        departureSoc = max(targetSoc, stationArrivalSoc);
    end
    departureSoc = min(departureSoc, maximumChargeSoc);

    [chargeTimeMinutes, chargeAddedKWh] = evcharge.estimateChargeTime( ...
        stationArrivalSoc * 100, departureSoc * 100, station.PowerKW, ...
        vehicle);
    if chargeAddedKWh > 1e-6
        chargeTimeMinutes = chargeTimeMinutes ...
            + vehicle.ChargeStopOverheadMinutes;
    end

    stops = [stops; makeStopRow( ...
        station, ...
        stationArrivalSoc * 100, departureSoc * 100, ...
        chargeAddedKWh, chargeTimeMinutes)]; %#ok<AGROW>
    if height(stops) > options.MaxStops
        status = "Infeasible";
        statusMessage = "Required charging stops exceed the maximum allowed.";
        finalSoc = currentSoc - energyToDestinationKWh / batteryCapacityKWh;
        break
    end

    currentDistanceKm = station.DistanceKm;
    currentSoc = departureSoc;
end

plan.Status = status;
plan.StatusMessage = statusMessage;
plan.Stops = stops;
plan.FinalSoCPercent = finalSoc * 100;
plan.MinimumSoCPercent = minimumSoc(routeEnergy, stops, ...
    initialSocPercent, finalSoc * 100, vehicle);
plan.TotalChargeTimeMinutes = sum(stops.ChargeTimeMinutes);
plan.SoCProfile = buildSocProfile(routeEnergy, stops, ...
    initialSocPercent, finalSoc * 100, vehicle);
end

function plan = planFastestTrip(routeEnergy, chargingStations, ...
    initialSocPercent, marginSoc, destinationSoc, vehicle, maxStops)
%PLANFASTESTTRIP Search charger combinations for minimum charge time.

batteryCapacityKWh = vehicle.UsableBatteryCapacityKWh;
maximumChargeSoc = vehicle.MaximumChargeSoCPercent / 100;
totalDistanceKm = routeEnergy.EndKm(end);
stations = chargingStations( ...
    chargingStations.DistanceKm > 0.1 ...
    & chargingStations.DistanceKm < totalDistanceKm - 0.1 ...
    & chargingStations.PowerKW > 0, :);
stations = sortrows(stations, ["DistanceKm", "PowerKW"], ...
    ["ascend", "descend"]);
stations = pruneFastestTripStations(stations);

nodeDistanceKm = [0; stations.DistanceKm; totalDistanceKm];
nodeEnergyKWh = cumulativeEnergyAtDistance(routeEnergy, nodeDistanceKm);
stationPowerByNodeKW = stations.PowerKW;
numNodes = numel(nodeDistanceKm);
destinationNode = numNodes;
chargeCurveCache = containers.Map("KeyType", "char", "ValueType", "any");

estimatedMaxLabels = max(1000, numNodes * 8);
labelNode = zeros(estimatedMaxLabels, 1);
labelCost = inf(estimatedMaxLabels, 1);
labelArrivalSoc = zeros(estimatedMaxLabels, 1);
labelPrev = zeros(estimatedMaxLabels, 1);
labelDepartureSoc = nan(estimatedMaxLabels, 1);
labelChargeTimeMinutes = zeros(estimatedMaxLabels, 1);
labelChargeAddedKWh = zeros(estimatedMaxLabels, 1);
labelStopCount = zeros(estimatedMaxLabels, 1);
labelProcessed = true(estimatedMaxLabels, 1);

numLabels = 1;
labelNode(1) = 1;
labelCost(1) = 0;
labelArrivalSoc(1) = initialSocPercent / 100;
labelProcessed(1) = false;
labelsByNode = cell(numNodes, 1);
labelsByNode{1} = 1;

bestDestinationLabel = 0;
while true
    activeRange = 1:numLabels;
    openLabels = activeRange(~labelProcessed(activeRange));
    if isempty(openLabels)
        break
    end

    [~, localIdx] = min(labelCost(openLabels));
    currentLabel = openLabels(localIdx);
    labelProcessed(currentLabel) = true;
    currentNode = labelNode(currentLabel);

    if currentNode == destinationNode
        bestDestinationLabel = currentLabel;
        break
    end

    currentSoc = labelArrivalSoc(currentLabel);
    maxDepartureSoc = currentSoc;
    currentStationPowerKW = Inf;
    if currentNode > 1
        maxDepartureSoc = maximumChargeSoc;
        currentStationPowerKW = stationPowerByNodeKW(currentNode - 1);
    end

    for nextNode = currentNode + 1:numNodes
        requiredArrivalSoc = marginSoc;
        if nextNode == destinationNode
            requiredArrivalSoc = destinationSoc;
        end

        energyKWh = nodeEnergyKWh(nextNode) - nodeEnergyKWh(currentNode);
        requiredDepartureSoc = requiredArrivalSoc ...
            + energyKWh / batteryCapacityKWh;
        if requiredDepartureSoc > maxDepartureSoc + 1e-9
            continue
        end

        departureSoc = max(currentSoc, requiredDepartureSoc);
        if departureSoc > maxDepartureSoc + 1e-9
            continue
        end

        chargeTimeMinutes = 0;
        chargeAddedKWh = 0;
        if currentNode > 1
            [chargeTimeMinutes, chargeAddedKWh] = ...
                chargeTimeCached(currentSoc * 100, ...
                departureSoc * 100, currentStationPowerKW);
            if chargeAddedKWh > 1e-6
                chargeTimeMinutes = chargeTimeMinutes ...
                    + vehicle.ChargeStopOverheadMinutes;
            end
        end
        nextStopCount = labelStopCount(currentLabel) ...
            + double(chargeAddedKWh > 1e-6);
        if nextStopCount > maxStops
            continue
        end

        nextArrivalSoc = departureSoc - energyKWh / batteryCapacityKWh;
        newCost = labelCost(currentLabel) + chargeTimeMinutes;
        [labelNode, labelCost, labelArrivalSoc, labelPrev, ...
            labelDepartureSoc, labelChargeTimeMinutes, ...
            labelChargeAddedKWh, labelStopCount, labelProcessed, ...
            numLabels, labelsByNode] = ...
            addLabelIfUseful( ...
            labelNode, labelCost, labelArrivalSoc, labelPrev, ...
            labelDepartureSoc, labelChargeTimeMinutes, ...
            labelChargeAddedKWh, labelStopCount, labelProcessed, ...
            numLabels, labelsByNode, ...
            nextNode, newCost, nextArrivalSoc, currentLabel, ...
            departureSoc, chargeTimeMinutes, chargeAddedKWh, ...
            nextStopCount);
    end
end

if bestDestinationLabel == 0
    plan.Status = "Infeasible";
    plan.StatusMessage = ...
        "No charger combination satisfies the requested SoC and stop constraints.";
    plan.Stops = makeEmptyStopsTable();
    energyToDestinationKWh = energyBetween(routeEnergy, 0, totalDistanceKm);
    plan.FinalSoCPercent = (initialSocPercent / 100 ...
        - energyToDestinationKWh / batteryCapacityKWh) * 100;
    plan.MinimumSoCPercent = plan.FinalSoCPercent;
    plan.TotalChargeTimeMinutes = 0;
    plan.SoCProfile = buildSocProfile(routeEnergy, plan.Stops, ...
        initialSocPercent, plan.FinalSoCPercent, vehicle);
    return
end

plan.Status = "Feasible";
plan.StatusMessage = "Charging plan found.";
plan.Stops = reconstructStops(bestDestinationLabel, labelNode, ...
    labelArrivalSoc, labelPrev, labelDepartureSoc, ...
    labelChargeTimeMinutes, labelChargeAddedKWh, stations);
plan.FinalSoCPercent = labelArrivalSoc(bestDestinationLabel) * 100;
plan.MinimumSoCPercent = minimumSoc(routeEnergy, plan.Stops, ...
    initialSocPercent, plan.FinalSoCPercent, vehicle);
plan.TotalChargeTimeMinutes = sum(plan.Stops.ChargeTimeMinutes);
plan.SoCProfile = buildSocProfile(routeEnergy, plan.Stops, ...
    initialSocPercent, plan.FinalSoCPercent, vehicle);

    function [chargeTimeMinutes, chargeAddedKWh] = chargeTimeCached( ...
            arrivalSocPercent, departureSocPercent, stationPower)
        roundedArrival = round(arrivalSocPercent * 2) / 2;
        roundedDeparture = round(departureSocPercent * 2) / 2;
        roundedPower = round(stationPower);
        if roundedDeparture <= roundedArrival
            chargeTimeMinutes = 0;
            chargeAddedKWh = 0;
            return
        end

        key = sprintf("%.0f", roundedPower);
        if isKey(chargeCurveCache, key)
            cumulativeChargeTimeMinutes = chargeCurveCache(key);
        else
            cumulativeChargeTimeMinutes = cumulativeChargeCurve( ...
                roundedPower, vehicle);
            chargeCurveCache(key) = cumulativeChargeTimeMinutes;
        end

        arrivalIndex = round(roundedArrival * 2) + 1;
        departureIndex = round(roundedDeparture * 2) + 1;
        chargeTimeMinutes = cumulativeChargeTimeMinutes(departureIndex) ...
            - cumulativeChargeTimeMinutes(arrivalIndex);
        chargeAddedKWh = (roundedDeparture - roundedArrival) ...
            / 100 * batteryCapacityKWh;
    end
end

function [labelNode, labelCost, labelArrivalSoc, labelPrev, ...
    labelDepartureSoc, labelChargeTimeMinutes, labelChargeAddedKWh, ...
    labelStopCount, labelProcessed, numLabels, labelsByNode] = ...
    addLabelIfUseful( ...
    labelNode, labelCost, ...
    labelArrivalSoc, labelPrev, labelDepartureSoc, ...
    labelChargeTimeMinutes, labelChargeAddedKWh, labelStopCount, ...
    labelProcessed, ...
    numLabels, labelsByNode, ...
    node, cost, arrivalSoc, prevLabel, departureSoc, chargeTimeMinutes, ...
    chargeAddedKWh, stopCount)
sameNode = labelsByNode{node};
dominatesNew = labelCost(sameNode) <= cost + 1e-6 ...
    & labelArrivalSoc(sameNode) >= arrivalSoc - 1e-6 ...
    & labelStopCount(sameNode) <= stopCount;
if any(dominatesNew)
    return
end

dominatedExisting = sameNode(labelCost(sameNode) >= cost - 1e-6 ...
    & labelArrivalSoc(sameNode) <= arrivalSoc + 1e-6 ...
    & labelStopCount(sameNode) >= stopCount);
labelProcessed(dominatedExisting) = true;

numLabels = numLabels + 1;
if numLabels > numel(labelNode)
    growBy = numel(labelNode);
    labelNode = [labelNode; zeros(growBy, 1)];
    labelCost = [labelCost; inf(growBy, 1)];
    labelArrivalSoc = [labelArrivalSoc; zeros(growBy, 1)];
    labelPrev = [labelPrev; zeros(growBy, 1)];
    labelDepartureSoc = [labelDepartureSoc; nan(growBy, 1)];
    labelChargeTimeMinutes = [labelChargeTimeMinutes; zeros(growBy, 1)];
    labelChargeAddedKWh = [labelChargeAddedKWh; zeros(growBy, 1)];
    labelStopCount = [labelStopCount; zeros(growBy, 1)];
    labelProcessed = [labelProcessed; true(growBy, 1)];
end

labelNode(numLabels) = node;
labelCost(numLabels) = cost;
labelArrivalSoc(numLabels) = arrivalSoc;
labelPrev(numLabels) = prevLabel;
labelDepartureSoc(numLabels) = departureSoc;
labelChargeTimeMinutes(numLabels) = chargeTimeMinutes;
labelChargeAddedKWh(numLabels) = chargeAddedKWh;
labelStopCount(numLabels) = stopCount;
labelProcessed(numLabels) = false;
labelsByNode{node}(end+1, 1) = numLabels;
end

function cumulativeChargeTimeMinutes = cumulativeChargeCurve(stationPowerKW, ...
    vehicle)
%CUMULATIVECHARGECURVE Precompute 0.5%-step charge time for one station.

socGrid = (0:0.5:100)';
midSoc = (socGrid(1:end-1) + socGrid(2:end)) ./ 2;
deltaEnergyKWh = diff(socGrid) ./ 100 .* vehicle.UsableBatteryCapacityKWh;

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
stepMinutes = deltaEnergyKWh ./ effectivePowerKW .* 60;
cumulativeChargeTimeMinutes = [0; cumsum(stepMinutes)];
end

function stops = reconstructStops(destinationLabel, labelNode, ...
    labelArrivalSoc, labelPrev, labelDepartureSoc, labelChargeTimeMinutes, ...
    labelChargeAddedKWh, stations)
stops = makeEmptyStopsTable();
edgeLabels = [];
label = destinationLabel;
while labelPrev(label) ~= 0
    edgeLabels(end+1, 1) = label; %#ok<AGROW>
    label = labelPrev(label);
end

edgeLabels = flipud(edgeLabels);
for k = 1:numel(edgeLabels)
    edgeLabel = edgeLabels(k);
    previousLabel = labelPrev(edgeLabel);
    previousNode = labelNode(previousLabel);
    if previousNode <= 1 || labelChargeAddedKWh(edgeLabel) <= 1e-6
        continue
    end

    station = stations(previousNode - 1, :);
    newStop = makeStopRow(station, ...
        labelArrivalSoc(previousLabel) * 100, ...
        labelDepartureSoc(edgeLabel) * 100, ...
        labelChargeAddedKWh(edgeLabel), ...
        labelChargeTimeMinutes(edgeLabel));
    stops = [stops; newStop]; %#ok<AGROW>
end
end

function stations = pruneFastestTripStations(stations)
%PRUNEFASTESTTRIPSTATIONS Keep strongest nearby chargers for graph search.

if height(stations) <= 250
    return
end

binWidthKm = 5;
maxStationsPerBin = 3;
stationBin = floor(stations.DistanceKm ./ binWidthKm);
uniqueBins = unique(stationBin, "stable");
keep = false(height(stations), 1);

for binIndex = 1:numel(uniqueBins)
    inBin = find(stationBin == uniqueBins(binIndex));
    [~, order] = sort(stations.PowerKW(inBin), "descend");
    keepCount = min(maxStationsPerBin, numel(order));
    keep(inBin(order(1:keepCount))) = true;
end

stations = sortrows(stations(keep, :), ["DistanceKm", "PowerKW"], ...
    ["ascend", "descend"]);
end

function stops = makeEmptyStopsTable()
stops = table(strings(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), ...
    VariableNames=["StationName", "DistanceKm", "PowerKW", ...
    "Operator", "ConnectorTypes", "UsageStatus", "Latitude", "Longitude", ...
    "ArrivalSoCPercent", "DepartureSoCPercent", "ChargeAddedKWh", ...
    "ChargeTimeMinutes"]);
end

function score = scoreReachableStations(stations, arrivalSoc, marginSoc, ...
    targetSoc, vehicle, objective)
chargeTimeMinutes = zeros(height(stations), 1);
for stationIndex = 1:height(stations)
    chargeTimeMinutes(stationIndex) = evcharge.estimateChargeTime( ...
        arrivalSoc(stationIndex) * 100, targetSoc * 100, ...
        stations.PowerKW(stationIndex), vehicle);
    if chargeTimeMinutes(stationIndex) > 0
        chargeTimeMinutes(stationIndex) = chargeTimeMinutes(stationIndex) ...
            + vehicle.ChargeStopOverheadMinutes;
    end
end
marginDistance = abs(arrivalSoc - marginSoc);

switch lower(objective)
    case "feweststops"
        primary = -stations.DistanceKm;
        secondary = -arrivalSoc;
        tertiary = -stations.PowerKW;
    case "lowestrisk"
        primary = -arrivalSoc;
        secondary = -stations.PowerKW;
        tertiary = stations.DistanceKm;
    otherwise
        primary = -stations.DistanceKm;
        secondary = chargeTimeMinutes;
        tertiary = -stations.PowerKW + marginDistance;
end

score = table(primary(:), secondary(:), tertiary(:), ...
    (1:height(stations))', ...
    VariableNames=["PrimaryScore", "SecondaryScore", ...
    "TertiaryScore", "OriginalIndex"]);
end

function stopRow = makeStopRow(station, arrivalSocPercent, ...
    departureSocPercent, chargeAddedKWh, chargeTimeMinutes)
stopRow = table( ...
    station.StationName, station.DistanceKm, station.PowerKW, ...
    station.Operator, station.ConnectorTypes, station.UsageStatus, ...
    station.Latitude, station.Longitude, arrivalSocPercent, ...
    departureSocPercent, chargeAddedKWh, chargeTimeMinutes, ...
    VariableNames=["StationName", "DistanceKm", "PowerKW", ...
    "Operator", "ConnectorTypes", "UsageStatus", "Latitude", "Longitude", ...
    "ArrivalSoCPercent", "DepartureSoCPercent", "ChargeAddedKWh", ...
    "ChargeTimeMinutes"]);
end

function energyKWh = energyBetween(routeEnergy, startKm, endKm)
distanceBreakpoints = [0; routeEnergy.EndKm];
energyBreakpoints = [0; routeEnergy.CumulativeEnergyKWh];

% Linear interpolation maps any distance along the route to cumulative
% energy, which makes station positions independent of segment boundaries.
startEnergyKWh = interp1(distanceBreakpoints, energyBreakpoints, ...
    startKm, "linear");
endEnergyKWh = interp1(distanceBreakpoints, energyBreakpoints, ...
    endKm, "linear");
energyKWh = endEnergyKWh - startEnergyKWh;
end

function cumulativeEnergyKWh = cumulativeEnergyAtDistance(routeEnergy, ...
    distanceKm)
distanceBreakpoints = [0; routeEnergy.EndKm];
energyBreakpoints = [0; routeEnergy.CumulativeEnergyKWh];
cumulativeEnergyKWh = interp1(distanceBreakpoints, energyBreakpoints, ...
    distanceKm, "linear");
end

function minSocPercent = minimumSoc(routeEnergy, stops, ...
    initialSocPercent, finalSocPercent, vehicle)
profile = buildSocProfile(routeEnergy, stops, initialSocPercent, ...
    finalSocPercent, vehicle);
minSocPercent = min(profile.SoCPercent);
end

function profile = buildSocProfile(routeEnergy, stops, ...
    initialSocPercent, finalSocPercent, vehicle)
distanceValues = [];
socValues = [];
eventValues = strings(0,1);
currentDistanceKm = 0;
currentSocPercent = initialSocPercent;

addPoint(0, initialSocPercent, "Start");

for k = 1:height(stops)
    stopDistanceKm = stops.DistanceKm(k);
    addRoutePointsUntil(stopDistanceKm, "Driving");
    addPoint(stopDistanceKm, stops.ArrivalSoCPercent(k), "Arrive charging stop");
    addPoint(stopDistanceKm, stops.DepartureSoCPercent(k), "Depart charging stop");
    currentDistanceKm = stopDistanceKm;
    currentSocPercent = stops.DepartureSoCPercent(k);
end

totalDistanceKm = routeEnergy.EndKm(end);
addRoutePointsUntil(totalDistanceKm, "Driving");
addPoint(totalDistanceKm, finalSocPercent, "Destination");

profile = table(distanceValues(:), socValues(:), eventValues(:), ...
    VariableNames=["DistanceKm", "SoCPercent", "Event"]);

    function addRoutePointsUntil(targetDistanceKm, eventName)
        routeDistances = routeEnergy.EndKm( ...
            routeEnergy.EndKm > currentDistanceKm ...
            & routeEnergy.EndKm < targetDistanceKm);
        routeDistances = [routeDistances; targetDistanceKm];
        for n = 1:numel(routeDistances)
            distanceKm = routeDistances(n);
            deltaEnergyKWh = energyBetween(routeEnergy, ...
                currentDistanceKm, distanceKm);
            socPercent = currentSocPercent ...
                - deltaEnergyKWh / vehicle.UsableBatteryCapacityKWh * 100;
            addPoint(distanceKm, socPercent, eventName);
        end
    end

    function addPoint(distanceKm, socPercent, eventName)
        distanceValues(end+1, 1) = distanceKm;
        socValues(end+1, 1) = socPercent;
        eventValues(end+1, 1) = eventName;
    end
end
