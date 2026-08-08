# api/routers/FleetRouterPackages.ps1 - Fleet scripts/packages/agent-package routes

function Invoke-LocFleetPackageRoutes {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$SubLower,
        [string]$Method,
        [string]$AgentSub,
        [string[]]$Segments,
        [hashtable]$BodyHash,
        [System.Net.HttpListenerRequest]$Request
    )

    switch ($SubLower) {
        'scripts' {
            if ($AgentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'content') {
                if ($Method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Script content requires GET" -StatusCode 405
                    return $true
                }
                $result = Get-LocFleetScriptContent -ScriptId $AgentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }
            if ($Method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Scripts require GET" -StatusCode 405
                return $true
            }
            $result = Get-LocFleetScripts
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return $true
        }
        'enroll-token' {
            if ($Segments.Count -ge 5 -and $Segments[4].ToLower() -eq 'rotate') {
                if ($Method -ne "POST") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Rotate requires POST" -StatusCode 405
                    return $true
                }
                $result = Rotate-LocFleetEnrollToken
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
                return $true
            }
            if ($Method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Enroll token requires GET" -StatusCode 405
                return $true
            }
            $result = Get-LocFleetEnrollToken
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return $true
        }
        'policy-packs' {
            if ($Method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Policy packs require GET" -StatusCode 405
                return $true
            }
            $result = Get-LocFleetPolicyPacks
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return $true
        }
        'packages' {
            $pkgId = if ($AgentSub) { [string]$AgentSub } else { '' }
            $pkgAction = if ($Segments.Count -ge 6) { $Segments[5].ToLower() } else { '' }

            if ($pkgAction -eq 'content') {
                if ($Method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Package content requires GET" -StatusCode 405
                    return $true
                }
                $result = Get-LocFleetPackageContent -PackageId $pkgId
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }

            if ($Method -eq "GET" -and -not $pkgId) {
                $result = Get-LocFleetPackages
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
                return $true
            }

            if ($Method -eq "POST" -and -not $pkgId) {
                $id = if ($BodyHash.Id) { [string]$BodyHash.Id } else { '' }
                $name = if ($BodyHash.Name) { [string]$BodyHash.Name } else { '' }
                $category = if ($BodyHash.Category) { [string]$BodyHash.Category } else { '' }
                $source = if ($BodyHash.Source) { [string]$BodyHash.Source } else { '' }
                $wingetId = if ($BodyHash.WingetId) { [string]$BodyHash.WingetId } else { '' }
                $url = if ($BodyHash.Url) { [string]$BodyHash.Url } else { '' }
                $fileName = if ($BodyHash.FileName) { [string]$BodyHash.FileName } else { '' }
                $silentArgs = if ($BodyHash.SilentArgs) { [string]$BodyHash.SilentArgs } else { '' }
                $sha256 = if ($BodyHash.Sha256) { [string]$BodyHash.Sha256 } else { '' }
                $result = Register-LocFleetPackage -Id $id -Name $name -Category $category -Source $source `
                    -WingetId $wingetId -Url $url -FileName $fileName -SilentArgs $silentArgs -Sha256 $sha256
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }

            if ($Method -eq "DELETE" -and $pkgId) {
                $deleteFiles = $false
                $dfRaw = $Request.QueryString["deleteFiles"]
                if ($dfRaw -and ($dfRaw -eq "1" -or $dfRaw -match '^(?i)true|yes$')) { $deleteFiles = $true }
                $result = Remove-LocFleetPackage -PackageId $pkgId -DeleteFiles:$deleteFiles
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }

            Send-JsonResponse -Context $Context -Success $false -Message "Use GET/POST /fleet/packages or DELETE /fleet/packages/{id}" -StatusCode 405
            return $true
        }
        'agent-package' {
            $pkgAction = if ($AgentSub) { $AgentSub.ToLower() } else { '' }
            if ($pkgAction -eq 'publish') {
                if ($Method -ne "POST") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Publish requires POST" -StatusCode 405
                    return $true
                }
                $result = Publish-LocFleetAgentPackage
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }
            if ($pkgAction -eq 'manifest') {
                if ($Method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Manifest requires GET" -StatusCode 405
                    return $true
                }
                $result = Get-LocFleetAgentPackageManifest -AutoPublish
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }
            if ($pkgAction -eq 'content') {
                if ($Method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Content requires GET" -StatusCode 405
                    return $true
                }
                $result = Get-LocFleetAgentPackageContent
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return $true
            }
            if ($Method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Agent package requires GET or POST .../publish" -StatusCode 405
                return $true
            }
            $result = Get-LocFleetAgentPackageManifest -AutoPublish
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return $true
        }
        default {
            return $false
        }
    }
}
