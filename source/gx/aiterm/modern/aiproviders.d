/*
 * AI provider presets (defaults, labels, model listing helpers).
 */
module gx.aiterm.modern.aiproviders;

import std.algorithm;
import std.conv;
import std.string;

import gx.aiterm.modern.store;

struct AiProviderPreset {
    string id;
    string label;
    string defaultBaseUrl;
    string defaultModel;
    bool apiKeyRequired;
    bool supportsModelList;
    string hint;
}

AiProviderPreset[] allAiProviderPresets() {
    AiProviderPreset[] p;
    p ~= AiProviderPreset("lmstudio", "LM Studio",
        "http://127.0.0.1:1234/v1", "", false, true,
        "Local server — enable «Local Server» in LM Studio.");
    p ~= AiProviderPreset("ollama", "Ollama",
        "http://127.0.0.1:11434/v1", "", false, true,
        "Run: ollama serve — then refresh models.");
    p ~= AiProviderPreset("openai", "OpenAI",
        "https://api.openai.com/v1", "gpt-4o-mini", true, true,
        "API key from platform.openai.com");
    p ~= AiProviderPreset("fetchai", "Fetch.ai (ASI:One)",
        "https://api.asi1.ai/v1", "asi1", true, true,
        "API token from asi1.ai. Models: asi1, asi1-ultra, asi1-mini (no /models API).");
    p ~= AiProviderPreset("google", "Google Gemini",
        "https://generativelanguage.googleapis.com/v1beta/openai",
        "gemini-2.0-flash", true, true,
        "API key from aistudio.google.com (OpenAI-compatible endpoint).");
    p ~= AiProviderPreset("custom", "Custom (OpenAI-compatible)",
        "", "", false, true,
        "Any OpenAI-compatible /v1 or …/openai base URL.");
    return p;
}

string normalizeProviderId(string id) {
    string p = id.toLower().strip();
    if (p == "fetchhub") return "fetchai";
    foreach (pr; allAiProviderPresets())
        if (pr.id == p) return p;
    return "custom";
}

AiProviderPreset aiProviderPreset(string id) {
    string p = normalizeProviderId(id);
    foreach (pr; allAiProviderPresets())
        if (pr.id == p) return pr;
    return AiProviderPreset("custom", "Custom", "", "", false, true, "");
}

void applyProviderDefaults(ref ModernAiSettings ai, bool overwriteBase = true) {
    ai.provider = normalizeProviderId(ai.provider);
    auto pr = aiProviderPreset(ai.provider);
    if (overwriteBase || ai.baseUrl.length == 0)
        ai.baseUrl = pr.defaultBaseUrl;
    if (pr.defaultModel.length > 0 && ai.model.length == 0)
        ai.model = pr.defaultModel;
    if (ai.provider == "fetchai" && ai.model.length == 0)
        ai.model = "asi1";
}

string defaultModelForProvider(string providerId) {
    return aiProviderPreset(providerId).defaultModel;
}

/** LM Studio / Ollama — saved local server list in preferences. */
bool providerSupportsSavedServers(string providerId) {
    switch (normalizeProviderId(providerId)) {
    case "lmstudio", "ollama":
        return true;
    default:
        return false;
    }
}

private bool urlAuthorityHasPort(string u) {
    size_t scheme = u.indexOf("://");
    string rest = scheme < u.length ? u[scheme + 3 .. $] : u;
    size_t slash = rest.indexOf("/");
    if (slash < rest.length) rest = rest[0 .. slash];
    return rest.indexOf(":") < rest.length;
}

private string insertUrlPort(string u, int port) {
    size_t scheme = u.indexOf("://");
    if (scheme >= u.length) return u;
    string prefix = u[0 .. scheme + 3];
    string rest = u[scheme + 3 .. $];
    size_t slash = rest.indexOf("/");
    string host = slash < rest.length ? rest[0 .. slash] : rest;
    string path = slash < rest.length ? rest[slash .. $] : "";
    if (host.indexOf(":") < host.length) return u;
    return prefix ~ host ~ ":" ~ to!string(port) ~ path;
}

/** Normalize host or full URL to OpenAI-compatible …/v1 base. */
string normalizeAiBaseUrl(string url, string providerId) {
    string u = url.strip();
    if (u.length == 0) return u;
    if (u.indexOf("://") < 0) u = "http://" ~ u;
    while (u.length > 1 && u.endsWith("/")) u = u[0 .. $ - 1];
    string p = normalizeProviderId(providerId);
    if (!urlAuthorityHasPort(u)) {
        if (p == "ollama") u = insertUrlPort(u, 11434);
        else if (p == "lmstudio") u = insertUrlPort(u, 1234);
    }
    if ((p == "lmstudio" || p == "ollama") && !u.endsWith("/v1"))
        u ~= "/v1";
    return u;
}

/** Cloud providers where an API key should be validated explicitly. */
bool providerIsCloud(string providerId) {
    switch (normalizeProviderId(providerId)) {
    case "openai", "google", "fetchai":
        return true;
    default:
        return false;
    }
}

/** Fixed catalog when provider has no OpenAI-style GET /models. */
string[] providerStaticModels(string providerId) {
    switch (normalizeProviderId(providerId)) {
    case "fetchai":
        return ["asi1", "asi1-ultra", "asi1-mini"];
    default:
        return null;
    }
}
