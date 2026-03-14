$privateRoot = Split-Path -Path $PSScriptRoot -Parent

. (Join-Path -Path $privateRoot -ChildPath 'Utility.ps1')
. (Join-Path -Path $privateRoot -ChildPath 'State.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'StateHelpers.ps1')
