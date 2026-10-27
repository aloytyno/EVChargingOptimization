%% Helsinki to Tampere Route Elevation Profile
% This script calls Google Maps Routes API for a driving route from Helsinki
% to Tampere, samples the returned route polyline, calls the Google Elevation
% API for those points, and plots elevation against route distance.
%
% The Google Maps API key is read from MATLAB Vault. Store it once with:
%   setSecret("Google.Maps.APIKey")

clearvars
close all
clc

%% User settings
originAddress = "Helsinki, Finland";
destinationAddress = "Tampere, Finland";
numElevationSamples = 160;

%% Fetch route and elevation data
apiKey = getSecret("Google.Maps.APIKey");

route = fetchGoogleRoute(originAddress, destinationAddress, apiKey);
routePoints = decodeGooglePolyline(route.encodedPolyline);
routeDistanceKm = cumulativeDistanceKm(routePoints);

sampleDistanceKm = linspace(0, routeDistanceKm(end), numElevationSamples)';
samplePoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    sampleDistanceKm);
elevationM = fetchGoogleElevations(samplePoints, apiKey);

%% Plot the elevation profile and route
figure("Name", "Helsinki to Tampere elevation profile");
tiledlayout(2, 1, "TileSpacing", "compact");

nexttile
plot(sampleDistanceKm, elevationM, "LineWidth", 1.8, "Color", [0.1 0.42 0.65])
grid on
xlabel("Route distance (km)")
ylabel("Elevation (m)")
title("Driving Route Elevation Profile: Helsinki to Tampere")
subtitle(sprintf("Google route distance: %.1f km, duration: %.0f min", ...
    route.distanceMeters/1000, seconds(route.duration)/60))

nexttile
geoplot(routePoints(:,1), routePoints(:,2), ...
    "LineWidth", 1.6, "Color", [0.1 0.42 0.65])
hold on
geoscatter(samplePoints(:,1), samplePoints(:,2), 12, elevationM, "filled")
geobasemap streets
colorbar
title("Route and sampled elevation points")

%% Collect outputs for follow-on analysis
elevationProfile = table(sampleDistanceKm, samplePoints(:,1), ...
    samplePoints(:,2), elevationM, ...
    VariableNames=["DistanceKm", "Latitude", "Longitude", "ElevationM"]);

fprintf("Fetched %d route vertices and %d elevation samples.\n", ...
    size(routePoints, 1), height(elevationProfile));
fprintf("Route distance: %.1f km\n", route.distanceMeters/1000);
fprintf("Route duration: %.0f minutes\n", seconds(route.duration)/60);
fprintf("Elevation range: %.1f m to %.1f m\n", ...
    min(elevationM), max(elevationM));

%% Local functions
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
        "Google Routes API did not return a route.");
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
