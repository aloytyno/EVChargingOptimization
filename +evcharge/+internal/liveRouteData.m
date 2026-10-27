function routeData = liveRouteData(startAddress, destinationAddress, ...
    departureTime)
%LIVEROUTEDATA Fetch live route, weather, elevation, and charger data.
%
%   ROUTEDATA = LIVEROUTEDATA(START, DESTINATION, DEPARTURETIME) uses
%   Google Routes and Elevation APIs, FMI Open Data, and Open Charge Map to
%   build the same routeData shape used by the optimizer.

arguments
    startAddress (1,1) string
    destinationAddress (1,1) string
    departureTime (1,1) datetime
end

departureTime.TimeZone = "UTC";

googleApiKey = getSecret("Google.Maps.APIKey");
route = fetchGoogleRoute(startAddress, destinationAddress, googleApiKey);

numProfilePoints = 90;
routePoints = decodeGooglePolyline(route.encodedPolyline);
routeDistanceKm = cumulativeDistanceKm(routePoints);
sampleDistanceKm = linspace(0, routeDistanceKm(end), numProfilePoints)';
samplePoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    sampleDistanceKm);
elevationM = fetchGoogleElevations(samplePoints, googleApiKey);

elapsedSeconds = sampleDistanceKm ./ routeDistanceKm(end) ...
    .* seconds(route.duration);
sampleTimesUtc = departureTime + seconds(elapsedSeconds);
temperatureC = fetchRouteTemperatures(samplePoints, sampleTimesUtc);

routeSegments = buildRouteSegments(sampleDistanceKm, samplePoints, ...
    elevationM, temperatureC, route.duration);
[chargingStations, stationWarnings] = fetchOpenChargeMapStations( ...
    samplePoints, sampleDistanceKm);

routeData.Name = startAddress + " to " + destinationAddress;
routeData.StartAddress = startAddress;
routeData.DestinationAddress = destinationAddress;
routeData.RouteSegments = routeSegments;
routeData.ChargingStations = chargingStations;
routeData.RoutePoints = array2table(samplePoints, ...
    VariableNames=["Latitude", "Longitude"]);
routeData.RoutePointDistanceKm = sampleDistanceKm;
routeData.RoutePointElevationM = elevationM;
routeData.RoutePointTemperatureC = temperatureC;
routeData.GoogleDistanceMeters = route.distanceMeters;
routeData.GoogleDuration = route.duration;
routeData.Source = "google-fmi-openchargemap";
routeData.Warnings = stationWarnings;
end

function route = fetchGoogleRoute(originAddress, destinationAddress, apiKey)
url = "https://routes.googleapis.com/directions/v2:computeRoutes";
requestBody = struct();
requestBody.origin = struct(address=originAddress);
requestBody.destination = struct(address=destinationAddress);
requestBody.travelMode = "DRIVE";
requestBody.routingPreference = "TRAFFIC_UNAWARE";
requestBody.computeAlternativeRoutes = false;
requestBody.polylineQuality = "HIGH_QUALITY";
requestBody.polylineEncoding = "ENCODED_POLYLINE";
requestBody.units = "METRIC";
requestBody.languageCode = "en-US";

options = weboptions( ...
    MediaType="application/json", ...
    Timeout=60, ...
    HeaderFields=[
        "X-Goog-Api-Key", apiKey
        "X-Goog-FieldMask", ...
        "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"]);

response = webwrite(url, requestBody, options);

if ~isfield(response, "routes") || isempty(response.routes)
    error("evcharge:GoogleNoRoute", ...
        "Google Routes API did not return a route.");
end

googleRoute = response.routes(1);
route.encodedPolyline = string(googleRoute.polyline.encodedPolyline);
route.distanceMeters = googleRoute.distanceMeters;
route.duration = parseGoogleDuration(string(googleRoute.duration));
end

function durationValue = parseGoogleDuration(durationText)
durationSeconds = sscanf(durationText, "%fs");
durationValue = seconds(durationSeconds);
end

function elevationsM = fetchGoogleElevations(points, apiKey)
maxLocationsPerRequest = 512;
numPoints = size(points, 1);
elevationsM = zeros(numPoints, 1);

for firstIndex = 1:maxLocationsPerRequest:numPoints
    lastIndex = min(firstIndex + maxLocationsPerRequest - 1, numPoints);
    batchPoints = points(firstIndex:lastIndex, :);
    locationParts = compose("%.7f,%.7f", batchPoints(:,1), batchPoints(:,2));
    locations = strjoin(locationParts, "|");

    response = webread( ...
        "https://maps.googleapis.com/maps/api/elevation/json", ...
        "locations", locations, ...
        "key", apiKey, ...
        weboptions(Timeout=60));

    if ~strcmp(response.status, "OK")
        error("evcharge:GoogleElevationFailed", ...
            "Google Elevation API returned status '%s'.", response.status);
    end

    elevationsM(firstIndex:lastIndex) = [response.results.elevation]';
