/*
 * SSH host manager with nested categories for the quick bar «SSH» menu.
 */
module gx.aiterm.modern.sshhub;

import std.conv;
import std.string;

import gtk.Box;
import gtk.Button;
import gtk.CheckButton;
import gtk.ComboBoxText;
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

private ref ModernCategory[] sshCategories() {
    return modernData().sshSnippets;
}

private ModernCategory* findSshCategoryIn(ref ModernCategory[] cats, string id) {
    foreach (ref c; cats) {
        if (c.id == id) return &c;
        auto p = findSshCategoryIn(c.children, id);
        if (p !is null) return p;
    }
    return null;
}

private ModernCategory* findSshCategory(string id) {
    return findSshCategoryIn(sshCategories(), id);
}

private bool removeSshCategoryById(ref ModernCategory[] cats, string id) {
    ModernCategory[] kept;
    bool removed;
    foreach (ref c; cats) {
        if (c.id == id) {
            removed = true;
            continue;
        }
        if (removeSshCategoryById(c.children, id))
            removed = true;
        kept ~= c;
    }
    cats = kept;
    return removed;
}

private void removeSshHostById(string hostId) {
    void strip(ref ModernCategory c) {
        ModernSshHost[] kept;
        foreach (h; c.sshHosts) if (h.id != hostId) kept ~= h;
        c.sshHosts = kept;
        foreach (ref ch; c.children) strip(ch);
    }
    foreach (ref c; sshCategories()) strip(c);
}

private void fillCategoryCombo(ComboBoxText cb) {
    cb.removeAll();
    foreach (ref c; sshCategories()) {
        if (c.children.length == 0)
            cb.append(c.id, c.name);
        foreach (ref ch; c.children)
            cb.append(ch.id, c.name ~ " / " ~ ch.name);
    }
}

