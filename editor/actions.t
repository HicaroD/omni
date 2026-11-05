package editor

fn mapping_action(name string) (Action, error) {
    if name == "write" {
        return Action::Write, nil
    }
    if name == "files" {
        return Action::Files, nil
    }
    if name == "search" {
        return Action::Search, nil
    }
    if name == "buffers" {
        return Action::Buffers, nil
    }
    if name == "undo" {
        return Action::Undo, nil
    }
    if name == "redo" {
        return Action::Redo, nil
    }
    if name == "quit" {
        return Action::Quit, nil
    }
    if name == "split" {
        return Action::Split, nil
    }
    if name == "vsplit" {
        return Action::VSplit, nil
    }
    if name == "normal" {
        return Action::Normal, nil
    }
    return Action::None, error("Unknown mapping action")
}

fn execute_action(app *App, action Action) error {
    app.group = app.group + 1
    if action == Action::Write {
        return save_buffer(app, "")
    } elif action == Action::Files {
        return start_picker(app, PickerKind::Files)
    } elif action == Action::Search {
        return start_picker(app, PickerKind::ProjectSearch)
    } elif action == Action::Buffers {
        return start_picker(app, PickerKind::Buffers)
    } elif action == Action::Undo or action == Action::Redo {
        return undo(app, action == Action::Redo)
    } elif action == Action::Quit {
        close_pane(app, false)
    } elif action == Action::Split or action == Action::VSplit {
        return split_pane(app, action == Action::VSplit)
    } elif action == Action::Normal {
        return builtin_key(app, KeyEscape)
    }
    return nil
}
