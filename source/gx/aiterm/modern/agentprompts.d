/*
 * Agent prompt tiers (simple / medium / complex / cloud / custom) and resolution.
 */
module gx.aiterm.modern.agentprompts;

import std.algorithm;
import std.string;

import gx.aiterm.modern.aiproviders;
import gx.aiterm.modern.store;

immutable string AGENT_TIER_SIMPLE = "simple";
immutable string AGENT_TIER_MEDIUM = "medium";
immutable string AGENT_TIER_COMPLEX = "complex";
immutable string AGENT_TIER_CLOUD = "cloud";
immutable string AGENT_TIER_CUSTOM = "custom";

string normalizeAgentPromptTier(string id) {
    string t = id.toLower().strip();
    switch (t) {
    case AGENT_TIER_SIMPLE, "small", "plain":
        return AGENT_TIER_SIMPLE;
    case AGENT_TIER_MEDIUM, "default":
        return AGENT_TIER_MEDIUM;
    case AGENT_TIER_COMPLEX, "large":
        return AGENT_TIER_COMPLEX;
    case AGENT_TIER_CLOUD:
        return AGENT_TIER_CLOUD;
    case AGENT_TIER_CUSTOM:
        return AGENT_TIER_CUSTOM;
    default:
        return AGENT_TIER_MEDIUM;
    }
}

/** Migrate legacy activeAgentPromptId from v1 config. */
string tierFromLegacyPromptId(string legacyId) {
    switch (legacyId) {
    case "agent-prompt-plain", "agent-prompt-strict":
        return AGENT_TIER_SIMPLE;
    case "agent-prompt-default":
        return AGENT_TIER_MEDIUM;
    default:
        return AGENT_TIER_MEDIUM;
    }
}

string defaultAgentPromptForTier(string tier) {
    tier = normalizeAgentPromptTier(tier);
    immutable fence = "```";
    switch (tier) {
    case AGENT_TIER_SIMPLE:
        return "You are a Linux shell command generator for Aiterm.\n" ~
            "Output ONLY executable shell commands, one per line.\n" ~
            "No markdown, no code fences, no explanations, no $ or # prefixes.\n" ~
            "The app runs your output directly in bash.\n" ~
            "User: ping google\n" ~
            "You:\nping -c 4 google.com";
    case AGENT_TIER_MEDIUM:
        return "TERMINAL AGENT MODE:\n" ~
            "The user has a real bash session. To run commands, reply with exactly ONE markdown block.\n" ~
            "Opening line must be " ~ fence ~ "bash. Put commands inside, one per line. Close with " ~ fence ~ ".\n" ~
            "You may add one short line after the block.\n" ~
            "Example:\n" ~ fence ~ "bash\nping -c 4 8.8.8.8\n" ~ fence;
    case AGENT_TIER_COMPLEX:
        return "Aiterm terminal agent is ON. The user runs a real Linux bash session.\n" ~
            "When the user asks to run something, include exactly ONE fenced block tagged bash with commands only.\n" ~
            "Brief explanation may appear outside the fence. Prefer safe, standard commands.\n" ~
            "Example:\n" ~ fence ~ "bash\nping -c 3 8.8.8.8\n" ~ fence;
    case AGENT_TIER_CLOUD:
        return "You assist via a cloud API. Aiterm may execute bash blocks in the user's terminal when Agent is enabled.\n" ~
            "For runnable requests, output exactly ONE " ~ fence ~ "bash block with commands (one per line).\n" ~
            "Do not assume root. Warn if a command is destructive. Keep prose minimal.";
    case AGENT_TIER_CUSTOM:
        return "Describe how the model should format terminal commands for Aiterm Agent.\n" ~
            "Use a " ~ fence ~ "bash block or plain command lines depending on your model.";
    default:
        return defaultAgentPromptForTier(AGENT_TIER_MEDIUM);
    }
}

bool agentPromptTierHasOverride(string tier) {
    tier = normalizeAgentPromptTier(tier);
    auto d = modernData();
    if (tier == AGENT_TIER_CUSTOM)
        return d.ai.agentPromptCustom.length > 0;
    return (tier in d.agentPromptOverrides) !is null;
}

string effectiveAgentPromptForTier(string tier) {
    tier = normalizeAgentPromptTier(tier);
    auto d = modernData();
    if (tier == AGENT_TIER_CUSTOM) {
        if (d.ai.agentPromptCustom.length > 0) return d.ai.agentPromptCustom;
        return defaultAgentPromptForTier(AGENT_TIER_CUSTOM);
    }
    if (auto ov = tier in d.agentPromptOverrides)
        return *ov;
    return defaultAgentPromptForTier(tier);
}

void setAgentPromptOverride(string tier, string text) {
    tier = normalizeAgentPromptTier(tier);
    if (tier == AGENT_TIER_CUSTOM)
        modernData().ai.agentPromptCustom = text;
    else
        modernData().agentPromptOverrides[tier] = text;
}

void clearAgentPromptOverride(string tier) {
    tier = normalizeAgentPromptTier(tier);
    if (tier == AGENT_TIER_CUSTOM)
        modernData().ai.agentPromptCustom = "";
    else
        modernData().agentPromptOverrides.remove(tier);
}

bool agentPromptTierIsCustomized(string tier) {
    return agentPromptTierHasOverride(tier);
}

string resolveAgentPromptText() {
    return effectiveAgentPromptForTier(modernData().ai.agentPromptTier);
}

/** Suggest tier from current AI provider (user can override). */
string suggestAgentPromptTierForProvider(string providerId) {
    if (providerIsCloud(providerId)) return AGENT_TIER_CLOUD;
    return AGENT_TIER_MEDIUM;
}
