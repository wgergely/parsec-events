return @{
    Name = 'window'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            throw "Window domain method '$Method' is not available."
        }
    }
}
