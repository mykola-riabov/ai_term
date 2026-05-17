/*
 * OpenAI-compatible chat/completions, model listing, API key checks (curl).
 */
module gx.aiterm.modern.llm;

import std.algorithm;
import std.ascii;
import std.conv;
import std.format;
import std.json;
import std.process;
import std.string;

import gx.aiterm.modern.aiproviders;
import gx.aiterm.modern.store;

struct LlmChatResult {
    bool ok;
    string content;
    string error;
}

struct LlmModelsResult {
    bool ok;
    string[] models;
    string error;
    string note;
}

struct LlmKeyVerifyResult {
    bool ok;
    string message;
}

private struct HttpResponse {
    bool curlOk;
    int httpCode;
    string body;
    string curlErr;
}

string normalizeOpenAiBase(string raw, string providerId = "") {
    string b = raw.strip();
    while (b.length > 0 && b[$ - 1] == '/') b = b[0 .. $ - 1];
    if (b.length == 0) return "";
    string p = normalizeProviderId(providerId);
    if (p == "google") {
        if (!b.endsWith("/openai")) b ~= "/openai";
        return b;
    }
    if (!b.endsWith("/v1")) b ~= "/v1";
    return b;
}

string resolveAiBaseUrl(ref ModernAiSettings ai) {
    string b = ai.baseUrl.strip();
    if (b.length > 0) return normalizeOpenAiBase(b, ai.provider);
    auto pr = aiProviderPreset(ai.provider);
    if (pr.defaultBaseUrl.length > 0)
        return normalizeOpenAiBase(pr.defaultBaseUrl, ai.provider);
    return "";
}

private string modelsUrl(string base) {
    string b = base.strip();
    while (b.length > 0 && b[$ - 1] == '/') b = b[0 .. $ - 1];
    return b ~ "/models";
}

private string extractApiErrorMessage(string body) {
    try {
        auto j = parseJSON(body);
        if ("message" in j && j["message"].type == JSONType.string)
            return j["message"].str;
        if ("error" in j) {
            if (j["error"].type == JSONType.string) return j["error"].str;
            if (j["error"].type == JSONType.object && "message" in j["error"])
                return j["error"]["message"].str;
        }
    } catch (Exception) { }
    return body.strip();
}

private bool isAuthError(int httpCode, string body) {
    if (httpCode == 401 || httpCode == 403) return true;
    string low = body.toLower();
    if (low.length == 0) return false;
    return low.indexOf("authenticate") >= 0 || low.indexOf("unauthorized") >= 0 ||
        low.indexOf("invalid api key") >= 0 || low.indexOf("incorrect api key") >= 0 ||
        low.indexOf("api key not valid") >= 0 || low.indexOf("invalid authentication") >= 0 ||
        low.indexOf("permission denied") >= 0;
}

private HttpResponse parseCurlOutput(string raw, bool curlStatusOk) {
    HttpResponse r;
    r.curlOk = curlStatusOk;
    r.curlErr = raw.strip();
    r.body = r.curlErr;
    r.httpCode = 0;
    if (!r.curlOk) return r;
    auto nl = raw.lastIndexOf('\n');
    if (nl >= 0) {
        string tail = raw[nl + 1 .. $].strip();
        if (tail.length > 0 && tail.all!(c => c >= '0' && c <= '9')) {
            r.httpCode = to!int(tail);
            r.body = raw[0 .. nl].strip();
        }
    }
    return r;
}

private HttpResponse httpGet(string url, string apiKey = "", int timeoutSec = 15) {
    string[] cmd = ["curl", "-sS", "-m", to!string(timeoutSec), "-w", "\n%{http_code}", url];
    if (apiKey.strip().length > 0)
        cmd ~= ["-H", "Authorization: Bearer " ~ apiKey.strip()];
    auto pr = execute(cmd);
    return parseCurlOutput(pr.output, pr.status == 0);
}

private HttpResponse httpPostJson(string url, string apiKey, string jsonBody, int timeoutSec = 30) {
    string[] cmd = ["curl", "-sS", "-m", to!string(timeoutSec), "-w", "\n%{http_code}",
        "-X", "POST", url, "-H", "Content-Type: application/json"];
    if (apiKey.strip().length > 0)
        cmd ~= ["-H", "Authorization: Bearer " ~ apiKey.strip()];
    cmd ~= ["-d", jsonBody];
    auto pr = execute(cmd);
    return parseCurlOutput(pr.output, pr.status == 0);
}

