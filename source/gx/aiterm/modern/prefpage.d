/*
 * Preferences pages: AI, Network, Commands (quick bar data hubs).
 */
module gx.aiterm.modern.prefpage;

import std.file;
import std.format;
import std.string;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.FileChooserDialog;
import gtk.Grid;
import gtk.Label;
import gtk.ScrolledWindow;
import gtk.Separator;
import gtk.Switch;
import gtk.TextBuffer;
import gtk.TextIter;
import gtk.TextView;
import gtk.Window;
import gtk.c.types;

import gx.aiterm.modern.agentprompts;
import gx.aiterm.modern.aiproviders;
import gx.aiterm.modern.aiservershub;
import gx.aiterm.modern.bashhub;
import gx.aiterm.modern.chathub;
import gx.aiterm.modern.llm;
import gx.aiterm.modern.prompthub;
import gx.aiterm.modern.sshhub;
import gx.aiterm.modern.store;

private Box makeSwitchRow(string labelText, Switch sw) {
    auto row = new Box(Orientation.HORIZONTAL, 6);
    auto lbl = new Label(labelText);
    lbl.setXalign(0);
    lbl.setHexpand(true);
    row.packStart(lbl, true, true, 0);
    row.packEnd(sw, false, false, 0);
    return row;
}

class AiPreferencesPage : Box {

    Switch swBarPrompts;
    Label lblPromptCount;
    Switch swBarAgent;
    Switch swBarAiChat;

