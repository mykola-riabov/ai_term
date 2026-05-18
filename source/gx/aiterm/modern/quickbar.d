/*
 * Aiterm toolbar: GTK nested menus (category → subcategory → command) for quick data.
 * Manage lists in Preferences → AI / Network / Commands.
 */
module gx.aiterm.modern.quickbar;

import std.format;

import gio.Menu : GMenu = Menu;
import gio.SimpleAction;
import gio.SimpleActionGroup;

import gtk.Box;
import gtk.Button;
import gtk.Label;
import gtk.MenuButton;
import gtk.Popover;
import gtk.Separator;
import gtk.ToggleButton;
import gtk.Widget;
import gtk.Window;
import gtk.c.types;

import gx.gtk.util;
import gx.aiterm.modern.aichat;
import gx.aiterm.modern.store;

alias TerminalFeedFn = void delegate(string text);

private enum ModernMenuAction { FEED, PROMPT, SSH }

class ModernQuickBar : Box {

private:
    TerminalFeedFn _feed;
    ToggleButton _btnAgent;
    SimpleActionGroup _actions;
    int _actionSeq;
    ModernCommand[] _pickFeed;
    ModernCommand[] _pickPrompt;
    ModernSshHost[] _pickSsh;
    Popover _openPopover;

public:
    this(TerminalFeedFn feed) {
        super(Orientation.HORIZONTAL, 6);
        _feed = feed;
        getStyleContext().addClass("aiterm-modern-quickbar");
        setMarginStart(6);
        setMarginEnd(6);
        setMarginTop(4);
        setMarginBottom(4);
        rebuild();
    }

    void rebuild() {
        foreach (w; gx.gtk.util.getChildren!Widget(this, false)) w.destroy();
        resetActions();
        auto d = modernData();
        auto ui = d.quickBar;
        _pickFeed = [];
        _pickPrompt = [];
        _pickSsh = [];
        _openPopover = null;

        if (!modernQuickBarHasItems()) {
            setVisible(false);
            return;
        }
        setVisible(true);

        bool hasLeft;
        bool hasRight;

        auto lbl = new Label("Quick:");
        lbl.setMarginEnd(4);
        packStart(lbl, false, false, 0);

        if (ui.showBashCheat) {
            packStart(createCategoryMenuButton("Commands", d.bashSnippets, ModernMenuAction.FEED,
                "(no commands — Preferences → Commands)"), false, false, 0);
            hasLeft = true;
        }

        if (ui.showSsh) {
            packStart(createSshMenuButton("SSH", d.sshSnippets,
                "(no servers — Preferences → Network)"), false, false, 0);
            hasLeft = true;
        }

        if (ui.showPrompts) {
            packStart(createCategoryMenuButton("Prompts", d.aiPrompts.categories, ModernMenuAction.PROMPT,
                "(no prompts — Preferences → AI → Edit categories and prompts…)"), false, false, 0);
            hasLeft = true;
        }

        if (ui.showAgent) {
            _btnAgent = new ToggleButton("Agent");
            _btnAgent.setTooltipText("Run AI ```bash``` blocks in the active terminal");
            _btnAgent.setActive(d.ai.agentExec);
            _btnAgent.addOnToggled(delegate(ToggleButton b) {
                modernData().ai.agentExec = b.getActive();
                saveModernStore();
            });
            hasRight = true;
        }

        Button btnAi;
        if (ui.showAiChat) {
            btnAi = new Button("AI Chat");
            btnAi.setTooltipText("Open AI chat window");
            btnAi.addOnClicked(delegate(Button) {
                auto win = cast(Window)getToplevel();
                if (win !is null) {
                    showAiChatDialog(win);
                    reloadAiChatFromStore();
                }
            });
            hasRight = true;
        }

        if (hasLeft && hasRight)
            packStart(new Separator(Orientation.VERTICAL), false, false, 0);

        if (ui.showAgent)
            packStart(_btnAgent, false, false, 0);
        if (ui.showAiChat)
            packStart(btnAi, false, false, 0);

        showAll();
    }

private:
    void resetActions() {
        _actions = new SimpleActionGroup();
        _actionSeq = 0;
        auto noop = new SimpleAction("noop", null);
        noop.addOnActivate(delegate(GVariant, SimpleAction) { });
        _actions.addAction(noop);
    }

    void closeOpenPopover() {
        if (_openPopover !is null) {
            _openPopover.popdown();
            _openPopover = null;
        }
    }

    string bindMenuAction(ModernMenuAction kind, uint idx) {
        string name = format("m%d", _actionSeq++);
        auto action = new SimpleAction(name, null);
        ModernMenuAction k = kind;
        uint i = idx;
        action.addOnActivate(delegate(GVariant, SimpleAction) { onMenuPick(k, i); });
        _actions.addAction(action);
        return "modern." ~ name;
    }

