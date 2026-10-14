BeforeAll {
    $root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $scriptPath=Join-Path $root 'installer/Configure-JawsDelegationToolbox.ps1'
    $source=Get-Content -LiteralPath $scriptPath -Raw
}

Describe 'Step C delegation toolbox collection handling' {
    It 'initializes discovered and verified versions as arrays under strict mode' {
        $source | Should -Match '(?m)^\$items=@\(\)'
        $source | Should -Match '(?m)^\s*if\(\$null -ne \$listProp -and \$null -ne \$listProp\.Value\)\{\$items=@\(\$listProp\.Value\)\}'
        $source | Should -Match '(?m)^\$actualItems=@\(\)'
        $source | Should -Match '(?m)^\s*if\(\$null -ne \$listProp -and \$null -ne \$listProp\.Value\)\{\$actualItems=@\(\$listProp\.Value\)\}'
    }

    It 'inspects optional value properties without strict-mode member access' {
        $source | Should -Match "PSObject\.Properties\['data'\]"
        $source | Should -Match "PSObject\.Properties\['value'\]"
        $source | Should -Not -Match '(?m)\$existing\.value|\$actual\.value'
    }

    It 'uses normalized arrays for all toolbox version counts' {
        $source | Should -Match '\$items\.Count'
        $source | Should -Match '\$actualItems\.Count'
        $source | Should -Not -Match '@\(\$actual\.value\)\.Count'
    }
}