end
end

function temperatureC = fetchRouteTemperatures(points, sampleTimesUtc)
numPoints = size(points, 1);
weatherSampleIndices = unique(round(linspace(1, numPoints, ...
    min(25, numPoints))));
weatherTemperatureC = zeros(numel(weatherSampleIndices), 1);

for k = 1:numel(weatherSampleIndices)
    idx = weatherSampleIndices(k);
    forecast = fetchFmiTemperatureForecast(points(idx,1), points(idx,2), ...
        sampleTimesUtc(idx) - hours(1), sampleTimesUtc(idx) + hours(2));
    weatherTemperatureC(k) = interpolateTemperature(forecast.TimeUtc, ...
        forecast.TemperatureC, sampleTimesUtc(idx));
    pause(0.05)
end

temperatureC = interp1(weatherSampleIndices(:), weatherTemperatureC, ...
    (1:numPoints)', "linear", "extrap");
end

function forecast = fetchFmiTemperatureForecast(latitude, longitude, ...
    startTimeUtc, endTimeUtc)
responseText = webread("https://opendata.fmi.fi/wfs", ...
    "service", "WFS", ...
    "version", "2.0.0", ...
    "request", "getFeature", ...
    "storedquery_id", ...
    "fmi::forecast::harmonie::surface::point::timevaluepair", ...
    "latlon", sprintf("%.6f,%.6f", latitude, longitude), ...
    "parameters", "temperature", ...
    "starttime", fmiTimeText(startTimeUtc), ...
    "endtime", fmiTimeText(endTimeUtc), ...
    weboptions(Timeout=30));

timeTokens = regexp(responseText, ...
    "<wml2:time>(.*?)</wml2:time>", "tokens");
valueTokens = regexp(responseText, ...
    "<wml2:value>(.*?)</wml2:value>", "tokens");

if isempty(timeTokens) || isempty(valueTokens)
    error("evcharge:FmiNoTemperatureData", ...
        "FMI returned no temperature data for %.4f, %.4f.", ...
        latitude, longitude);
end

numValues = min(numel(timeTokens), numel(valueTokens));
timeText = strings(numValues, 1);
temperatureC = zeros(numValues, 1);

for valueIndex = 1:numValues
    timeText(valueIndex) = string(timeTokens{valueIndex}{1});
    temperatureC(valueIndex) = str2double(valueTokens{valueIndex}{1});
end

forecast = table( ...
    datetime(timeText, InputFormat="yyyy-MM-dd'T'HH:mm:ss'Z'", ...
    TimeZone="UTC"), ...
    temperatureC, ...
    VariableNames=["TimeUtc", "TemperatureC"]);
end

function timeText = fmiTimeText(timeValue)
timeValue.TimeZone = "UTC";
timeText = char(string(timeValue, "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function temperatureC = interpolateTemperature(forecastTimeUtc, ...
    forecastTemperatureC, queryTimeUtc)
queryHours = hours(queryTimeUtc - forecastTimeUtc(1));
forecastHours = hours(forecastTimeUtc - forecastTimeUtc(1));
temperatureC = interp1(forecastHours, forecastTemperatureC, ...
    queryHours, "linear", "extrap");
end

function [chargingStations, warnings] = fetchOpenChargeMapStations(routePoints, ...
    routeDistanceKm)
warnings = strings(0,1);

if ~(exist("isSecret", "file") == 2 && isSecret("OpenChargeMap"))
    chargingStations = fallbackChargingStations(routePoints, routeDistanceKm);
    warnings = "Open Charge Map API key not found in MATLAB Vault. " ...
        + "Using cached charger samples near the route.";
    return
end

options = weboptions(Timeout=60, ...
    HeaderFields=["X-API-Key", getSecret("OpenChargeMap")]);

try
    response = queryOpenChargeMapCorridor(routePoints, routeDistanceKm, ...
        options);
catch ME
    chargingStations = fallbackChargingStations(routePoints, routeDistanceKm);
    warnings = "Open Charge Map request failed: " + string(ME.message) ...
        + " Using cached charger samples near the route.";
    return
end

stationRows = makeEmptyStationTable();
if isempty(response)
    chargingStations = stationRows;
    return
end

for responseIndex = 1:numel(response)
    if iscell(response)
        station = response{responseIndex};
    else
        station = response(responseIndex);
    end
    if ~isfield(station, "AddressInfo") || isempty(station.AddressInfo)
        continue
    end

    lat = getFieldOr(station.AddressInfo, "Latitude", NaN);
    lon = getFieldOr(station.AddressInfo, "Longitude", NaN);
    if isnan(lat) || isnan(lon)
        continue
    end

    [distanceAlongKm, corridorDistanceKm] = nearestRouteDistance( ...
        [lat lon], routePoints, routeDistanceKm);
    if corridorDistanceKm > 18
        continue
    end

    [powerKW, connectors] = connectionSummary(station);
    if powerKW <= 0
        powerKW = 50;
    end

    newRow = table( ...
        string(getFieldOr(station.AddressInfo, "Title", "Unnamed charger")), ...
        distanceAlongKm, lat, lon, powerKW, ...
        string(nestedTitle(station, "OperatorInfo")), ...
        connectors, string(nestedTitle(station, "UsageType")), ...
        VariableNames=stationRows.Properties.VariableNames);
    stationRows = [stationRows; newRow]; %#ok<AGROW>
end

chargingStations = deduplicateStations(stationRows);
end

function response = queryOpenChargeMapCorridor(routePoints, routeDistanceKm, ...
    options)
%QUERYOPENCHARGEMAPCORRIDOR Query chargers along a long route in chunks.

routeLengthKm = routeDistanceKm(end);
querySpacingKm = 120;
queryRadiusKm = 85;
queryDistancesKm = unique([0; (querySpacingKm:querySpacingKm:routeLengthKm)'; ...
    routeLengthKm]);
queryPoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    queryDistancesKm);

response = {};
for queryIndex = 1:size(queryPoints, 1)
    requestArgs = { ...
        "output", "json", ...
        "countrycode", "FI", ...
        "latitude", queryPoints(queryIndex, 1), ...
        "longitude", queryPoints(queryIndex, 2), ...
        "distance", queryRadiusKm, ...
        "distanceunit", "KM", ...
        "maxresults", 500, ...
        "compact", true, ...
        "verbose", false};

    queryResponse = webread("https://api.openchargemap.io/v3/poi/", ...
        requestArgs{:}, options);
    response = appendOcmResponse(response, queryResponse);
    pause(0.05)
end
end

function response = appendOcmResponse(response, queryResponse)
if isempty(queryResponse)
    return
end

if iscell(queryResponse)
    response = [response; queryResponse(:)];
else
    response = [response; num2cell(queryResponse(:))];
end
end

function chargingStations = deduplicateStations(stationRows)
if isempty(stationRows)
    chargingStations = stationRows;
    return
end

stationRows = sortrows(stationRows, ["DistanceKm", "StationName", ...
    "PowerKW"], ["ascend", "ascend", "descend"]);
roundedLatitude = round(stationRows.Latitude, 4);
roundedLongitude = round(stationRows.Longitude, 4);
key = stationRows.StationName + "|" + string(roundedLatitude) ...
    + "|" + string(roundedLongitude);
[~, firstIdx] = unique(key, "stable");
chargingStations = sortrows(stationRows(firstIdx, :), "DistanceKm");
end

function chargingStations = fallbackChargingStations(routePoints, routeDistanceKm)
%FALLBACKCHARGINGSTATIONS Project cached Finland demo chargers to live route.

scenarioNames = ["helsinki-to-oulu", "helsinki-to-tampere"];
cachedStations = makeEmptyStationTable();
for scenarioName = scenarioNames
    scenario = evcharge.getScenario(scenarioName);
    cachedStations = [cachedStations; scenario.ChargingStations]; %#ok<AGROW>
end

cachedStations = unique(cachedStations);
chargingStations = makeEmptyStationTable();
for stationIndex = 1:height(cachedStations)
    [distanceAlongKm, corridorDistanceKm] = nearestRouteDistance( ...
        [cachedStations.Latitude(stationIndex), ...
        cachedStations.Longitude(stationIndex)], ...
        routePoints, routeDistanceKm);
    if corridorDistanceKm > 35
        continue
    end

    row = cachedStations(stationIndex, :);
    row.DistanceKm = distanceAlongKm;
    chargingStations = [chargingStations; row]; %#ok<AGROW>
end

chargingStations = sortrows(chargingStations, "DistanceKm");
end

function stations = makeEmptyStationTable()
stations = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    VariableNames=["StationName", "DistanceKm", "Latitude", "Longitude", ...
    "PowerKW", "Operator", "ConnectorTypes", "UsageStatus"]);