void showSshHubDialog(Window parent, TerminalFeedFn feed, VoidFn onChanged) {
    auto dlg = new Dialog();
    dlg.setTitle("SSH servers");
    if (parent !is null) dlg.setTransientFor(parent);
    dlg.setModal(true);
    dlg.setDefaultSize(560, 480);
    auto content = dlg.getContentArea();
    content.setOrientation(Orientation.VERTICAL);
    content.setSpacing(8);
    content.setMarginStart(12);
    content.setMarginEnd(12);
    content.setMarginTop(12);
    content.setMarginBottom(12);

    auto hint = new Label(
        "Categories and SSH hosts for the quick bar «SSH» menu. "
        ~ "Use subcategories to group servers (e.g. Production → web-01). "
        ~ "Connect runs ssh in the active terminal.");
    hint.setLineWrap(true);
    hint.setXalign(0);
    content.packStart(hint, false, false, 0);

    auto scroll = new ScrolledWindow();
    scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
    scroll.setMinContentHeight(260);
    auto list = new ListBox();
    list.setSelectionMode(SelectionMode.SINGLE);
    scroll.add(list);
    content.packStart(scroll, true, true, 0);

    void addCategoryRows(ModernCategory cat, string indent, string rowPrefix) {
        auto catRow = new ListBoxRow();
        catRow.setName(rowPrefix ~ cat.id);
        auto catLbl = new Label(indent ~ "▸ " ~ cat.name);
        catLbl.setXalign(0);
        catRow.add(catLbl);
        list.add(catRow);
        foreach (h; cat.sshHosts) {
            string lab = h.label.length > 0 ? h.label : h.host;
            string sub = h.user.length > 0 ? h.user ~ "@" ~ h.host : h.host;
            if (h.port != 22 && h.port > 0) sub ~= ":" ~ to!string(h.port);
            auto hostRow = new ListBoxRow();
            hostRow.setName("host:" ~ cat.id ~ ":" ~ h.id);
            auto box = new Box(Orientation.VERTICAL, 2);
            auto lbl = new Label(indent ~ "   • " ~ lab);
            lbl.setXalign(0);
            box.packStart(lbl, false, false, 0);
            auto subLbl = new Label(indent ~ "      " ~ sub);
            subLbl.setXalign(0);
            subLbl.setOpacity(0.7);
            box.packStart(subLbl, false, false, 0);
            hostRow.add(box);
            list.add(hostRow);
        }
        foreach (ch; cat.children)
            addCategoryRows(ch, indent ~ "  ", "sub:");
    }

    void refreshList() {
        foreach (w; getChildren!Widget(list, false)) w.destroy();
        foreach (cat; sshCategories())
            addCategoryRows(cat, "", "cat:");
        list.showAll();
    }

    void editCategory(string catId, string parentId = "") {
        ModernCategory c;
        bool isNew = catId.length == 0;
        if (!isNew) {
            auto p = findSshCategory(catId);
            if (p is null) return;
            c = *p;
        } else {
            c.id = genId();
        }
        auto ed = new Dialog();
        ed.setTitle(isNew ? (parentId.length > 0 ? "New subcategory" : "New category")
                         : "Edit category");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto eName = new Entry();
        eName.setText(c.name);
        eName.setPlaceholderText(parentId.length > 0 ? "e.g. Production, Lab" : "e.g. Servers, Cloud");
        auto box = new Box(Orientation.VERTICAL, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        if (parentId.length > 0) {
            auto pp = findSshCategory(parentId);
            string parentName = pp !is null ? pp.name : "";
            auto lblParent = new Label("Parent: " ~ parentName);
            lblParent.setXalign(0);
            box.packStart(lblParent, false, false, 0);
        }
        box.packStart(new Label("Category name"), false, false, 0);
        box.packStart(eName, false, false, 0);
        ed.getContentArea().packStart(box, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        c.name = eName.getText().strip();
        if (isNew) {
            if (parentId.length > 0) {
                auto pp = findSshCategory(parentId);
                if (pp !is null) pp.children ~= c;
            } else {
                sshCategories() ~= c;
            }
        } else {
            auto p = findSshCategory(catId);
            if (p !is null) p.name = c.name;
        }
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    void editHost(string catId, string hostId) {
        auto cp = findSshCategory(catId);
        if (cp is null && catId.length > 0) return;
        ModernSshHost host;
        bool isNew = hostId.length == 0;
        if (!isNew && cp !is null) {
            ModernSshHost* hp;
            foreach (ref h; cp.sshHosts)
                if (h.id == hostId) { hp = &h; break; }
            if (hp is null) return;
            host = *hp;
        } else if (hostId.length > 0) {
            auto hp = findSshHostById(hostId);
            if (hp is null) return;
            host = *hp;
        }

        auto ed = new Dialog();
        ed.setTitle(isNew ? "Add SSH server" : "Edit SSH server");
        ed.setTransientFor(dlg);
        ed.setModal(true);
        auto cbCat = new ComboBoxText();
        fillCategoryCombo(cbCat);
        if (catId.length > 0) cbCat.setActiveId(catId);

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

        auto outer = new Box(Orientation.VERTICAL, 8);
        outer.packStart(new Label("Category"), false, false, 0);
        outer.packStart(cbCat, false, false, 0);
        outer.packStart(g, true, true, 0);
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

        ed.getContentArea().packStart(outer, true, true, 0);
        ed.addButton("Cancel", ResponseType.CANCEL);
        ed.addButton("Save", ResponseType.OK);
        ed.setDefaultResponse(ResponseType.OK);
        ed.showAll();
        if (ed.run() != ResponseType.OK) {
            ed.destroy();
            return;
        }
        string targetCatId = cbCat.getActiveId();
        if (targetCatId.length == 0) {
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
        if (host.host.length == 0) {
            ed.destroy();
            return;
        }
        removeSshHostById(host.id);
        auto tp = findSshCategory(targetCatId);
        if (tp !is null) tp.sshHosts ~= host;
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
        ed.destroy();
    }

    auto rowBtns = new Box(Orientation.HORIZONTAL, 6);
    auto btnAddCat = new Button("Add category");
    auto btnAddSub = new Button("Add subcategory");
    auto btnAddHost = new Button("Add server");
    auto btnEdit = new Button("Edit");
    auto btnDel = new Button("Delete");
    auto btnConnect = new Button("Connect");
    rowBtns.packStart(btnAddCat, false, false, 0);
    rowBtns.packStart(btnAddSub, false, false, 0);
    rowBtns.packStart(btnAddHost, false, false, 0);
    rowBtns.packStart(btnEdit, false, false, 0);
    rowBtns.packStart(btnDel, false, false, 0);
    rowBtns.packEnd(btnConnect, false, false, 0);
    content.packStart(rowBtns, false, false, 0);

    btnAddCat.addOnClicked(delegate(Button) { editCategory("", ""); });
    btnAddSub.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        string parentId = "";
        if (r !is null && r.getName().startsWith("cat:"))
            parentId = r.getName()[4 .. $];
        else if (sshCategories().length > 0)
            parentId = sshCategories()[0].id;
        editCategory("", parentId);
    });
    btnAddHost.addOnClicked(delegate(Button) {
        string catId = "";
        auto r = list.getSelectedRow();
        if (r !is null) {
            string name = r.getName();
            if (name.startsWith("host:")) {
                auto parts = name[5 .. $].split(":");
                if (parts.length >= 1) catId = parts[0];
            } else if (name.startsWith("sub:"))
                catId = name[4 .. $];
            else if (name.startsWith("cat:"))
                catId = name[4 .. $];
        }
        if (catId.length == 0) {
            foreach (ref c; sshCategories()) {
                if (c.children.length > 0) {
                    catId = c.children[0].id;
                    break;
                }
                catId = c.id;
                break;
            }
        }
        editHost(catId, "");
    });
    btnEdit.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:")) editCategory(name[4 .. $], "");
        else if (name.startsWith("sub:")) editCategory(name[4 .. $], "");
        else if (name.startsWith("host:")) {
            auto parts = name[5 .. $].split(":");
            if (parts.length >= 2) editHost(parts[0], parts[1]);
        }
    });
    btnDel.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (name.startsWith("cat:") || name.startsWith("sub:")) {
            string id = name[4 .. $];
            removeSshCategoryById(sshCategories(), id);
        } else if (name.startsWith("host:")) {
            auto parts = name[5 .. $].split(":");
            if (parts.length >= 2) {
                auto cp = findSshCategory(parts[0]);
                if (cp !is null) {
                    ModernSshHost[] kept;
                    foreach (h; cp.sshHosts) if (h.id != parts[1]) kept ~= h;
                    cp.sshHosts = kept;
                }
            }
        } else return;
        saveModernStore();
        refreshList();
        notifyModernDataChanged();
        if (onChanged !is null) onChanged();
    });
    btnConnect.addOnClicked(delegate(Button) {
        auto r = list.getSelectedRow();
        if (r is null) return;
        string name = r.getName();
        if (!name.startsWith("host:")) return;
        auto parts = name[5 .. $].split(":");
        if (parts.length < 2) return;
        auto hp = findSshHostById(parts[1]);
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
