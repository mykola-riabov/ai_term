/*
 * SSH host manager (ported from Win Tileterm ssh hub).
 */
module gx.aiterm.modern.sshhub;

import std.conv;
import std.string;

import gtk.Box;
import gtk.Button;
import gtk.CheckButton;
import gtk.Dialog;
import gtk.Entry;
import gtk.Grid;
import gtk.Label;
import gtk.ListBox;
import gtk.ListBoxRow;
import gtk.ScrolledWindow;
import gtk.SpinButton;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gx.gtk.util;
import gx.aiterm.modern.store;

alias TerminalFeedFn = void delegate(string text);
alias VoidFn = void delegate();

private ModernSshHost* findSshHostById(string id) {
    foreach (ref h; modernData().sshHosts) {
        if (h.id == id) return &h;
    }
    return null;
}

void showSshHubDialog(Window parent, TerminalFeedFn feed, VoidFn onChanged) {
    auto dlg = new Dialog();
    dlg.setTitle("SSH servers");
    if (parent !is null) dlg.setTransientFor(parent);
    dlg.setModal(true);
    dlg.setDefaultSize(520, 420);
    auto content = dlg.getContentArea();
    content.setOrientation(Orientation.VERTICAL);
    content.setSpacing(8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(220);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void refreshList() {
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        foreach (ref h; modernData().sshHosts) {
            string lab = h.label.length > 0 ? h.label : h.host;
            string sub = h.user.length > 0 ? h.user ~ "@" ~ h.host : h.host;
            if (h.port != 22 && h.port > 0) sub ~= ":" ~ to!string(h.port);
            auto row = new ListBoxRow();
            auto box = new Box(Orientation.VERTICAL, 2);
            box.packStart(new Label(lab), false, false, 0);
            auto subLbl = new Label(sub);
            subLbl.setOpacity(0.7);
            box.packStart(subLbl, false, false, 0);
            row.add(box);
            row.setName(h.id);
            list.add(row);
        }
        list.showAll();
    }

    void editHost(string hostId, bool isNew) {
        ModernSshHost host;
        if (!isNew) {
            auto hp = findSshHostById(hostId);
            if (hp is null) return;
            host = *hp;
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? "Add SSH server" : "Edit SSH server");
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
        Entry eHost = new Entry();
        Entry eUser = new Entry();
        SpinButton ePort = new SpinButton(1, 65535, 1);
        ePort.setValue(host.port > 0 ? host.port : 22);
        Entry eIdentity = new Entry();
        CheckButton cbAgent = new CheckButton("Use ssh-agent");
        CheckButton cbKeyOnly = new CheckButton("Key only (BatchMode)");
        Entry eExtra = new Entry();

        eLabel.setText(host.label);
        eHost.setText(host.host);
        eUser.setText(host.user);
        eIdentity.setText(host.identityFile);
        eIdentity.setPlaceholderText("~/.ssh/id_ed25519");
        cbAgent.setActive(host.useAgent);
        cbKeyOnly.setActive(host.keyOnly);
        eExtra.setText(host.extraArgs);
        eExtra.setPlaceholderText("-o StrictHostKeyChecking=no");

        void attach(string cap, Widget w) {
            g.attach(new Label(cap), 0, row, 1, 1);
            g.attach(w, 1, row, 1, 1);
            row++;
        }
        attach("Label", eLabel);
        attach("Host", eHost);
        attach("User", eUser);
        attach("Port", ePort);
        attach("Private key", eIdentity);
        g.attach(cbAgent, 1, row, 1, 1);
        row++;
        g.attach(cbKeyOnly, 1, row, 1, 1);
        row++;
        attach("Extra args", eExtra);

        ed.getContentArea().packStart(g, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.setDefaultResponse(ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        host.label = eLabel.getText().strip();
        host.host = eHost.getText().strip();
        host.user = eUser.getText().strip();
        host.port = cast(int)ePort.getValue();
        host.identityFile = eIdentity.getText().strip();
        host.useAgent = cbAgent.getActive();
        host.keyOnly = cbKeyOnly.getActive();
        host.extraArgs = eExtra.getText().strip();
        if (host.id.length == 0) host.id = genId();
        if (isNew) {
            modernData().sshHosts ~= host;
        } else {
            foreach (i, ref h; modernData().sshHosts) {
                if (h.id == hostId) {
                    modernData().sshHosts[i] = host;
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
    auto btnConnect = new Button("Connect");
    rowBtns.packStart(btnAdd, false, false, 0);
    rowBtns.packStart(btnEdit, false, false, 0);
    rowBtns.packStart(btnDel, false, false, 0);
    rowBtns.packEnd(btnConnect, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnAdd.addOnClicked(delegate(Button) { editHost("", true); });
    btnEdit.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        editHost(r.getName(), false);
    });
    btnDel.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string id = r.getName();
        ModernSshHost[] next;
        foreach (h; modernData().sshHosts) if (h.id != id) next ~= h;
        modernData().sshHosts = next;
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
    });
    btnConnect.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        auto hp = findSshHostById(r.getName());
        if (hp is null) return;
        if (feed !is null) feed(buildSshCommand(*hp));
        dlg.close();
    });

    dlg.addButton("Close", ResponseType.CLOSE);
    refreshList();
    dlg.showAll();
    dlg.run();
    dlg.destroy();
}
