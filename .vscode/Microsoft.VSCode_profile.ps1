# PowerShell Profile for VS Code
# This profile is loaded when PowerShell starts in VS Code

# Set strict mode to catch common scripting mistakes
Set-StrictMode -Version Latest

# Error handling preference
$ErrorActionPreference = 'Stop'

# Import required modules with error handling
function Import-RequiredModule {
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )
    
    try {
        Import-Module -Name $ModuleName -ErrorAction Stop
        Write-Host "Successfully imported $ModuleName" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to import $ModuleName. Error: $($_.Exception.Message)"
    }
}

# Try to import PSScriptAnalyzer
Import-RequiredModule -ModuleName 'PSScriptAnalyzer'

# Function to analyze scripts
function Invoke-CodeAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        $results = Invoke-ScriptAnalyzer -Path $Path -Settings "$PSScriptRoot\PSScriptAnalyzerSettings.psd1"
        if ($results) {
            Write-Host "Found $($results.Count) issue(s):" -ForegroundColor Yellow
            $results | Format-Table -AutoSize
        }
        else {
            Write-Host "No issues found." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to analyze script. Error: $($_.Exception.Message)"
    }
}

# Set up common aliases with warning messages
function Set-SafeAlias {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value
    )
    
    try {
        Set-Alias -Name $Name -Value $Value -Option AllScope -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to set alias $Name. Error: $($_.Exception.Message)"
    }
}

# Set up some useful aliases
Set-SafeAlias -Name 'analyze' -Value 'Invoke-CodeAnalysis'

# Welcome message
Write-Host "PowerShell Profile loaded successfully." -ForegroundColor Green
Write-Host "Use 'analyze <path>' to run script analysis." -ForegroundColor Cyan 