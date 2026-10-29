classdef Assistant < handle
    %ASSISTANT Conversational EV co-driver backed by a local LLM.
    %
    %   A = EVCHARGE.ASSISTANT.ASSISTANT creates an assistant that talks to
    %   Ollama through llms-with-matlab and calls the +evcharge planning
    %   tools on a simulated car.
    %
    %   REPLY = ASK(A, TEXT) sends one driver utterance and returns a struct
    %   with fields Text (what to say), ToolsCalled, and Plan (the latest
    %   optimization result, or [] if no trip has been planned).
    %
    %   A = EVCHARGE.ASSISTANT.ASSISTANT(State=S, GenerateFcn=F) uses an
    %   existing VehicleState and a custom generator. F has the signature
    %   [TEXT, MESSAGE] = F(MESSAGEHISTORY) and lets tests run without an LLM.
    %
    %   Set ToolStartFcn to a handle F(NAME, ARGS) to be told just before a
    %   tool runs, e.g. to say "Checking the route..." during slow lookups.

    properties
        % No default value: a handle default would be shared by every
        % Assistant instance. The constructor creates one per assistant.
        State evcharge.assistant.VehicleState
        History (1,1) messageHistory = messageHistory()
        Config struct
        ToolStartFcn function_handle = function_handle.empty
    end

    properties (SetAccess = private)
        GenerateFcn function_handle
        RunTool function_handle
    end

    methods
        function obj = Assistant(options)
            arguments
                options.State evcharge.assistant.VehicleState
                options.GenerateFcn function_handle
                options.Config struct = evcharge.assistant.config()
            end

            obj.Config = options.Config;
            if isfield(options, "State")
                obj.State = options.State;
            else
                obj.State = evcharge.assistant.VehicleState();
            end

            [toolDefs, obj.RunTool] = evcharge.assistant.tools( ...
                UseLiveData=obj.Config.UseLiveData);

            if isfield(options, "GenerateFcn")
                obj.GenerateFcn = options.GenerateFcn;
            else
                obj.GenerateFcn = evcharge.assistant.ollamaGenerator( ...
                    obj.Config, toolDefs, ...
                    evcharge.assistant.Assistant.systemPrompt());
            end
        end

        function reply = ask(obj, userText)
            arguments
                obj
                userText (1,1) string
            end

            reply = struct("Text", "", "ToolsCalled", strings(1, 0), ...
                "Plan", []);
            obj.trimHistory();
            obj.History = addUserMessage(obj.History, ...
                obj.carContext() + newline + userText);

            try
                for iteration = 1:obj.Config.MaxToolRounds
                    [text, message] = obj.GenerateFcn(obj.History);
                    toolCalls = toolCallsOf(message);
                    obj.History = addResponseMessage(obj.History, message);
                    if isempty(toolCalls)
                        reply.Text = cleanReply(text);
                        break
                    end
                    for k = 1:numel(toolCalls)
                        [name, result, id] = obj.runToolCall(toolCalls{k});
                        reply.ToolsCalled(end+1) = name;
                        obj.History = addToolMessage(obj.History, id, name, ...
                            jsonencode(result));
                    end
                end
                if reply.Text == ""
                    reply.Text = "Sorry, I got stuck working that out. " ...
                        + "Could you say it again?";
                end
            catch ME
                reply.Text = "I can't reach my language model right now. " ...
                    + "Check that Ollama is running.";
                reply.Error = string(ME.message);
                % Drop the half-finished turn so the next one starts clean.
                obj.History = messageHistory();
            end
            reply.Plan = obj.State.ActivePlan;
        end

        function reset(obj)
            %RESET Forget the conversation (the car state is kept).
            obj.History = messageHistory();
        end
    end

    methods (Access = private)
        function [name, result, id] = runToolCall(obj, call)
            id = "";
            if isfield(call, "id") && ~isempty(call.id)
                id = string(call.id);
            end
            name = string(call.function.name);
            args = call.function.arguments;
            if ischar(args) || isstring(args)
                if strlength(args) == 0
                    args = struct();
                else
                    args = jsondecode(args);
                end
            end
            if ~isempty(obj.ToolStartFcn)
                try
                    obj.ToolStartFcn(name, args);
                catch
                    % Progress feedback must never break the tool call.
                end
            end
            result = obj.RunTool(name, args, obj.State);
        end

        function context = carContext(obj)
            s = obj.State;
            context = sprintf("[Car now: battery %d%%, at %s, outside %d °C, " ...
                + "battery %d °C, charge limit %d%%.]", round(s.SoCPercent), ...
                s.LocationName, round(s.OutsideTempC), round(s.BatteryTempC), ...
                round(s.ChargeLimitPercent));
        end

        function trimHistory(obj)
            % Small local models lose focus with long histories. Starting
            % over is safe because the car state is sent with every turn.
            maxMessages = 6 * obj.Config.HistoryTurnsToKeep;
            if numel(obj.History.Messages) > maxMessages
                obj.History = messageHistory();
            end
        end
    end

    methods (Static)
        function prompt = systemPrompt()
            prompt = join([ ...
                "You are a friendly co-driver in an electric car in Finland. " ...
                + "The driver is not technical. Your replies are spoken aloud, " ...
                + "so answer in one to three short, plain sentences. " ...
                + "No lists, tables, markdown, or emoji."
                "Never guess numbers. Use plan_trip for any question about " ...
                + "a destination, range, or where to charge. Use " ...
                + "get_battery_advice for questions about charging habits, " ...
                + "charging to 100 percent, or warming the battery."
                "When you describe a trip, say whether they can make it, the " ...
                + "first stop and roughly how long to charge there, and the " ...
                + "battery left on arrival. Round times to the nearest five " ...
                + "minutes and say hours and minutes, not total minutes."
                "Take care of the battery for the driver. If a tool says " ...
                + "preconditioning is scheduled, mention it and give the reason " ...
                + "in one sentence. If advice suggests an action like " ...
                + "set_charge_limit or start_preconditioning, just do it and " ...
                + "tell them."
                "If a tool returns an error, explain it simply and suggest " ...
                + "what they can do."
                "Each message starts with the car's current state in " ...
                + "brackets; use it, but do not read it back unless asked."], ...
                " ");
        end

        function text = progressMessage(name, args)
            %PROGRESSMESSAGE Short spoken filler for slow tools, or "".
            text = "";
            if name == "plan_trip"
                destination = "";
                if isstruct(args) && isfield(args, "destination")
                    destination = strtrim(string(args.destination));
                end
                if destination == ""
                    text = "Checking the route.";
                else
                    text = "Checking the route to " ...
                        + extractBefore(destination + ",", ",") + ".";
                end
            end
        end
    end
end

function calls = toolCallsOf(message)
calls = {};
if ~isstruct(message) || ~isfield(message, "tool_calls") ...
        || isempty(message.tool_calls)
    return
end
calls = message.tool_calls;
if isstruct(calls)
    calls = num2cell(calls);
end
end

function text = cleanReply(text)
text = string(text);
text = regexprep(text, "<think>.*?</think>", "");
text = regexprep(text, "[*#`_]", "");
text = strtrim(text);
end
