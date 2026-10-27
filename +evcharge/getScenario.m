function scenario = getScenario(name)
%GETSCENARIO Return cached Finland route and station scenarios.
%
%   SCENARIO = GETSCENARIO(NAME) returns route segments and charging
%   stations for repeatable Finland demos.

arguments
    name (1,1) string = "helsinki-to-oulu"
end

normalizedName = lower(strrep(name, "_", "-"));

switch normalizedName
    case {"helsinki-to-oulu", "default", "long"}
        scenario = helsinkiToOulu();
    case {"helsinki-to-tampere", "short"}
        scenario = helsinkiToTampere();
    otherwise
        error("evcharge:UnknownScenario", ...
            "Unknown EV charging scenario '%s'.", name);
end
end

function scenario = helsinkiToOulu()
segmentName = [
    "Helsinki-Lahti";
    "Lahti-Heinola";
    "Heinola-Jyvaskyla";
    "Jyvaskyla-Aanekoski";
    "Aanekoski-Pyhajarvi";
    "Pyhajarvi-Pulkkila";
    "Pulkkila-Liminka";
    "Liminka-Kempele";
    "Kempele-Oulu"];
distanceKm = [58; 45; 75; 60; 70; 75; 80; 72; 75];
speedLimitKmh = [100; 100; 100; 80; 100; 100; 100; 100; 80];
elevationDeltaM = [15; 20; -10; 35; -15; 20; 10; -5; 5];
routeSegments = makeRouteSegments(segmentName, distanceKm, ...
    speedLimitKmh, elevationDeltaM);

stationName = [
    "Lahti HPC";
    "Heinola Express";
    "Jyvaskyla North";
    "Aanekoski Supercharge";
    "Pyhajarvi Rapid";
    "Pulkkila Hub";
    "Liminka HPC"];
distanceKm = [103; 154; 228; 302; 384; 470; 545];
latitude = [60.9827; 61.2056; 62.2426; 62.6000; 63.6689; 64.2664; 64.8099];
longitude = [25.6615; 26.0381; 25.7473; 25.7300; 25.9800; 25.8667; 25.4155];
powerKW = [180; 150; 250; 250; 150; 180; 250];
operator = [
    "Cached Finland Demo";
    "Cached Finland Demo";
    "Cached Finland Demo";
    "Cached Finland Demo";
    "Cached Finland Demo";
    "Cached Finland Demo";
    "Cached Finland Demo"];
connectorTypes = repmat("CCS (Type 2)", numel(powerKW), 1);
usageStatus = repmat("Operational", numel(powerKW), 1);
chargingStations = table(stationName, distanceKm, latitude, longitude, ...
    powerKW, operator, connectorTypes, usageStatus, ...
    VariableNames=["StationName", "DistanceKm", "Latitude", "Longitude", ...
    "PowerKW", "Operator", "ConnectorTypes", "UsageStatus"]);

scenario.Name = "Helsinki to Oulu";
scenario.StartAddress = "Helsinki, Finland";
scenario.DestinationAddress = "Oulu, Finland";
scenario.RouteSegments = routeSegments;
scenario.ChargingStations = chargingStations;
end

function scenario = helsinkiToTampere()
segmentName = [
    "Helsinki-Hameenlinna";
    "Hameenlinna-Valkeakoski";
    "Valkeakoski-Tampere"];
distanceKm = [98; 42; 39];
speedLimitKmh = [100; 100; 80];
elevationDeltaM = [25; 8; 5];
routeSegments = makeRouteSegments(segmentName, distanceKm, ...
    speedLimitKmh, elevationDeltaM);

stationName = [
    "Hameenlinna HPC";
    "Valkeakoski Rapid"];
distanceKm = [98; 140];
latitude = [61.0038; 61.2642];
longitude = [24.4590; 24.0312];
powerKW = [180; 120];
operator = ["Cached Finland Demo"; "Cached Finland Demo"];
connectorTypes = repmat("CCS (Type 2)", numel(powerKW), 1);
usageStatus = repmat("Operational", numel(powerKW), 1);
chargingStations = table(stationName, distanceKm, latitude, longitude, ...
    powerKW, operator, connectorTypes, usageStatus, ...
    VariableNames=["StationName", "DistanceKm", "Latitude", "Longitude", ...
    "PowerKW", "Operator", "ConnectorTypes", "UsageStatus"]);

scenario.Name = "Helsinki to Tampere";
scenario.StartAddress = "Helsinki, Finland";
scenario.DestinationAddress = "Tampere, Finland";
scenario.RouteSegments = routeSegments;
scenario.ChargingStations = chargingStations;
end

function routeSegments = makeRouteSegments(segmentName, distanceKm, ...
    speedLimitKmh, elevationDeltaM)
startKm = [0; cumsum(distanceKm(1:end-1))];
endKm = cumsum(distanceKm);
routeSegments = table(segmentName, startKm, endKm, distanceKm, ...
    speedLimitKmh, elevationDeltaM, ...
    VariableNames=["SegmentName", "StartKm", "EndKm", "DistanceKm", ...
    "SpeedLimitKmh", "ElevationDeltaM"]);
end
