echo off
cls

set input=%1
set arg1=
set arg2=

for /f "tokens=1,2,3,4,5 delims=|" %%I in (%input%) do (
	set host=%%I
	set login=%%J
	set password=%%K
	set id=%%L
	set folder=%%M
)

echo Please wait while downloading item %id% to %folder%

winscp.exe /command ^
	"open sftp://%login%:%password%@%host%" ^
    "get ""/Swaps/%id%/"" ""%folder%""" ^
    "exit"

echo Done! Item %id% downloaded!

exit 0