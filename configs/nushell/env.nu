$env.EDITOR = "zed --wait"

$env.PATH = ($env.PATH | split row (char esep) | prepend [
    ($env.USERPROFILE | path join ".local" "bin")
    ($env.USERPROFILE | path join ".cargo" "bin")
])

zoxide init nushell | save -f ~/.zoxide.nu
