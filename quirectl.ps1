param (
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$ArgsList
)

$Command = $ArgsList -join " "
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", "quire", [System.IO.Pipes.PipeDirection]::InOut)

try {
    $pipe.Connect(1000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $reader = New-Object System.IO.StreamReader($pipe)

    $writer.Write($Command)
    $writer.Flush()

    $response = $reader.ReadToEnd()
    Write-Host $response
}
catch {
    Write-Error "QuireTWM IPC unreachable (pipe '\\.\pipe\quire'): $_"
}
finally {
    $pipe.Dispose()
}