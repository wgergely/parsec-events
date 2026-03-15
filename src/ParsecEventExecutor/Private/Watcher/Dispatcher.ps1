function New-ParsecWatcherDispatcher {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return [ordered]@{
        state_root = $StateRoot
        is_busy = $false
        queue = [System.Collections.Generic.Queue[hashtable]]::new()
        last_result = $null
        last_error = $null
    }
}

function Invoke-ParsecWatcherDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Dispatcher,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Recipe,

        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter(Mandatory)]
        [ValidateSet('connect', 'disconnect')]
        [string] $EventType
    )

    $dispatchItem = [ordered]@{
        recipe_name = $Recipe.name
        recipe = $Recipe
        target_mode = $Recipe.target_mode
        username = $Username
        event_type = $EventType
        queued_at = [DateTimeOffset]::UtcNow.ToString('o')
    }

    if ($Dispatcher.is_busy) {
        $Dispatcher.queue.Enqueue($dispatchItem)
        Write-Information "Watcher: Recipe '$($Recipe.name)' queued (dispatcher busy). Queue depth: $($Dispatcher.queue.Count)"
        return [ordered]@{
            status = 'Queued'
            message = "Recipe '$($Recipe.name)' queued behind active execution."
            item = $dispatchItem
        }
    }

    return Invoke-ParsecWatcherDispatchInternal -Dispatcher $Dispatcher -Item $dispatchItem
}

function Invoke-ParsecWatcherDispatchInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Dispatcher,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Item
    )

    $Dispatcher.is_busy = $true
    $Dispatcher.last_error = $null

    Write-Information "Watcher: Dispatching recipe '$($Item.recipe_name)' for $($Item.event_type) event (user: $($Item.username))"

    try {
        $result = Invoke-ParsecRecipeInternal -Recipe $Item.recipe -StateRoot $Dispatcher.state_root

        $Dispatcher.last_result = [ordered]@{
            recipe_name = $Item.recipe_name
            event_type = $Item.event_type
            username = $Item.username
            terminal_status = $result.terminal_status
            started_at = $Item.queued_at
            completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        }

        $statusMsg = if ($result.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
            "succeeded ($($result.terminal_status))"
        }
        else {
            "failed ($($result.terminal_status))"
        }

        Write-Information "Watcher: Recipe '$($Item.recipe_name)' $statusMsg"

        return [ordered]@{
            status = 'Dispatched'
            terminal_status = $result.terminal_status
            target_mode = $Item.target_mode
            message = "Recipe '$($Item.recipe_name)' $statusMsg"
            result = $result
        }
    }
    catch {
        $Dispatcher.last_error = $_.Exception.Message
        Write-Warning "Watcher: Recipe '$($Item.recipe_name)' threw an exception: $_"

        return [ordered]@{
            status = 'Error'
            message = "Recipe '$($Item.recipe_name)' threw: $($_.Exception.Message)"
            error = $_.Exception.Message
        }
    }
    finally {
        $Dispatcher.is_busy = $false
    }
}

function Invoke-ParsecWatcherDrainQueue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Dispatcher
    )

    $results = @()

    while ($Dispatcher.queue.Count -gt 0 -and -not $Dispatcher.is_busy) {
        $item = $Dispatcher.queue.Dequeue()
        Write-Information "Watcher: Draining queued recipe '$($item.recipe_name)'"
        $results += Invoke-ParsecWatcherDispatchInternal -Dispatcher $Dispatcher -Item $item
    }

    return $results
}
