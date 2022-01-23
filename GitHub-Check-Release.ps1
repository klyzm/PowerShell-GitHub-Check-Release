$ScriptDirectory = $env:LOCALAPPDATA + "\gh-check-release"
$ReleaseFile = $ScriptDirectory + "\gh-prev-rel.json"
$RepositoryURI  = "https://api.github.com/repos/Nifury/ungoogled-chromium-binaries/releases"

function Initialize {
    Param(
        [parameter()][System.String]$ScriptDirectory,
        [parameter()][System.String]$ReleaseFile
    )
    if(!(Test-Path -Path $ScriptDirectory)){
        mkdir $ScriptDirectory
    }

    if(!(Test-Path -Path $ReleaseFile)){
        Out-File -FilePath $ReleaseFile
    }
}

# "Show-Notification"-Code from https://gist.github.com/dend/5ae8a70678e3a35d02ecd39c12f99110
function Show-Notification {
    [cmdletbinding()]
    Param (
        [string]
        $ToastTitle,
        [string]
        [parameter(ValueFromPipeline)]
        $ToastText
    )

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $Template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)

    $RawXml = [xml] $Template.GetXml()
    ($RawXml.toast.visual.binding.text| Where-Object {$_.id -eq "1"}).AppendChild($RawXml.CreateTextNode($ToastTitle)) > $null
    ($RawXml.toast.visual.binding.text| Where-Object {$_.id -eq "2"}).AppendChild($RawXml.CreateTextNode($ToastText)) > $null

    $SerializedXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $SerializedXml.LoadXml($RawXml.OuterXml)

    $Toast = [Windows.UI.Notifications.ToastNotification]::new($SerializedXml)
    $Toast.Tag = "PowerShell"
    $Toast.Group = "PowerShell"
    $Toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(1)

    $Notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Github Check Release")
    $Notifier.Show($Toast);
}

function Get-GitHubContent {
    Param (
    [parameter()][System.String]$URI
    )
    
    try{
        $Response = Invoke-WebRequest -Method "GET" -URI $RepoToMonitor -UseBasicParsing
    }
    catch{
        Write-Error "Invoke-WebRequest failed"
        break
    }

    if($Response.StatusCode -ne 200){
        Write-Error "Status Code wasn't 200"
        break
    }

    return $Response.Content
}

function Get-LocalContent {
    param (
        [parameter()][System.String]$LocalFilePath
    )
    try{
        $LocalContent = Get-Content -Raw -Path $LocalFilePath
    }
    catch{
        Write-Error "Couldn't load local files"
        break
    }
    

    return $LocalContent
}

function New-ReleaseList {
    Param(
        [parameter()][System.String]$JsonString
    )
    $Json = $JsonString | ConvertFrom-Json

    $CompareList = @()

    foreach($x in $Json){
        $CompareList += @{
            "name" = $x.name
            "published" = $x.published_at
        }
    }

    return $CompareList
}

function Compare-ReleaseLists {
    Param(
        [parameter()][System.Array]$RemoteList,
        [parameter()][System.Array]$LocalList
    )

    $HasNewRelease = $False
    $NewReleases = @()

    foreach($y in $RemoteList){
        if(!($y.name -in $LocalList.name)){
            $HasNewRelease = $True
            $NewReleases += $y.name.Clone()
        }
    }
    return $HasNewRelease, $NewReleases
}

Initialize -ScriptDirectory $ScriptDirectory -ReleaseFile $ReleaseFile

$RemoteResponse = Get-GitHubContent -URI $RepositoryURI
$Rem = New-ReleaseList -JsonString $RemoteResponse
$LocalResponse = Get-LocalContent -LocalFilePath $ReleaseFile
$Loc = New-ReleaseList -JsonString $LocalResponse

$ComparisonResult = Compare-ReleaseLists -RemoteList $Rem -LocalList $Loc

if($ComparisonResult[0]){

    $Rem | ConvertTo-Json | Out-File $ReleaseFile
    Show-Notification -ToastTitle "GitHub Check Release" -ToastText "Neuer Release $($ComparisonResult[1]) verfuegbar!"

}
