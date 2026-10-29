function future = preloadModel(cfg)
%PRELOADMODEL Load the Ollama model into memory in the background.
%
%   F = EVCHARGE.ASSISTANT.PRELOADMODEL(CFG) asks Ollama to load CFG.Model
%   and keep it loaded for CFG.KeepAlive, without generating any text. The
%   request runs on the background pool so the caller can load the speech
%   models at the same time. F is the parfeval future; wait(F) blocks
%   until the model is ready.
%
%   The first load after a reboot reads ~5 GB from disk and can take tens
%   of seconds, so doing it at app startup keeps it out of the first
%   question.

arguments
    cfg struct = evcharge.assistant.config()
end

url = "http://" + cfg.Endpoint + "/api/generate";
body = struct("model", cfg.Model, "keep_alive", cfg.KeepAlive);
options = weboptions(MediaType="application/json", Timeout=300);
future = parfeval(backgroundPool, @webwrite, 1, url, body, options);
end
