$env.config = {
    show_banner: false
    edit_mode: vi
    cursor_shape: {
        vi_insert: line
        vi_normal: block
    }
    completions: {
        algorithm: fuzzy
        external: {
            enable: true
            max_results: 50
        }
    }
    ls: {
        use_ls_colors: true
        clickable_links: true
    }
    rm: {
        always_trash: true
    }
    history: {
        max_size: 50_000
        file_format: sqlite
        sync_on_enter: true
        isolation: true
    }
    keybindings: [
        {
            name: completion_menu
            modifier: none
            keycode: tab
            mode: [vi_insert vi_normal]
            event: {
                until: [
                    { send: menu name: completion_menu }
                    { send: menunext }
                ]
            }
        }
        {
            name: history_menu
            modifier: control
            keycode: char_r
            mode: [vi_insert vi_normal]
            event: { send: menu name: history_menu }
        }
        {
            name: fuzzy_history
            modifier: control
            keycode: char_f
            mode: [vi_insert vi_normal]
            event: [
                { send: menu name: history_menu }
                { edit: clear }
            ]
        }
    ]
}

alias ll = ls -la
alias la = ls -a
alias cat = open --raw
