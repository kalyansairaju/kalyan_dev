@echo off
setlocal
cd /d "%~dp0"
"C:\Program Files\Microsoft SQL Server\150\DTS\Binn\DTExec.exe" /File "%~dp0BankingDailyLoad.dtsx" /Reporting E
set "LoadResult=%ERRORLEVEL%"
if not "%LoadResult%"=="0" echo Banking load failed. Review the errors above.
exit /b %LoadResult%
