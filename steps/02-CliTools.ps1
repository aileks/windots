function Step-CliTools {
    if (Test-StateCompleted "02-CliTools") { return }

    Write-Log "Selecting CLI tools to install..." "INFO"
    if (Invoke-CliToolsSelectionInstall) {
        Set-StateCompleted "02-CliTools"
        Write-Log "CLI tools installation step complete" "SUCCESS"
    }
}
Step-CliTools
