function MD5HashFile([string] $filePath)
{
    if ([string]::IsNullOrEmpty($filePath) -or !(Test-Path $filePath -PathType Leaf))
    {
        return $null
    }

    return Get-FileHash -Path $filePath -Algorithm MD5
}

Write-Host "Preparing to run build script..."

if(!$PSScriptRoot){
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$TOOLS_DIR = Join-Path $PSScriptRoot "tools"
$NUGET_EXE = Join-Path $TOOLS_DIR "nuget.exe"
$CAKE_EXE = Join-Path $TOOLS_DIR "Cake/Cake.exe"
$NUGET_URL = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$PACKAGES_CONFIG = Join-Path $TOOLS_DIR "packages.config"
$PACKAGES_CONFIG_MD5 = Join-Path $TOOLS_DIR "packages.config.md5sum"

# Make sure tools folder exists
if ((Test-Path $PSScriptRoot) -and !(Test-Path $TOOLS_DIR)) {
    Write-Verbose -Message "Creating tools directory..."
    New-Item -Path $TOOLS_DIR -Type directory | out-null
}

# Make sure that packages.config exist.
if (!(Test-Path $PACKAGES_CONFIG)) {
    Write-Verbose -Message "Downloading packages.config..."
    try { (New-Object System.Net.WebClient).DownloadFile("http://cakebuild.net/download/bootstrapper/packages", $PACKAGES_CONFIG) } catch {
        Throw "Could not download packages.config."
    }
}

# Try find NuGet.exe in path if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Trying to find nuget.exe in PATH..."
    $existingPaths = $Env:Path -Split ';' | Where-Object { (![string]::IsNullOrEmpty($_)) -and (Test-Path $_ -PathType Container) }
    $NUGET_EXE_IN_PATH = Get-ChildItem -Path $existingPaths -Filter "nuget.exe" | Select -First 1
    if ($NUGET_EXE_IN_PATH -ne $null -and (Test-Path $NUGET_EXE_IN_PATH.FullName)) {
        Write-Verbose -Message "Found in PATH at $($NUGET_EXE_IN_PATH.FullName)."
        $NUGET_EXE = $NUGET_EXE_IN_PATH.FullName
    }
}

# Try download NuGet.exe if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Downloading NuGet.exe..."
    try {
        (New-Object System.Net.WebClient).DownloadFile($NUGET_URL, $NUGET_EXE)
    } catch {
        Throw "Could not download NuGet.exe."
    }
}

# Save nuget.exe path to environment to be available to child processed
$ENV:NUGET_EXE = $NUGET_EXE

# Restore tools from NuGet?
if(-Not $SkipToolPackageRestore.IsPresent) {
    Push-Location
    Set-Location $TOOLS_DIR

    # Check for changes in packages.config and remove installed tools if true.
    [string] $md5Hash = MD5HashFile($PACKAGES_CONFIG)
    if((!(Test-Path $PACKAGES_CONFIG_MD5)) -Or
      ($md5Hash -ne (Get-Content $PACKAGES_CONFIG_MD5 ))) {
        Write-Verbose -Message "Missing or changed package.config hash..."
        Remove-Item * -Recurse -Exclude packages.config,nuget.exe
    }

    Write-Verbose -Message "Restoring tools from NuGet..."
    $NuGetOutput = Invoke-Expression "&`"$NUGET_EXE`" install -ExcludeVersion -OutputDirectory `"$TOOLS_DIR`""

    if ($LASTEXITCODE -ne 0) {
        Throw "An error occured while restoring NuGet tools."
    }
    else
    {
        $md5Hash | Out-File $PACKAGES_CONFIG_MD5 -Encoding "ASCII"
    }
    Write-Verbose -Message ($NuGetOutput | out-string)
    Pop-Location
}

Write-Host -ForegroundColor Cyan "Running Net46 tests..."
./tools/Cake/Cake.exe ./tests/Cake.FileSet.IntegrationTests/test.net46.cake --verbosity=Diagnostic

Write-Host -ForegroundColor Cyan "`nRunning NetStandard1.6 tests..."
dotnet ./tools/Cake.CoreCLR/Cake.dll ./tests/Cake.FileSet.IntegrationTests/test.netstandard16.cake --verbosity=Diagnostic