    ComboBoxText cbProvider;
    Label lblProviderHint;
    ComboBoxText cbSavedServer;
    Button btnManageServers;
    Entry eBase;
    ComboBoxText cbModel;
    Button btnRefreshModels;
    Label lblModelStatus;
    Entry eApiKey;
    Button btnKeyFromFile;
    Button btnTestKey;
    Switch swPersist;
    Switch swAgent;
    ComboBoxText cbAgentTier;
    TextView tvAgentPrompt;
    TextBuffer _agentPromptBuf;
    Switch swAgentPromptLock;
    Button btnRestoreAgentPrompt;
    bool _suppressUi;

public:
    this() {
        super(Orientation.VERTICAL, 12);
        setMarginStart(18);
        setMarginEnd(18);
        setMarginTop(18);
        setMarginBottom(18);
        auto grid = new Grid();
        grid.setColumnSpacing(12);
        grid.setRowSpacing(8);
        int row = 0;

        grid.attach(new Label("Provider"), 0, row, 1, 1);
        cbProvider = new ComboBoxText();
        foreach (pr; allAiProviderPresets())
            cbProvider.append(pr.id, pr.label);
        grid.attach(cbProvider, 1, row, 1, 1);
        row++;

        lblProviderHint = new Label("");
        lblProviderHint.setLineWrap(true);
        lblProviderHint.setXalign(0);
        grid.attach(lblProviderHint, 0, row, 2, 1);
        row++;

        grid.attach(new Label("Saved server"), 0, row, 1, 1);
        auto savedBox = new Box(Orientation.HORIZONTAL, 6);
        cbSavedServer = new ComboBoxText();
        cbSavedServer.setHexpand(true);
        savedBox.packStart(cbSavedServer, true, true, 0);
        btnManageServers = new Button("Manage…");
        btnManageServers.setTooltipText("Add, edit, or remove saved LM Studio / Ollama servers");
        savedBox.packStart(btnManageServers, false, false, 0);
        grid.attach(savedBox, 1, row, 1, 1);
        row++;

        grid.attach(new Label("API base URL"), 0, row, 1, 1);
        eBase = new Entry();
        eBase.setPlaceholderText("Filled from provider; editable");
        grid.attach(eBase, 1, row, 1, 1);
        row++;

        auto modelLbl = new Label("Model");
        grid.attach(modelLbl, 0, row, 1, 1);
        auto modelBox = new Box(Orientation.HORIZONTAL, 6);
        cbModel = new ComboBoxText(true);
        cbModel.setHexpand(true);
        modelBox.packStart(cbModel, true, true, 0);
        btnRefreshModels = new Button("Refresh models");
        btnRefreshModels.setTooltipText("Fetch model list from the API (GET /models)");
        modelBox.packStart(btnRefreshModels, false, false, 0);
        grid.attach(modelBox, 1, row, 1, 1);
        row++;

        lblModelStatus = new Label("");
        lblModelStatus.setLineWrap(true);
        lblModelStatus.setXalign(0);
        grid.attach(lblModelStatus, 0, row, 2, 1);
        row++;

        grid.attach(new Label("API key"), 0, row, 1, 1);
        auto keyBox = new Box(Orientation.HORIZONTAL, 6);
        eApiKey = new Entry();
        eApiKey.setVisibility(false);
        eApiKey.setHexpand(true);
        keyBox.packStart(eApiKey, true, true, 0);
        btnKeyFromFile = new Button("From file…");
        btnKeyFromFile.setTooltipText("Load API key from a text file (trimmed)");
        btnTestKey = new Button("Test key");
        btnTestKey.setTooltipText("Check API key (GET /models, or chat probe for Fetch.ai)");
        keyBox.packStart(btnKeyFromFile, false, false, 0);
        keyBox.packStart(btnTestKey, false, false, 0);
        grid.attach(keyBox, 1, row, 1, 1);
        row++;

        auto lblAgent = new Label("Agent: run model output in terminal");
        swAgent = new Switch();
        auto boxA = new Box(Orientation.HORIZONTAL, 6);
        boxA.packStart(lblAgent, false, false, 0);
        boxA.packEnd(swAgent, false, false, 0);
        grid.attach(boxA, 0, row, 2, 1);
        row++;

        grid.attach(new Label("Agent template"), 0, row, 1, 1);
        cbAgentTier = new ComboBoxText();
        cbAgentTier.append(AGENT_TIER_SIMPLE, "Simple models");
        cbAgentTier.append(AGENT_TIER_MEDIUM, "Medium models");
        cbAgentTier.append(AGENT_TIER_COMPLEX, "Complex models");
        cbAgentTier.append(AGENT_TIER_CLOUD, "Cloud APIs");
        cbAgentTier.append(AGENT_TIER_CUSTOM, "Custom");
        cbAgentTier.setTooltipText(
            "Pick a template for Agent system instructions. Simple suits small Ollama models.");
        grid.attach(cbAgentTier, 1, row, 1, 1);
        row++;

        packStart(grid, false, false, 0);

        auto agentPromptLbl = new Label("Agent prompt text");
        agentPromptLbl.setXalign(0);
        packStart(agentPromptLbl, false, false, 0);

        auto agentPromptToolbar = new Box(Orientation.HORIZONTAL, 6);
        swAgentPromptLock = new Switch();
        swAgentPromptLock.setActive(true);
        auto lockBox = new Box(Orientation.HORIZONTAL, 6);
        lockBox.packStart(new Label("Lock prompt (read-only)"), false, false, 0);
        lockBox.packEnd(swAgentPromptLock, false, false, 0);
        agentPromptToolbar.packStart(lockBox, false, false, 0);
        btnRestoreAgentPrompt = new Button("Restore default");
        btnRestoreAgentPrompt.setTooltipText("Reset this template to the built-in default text");
        agentPromptToolbar.packEnd(btnRestoreAgentPrompt, false, false, 0);
        packStart(agentPromptToolbar, false, false, 0);

        tvAgentPrompt = new TextView();
        tvAgentPrompt.setWrapMode(WrapMode.WORD);
        tvAgentPrompt.setEditable(false);
        tvAgentPrompt.setMonospace(true);
        _agentPromptBuf = tvAgentPrompt.getBuffer();
        auto agentPromptScroll = new ScrolledWindow();
        agentPromptScroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        agentPromptScroll.setMinContentHeight(140);
        agentPromptScroll.add(tvAgentPrompt);
        packStart(agentPromptScroll, false, false, 0);

        cbProvider.addOnChanged(delegate(ComboBoxText) {
            if (_suppressUi) return;
            onProviderChanged(true);
        });
        btnRefreshModels.addOnClicked(delegate(Button) { refreshModelsFromUi(); });
        btnKeyFromFile.addOnClicked(delegate(Button) { loadApiKeyFromFile(); });
        btnTestKey.addOnClicked(delegate(Button) { testApiKeyFromUi(); });
        cbSavedServer.addOnChanged(delegate(ComboBoxText) {
            if (_suppressUi) return;
            applySavedServer();
        });
        btnManageServers.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showAiServersHubDialog(w, cbProvider.getActiveId(), delegate() {
                refreshSavedServerCombo();
                applySavedServer();
            });
        });
        cbAgentTier.addOnChanged(delegate(ComboBoxText) {
            if (_suppressUi) return;
            onAgentTierChanged();
        });
        swAgentPromptLock.addOnNotify(delegate(ParamSpec, ObjectG) {
            if (_suppressUi) return;
            if (!swAgentPromptLock.getActive())
                persistAgentPromptEditorToStore();
            applyAgentPromptLockState();
        }, "active");
        btnRestoreAgentPrompt.addOnClicked(delegate(Button) { restoreAgentPromptDefault(); });

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto barTitle = new Label("Quick bar buttons");
        barTitle.setXalign(0);
        packStart(barTitle, false, false, 0);

        swBarPrompts = new Switch();
        packStart(makeSwitchRow("Show «Prompts» on panel", swBarPrompts), false, false, 0);

        lblPromptCount = new Label("");
        lblPromptCount.setXalign(0);
        lblPromptCount.setMarginStart(12);
        packStart(lblPromptCount, false, false, 0);

        auto btnEditPrompts = new Button("Edit categories and prompts…");
        btnEditPrompts.setHalign(Align.START);
        btnEditPrompts.setMarginStart(12);
        btnEditPrompts.setTooltipText("Add categories, subcategories, and prompts for the quick bar menu");
        packStart(btnEditPrompts, false, false, 0);

        auto btnRestorePrompts = new Button("Restore default prompts");
        btnRestorePrompts.setHalign(Align.START);
        btnRestorePrompts.setMarginStart(12);
        packStart(btnRestorePrompts, false, false, 0);

        btnEditPrompts.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showAiPromptHubDialog(w, delegate() { updatePromptCountLabel(); });
        });
        btnRestorePrompts.addOnClicked(delegate(Button) { confirmRestoreDefaultPrompts(); });

        swBarAgent = new Switch();
        packStart(makeSwitchRow("Show «Agent» on panel", swBarAgent), false, false, 0);
        swBarAiChat = new Switch();
        packStart(makeSwitchRow("Show «AI Chat» on panel", swBarAiChat), false, false, 0);

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto hubLbl = new Label("Saved AI chat conversations.");
        hubLbl.setLineWrap(true);
        hubLbl.setXalign(0);
        packStart(hubLbl, false, false, 0);

        swPersist = new Switch();
        swPersist.setTooltipText(
            "When enabled, each AI Chat exchange is written to ~/.config/aiterm/modern.json");
        packStart(makeSwitchRow("Persist AI chats", swPersist), false, false, 0);

        auto hubBox = new Box(Orientation.VERTICAL, 6);
        auto btnChats = new Button("AI chats…");
        btnChats.setHalign(Align.START);
        btnChats.setTooltipText("Open, rename, or delete saved conversations");
        hubBox.packStart(btnChats, false, false, 0);
        packStart(hubBox, false, false, 0);

        btnChats.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showAiChatsHubDialog(w, null);
        });

        packStart(new Label("Data file: ~/.config/aiterm/modern.json"), false, false, 0);
        loadFromStore();
    }

