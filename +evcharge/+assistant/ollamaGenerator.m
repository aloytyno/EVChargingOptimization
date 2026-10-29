function generateFcn = ollamaGenerator(cfg, toolDefs, systemPrompt)
%OLLAMAGENERATOR Fast Ollama chat call with thinking turned off.
%
%   F = EVCHARGE.ASSISTANT.OLLAMAGENERATOR(CFG, TOOLDEFS, SYSTEMPROMPT)
%   returns a handle [TEXT, MESSAGE] = F(HISTORY) for
%   evcharge.assistant.Assistant. It posts to Ollama's /api/chat directly
%   because ollamaChat cannot pass "think": false. Without it, reasoning
%   models such as qwen3 spend several seconds on hidden thinking before
%   every tool call. HISTORY is a llms-with-matlab messageHistory and
%   MESSAGE has the same shape that ollamaChat returns.

arguments
    cfg struct
    toolDefs openAIFunction
    systemPrompt (1,1) string
end

url = "http://" + cfg.Endpoint + "/api/chat";
tools = arrayfun(@(f) struct("type", "function", "function", ...
    encodeStruct(f)), toolDefs, UniformOutput=false);
systemMessage = struct("role", "system", "content", systemPrompt);
options = weboptions(MediaType="application/json", ...
    Timeout=cfg.TimeOutSeconds);

generateFcn = @generate;

    function [text, message] = generate(history)
        body = struct( ...
            "model", cfg.Model, ...
            "messages", {[{systemMessage}, history.Messages]}, ...
            "tools", {tools}, ...
            "stream", false, ...
            "think", false, ...
            "keep_alive", cfg.KeepAlive, ...
            "options", struct("temperature", cfg.Temperature));
        try
            response = webwrite(url, body, options);
        catch ME
            error("evcharge:assistant:OllamaRequestFailed", ...
                "Ollama request failed: %s", ME.message);
        end
        message = response.message;
        if isfield(message, "thinking")
            message = rmfield(message, "thinking");
        end
        text = string(message.content);
    end
end
