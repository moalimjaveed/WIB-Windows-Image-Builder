@{
    # PSScriptAnalyzer custom rule configuration for Windows Image Builder (WIB)
    Severity = @('Error', 'Warning')

    # Exclude rules that conflict with CLI console design, plural function naming, test mocking, and offline unattend XML generation
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSAvoidGlobalFunctions',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidGlobalVars',
        'PSAvoidUsingEmptyCatchBlock',
        'PSPossibleIncorrectComparisonWithNull',
        'PSUseApprovedVerbs',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSAvoidOverwritingBuiltInCmdlets',
        'PSUseProcessBlockForPipelineCommand'
    )
}