private:
    ModernAiSettings readAiFromUi() {
        ModernAiSettings ai;
        ai.provider = cbProvider.getActiveId();
        ai.baseUrl = eBase.getText().strip();
        ai.model = cbModel.getActiveText().strip();
        ai.apiKey = eApiKey.getText().strip();
        ai.persistHistory = swPersist.getActive();
        ai.agentExec = swAgent.getActive();
        return ai;
    }

    void updateProviderHint() {
        auto pr = aiProviderPreset(cbProvider.getActiveId());
        lblProviderHint.setText(pr.hint);
    }

    void setModelComboValue(string model) {
        if (model.length == 0) return;
        cbModel.removeAll();
        cbModel.append(model, model);
        cbModel.setActive(0);
        auto ent = cast(Entry)cbModel.getChild();
        if (ent !is null) ent.setText(model);
    }

    void refreshSavedServerCombo() {
        string prevId = cbSavedServer.getActiveId();
        cbSavedServer.removeAll();
        string prov = cbProvider.getActiveId();
        bool supported = providerSupportsSavedServers(prov);
        cbSavedServer.setSensitive(supported);
        if (!supported) return;
        cbSavedServer.append("", "(manual entry)");
        foreach (ref s; modernData().aiServers) {
            if (!providerSupportsSavedServers(s.provider)) continue;
            string lab = s.label.length > 0 ? s.label : s.baseUrl;
            if (normalizeProviderId(s.provider) != normalizeProviderId(prov))
                lab ~= " (" ~ aiProviderPreset(s.provider).label ~ ")";
            cbSavedServer.append(s.id, lab);
        }
        string pick = modernData().ai.activeAiServerId;
        if (pick.length == 0) pick = prevId;
        if (pick.length > 0 && findAiServerById(pick) !is null)
            cbSavedServer.setActiveId(pick);
        else
            cbSavedServer.setActiveId("");
    }

    string readAgentPromptTextView() {
        TextIter s, e;
        _agentPromptBuf.getBounds(s, e);
        return _agentPromptBuf.getText(s, e, false);
    }

    void setAgentPromptTextView(string text) {
        _agentPromptBuf.setText(text);
    }

    void applyAgentPromptLockState() {
        bool locked = swAgentPromptLock.getActive();
        tvAgentPrompt.setEditable(!locked);
    }

    void persistAgentPromptEditorToStore() {
        if (swAgentPromptLock.getActive()) return;
        string tier = cbAgentTier.getActiveId();
        string text = readAgentPromptTextView().strip();
        string def = defaultAgentPromptForTier(tier);
        if (text == def.strip()) clearAgentPromptOverride(tier);
        else setAgentPromptOverride(tier, text);
    }

    void loadAgentPromptIntoEditor() {
        string tier = cbAgentTier.getActiveId();
        setAgentPromptTextView(effectiveAgentPromptForTier(tier));
        applyAgentPromptLockState();
    }

    void onAgentTierChanged() {
        persistAgentPromptEditorToStore();
        loadAgentPromptIntoEditor();
        string tier = cbAgentTier.getActiveId();
        if (tier == AGENT_TIER_CUSTOM && swAgentPromptLock.getActive()) {
            _suppressUi = true;
            swAgentPromptLock.setActive(false);
            _suppressUi = false;
            applyAgentPromptLockState();
        }
    }

    void restoreAgentPromptDefault() {
        clearAgentPromptOverride(cbAgentTier.getActiveId());
        loadAgentPromptIntoEditor();
    }

    void updatePromptCountLabel() {
        ensureDefaults(modernData());
        auto cats = modernData().aiPrompts.categories;
        lblPromptCount.setText(format("%d categories, %d prompts",
            modernCountCategories(cats), modernCountCommands(cats)));
    }

    void confirmRestoreDefaultPrompts() {
        auto conf = new Dialog();
        conf.setTitle("Restore defaults");
        conf.setTransientFor(cast(Window)getToplevel());
        conf.setModal(true);
        auto lbl = new Label("Replace all prompt categories with the built-in defaults?");
        lbl.setMarginStart(12);
        lbl.setMarginEnd(12);
        lbl.setMarginTop(12);
        lbl.setMarginBottom(12);
        conf.getContentArea().packStart(lbl, false, false, 0);
        conf.addButton("Cancel", ResponseType.CANCEL);
        conf.addButton("Restore", ResponseType.OK);
        conf.showAll();
        if (conf.run() != ResponseType.OK) {
            conf.destroy();
            return;
        }
        conf.destroy();
        restoreDefaultAiPrompts();
        updatePromptCountLabel();
    }

    void applySavedServer() {
        string id = cbSavedServer.getActiveId();
        if (id.length == 0) return;
        auto sp = findAiServerById(id);
        if (sp is null) return;
        string srvProv = normalizeProviderId(sp.provider);
        if (srvProv != normalizeProviderId(cbProvider.getActiveId())) {
            _suppressUi = true;
            cbProvider.setActiveId(srvProv);
            updateProviderHint();
            refreshSavedServerCombo();
            cbSavedServer.setActiveId(id);
            _suppressUi = false;
        }
        eBase.setText(sp.baseUrl);
        if (sp.defaultModel.length > 0)
            setModelComboValue(sp.defaultModel);
    }

    void onProviderChanged(bool refreshModels) {
        string id = cbProvider.getActiveId();
        auto pr = aiProviderPreset(id);
        updateProviderHint();
        refreshSavedServerCombo();
        string sid = cbSavedServer.getActiveId();
        if (sid.length > 0) {
            applySavedServer();
        } else {
            eBase.setText(pr.defaultBaseUrl);
            if (pr.defaultModel.length > 0)
                setModelComboValue(pr.defaultModel);
            else {
                cbModel.removeAll();
                lblModelStatus.setText("");
            }
        }
        if (refreshModels && pr.supportsModelList)
            refreshModelsFromUi();
    }

    void testApiKeyFromUi() {
        auto ai = readAiFromUi();
        lblModelStatus.setText("Checking API key…");
        auto res = verifyApiKey(ai);
        lblModelStatus.setText(res.ok ? ("✓ " ~ res.message) : ("✗ " ~ res.message));
    }

    void refreshModelsFromUi() {
        auto ai = readAiFromUi();
        string keepModel = ai.model;
        lblModelStatus.setText("Checking key and loading models…");
        auto res = listAvailableModels(ai);
        cbModel.removeAll();
        if (res.ok) {
            foreach (m; res.models)
                cbModel.append(m, m);
            string status = format("%d model(s) loaded", res.models.length);
            if (res.note.length > 0) status ~= " — " ~ res.note;
            lblModelStatus.setText(status);
            bool found;
            foreach (m; res.models) if (m == keepModel) found = true;
            if (found) {
                int i = 0;
                foreach (m; res.models) {
                    if (m == keepModel) {
                        cbModel.setActive(i);
                        break;
                    }
                    i++;
                }
            } else if (res.models.length > 0) {
                cbModel.setActive(0);
            }
            if (keepModel.length > 0) {
                auto ent = cast(Entry)cbModel.getChild();
                if (ent !is null) ent.setText(keepModel);
            }
        } else {
            lblModelStatus.setText(res.error);
            if (keepModel.length > 0)
                setModelComboValue(keepModel);
        }
    }

    void loadApiKeyFromFile() {
        auto dlg = new FileChooserDialog("Select API key file", cast(Window)getToplevel(),
            FileChooserAction.OPEN, ["Open", "Cancel"]);
        dlg.setModal(true);
        if (dlg.run() != ResponseType.OK) {
            dlg.destroy();
            return;
        }
        string path = dlg.getFilename();
        dlg.destroy();
        if (path.length == 0) return;
        try {
            eApiKey.setText(readText(path).strip());
        } catch (Exception e) {
            lblModelStatus.setText("Could not read key file: " ~ e.msg);
        }
    }

