%% Drive-Time Weighted Route Temperature from FMI Forecasts
% This standalone script fetches a Google driving route from Helsinki to
% Tampere, samples positions along the drive, queries the Finnish
% Meteorological Institute (FMI) Open Data API for forecast temperature at
% each sampled position, and calculates the drive-time weighted average
% temperature along the route.
%
% Google Maps API key:
%   The key is read from MATLAB Vault with getSecret("Google.Maps.APIKey").
%
% FMI API:
%   FMI Open Data does not need an API key. This script uses WFS stored
%   query fmi::forecast::harmonie::surface::point::timevaluepair with:
%   - latlon = "latitude,longitude"
%   - parameters = "temperature"

clearvars
close all
clc

%% User settings
originAddress = "Helsinki, Finland";
destinationAddress = "Tampere, Finland";
numWeatherSamples = 25;
pauseBetweenFmiRequestsSeconds = 0.1;

%% Fetch the route from Google
googleApiKey = getSecret("Google.Maps.APIKey");
route = fetchGoogleRoute(originAddress, destinationAddress, googleApiKey);
routePoints = decodeGooglePolyline(route.encodedPolyline);
routeDistanceKm = cumulativeDistanceKm(routePoints);

%% Build route samples with estimated drive times
departureTimeUtc = dateshift(datetime("now", TimeZone="UTC"), ...
    "start", "hour", "next");
elapsedSeconds = linspace(0, seconds(route.duration), numWeatherSamples)';
sampleTimesUtc = departureTimeUtc + seconds(elapsedSeconds);

% The route polyline does not include per-segment speed. For this focused
% script, distance is used as a proxy for elapsed time along the route.
sampleDistanceKm = routeDistanceKm(end) .* elapsedSeconds ...
    ./ seconds(route.duration);
samplePoints = sampleRouteByDistance(routePoints, routeDistanceKm, ...
    sampleDistanceKm);

%% Query FMI forecast temperature at each route sample
temperatureC = zeros(numWeatherSamples, 1);
for sampleIndex = 1:numWeatherSamples
    forecast = fetchFmiTemperatureForecast( ...
        samplePoints(sampleIndex, 1), samplePoints(sampleIndex, 2), ...
        sampleTimesUtc(sampleIndex) - hours(1), ...
        sampleTimesUtc(sampleIndex) + hours(2));

    temperatureC(sampleIndex) = interpolateTemperature( ...
        forecast.TimeUtc, forecast.TemperatureC, sampleTimesUtc(sampleIndex));

    fprintf("%2d/%2d  %s  %.2f, %.2f  %.1f C\n", ...
        sampleIndex, numWeatherSamples, ...
        string(sampleTimesUtc(sampleIndex), "yyyy-MM-dd HH:mm 'UTC'"), ...
        samplePoints(sampleIndex, 1), samplePoints(sampleIndex, 2), ...
        temperatureC(sampleIndex));

    pause(pauseBetweenFmiRequestsSeconds)
end

%% Calculate time-weighted average temperature
elapsedHours = elapsedSeconds ./ 3600;
averageTemperatureC = trapz(elapsedHours, temperatureC) ...
    ./ elapsedHours(end);

routeTemperatureProfile = table(sampleTimesUtc, elapsedSeconds./60, ...
    sampleDistanceKm, samplePoints(:,1), samplePoints(:,2), temperatureC, ...
    VariableNames=["TimeUtc", "ElapsedMinutes", "DistanceKm", ...
    "Latitude", "Longitude", "TemperatureC"]);

fprintf("\nRoute: %s to %s\n", originAddress, destinationAddress);
fprintf("Departure time: %s\n", ...
    string(departureTimeUtc, "yyyy-MM-dd HH:mm 'UTC'"));
fprintf("Google route distance: %.1f km\n", route.distanceMeters/1000);
fprintf("Google route duration: %.0f minutes\n", seconds(route.duration)/60);
fprintf("Drive-time weighted average temperature: %.1f C\n", ...
    averageTemperatureC);

%% Plot the sampled temperatures along the route
figure("Name", "Route average temperature from FMI forecasts");
tiledlayout(2, 1, "TileSpacing", "compact");

nexttile
plot(routeTemperatureProfile.ElapsedMinutes, temperatureC, ...
    "LineWidth", 1.8, "Color", [0.1 0.42 0.65])
grid on
xlabel("Elapsed drive time (min)")
ylabel("Temperature (C)")
title("FMI Forecast Temperature Along Helsinki to Tampere Route")
subtitle(sprintf("Time-weighted average: %.1f C", averageTemperatureC))

nexttile
geoplot(routePoints(:,1), routePoints(:,2), ...
    "LineWidth", 1.4, "Color", [0.1 0.42 0.65])
hold on
geoscatter(samplePoints(:,1), samplePoints(:,2), 36, temperatureC, "filled")
geobasemap streets
colorbar
title("Sampled route positions colored by forecast temperature")

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

function forecast = fetchFmiTemperatureForecast(latitude, longitude, ...
    startTimeUtc, endTimeUtc)
%FETCHFMITEMPERATUREFORECAST Fetch FMI HARMONIE temperature forecast.

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
    error("FMI:NoTemperatureData", ...
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
%FMITIMETEXT Format datetime for FMI WFS query parameters.

timeValue.TimeZone = "UTC";
timeText = char(string(timeValue, "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function temperatureC = interpolateTemperature(forecastTimeUtc, ...
    forecastTemperatureC, queryTimeUtc)
%INTERPOLATETEMPERATURE Interpolate an hourly FMI forecast to drive time.

queryHours = hours(queryTimeUtc - forecastTimeUtc(1));
forecastHours = hours(forecastTimeUtc - forecastTimeUtc(1));
temperatureC = interp1(forecastHours, forecastTemperatureC, ...
    queryHours, "linear", "extrap");
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

function distanceKm = haversineKm(pointA, pointB)
%HAVERSINEKM Great-circle distance for arrays of [lat lon] coordinates.

earthRadiusKm = 6371.0088;
lat1 = deg2rad(pointA(:,1));
lat2 = deg2rad(pointB(:,1));
deltaLat = deg2rad(pointB(:,1) - pointA(:,1));
deltaLon = deg2rad(pointB(:,2) - pointA(:,2));

% Vectorized haversine computation gives accurate enough route-distance
% spacing for sampling the polyline before querying the weather forecast.
a = sin(deltaLat ./ 2).^2 ...
    + cos(lat1) .* cos(lat2) .* sin(deltaLon ./ 2).^2;
c = 2 .* atan2(sqrt(a), sqrt(1 - a));
distanceKm = earthRadiusKm .* c;
end