/** ASI:One has no GET /models — probe with minimal chat/completions. */
private LlmKeyVerifyResult verifyFetchAiKey(ref ModernAiSettings ai, string base) {
    string model = ai.model.strip();
    if (model.length == 0) model = "asi1-mini";
    JSONValue[] msgs = [JSONValue(["role": JSONValue("user"), "content": JSONValue("ping")])];
    JSONValue body = JSONValue([
        "model": JSONValue(model),
        "messages": JSONValue(msgs),
        "max_tokens": JSONValue(1),
    ]);
    string url = base ~ "/chat/completions";
    auto r = httpPostJson(url, ai.apiKey, body.toString(), 25);
    if (!r.curlOk)
        return LlmKeyVerifyResult(false, "Request failed: " ~ r.curlErr);
    if (isAuthError(r.httpCode, r.body)) {
        string err = extractApiErrorMessage(r.body);
        return LlmKeyVerifyResult(false,
            err.length > 0 ? err : format("API key rejected (HTTP %d)", r.httpCode));
    }
    if (r.httpCode >= 200 && r.httpCode < 300)
        return LlmKeyVerifyResult(true, "API key valid (Fetch.ai ASI:One).");
    string err = extractApiErrorMessage(r.body);
    if (err.length > 0)
        return LlmKeyVerifyResult(false, err);
    return LlmKeyVerifyResult(false, format("HTTP %d from chat/completions", r.httpCode));
}

private string[] parseModelsJson(string body) {
    string[] ids;
    try {
        auto j = parseJSON(body);
        if ("data" in j && j["data"].type == JSONType.array) {
            foreach (item; j["data"].array) {
                if (item.type != JSONType.object) continue;
                if ("id" in item) {
                    string id = item["id"].str;
                    if (id.length > 0) ids ~= id;
                }
            }
        } else if ("models" in j && j["models"].type == JSONType.array) {
            foreach (item; j["models"].array) {
                if (item.type == JSONType.string) ids ~= item.str;
                else if (item.type == JSONType.object && "name" in item) {
                    string name = item["name"].str;
                    if (name.startsWith("models/")) name = name[7 .. $];
                    if (name.length > 0) ids ~= name;
                }
            }
        }
    } catch (Exception) { }
    ids.sort();
    return ids;
}

/** Check API key / server reachability (GET /models or static catalog for ASI:One). */
LlmKeyVerifyResult verifyApiKey(ref ModernAiSettings ai) {
    ai.provider = normalizeProviderId(ai.provider);
    auto pr = aiProviderPreset(ai.provider);
    string base = resolveAiBaseUrl(ai);
    if (base.length == 0)
        return LlmKeyVerifyResult(false, "Set API base URL or pick a provider with defaults.");

    if (pr.apiKeyRequired && ai.apiKey.strip().length == 0)
        return LlmKeyVerifyResult(false, "API key is empty.");

    if (providerStaticModels(ai.provider).length > 0)
        return verifyFetchAiKey(ai, base);

    if (!pr.apiKeyRequired && ai.apiKey.strip().length == 0) {
        auto r = httpGet(modelsUrl(base), "");
        if (!r.curlOk)
            return LlmKeyVerifyResult(false, "Cannot reach server: " ~ r.curlErr);
        if (isAuthError(r.httpCode, r.body)) {
            string err = extractApiErrorMessage(r.body);
            return LlmKeyVerifyResult(false,
                err.length > 0 ? err : format("HTTP %d", r.httpCode));
        }
        if (r.httpCode >= 400) {
            string err = extractApiErrorMessage(r.body);
            return LlmKeyVerifyResult(false,
                err.length > 0 ? err : format("Server error HTTP %d", r.httpCode));
        }
        string[] models = parseModelsJson(r.body);
        if (models.length > 0)
            return LlmKeyVerifyResult(true, format("Server OK (%d models)", models.length));
        return LlmKeyVerifyResult(true, "Server reachable (no model list — check Local Server / ollama serve).");
    }

    auto r = httpGet(modelsUrl(base), ai.apiKey);
    if (!r.curlOk)
        return LlmKeyVerifyResult(false, "Request failed: " ~ r.curlErr);
    if (isAuthError(r.httpCode, r.body)) {
        string err = extractApiErrorMessage(r.body);
        return LlmKeyVerifyResult(false,
            err.length > 0 ? err : format("API key rejected (HTTP %d)", r.httpCode));
    }

    string[] models = parseModelsJson(r.body);
    if (models.length > 0)
        return LlmKeyVerifyResult(true, format("API key valid (%d models)", models.length));
    if (r.httpCode >= 200 && r.httpCode < 300)
        return LlmKeyVerifyResult(true, "API key accepted (endpoint responded OK).");
    string err = extractApiErrorMessage(r.body);
    return LlmKeyVerifyResult(false,
        err.length > 0 ? err : format("Unexpected HTTP %d", r.httpCode));
}