public:
    void loadFromStore() {
        _suppressUi = true;
        auto ai = modernData().ai;
        ai.provider = normalizeProviderId(ai.provider);
        cbProvider.setActiveId(ai.provider);
        eBase.setText(ai.baseUrl);
        setModelComboValue(ai.model);
        eApiKey.setText(ai.apiKey);
        swPersist.setActive(ai.persistHistory);
        swAgent.setActive(ai.agentExec);
        cbAgentTier.setActiveId(normalizeAgentPromptTier(ai.agentPromptTier));
        swAgentPromptLock.setActive(ai.agentPromptLocked);
        loadAgentPromptIntoEditor();
        auto qb = modernData().quickBar;
        swBarPrompts.setActive(qb.showPrompts);
        updatePromptCountLabel();
        swBarAgent.setActive(qb.showAgent);
        swBarAiChat.setActive(qb.showAiChat);
        updateProviderHint();
        refreshSavedServerCombo();
        if (ai.activeAiServerId.length > 0 && findAiServerById(ai.activeAiServerId) !is null)
            applySavedServer();
        else if (ai.baseUrl.length == 0)
            onProviderChanged(false);
        _suppressUi = false;
    }

    void saveToStore() {
        modernData().ai.provider = normalizeProviderId(cbProvider.getActiveId());
        modernData().ai.activeAiServerId = cbSavedServer.getActiveId();
        modernData().ai.baseUrl = normalizeAiBaseUrl(eBase.getText().strip(), cbProvider.getActiveId());
        modernData().ai.model = cbModel.getActiveText().strip();
        modernData().ai.apiKey = eApiKey.getText().strip();
        modernData().ai.persistHistory = swPersist.getActive();
        modernData().ai.agentExec = swAgent.getActive();
        persistAgentPromptEditorToStore();
        modernData().ai.agentPromptTier = normalizeAgentPromptTier(cbAgentTier.getActiveId());
        modernData().ai.agentPromptLocked = swAgentPromptLock.getActive();
        modernData().quickBar.showPrompts = swBarPrompts.getActive();
        modernData().quickBar.showAgent = swBarAgent.getActive();
        modernData().quickBar.showAiChat = swBarAiChat.getActive();
        applyProviderDefaults(modernData().ai, false);
        saveModernStore();
        notifyModernDataChanged();
    }
}

