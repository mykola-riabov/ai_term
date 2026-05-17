/*
 * Preferences page: Modern Tilix (AI API, data hubs).
 */
module gx.tilix.modern.prefpage;

import std.file;
import std.string;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Entry;
import gtk.FileChooserDialog;
import gtk.Grid;
import gtk.Label;
import gtk.Separator;
import gtk.Switch;
import gtk.Window;
import gtk.c.types;

import gx.tilix.modern.aiproviders;
import gx.tilix.modern.chathub;
import gx.tilix.modern.llm;
import gx.tilix.modern.prompthub;
import gx.tilix.modern.sshhub;
import gx.tilix.modern.store;

class ModernPreferencesPage : Box {

    ComboBoxText cbProvider;
    Label lblProviderHint;
    Entry eBase;
    ComboBoxText cbModel;
    Button btnRefreshModels;
    Label lblModelStatus;
    Entry eApiKey;
    Button btnKeyFromFile;
    Button btnTestKey;
    Switch swPersist;
    Switch swAgent;
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

        auto lblPersist = new Label("Persist AI chats");
        swPersist = new Switch();
        auto boxP = new Box(Orientation.HORIZONTAL, 6);
        boxP.packStart(lblPersist, false, false, 0);
        boxP.packEnd(swPersist, false, false, 0);
        grid.attach(boxP, 0, row, 2, 1);
        row++;

        auto lblAgent = new Label("Run model commands in terminal (agent, ```bash``` blocks)");
        swAgent = new Switch();
        auto boxA = new Box(Orientation.HORIZONTAL, 6);
        boxA.packStart(lblAgent, false, false, 0);
        boxA.packEnd(swAgent, false, false, 0);
        grid.attach(boxA, 0, row, 2, 1);
        row++;

        packStart(grid, false, false, 0);

        cbProvider.addOnChanged(delegate(ComboBoxText) {
            if (_suppressUi) return;
            onProviderChanged(true);
        });
        btnRefreshModels.addOnClicked(delegate(Button) { refreshModelsFromUi(); });
        btnKeyFromFile.addOnClicked(delegate(Button) { loadApiKeyFromFile(); });
        btnTestKey.addOnClicked(delegate(Button) { testApiKeyFromUi(); });

        packStart(new Separator(Orientation.HORIZONTAL), false, false, 0);

        auto hubLbl = new Label("Quick bar: servers and prompts. Chats: here or in the AI Chat window.");
        hubLbl.setLineWrap(true);
        hubLbl.setXalign(0);
        packStart(hubLbl, false, false, 0);

        auto hubBox = new Box(Orientation.VERTICAL, 6);
        auto btnSsh = new Button("SSH servers…");
        auto btnPrompts = new Button("AI prompts…");
        auto btnChats = new Button("AI chats…");
        btnSsh.setHalign(Align.START);
        btnPrompts.setHalign(Align.START);
        btnChats.setHalign(Align.START);
        hubBox.packStart(btnSsh, false, false, 0);
        hubBox.packStart(btnPrompts, false, false, 0);
        hubBox.packStart(btnChats, false, false, 0);
        packStart(hubBox, false, false, 0);

        btnSsh.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showSshHubDialog(w, null, null);
        });
        btnPrompts.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showAiPromptHubDialog(w, null);
        });
        btnChats.addOnClicked(delegate(Button) {
            auto w = cast(Window)getToplevel();
            showAiChatsHubDialog(w, null);
        });
        packStart(new Label("Data file: ~/.config/tilix/modern.json"), false, false, 0);
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

    void onProviderChanged(bool refreshModels) {
        string id = cbProvider.getActiveId();
        auto pr = aiProviderPreset(id);
        eBase.setText(pr.defaultBaseUrl);
        updateProviderHint();
        if (pr.defaultModel.length > 0)
            setModelComboValue(pr.defaultModel);
        else {
            cbModel.removeAll();
            lblModelStatus.setText("");
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
        updateProviderHint();
        if (ai.baseUrl.length == 0)
            onProviderChanged(false);
        _suppressUi = false;
    }

    void saveToStore() {
        modernData().ai.provider = normalizeProviderId(cbProvider.getActiveId());
        modernData().ai.baseUrl = eBase.getText().strip();
        modernData().ai.model = cbModel.getActiveText().strip();
        modernData().ai.apiKey = eApiKey.getText().strip();
        modernData().ai.persistHistory = swPersist.getActive();
        modernData().ai.agentExec = swAgent.getActive();
        applyProviderDefaults(modernData().ai, false);
        saveModernStore();
        notifyModernDataChanged();
    }
}
