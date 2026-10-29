function advice = batteryAdvice(state, context)
%BATTERYADVICE Rule-based battery care advice for the current situation.
%
%   ADVICE = EVCHARGE.ASSISTANT.BATTERYADVICE(STATE, CONTEXT) returns
%   plain-language tips and suggested actions. CONTEXT is "daily",
%   "before_trip", or "before_fast_charge". The rules live here so the
%   language model explains them instead of inventing them.

arguments
    state (1,1) evcharge.assistant.VehicleState
    context (1,1) string {mustBeMember(context, ...
        ["daily", "before_trip", "before_fast_charge"])} = "daily"
end

dailyLimitPercent = 80;
coldBatteryC = 15;
tips = strings(0, 1);
actions = struct("action", {}, "value", {});
plan = state.ActivePlan;
hasPlan = isstruct(plan) && isfield(plan, "Status");

switch context
    case "daily"
        tips(end+1) = sprintf("For everyday driving, charge to about %d%%. " ...
            + "Keeping the battery very full for long periods wears it faster.", ...
            dailyLimitPercent);
        tips(end+1) = "Charging to 100% is fine right before a long trip " ...
            + "that needs it, as long as you leave soon after it finishes.";
        if state.SoCPercent < 20
            tips(end+1) = "The battery is getting low; plug in when you can.";
        end

    case "before_trip"
        if hasPlan
            % Battery needed at departure to drive the whole trip nonstop.
            nonstopStartPercent = plan.TotalEnergyKWh ...
                / plan.Vehicle.UsableBatteryCapacityKWh * 100 ...
                + plan.DestinationSoCPercent;
            if isempty(plan.Stops)
                tips(end+1) = "You already have enough charge for this trip.";
            elseif nonstopStartPercent <= 100
                tips(end+1) = sprintf("Charging to about %.0f%% at home " ...
                    + "before you leave would let you skip the charging stops.", ...
                    ceil(nonstopStartPercent / 5) * 5);
            else
                tips(end+1) = "This trip needs charging stops even with a " ...
                    + "full battery, so there is no need to charge to 100%. " ...
                    + "Fast chargers are quickest when the battery arrives " ...
                    + "low, around 10-30%.";
            end
        else
            tips(end+1) = "Tell me where you are going and I can check whether " ...
                + "you need to charge more tonight.";
        end
        if state.OutsideTempC < 5
            tips(end+1) = "In cold weather, warm the car while it is still " ...
                + "plugged in. That heat comes from the grid, not the battery.";
        end

    case "before_fast_charge"
        if state.BatteryTempC < coldBatteryC
            tips(end+1) = sprintf("The battery is cold (%d °C). Warming it up " ...
                + "for about 20-30 minutes before the charger can roughly halve " ...
                + "the charging time.", round(state.BatteryTempC));
            target = "";
            if hasPlan && ~isempty(plan.Stops)
                target = plan.Stops.StationName(1);
            end
            actions(end+1) = struct("action", "start_preconditioning", ...
                "value", target);
        else
            tips(end+1) = "The battery is warm enough to fast charge at full speed.";
        end
        tips(end+1) = "Charging slows down a lot above about 80%. Leave once " ...
            + "you have enough to reach the next stop.";
end

advice.context = context;
advice.tips = tips';
advice.suggested_actions = actions;
end