class NetworkPreferencesPage : Box {

    Switch swBarSsh;

public:
    this() {
        super(Orientation.VERTICAL, 12);
        setMarginStart(18);
        setMarginEnd(18);
        setMarginTop(18);
        setMarginBottom(18);

        auto intro = new Label(
            "SSH hosts for the quick panel «SSH» menu. Organize servers in categories "
            ~ "and subcategories (same nested menu style as Commands).");
        intro.setLineWrap(true);
        intro.setXalign(0);
        packStart(intro, false, false, 0);

        auto barTitle = new Label("Quick bar");
        barTitle.setXalign(0);
        packStart(barTitle, false, false, 0);

        swBarSsh = new Switch();
        packStart(makeSwitchRow("Show «SSH» on panel", swBarSsh), false, false, 0);

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto btnSsh = new Button("SSH servers…");
        btnSsh.setHalign(Align.START);
        packStart(btnSsh, false, false, 0);

        btnSsh.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showSshHubDialog(w, null, null);
        });

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto note = new Label("Shell commands: Preferences → Commands. Data: ~/.config/aiterm/modern.json");
        note.setLineWrap(true);
        note.setXalign(0);
        packStart(note, false, false, 0);
        loadFromStore();
    }

    void loadFromStore() {
        swBarSsh.setActive(modernData().quickBar.showSsh);
    }

    void saveToStore() {
        modernData().quickBar.showSsh = swBarSsh.getActive();
        saveModernStore();
        notifyModernDataChanged();
    }
}

