/*
 * Saved LM Studio / Ollama servers (name → base URL).
 */
module gx.aiterm.modern.aiservershub;

import std.string;

import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Dialog;
import gtk.Entry;
import gtk.Grid;
import gtk.Label;
import gtk.ListBox;
import gtk.ListBoxRow;
import gtk.ScrolledWindow;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gx.gtk.util;
import gx.aiterm.modern.aiproviders;
import gx.aiterm.modern.store;

alias VoidFn = void delegate();

private ModernAiServer* findAiServerByIdLocal(string id) {
    return findAiServerById(id);
}

void showAiServersHubDialog(Window parent, string defaultProvider, VoidFn onChanged) {
    string defaultProv = normalizeProviderId(defaultProvider);
    if (!providerSupportsSavedServers(defaultProv)) defaultProv = "lmstudio";
    auto dlg = new Dialog();
    dlg.setTitle("AI servers (LM Studio / Ollama)");
    if (parent !is null) dlg.setTransientFor(parent);
    dlg.setModal(true);
    dlg.setDefaultSize(540, 420);
    auto content = dlg.getContentArea();
    content.setOrientation(Orientation.VERTICAL);
    content.setSpacing(8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);

    auto intro = new Label(
        "Save remote or local API endpoints with a short name. " ~
        "Pick them in Preferences -> AI.");
    intro.setLineWrap(true);
    intro.setXalign(0);
    content.packStart(intro, false, false, 0);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(220);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void refreshList() {
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        foreach (ref s; modernData().aiServers) {
            auto pr = aiProviderPreset(s.provider);
            string lab = s.label.length > 0 ? s.label : s.baseUrl;
            auto row = new ListBoxRow();
            auto box = new Box(Orientation.VERTICAL, 2);
            box.packStart(new Label(lab), false, false, 0);
            auto subLbl = new Label(pr.label ~ " — " ~ s.baseUrl);
            subLbl.setOpacity(0.7);
            box.packStart(subLbl, false, false, 0);
            row.add(box);
            row.setName(s.id);
            list.add(row);
        }
        list.showAll();
    }

    void editServer(string serverId, bool isNew) {
        ModernAiServer srv;
        if (!isNew) {
            auto sp = findAiServerByIdLocal(serverId);
            if (sp is null) return;
            srv = *sp;
        } else {
            srv.provider = defaultProv;
        }

        auto ed = new Dialog();
        ed.setTitle(isNew ? "Add AI server" : "Edit AI server");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto g = new Grid();
        g.setColumnSpacing(10);
        g.setRowSpacing(8);
        g.setMarginStart(12);
        g.setMarginEnd(12);
        g.setMarginTop(12);
        g.setMarginBottom(12);
        int row = 0;

        Entry eLabel = new Entry();
        ComboBoxText cbProvider = new ComboBoxText();
        cbProvider.append("lmstudio", "LM Studio");
        cbProvider.append("ollama", "Ollama");
        Entry eBase = new Entry();
        Entry eModel = new Entry();

        eLabel.setText(srv.label);
        eLabel.setPlaceholderText("e.g. Home server");
        cbProvider.setActiveId(normalizeProviderId(srv.provider));
        eBase.setText(srv.baseUrl);
        eBase.setPlaceholderText("192.168.1.10:11434 or http://host:1234/v1");
        eModel.setText(srv.defaultModel);
        eModel.setPlaceholderText("Optional default model name");

        void attach(string cap, Widget w) {
            g.attach(new Label(cap), 0, row, 1, 1);
            g.attach(w, 1, row, 1, 1);
            row++;
        }
        attach("Name", eLabel);
        attach("Provider", cbProvider);
        attach("API base URL", eBase);
        attach("Default model", eModel);

        ed.getContentArea().packStart(g, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.setDefaultResponse(ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        srv.label = eLabel.getText().strip();
        srv.provider = normalizeProviderId(cbProvider.getActiveId());
        srv.baseUrl = normalizeAiBaseUrl(eBase.getText().strip(), srv.provider);
        srv.defaultModel = eModel.getText().strip();
        if (srv.baseUrl.length == 0) {
            ed.destroy();
            return;
        }
        if (srv.id.length == 0) srv.id = genId();
        if (isNew) {
            modernData().aiServers ~= srv;
        } else {
            foreach (i, ref h; modernData().aiServers) {
                if (h.id == serverId) {
                    modernData().aiServers[i] = srv;
                    break;
                }
            }
        }
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    auto rowBtns = new Box(Orientation.HORIZONTAL, 6);
    auto btnAdd = new Button("Add");
    auto btnEdit = new Button("Edit");
    auto btnDel = new Button("Delete");
    rowBtns.packStart(btnAdd, false, false, 0);
    rowBtns.packStart(btnEdit, false, false, 0);
    rowBtns.packStart(btnDel, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnAdd.addOnClicked(delegate(Button) { editServer("", true); });
    btnEdit.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        editServer(r.getName(), false);
    });
    btnDel.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string id = r.getName();
        ModernAiServer[] next;
        foreach (s; modernData().aiServers) if (s.id != id) next ~= s;
        modernData().aiServers = next;
        if (modernData().ai.activeAiServerId == id)
            modernData().ai.activeAiServerId = "";
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
    });

    dlg.addButton("Close", ResponseType.CLOSE);
    refreshList();
    dlg.showAll();
    dlg.run();
    dlg.destroy();
}
