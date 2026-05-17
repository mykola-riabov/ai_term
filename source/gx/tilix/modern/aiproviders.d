/*
 * AI provider presets (defaults, labels, model listing helpers).
 */
module gx.tilix.modern.aiproviders;

import std.algorithm;
import std.string;

import gx.tilix.modern.store;

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