LlmModelsResult listAvailableModels(ref ModernAiSettings ai) {
    ai.provider = normalizeProviderId(ai.provider);
    string base = resolveAiBaseUrl(ai);
    if (base.length == 0)
        return LlmModelsResult(false, null, "Set API base URL or choose a provider with a default URL.", "");

    auto pr = aiProviderPreset(ai.provider);
    if (pr.apiKeyRequired && ai.apiKey.strip().length == 0)
        return LlmModelsResult(false, null, "API key required for this provider.", "");

    if (providerIsCloud(ai.provider) || (pr.apiKeyRequired && ai.apiKey.strip().length > 0)) {
        auto check = verifyApiKey(ai);
        if (!check.ok)
            return LlmModelsResult(false, null, check.message, "");
    }

    string[] catalog = providerStaticModels(ai.provider);
    if (catalog.length > 0) {
        return LlmModelsResult(true, catalog, "",
            "ASI:One: documented models (no /models listing).");
    }

    auto r = httpGet(modelsUrl(base), ai.apiKey);
    if (!r.curlOk)
        return LlmModelsResult(false, null, r.curlErr, "");
    if (isAuthError(r.httpCode, r.body)) {
        string err = extractApiErrorMessage(r.body);
        return LlmModelsResult(false, null,
            err.length > 0 ? err : format("API key rejected (HTTP %d)", r.httpCode), "");
    }
    string[] models = parseModelsJson(r.body);
    if (models.length == 0) {
        string err = extractApiErrorMessage(r.body);
        if (err.length > 0 && err != r.body)
            return LlmModelsResult(false, null, err, "");
        if (r.httpCode >= 400)
            return LlmModelsResult(false, null, format("HTTP %d: %s", r.httpCode,
                r.body.length > 120 ? r.body[0 .. 120] ~ "…" : r.body), "");
        string snippet = r.body.length > 200 ? r.body[0 .. 200] ~ "…" : r.body;
        return LlmModelsResult(false, null, "No models in response: " ~ snippet, "");
    }
    string note = providerIsCloud(ai.provider) ? "API key valid." : "";
    return LlmModelsResult(true, models, "", note);
}

LlmChatResult llmChat(JSONValue[] messages) {
    auto ai = modernData().ai;
    ai.provider = normalizeProviderId(ai.provider);
    string base = resolveAiBaseUrl(ai);
    if (base.length == 0) {
        return LlmChatResult(false, "", "No API base URL configured");
    }
    string model = ai.model.strip();
    if (model.length == 0) model = defaultModelForProvider(ai.provider);
    if (model.length == 0) model = "gpt-4o-mini";
    JSONValue body = JSONValue([
        "model": JSONValue(model),
        "messages": JSONValue(messages),
        "temperature": JSONValue(0.5),
        "max_tokens": JSONValue(4096),
    ]);
    string url = base ~ "/chat/completions";
    string[] cmd = ["curl", "-sS", "-m", "120", "-X", "POST", url,
        "-H", "Content-Type: application/json"];
    if (ai.apiKey.strip().length > 0) {
        cmd ~= ["-H", "Authorization: Bearer " ~ ai.apiKey.strip()];
    }
    cmd ~= ["-d", body.toString()];
    auto pr = execute(cmd);
    if (pr.status != 0) {
        return LlmChatResult(false, "", pr.output);
    }
    try {
        auto j = parseJSON(pr.output);
        if ("error" in j) {
            string err = ("message" in j["error"]) ? j["error"]["message"].str : j["error"].toString();
            return LlmChatResult(false, "", err);
        }
        if ("choices" in j && j["choices"].array.length > 0) {
            auto msg = j["choices"][0];
            if ("message" in msg && "content" in msg["message"]) {
                return LlmChatResult(true, msg["message"]["content"].str, "");
            }
        }
        return LlmChatResult(false, "", "Unexpected API response");
    } catch (Exception e) {
        return LlmChatResult(false, "", e.msg);
    }
}

string buildSystemPrompt() {
    auto ai = modernData().ai;
    string base = "You are a helpful assistant for Linux shell commands, scripts, and networks. Be concise.";
    if (!ai.agentExec) return base;
    return base ~ "\n\n" ~
        "CRITICAL: Aiterm terminal agent is ON. The user runs a real bash session. " ~
        "To run commands, output exactly ONE fenced block tagged bash with command lines only. " ~
        "Example:\n```bash\nping -c 3 8.8.8.8\n```\n" ~
        "The app executes that block. Brief explanation may be outside the fence.";
}
