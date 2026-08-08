# PSScriptAnalyzer settings for LocalOpsConsole (ops / agent scripts).
# Used by: PowerShell extension in Cursor, and tools/Invoke-ScriptAnalyzerScan.ps1
@{
    Severity = @('Error', 'Warning', 'Information')

    IncludeDefaultRules = $true

    ExcludeRules = @(
        # Console UX / installers
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingInvokeExpression'
        # Product API uses plural collection nouns (Get-LocFleetAgents, etc.)
        'PSUseSingularNouns'
        # Domain verbs (Enroll/Claim/Evaluate/Pulse/...) are intentional Loc-* vocabulary
        'PSUseApprovedVerbs'
        # Repo standard is UTF-8 without BOM (cross-tool friendly)
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
        PSAvoidGlobalVars = @{
            Enable = $true
        }
    }
}
