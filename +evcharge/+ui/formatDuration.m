function text = formatDuration(minutes)
%FORMATDURATION Driver-friendly duration rounded to 5 minutes.
%
%   TEXT = EVCHARGE.UI.FORMATDURATION(MINUTES) returns e.g. "25 min" or
%   "2 h 05 min".

minutes = round(minutes / 5) * 5;
if minutes < 60
    text = string(sprintf("%d min", minutes));
else
    text = string(sprintf("%d h %02d min", floor(minutes / 60), ...
        mod(minutes, 60)));
end
end
