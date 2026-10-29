function text = nextActionText(plan)
%NEXTACTIONTEXT One-glance instruction for the driver's next step.
%
%   TEXT = EVCHARGE.UI.NEXTACTIONTEXT(PLAN) turns an
%   evcharge.runChargingOptimization result into the big "Next" text, e.g.
%   "Charge at Lahti HPC in 1 h 05 min" followed by the charge time and
%   target on a second line.

if plan.Status ~= "Feasible"
    text = "This trip doesn't work as planned: " + plan.StatusMessage;
elseif isempty(plan.Stops)
    text = sprintf("Drive straight there. You'll arrive with %.0f%%.", ...
        plan.FinalSoCPercent);
else
    summary = evcharge.assistant.summarizePlan(plan);
    stop = summary.stops(1);
    text = sprintf("Charge at %s in %s\n%d min, up to %d%%", stop.name, ...
        evcharge.ui.formatDuration(stop.drive_minutes_to_stop), ...
        stop.charge_minutes, stop.leave_percent);
end
text = string(text);
end
