$ErrorActionPreference='Stop'
Add-Type -Path 'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.ManagedDTS\v4.0_15.0.0.0__89845dcd8080cc91\Microsoft.SqlServer.ManagedDTS.dll'
$p=New-Object Microsoft.SqlServer.Dts.Runtime.Package
$a=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$p.Name='BankingDailyLoad'
$p.Description='Loop daily banking CSV files into raw staging, then publish active customers and valid transactions. Dates use British day/month/year format.'
$p.ProtectionLevel=0
$p.MaxConcurrentExecutables=1
$p.Variables.Add('InputFolder',$false,'User',(Join-Path $PSScriptRoot 'input')) | Out-Null
$p.Variables.Add('CurrentFile',$false,'User','') | Out-Null
$cm=$p.Connections.Add('OLEDB')
$cm.Name='Local_SQL_Server'
$cm.ConnectionString='Provider=SQLNCLI11;Data Source=.\SQLEXPRESS;Initial Catalog=GOC_DataEngineer_Practice;Integrated Security=SSPI;'
$f=$p.Executables.Add('STOCK:FOREACHLOOP')
$f.Name='Stage each daily CSV file'
$f.ForEachEnumerator=$a.ForEachEnumeratorInfos.Item('Foreach File Enumerator').CreateNew()
$e=$f.ForEachEnumerator
$e.Properties['Directory'].SetValue($e,(Join-Path $PSScriptRoot 'input'))
$e.SetExpression('Directory','@[User::InputFolder]')
$e.Properties['FileSpec'].SetValue($e,'bank_*.csv')
$e.Properties['FileNameRetrieval'].SetValue($e,0)
$e.Properties['Recurse'].SetValue($e,$false)
$m=$f.VariableMappings.Add(); $m.VariableName='User::CurrentFile'; $m.ValueIndex=0
$t=$f.Executables.Add('STOCK:SQLTask'); $t.Name='Read CSV and stage all rows with validation'
$t.InnerObject.Connection=$cm.ID
$t.InnerObject.SqlStatementSource='EXEC bankdemo.StageFile @FilePath=?;'
$t.InnerObject.BypassPrepare=$true
$b=$t.InnerObject.ParameterBindings.Add(); $b.ParameterName='0'; $b.DtsVariableName='User::CurrentFile'; $b.DataType=130; $b.ParameterSize=450
$pub=$p.Executables.Add('STOCK:SQLTask'); $pub.Name='Convert dates and publish active customers and transactions'
$pub.InnerObject.Connection=$cm.ID
$pub.InnerObject.SqlStatementSource='EXEC bankdemo.PublishActive;'
$p.PrecedenceConstraints.Add($f,$pub) | Out-Null
$a.SaveToXml((Join-Path $PSScriptRoot 'BankingDailyLoad.dtsx'),$p,$null)
Write-Output 'Saved BankingDailyLoad.dtsx'
