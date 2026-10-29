function plotSocProfile(ax, result, colors)
%PLOTSOCPROFILE Plot state of charge along the route with margin lines.
%
%   EVCHARGE.UI.PLOTSOCPROFILE(AX, RESULT, COLORS) draws the SoC profile of
%   an evcharge.runChargingOptimization result. COLORS needs the fields
%   accent and warn.

cla(ax)
plot(ax, result.SoCProfile.DistanceKm, result.SoCProfile.SoCPercent, ...
    LineWidth=2.2, Color=colors.accent)
yline(ax, result.MarginSoCPercent, "--", "Margin", Color=colors.warn)
if isfield(result, "DestinationSoCPercent") ...
        && result.DestinationSoCPercent > result.MarginSoCPercent
    yline(ax, result.DestinationSoCPercent, ":", ...
        "Destination target", Color=[0.47 0.78 0.96])
end
grid(ax, "on")
ylim(ax, [0 100])
end
