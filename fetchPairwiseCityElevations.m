%% Fetch Pairwise Finnish City Route Elevation Profiles
% This script fetches driving routes for all directed pairwise combinations
% of Helsinki, Turku, Tampere, Lahti, and Pori using Google Maps Routes API.
% It then samples each route, calls Google Elevation API, and saves route
% names plus elevation profiles to a MAT-file.
%
% The Google Maps API key is read from MATLAB Vault. Store it once with:
%   setSecret("Google.Maps.APIKey")

clearvars
clc

%% User settings
cities = ["Helsinki", "Turku", "Tampere", "Lahti", "Pori"];
countryName = "Finland";
numElevationSamples = 160;
includeReverseRoutes = true;
pauseBetweenRoutesSeconds = 0.2;
outputFile = "pairwiseFinnishCityElevations.mat";

%% Fetch route and elevation data
apiKey = getSecret("Google.Maps.APIKey");
routePairs = makeRoutePairs(cities, includeReverseRoutes);
numRoutes = size(routePairs, 1);

routeElevationData = repmat(emptyRouteResult(), numRoutes, 1);

for routeIndex = 1:numRoutes
    originCity = routePairs(routeIndex, 1);
    destinationCity = routePairs(routeIndex, 2);
    originAddress = originCity + ", " + countryName;
    destinationAddress = destinationCity + ", " + countryName;
    routeName = originCity + " to " + destinationCity;

    fprintf("Fetching %s (%d of %d)...\n", ...
        routeName, routeIndex, numRoutes);

    route = fetchGoogleRoute(originAddress, destinationAddress, apiKey);
    routePoints = decodeGooglePolyline(route.encodedPolyline);
    routeDistanceKm = cumulativeDistanceKm(routePoints);

    sampleDistanceKm = linspace(0, routeDistanceKm(end), ...
        numElevationSamples)';
    samplePoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
        sampleDistanceKm);
    elevationM = fetchGoogleElevations(samplePoints, apiKey);

    elevationProfile = table(sampleDistanceKm, samplePoints(:,1), ...
        samplePoints(:,2), elevationM, ...
        VariableNames=["DistanceKm", "Latitude", "Longitude", ...
        "ElevationM"]);

    routeElevationData(routeIndex).RouteName = routeName;
    routeElevationData(routeIndex).OriginCity = originCity;
    routeElevationData(routeIndex).DestinationCity = destinationCity;
    routeElevationData(routeIndex).OriginAddress = originAddress;
    routeElevationData(routeIndex).DestinationAddress = destinationAddress;
    routeElevationData(routeIndex).RouteDistanceKm = route.distanceMeters / 1000;
    routeElevationData(routeIndex).RouteDurationMinutes = ...
        seconds(route.duration) / 60;
    routeElevationData(routeIndex).ElevationProfile = elevationProfile;
    routeElevationData(routeIndex).RouteVertices = array2table(routePoints, ...
        VariableNames=["Latitude", "Longitude"]);

    pause(pauseBetweenRoutesSeconds)
end

routeSummary = buildRouteSummary(routeElevationData);
generatedAt = datetime("now", TimeZone="local");
settings = struct( ...
    Cities=cities, ...
    CountryName=countryName, ...
    NumElevationSamples=numElevationSamples, ...
    IncludeReverseRoutes=includeReverseRoutes);

save(outputFile, "routeElevationData", "routeSummary", ...
    "generatedAt", "settings")

fprintf("Saved %d route elevation profiles to %s.\n", numRoutes, outputFile);

%% Local functions
function routePairs = makeRoutePairs(cities, includeReverseRoutes)
%MAKEROUTEPAIRS Create unique or directed city pairs.

if includeReverseRoutes
    [originGrid, destinationGrid] = ndgrid(cities, cities);
    keepPair = originGrid ~= destinationGrid;
    routePairs = [originGrid(keepPair), destinationGrid(keepPair)];
else
    pairIndices = nchoosek(1:numel(cities), 2);
    routePairs = [cities(pairIndices(:,1))', cities(pairIndices(:,2))'];
end
end

function result = emptyRouteResult()
%EMPTYROUTERESULT Return the scalar struct template saved for each route.

result = struct( ...
    RouteName="", ...
    OriginCity="", ...
    DestinationCity="", ...
    OriginAddress="", ...
    DestinationAddress="", ...
    RouteDistanceKm=NaN, ...
    RouteDurationMinutes=NaN, ...
    ElevationProfile=table(), ...
    RouteVertices=table());
end

function routeSummary = buildRouteSummary(routeElevationData)
%BUILDROUTESUMMARY Create a compact table for quick inspection.