class CommandsPreferencesPage : Box {

    Switch swBarCommands;
    Label lblCommandCount;

public:
    this() {
        super(Orientation.VERTICAL, 12);
        setMarginStart(18);
        setMarginEnd(18);
        setMarginTop(18);
        setMarginBottom(18);

        auto intro = new Label(
            "Bash command snippets for the quick panel. Categories may contain subcategories "
            ~ "(e.g. Apps → Docker). Default set includes network, files, system, and apps.");
        intro.setLineWrap(true);
        intro.setXalign(0);
        packStart(intro, false, false, 0);

        auto barTitle = new Label("Quick bar");
        barTitle.setXalign(0);
        packStart(barTitle, false, false, 0);

        swBarCommands = new Switch();
        packStart(makeSwitchRow("Show «Commands» on panel", swBarCommands), false, false, 0);

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        lblCommandCount = new Label("");
        lblCommandCount.setXalign(0);
        packStart(lblCommandCount, false, false, 0);

        auto btnEdit = new Button("Edit categories and commands…");
        btnEdit.setHalign(Align.START);
        packStart(btnEdit, false, false, 0);

        auto btnRestore = new Button("Restore default commands");
        btnRestore.setHalign(Align.START);
        btnRestore.setTooltipText("Replace all categories and commands with the built-in default set");
        packStart(btnRestore, false, false, 0);

        btnEdit.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showBashCommandsHubDialog(w, delegate() { updateCommandCountLabel(); });
        });
        btnRestore.addOnClicked(delegate(Button) { confirmRestoreDefaults(); });

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto note = new Label("Data file: ~/.config/aiterm/modern.json (bashSnippets)");
        note.setLineWrap(true);
        note.setXalign(0);
        packStart(note, false, false, 0);
        loadFromStore();
    }

private:
    void updateCommandCountLabel() {
        ensureDefaults(modernData());
        auto cats = modernData().bashSnippets;
        lblCommandCount.setText(format("%d categories, %d commands",
            modernCountCategories(cats), modernCountCommands(cats)));
    }

    void confirmRestoreDefaults() {
        auto conf = new Dialog();
        conf.setTitle("Restore defaults");
        conf.setTransientFor(cast(Window)getToplevel());
        conf.setModal(true);
        auto lbl = new Label("Replace all command categories with the built-in defaults?");
        lbl.setMarginStart(12);
        lbl.setMarginEnd(12);
        lbl.setMarginTop(12);
        lbl.setMarginBottom(12);
        conf.getContentArea().packStart(lbl, false, false, 0);
        conf.addButton("Cancel", ResponseType.CANCEL);
        conf.addButton("Restore", ResponseType.OK);
        conf.showAll();
        if (conf.run() != ResponseType.OK) {
            conf.destroy();
            return;
        }
        conf.destroy();
        restoreDefaultBashSnippets();
        updateCommandCountLabel();
    }

public:
    void loadFromStore() {
        ensureDefaults(modernData());
        swBarCommands.setActive(modernData().quickBar.showBashCheat);
        updateCommandCountLabel();
    }

    void saveToStore() {
        modernData().quickBar.showBashCheat = swBarCommands.getActive();
        saveModernStore();
        notifyModernDataChanged();
    }
}
