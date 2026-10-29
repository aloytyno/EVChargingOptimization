function stopData = plotRouteMap(ax, result, colors)
%PLOTROUTEMAP Draw the route and charging stops on geographic axes.
%
%   STOPDATA = EVCHARGE.UI.PLOTROUTEMAP(AX, RESULT, COLORS) plots the route
%   of an evcharge.runChargingOptimization result and returns the stop
%   name, position, and power table used for hover labels. COLORS needs
%   the fields accent and warn.

cla(ax)
hold(ax, "on")
routePoints = routePointsForMap(result);
if ~isempty(routePoints)
    geoplot(ax, routePoints.Latitude, routePoints.Longitude, ...
        LineWidth=3.0, Color=colors.accent)
    geoscatter(ax, routePoints.Latitude(1), routePoints.Longitude(1), ...
        72, "filled", MarkerFaceColor=[0.47 0.78 0.96], ...
        MarkerEdgeColor="none")
    geoscatter(ax, routePoints.Latitude(end), routePoints.Longitude(end), ...
        72, "filled", MarkerFaceColor=colors.warn, MarkerEdgeColor="none")
end

if ~isempty(result.Stops)
    geoscatter(ax, result.Stops.Latitude, result.Stops.Longitude, 92, ...
        "filled", MarkerFaceColor=[1.0 0.85 0.22], ...
        MarkerEdgeColor=[0.04 0.06 0.065], LineWidth=1.5)
    stopData = result.Stops(:, ["StationName", "Latitude", "Longitude", ...
        "PowerKW"]);
else
    stopData = table();
end

if ~isempty(routePoints)
    padGeoLimits(ax, routePoints)
end
end

function routePoints = routePointsForMap(result)
if isfield(result, "RoutePoints") && ~isempty(result.RoutePoints) ...
        && height(result.RoutePoints) > 0
    routePoints = result.RoutePoints;
elseif all(ismember(["Latitude", "Longitude"], ...
        result.RouteEnergy.Properties.VariableNames))
    routePoints = result.RouteEnergy(:, ["Latitude", "Longitude"]);
else
    routePoints = table();
end
end

function padGeoLimits(ax, routePoints)
latLimits = [min(routePoints.Latitude), max(routePoints.Latitude)];
lonLimits = [min(routePoints.Longitude), max(routePoints.Longitude)];
if diff(latLimits) == 0 || diff(lonLimits) == 0
    return
end
latPad = diff(latLimits) * 0.08;
lonPad = diff(lonLimits) * 0.08;
geolimits(ax, latLimits + [-latPad latPad], lonLimits + [-lonPad lonPad])
end
