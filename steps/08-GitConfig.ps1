function Step-GitConfig {
    if (Test-StateCompleted "08-GitConfig") { return }
    Write-Log "Configuring git..." "INFO"

    $existingName = git config --global user.name 2>$null
    $existingEmail = git config --global user.email 2>$null

    $name = Ask-Input "Git user name" $existingName
    $email = Ask-Input "Git user email" $existingEmail

    git config --global user.name $name
    git config --global user.email $email
    git config --global init.defaultBranch main
    git config --global core.autocrlf true
    git config --global pull.rebase true
    git config --global core.editor "zed --wait"
    git config --global core.pager ""
    git config --global alias.st "status -sb"
    git config --global alias.ll "log --oneline -n 15"

    Set-StateCompleted "08-GitConfig"
    Write-Log "Git configured" "SUCCESS"
}
Step-GitConfig
