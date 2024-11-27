@{
    # Define the rules for PowerShell Script Analyzer
    Rules = @{
        # Rule for consistent indentation
        PSUseConsistentIndentation = @{
            Enable          = $true;
            Kind            = 'space';
            IndentationSize = 4;
        };
        # Rule for consistent whitespace
        PSUseConsistentWhitespace  = @{
            Enable         = $true;
            CheckOpenBrace = $true;
            CheckOpenParen = $true;
            CheckOperator  = $true;
            CheckSeparator = $true;
        };
        # Rule to avoid using aliases
        PSAvoidUsingCmdletAliases  = @{
            Enable = $true;
        };
    };
}