numRoutes = numel(routeElevationData);
routeName = strings(numRoutes, 1);
originCity = strings(numRoutes, 1);
destinationCity = strings(numRoutes, 1);
routeDistanceKm = zeros(numRoutes, 1);
routeDurationMinutes = zeros(numRoutes, 1);
minElevationM = zeros(numRoutes, 1);
maxElevationM = zeros(numRoutes, 1);

for routeIndex = 1:numRoutes
    profile = routeElevationData(routeIndex).ElevationProfile;
    routeName(routeIndex) = routeElevationData(routeIndex).RouteName;
    originCity(routeIndex) = routeElevationData(routeIndex).OriginCity;
    destinationCity(routeIndex) = routeElevationData(routeIndex).DestinationCity;
    routeDistanceKm(routeIndex) = ...
        routeElevationData(routeIndex).RouteDistanceKm;
    routeDurationMinutes(routeIndex) = ...
        routeElevationData(routeIndex).RouteDurationMinutes;
    minElevationM(routeIndex) = min(profile.ElevationM);
    maxElevationM(routeIndex) = max(profile.ElevationM);
end

routeSummary = table(routeName, originCity, destinationCity, ...
    routeDistanceKm, routeDurationMinutes, minElevationM, maxElevationM, ...
    VariableNames=["RouteName", "OriginCity", "DestinationCity", ...
    "RouteDistanceKm", "RouteDurationMinutes", "MinElevationM", ...
    "MaxElevationM"]);
end

function route = fetchGoogleRoute(originAddress, destinationAddress, apiKey)
%FETCHGOOGLEROUTE Request a driving route from Google Routes API.

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
    error("GoogleMaps:NoRoutes", ...
        "Google Routes API did not return a route from %s to %s.", ...
        originAddress, destinationAddress);
end

googleRoute = response.routes(1);
route.encodedPolyline = string(googleRoute.polyline.encodedPolyline);
route.distanceMeters = googleRoute.distanceMeters;
route.duration = parseGoogleDuration(string(googleRoute.duration));
end

function durationValue = parseGoogleDuration(durationText)
%PARSEGOOGLEDURATION Convert Google duration text, such as "6823s".

durationSeconds = sscanf(durationText, "%fs");
durationValue = seconds(durationSeconds);
end

function points = decodeGooglePolyline(encodedPolyline)
%DECODEGOOGLEPOLYLINE Decode Google's encoded polyline into [lat lon].

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
%DECODEPOLYLINEVALUE Decode one signed coordinate delta.

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

% Google's format stores signed values by interleaving positive and negative
% integers; odd results represent negative deltas.
if bitand(result, 1)
    value = -floor(result / 2) - 1;
else
    value = floor(result / 2);
end
end

function distanceKm = cumulativeDistanceKm(points)
%CUMULATIVEDISTANCEKM Compute cumulative great-circle distance along points.

segmentDistanceKm = haversineKm(points(1:end-1,:), points(2:end,:));
distanceKm = [0; cumsum(segmentDistanceKm)];
end

function sampledPoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    sampleDistanceKm)
%SAMPLEROUTEBYDISTANCE Interpolate latitude/longitude at target distances.

sampledLatitude = interp1(routeDistanceKm, routePoints(:,1), ...
    sampleDistanceKm, "linear");
sampledLongitude = interp1(routeDistanceKm, routePoints(:,2), ...
    sampleDistanceKm, "linear");
sampledPoints = [sampledLatitude, sampledLongitude];
end

function elevationM = fetchGoogleElevations(points, apiKey)
%FETCHGOOGLEELEVATIONS Request elevation values for [lat lon] points.

maxLocationsPerRequest = 512;
numPoints = size(points, 1);
elevationM = zeros(numPoints, 1);

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
        error("GoogleMaps:ElevationFailed", ...
            "Google Elevation API returned status '%s'.", response.status);
    end

    elevationM(firstIndex:lastIndex) = [response.results.elevation]';
end
end

function distanceKm = haversineKm(pointA, pointB)
%HAVERSINEKM Great-circle distance for arrays of [lat lon] coordinates.

earthRadiusKm = 6371.0088;
lat1 = deg2rad(pointA(:,1));
lat2 = deg2rad(pointB(:,1));
deltaLat = deg2rad(pointB(:,1) - pointA(:,1));
deltaLon = deg2rad(pointB(:,2) - pointA(:,2));

% Vectorized haversine computation gives accurate enough route-distance
% spacing for sampling the polyline before querying elevations.
a = sin(deltaLat ./ 2).^2 ...
    + cos(lat1) .* cos(lat2) .* sin(deltaLon ./ 2).^2;
c = 2 .* atan2(sqrt(a), sqrt(1 - a));
distanceKm = earthRadiusKm .* c;
end
