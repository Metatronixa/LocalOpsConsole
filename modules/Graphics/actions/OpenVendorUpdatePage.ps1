param(
    [ValidateSet("NVIDIA", "AMD", "Intel", "Other")]
    [string]$Vendor = "NVIDIA"
)

$url = switch ($Vendor) {
    "NVIDIA" { "https://www.nvidia.com/Download/index.aspx" }
    "AMD"    { "https://www.amd.com/en/support" }
    "Intel"  { "https://www.intel.com/content/www/us/en/download-center/home.html" }
    default  { "https://www.google.com/search?q=graphics+driver+download" }
}

return New-ApiResult -Success $true -Message "Open $Vendor driver download page" -Data ([PSCustomObject]@{
    Vendor = $Vendor
    Url    = $url
})