    void onMenuPick(ModernMenuAction kind, uint idx) {
        switch (kind) {
        case ModernMenuAction.FEED:
            if (_feed !is null && idx < _pickFeed.length) {
                string t = _pickFeed[idx].text;
                if (t.length > 0) _feed(t);
            }
            break;
        case ModernMenuAction.PROMPT:
            if (idx < _pickPrompt.length) {
                auto win = cast(Window)getToplevel();
                if (win !is null) showAiChatDialog(win, _pickPrompt[idx].text);
            }
            break;
        case ModernMenuAction.SSH:
            if (_feed !is null && idx < _pickSsh.length)
                _feed(buildSshCommand(_pickSsh[idx]));
            break;
        default:
            break;
        }
        closeOpenPopover();
    }

    MenuButton createCategoryMenuButton(string title, ModernCategory[] categories,
            ModernMenuAction kind, string emptyHint) {
        auto mb = new MenuButton();
        mb.setLabel(title);
        mb.insertActionGroup("modern", _actions);
        GMenu model = buildCategoryRootMenu(categories, kind);
        if (!categoriesHaveContent(categories)) {
            model = new GMenu();
            model.append(emptyHint, "modern.noop");
        }
        mb.setPopover(wrapModelPopover(mb, model));
        return mb;
    }

    MenuButton createSshMenuButton(string title, ModernCategory[] categories, string emptyHint) {
        auto mb = new MenuButton();
        mb.setLabel(title);
        mb.insertActionGroup("modern", _actions);
        GMenu model = buildSshRootMenu(categories);
        if (!categoriesHaveContent(categories)) {
            model = new GMenu();
            model.append(emptyHint, "modern.noop");
        }
        mb.setPopover(wrapModelPopover(mb, model));
        return mb;
    }

    Popover wrapModelPopover(MenuButton mb, GMenu model) {
        auto pop = new Popover(mb, model);
        pop.setPosition(PositionType.BOTTOM);
        pop.addOnClosed(delegate(Popover p) {
            if (_openPopover is p) _openPopover = null;
        });
        pop.addOnMap(delegate(Widget) { _openPopover = pop; });
        return pop;
    }

    bool categoriesHaveContent(ModernCategory[] categories) {
        foreach (c; categories)
            if (modernCategoryHasContent(c)) return true;
        return false;
    }

    GMenu buildCategoryRootMenu(ModernCategory[] categories, ModernMenuAction kind) {
        auto root = new GMenu();
        foreach (cat; categories)
            appendCategoryToGMenu(root, cat, kind);
        return root;
    }

    /** Category → submenu; nested children become nested submenus (Apps → Docker → commands). */
    bool appendCategoryToGMenu(GMenu menu, ModernCategory cat, ModernMenuAction kind) {
        if (!modernCategoryHasContent(cat)) return false;

        auto sub = new GMenu();
        bool hasItems;

        foreach (cmd; cat.commands) {
            string lab = cmd.label.length > 0 ? cmd.label : cmd.text;
            uint idx = registerPick(kind, cmd);
            sub.append(lab, bindMenuAction(kind, idx));
            hasItems = true;
        }

        foreach (ch; cat.children) {
            if (appendCategoryToGMenu(sub, ch, kind))
                hasItems = true;
        }

        if (!hasItems) return false;
        menu.appendSubmenu(cat.name, sub);
        return true;
    }

    uint registerPick(ModernMenuAction kind, ModernCommand cmd) {
        switch (kind) {
        case ModernMenuAction.FEED:
            _pickFeed ~= cmd;
            return cast(uint)(_pickFeed.length - 1);
        case ModernMenuAction.PROMPT:
            _pickPrompt ~= cmd;
            return cast(uint)(_pickPrompt.length - 1);
        default:
            return 0;
        }
    }

    GMenu buildSshRootMenu(ModernCategory[] categories) {
        auto root = new GMenu();
        foreach (cat; categories)
            appendSshCategoryToGMenu(root, cat);
        return root;
    }

    bool appendSshCategoryToGMenu(GMenu menu, ModernCategory cat) {
        if (!modernCategoryHasContent(cat)) return false;

        auto sub = new GMenu();
        bool hasItems;

        foreach (h; cat.sshHosts) {
            string lab = h.label.length > 0 ? h.label : h.host;
            _pickSsh ~= h;
            uint idx = cast(uint)(_pickSsh.length - 1);
            sub.append(lab, bindMenuAction(ModernMenuAction.SSH, idx));
            hasItems = true;
        }

        foreach (ch; cat.children) {
            if (appendSshCategoryToGMenu(sub, ch))
                hasItems = true;
        }

        if (!hasItems) return false;
        menu.appendSubmenu(cat.name, sub);
        return true;
    }

}
