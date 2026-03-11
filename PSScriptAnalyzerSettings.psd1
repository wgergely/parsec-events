@{
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSReviewUnusedParameter',
        'PSUseOutputTypeCorrectly',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns'
    )
}
