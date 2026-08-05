# Placeholder smoke tests — expand with Pester later
Describe "System module" {
    It "module.json exists" {
        Test-Path (Join-Path $PSScriptRoot "..\module.json") | Should -Be $true
    }
}