end

function [powerKW, connectors] = connectionSummary(station)
powerKW = 0;
connectorList = strings(0,1);
if ~isfield(station, "Connections") || isempty(station.Connections)
    connectors = "";
    return
end

for c = 1:numel(station.Connections)
    connection = station.Connections(c);
    if isfield(connection, "PowerKW") && ~isempty(connection.PowerKW)
        powerKW = max(powerKW, double(connection.PowerKW));
    end
    if isfield(connection, "ConnectionType") ...
            && isfield(connection.ConnectionType, "Title")
        connectorList(end+1, 1) = string(connection.ConnectionType.Title); %#ok<AGROW>
    end
end

connectorList = unique(connectorList(connectorList ~= ""));
connectors = strjoin(connectorList, ", ");
end

function title = nestedTitle(item, fieldName)
title = "";
if isfield(item, fieldName) && ~isempty(item.(fieldName)) ...
        && isfield(item.(fieldName), "Title")
    title = string(item.(fieldName).Title);
end
end

function value = getFieldOr(item, fieldName, defaultValue)
if isfield(item, fieldName) && ~isempty(item.(fieldName))
    value = item.(fieldName);
else
    value = defaultValue;
end
end

function [distanceAlongKm, corridorDistanceKm] = nearestRouteDistance( ...
    point, routePoints, routeDistanceKm)
