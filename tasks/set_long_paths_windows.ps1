# enable long path support Windows 2016 or later.
if ( $env:PT__noop == "true" ) {
    echo "Running in noop: bailing out"
    exit 0
}
if ( $env:PT_noop -eq "true" )
{
    echo "Running in noop: bailing out"
    exit 0
}
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force