function Remove-ParsecTomlComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line
    )

    $inString = $false
    $builder = New-Object System.Text.StringBuilder

    for ($index = 0; $index -lt $Line.Length; $index++) {
        $char = $Line[$index]
        if ($char -eq '"') {
            $escaped = $index -gt 0 -and $Line[$index - 1] -eq '\'
            if (-not $escaped) {
                $inString = -not $inString
            }
        }

        if (-not $inString -and $char -eq '#') {
            break
        }

        [void] $builder.Append($char)
    }

    return $builder.ToString().Trim()
}

function Split-ParsecTomlPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    return ,([string[]] ($Path.Split('.', [System.StringSplitOptions]::RemoveEmptyEntries)))
}

function Get-ParsecTomlContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document,

        [Parameter(Mandatory)]
        [string[]] $Segments,

        [Parameter()]
        [switch] $AsArrayItem
    )

    $context = $Document
    for ($index = 0; $index -lt $Segments.Count; $index++) {
        $segment = $Segments[$index]
        $isLast = $index -eq ($Segments.Count - 1)

        if ($AsArrayItem -and $isLast) {
            if (-not $context.Contains($segment)) {
                $context[$segment] = New-Object System.Collections.ArrayList
            }

            $item = [ordered]@{}
            [void] $context[$segment].Add($item)
            return $item
        }

        if (-not $context.Contains($segment)) {
            $context[$segment] = [ordered]@{}
        }

        $context = $context[$segment]
    }

    return $context
}

function Split-ParsecTomlArrayItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Text
    )

    $items = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $depth = 0
    $inString = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        if ($char -eq '"') {
            $escaped = $index -gt 0 -and $Text[$index - 1] -eq '\'
            if (-not $escaped) {
                $inString = -not $inString
            }
        }

        if (-not $inString) {
            if ($char -eq '[') {
                $depth++
            }
            elseif ($char -eq ']') {
                $depth--
            }
            elseif ($char -eq ',' -and $depth -eq 0) {
                $items.Add($builder.ToString().Trim())
                [void] $builder.Clear()
                continue
            }
        }

        [void] $builder.Append($char)
    }

    if ($builder.Length -gt 0) {
        $items.Add($builder.ToString().Trim())
    }

    return @($items)
}

function ConvertFrom-ParsecTomlValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace('\"', '"')
    }

    if ($trimmed -in @('true', 'false')) {
        return [System.Convert]::ToBoolean($trimmed)
    }

    if ($trimmed -match '^-?\d+$') {
        return [int] $trimmed
    }

    if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
        $inner = $trimmed.Substring(1, $trimmed.Length - 2).Trim()
        if ([string]::IsNullOrWhiteSpace($inner)) {
            return @()
        }

        $values = foreach ($item in (Split-ParsecTomlArrayItems -Text $inner)) {
            ConvertFrom-ParsecTomlValue -Value $item
        }

        return @($values)
    }

    return $trimmed
}

function ConvertFrom-ParsecToml {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [string] $Text
    )

    $content = if ($PSCmdlet.ParameterSetName -eq 'Path') {
        Get-Content -LiteralPath $Path -Raw
    }
    else {
        $Text
    }

    $document = [ordered]@{}
    $context = $document
    $lines = $content -split "`r?`n"

    foreach ($originalLine in $lines) {
        $line = Remove-ParsecTomlComment -Line $originalLine
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\[\[(.+)\]\]$') {
            $segments = Split-ParsecTomlPath -Path $Matches[1].Trim()
            if (@($segments).Count -eq 1) {
                $segment = $segments[0]
                if (-not $document.Contains($segment)) {
                    $document[$segment] = New-Object System.Collections.ArrayList
                }

                $item = [ordered]@{}
                [void] $document[$segment].Add($item)
                $context = $item
            }
            else {
                $context = Get-ParsecTomlContext -Document $document -Segments $segments -AsArrayItem
            }
            continue
        }

        if ($line -match '^\[(.+)\]$') {
            $segments = Split-ParsecTomlPath -Path $Matches[1].Trim()
            if (@($segments).Count -gt 1 -and $document.Contains($segments[0]) -and $document[$segments[0]] -is [System.Collections.IList]) {
                $context = $document[$segments[0]][$document[$segments[0]].Count - 1]
                foreach ($segment in $segments[1..(@($segments).Count - 1)]) {
                    if (-not $context.Contains($segment)) {
                        $context[$segment] = [ordered]@{}
                    }

                    $context = $context[$segment]
                }
            }
            else {
                $context = Get-ParsecTomlContext -Document $document -Segments $segments
            }
            continue
        }

        if ($line -notmatch '^([A-Za-z0-9_\-]+)\s*=\s*(.+)$') {
            throw "Unsupported TOML line: $line"
        }

        $key = $Matches[1]
        $value = $Matches[2]
        $context[$key] = ConvertFrom-ParsecTomlValue -Value $value
    }

    return $document
}