distancesKm = haversineKm(routePoints, repmat(point, size(routePoints,1), 1));
[corridorDistanceKm, idx] = min(distancesKm);
distanceAlongKm = routeDistanceKm(idx);
end

function routeSegments = buildRouteSegments(sampleDistanceKm, samplePoints, ...
    elevationM, temperatureC, routeDuration)
numSegments = numel(sampleDistanceKm) - 1;
segmentName = "Route segment " + (1:numSegments)';
startKm = sampleDistanceKm(1:end-1);
endKm = sampleDistanceKm(2:end);
distanceKm = endKm - startKm;
durationSeconds = distanceKm ./ sampleDistanceKm(end) .* seconds(routeDuration);
speedKmh = distanceKm ./ max(durationSeconds, 1) .* 3600;
elevationDeltaM = diff(elevationM);
segmentTemperatureC = (temperatureC(1:end-1) + temperatureC(2:end)) ./ 2;
midLatitude = (samplePoints(1:end-1,1) + samplePoints(2:end,1)) ./ 2;
midLongitude = (samplePoints(1:end-1,2) + samplePoints(2:end,2)) ./ 2;

routeSegments = table(segmentName, startKm, endKm, distanceKm, ...
    speedKmh, speedKmh, durationSeconds, elevationDeltaM, ...
    segmentTemperatureC, midLatitude, midLongitude, ...
    VariableNames=["SegmentName", "StartKm", "EndKm", "DistanceKm", ...
    "SpeedLimitKmh", "SpeedKmh", "DurationSeconds", "ElevationDeltaM", ...
    "TemperatureC", "Latitude", "Longitude"]);
end

function points = decodeGooglePolyline(encodedPolyline)
encodedPolyline = char(encodedPolyline);
index = 1;
latitude = 0;
longitude = 0;
points = zeros(0, 2);

while index <= numel(encodedPolyline)
    [deltaLatitude, index] = decodePolylineValue(encodedPolyline, index);
    [deltaLongitude, index] = decodePolylineValue(encodedPolyline, index);
    latitude = latitude + deltaLatitude;
    longitude = longitude + deltaLongitude;
    points(end+1, :) = [latitude, longitude] ./ 1e5; %#ok<AGROW>
end
end

function [value, index] = decodePolylineValue(encodedPolyline, index)
result = 0;
shift = 0;
while true
    chunk = double(encodedPolyline(index)) - 63;
    index = index + 1;
    result = result + bitshift(bitand(chunk, 31), shift);
    shift = shift + 5;
    if chunk < 32
        break
    end
end

if bitand(result, 1)
    value = -floor(result / 2) - 1;
else
    value = floor(result / 2);
end
end

function distanceKm = cumulativeDistanceKm(points)
segmentDistanceKm = haversineKm(points(1:end-1,:), points(2:end,:));
distanceKm = [0; cumsum(segmentDistanceKm)];
end

function sampledPoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    sampleDistanceKm)
sampledLatitude = interp1(routeDistanceKm, routePoints(:,1), ...
    sampleDistanceKm, "linear");
sampledLongitude = interp1(routeDistanceKm, routePoints(:,2), ...
    sampleDistanceKm, "linear");
sampledPoints = [sampledLatitude, sampledLongitude];
end

function distanceKm = haversineKm(pointA, pointB)
earthRadiusKm = 6371.0088;
lat1 = deg2rad(pointA(:,1));
lat2 = deg2rad(pointB(:,1));
deltaLat = deg2rad(pointB(:,1) - pointA(:,1));
deltaLon = deg2rad(pointB(:,2) - pointA(:,2));
a = sin(deltaLat ./ 2).^2 ...
    + cos(lat1) .* cos(lat2) .* sin(deltaLon ./ 2).^2;
c = 2 .* atan2(sqrt(a), sqrt(1 - a));
distanceKm = earthRadiusKm .* c;
end
