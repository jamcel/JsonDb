<#
.SYNOPSIS
    Module for quickly (re-)storing data in a json file.

    It is object-oriented in such a way that you first create a jsonDb object:

    > $myJsonDb = Initialize-JsonDb <file name>  # if the file is present data will be loaded

    The db data is accessible via the property .data (should be ordered dictionary for sorting to work)
    and all interaction functions are called on the object.

    > $myJsonDb.data = @{a=1,b=2}
    > $myJsonDb.saveToFile()

    ---------------------------------------
    Later in a different script/context:

    # load the stored data
    > $myJsonDb = Initialize-JsonDb <file name>
    > Write-Host $myJsonDb.data.a   # output: 1

.DESCRIPTION

    For detailed help about parameters use:
         get-help <this_script_name>.ps1 -Parameter <parameter name>
      or get-help <this_script_name>.ps1 -Parameter *
      or get-help <this_script_name>.ps1 -detailed

.NOTES
    Date: 08/2020
    Author: gottscha

    CAUTION when modifying ps modules:
    The commands imported from ps modules might be cached (especially when using PowerShell ISE).

    To refresh the cache and reload your module changes in the command line modify the command for calling
    exported functions of this module to:

    import-module <this_module_name>.psm1 -force; your-command-to-run
#>

#***************************************************
#
function Get-JsonDbDataReordered {
    param($jsonDb)
    $reorderedDbData = [ordered]@{}
    $jsonDb.data.GetEnumerator() `
    | Sort-Object -Descending -Property $this.orderBy `
    | ForEach-Object {
        $reorderedDbData[ $_.key ] = $_.value
    }
    $reorderedDbData
}

#***************************************************
#
 function Save-JsonDbToFile {
     param($jsonDb, $depth=20, $forceDirCreate=$false)
    Write-Host "Updating JSON database file $($jsonDb.dbFilePath)"
    $dbData=$jsonDb.getDbDataReordered()
    $dirPath = (split-path $jsonDb.dbFilePath)
    if(-not (Test-IsDirectory $dirPath )){

        if($forceDirCreate){
            New-Item -path $dirPath -ItemType Directory -Force
        }else{
            Write-Warning "The directory in which to save the json db doesn't exist:"
            Write-Host $dirPath -ForegroundColor cyan
            if((Read-Host "Would you like to create the path?`n(y/n)") -eq "y"){
                New-Item -path $dirPath -ItemType Directory -Force
            }else{
                Write-Host "Not saved."
                return
            }
        }
    }
    ConvertTo-Json $dbData -Depth $depth | out-file $jsonDb.dbFilePath
}

#***************************************************
#
function Remove-JsonDbFile {
  param($jsonDb,[bool]$force)
  if(Test-Path $jsonDb.dbFilePath){
    if(-not $force){
      $confirm = (Read-Host "Are you sure you want to delete the database file (y/n):`n    $($jsonDb.dbFilePath)").ToLower()
    }else{
      $confirm = 'y'
    }
    if($confirm -eq 'y'){
      Write-Host "Removing JSON database file $($jsonDb.dbFilePath)"
      Remove-Item -Path $jsonDb.dbFilePath
    }
  }
}

#***************************************************
#
function New-JsonDbBackupFile{
    param($jsonDb)
    import-module "$PSScriptRoot\..\agilent.fw.utils.psm1"
    $db_file = (get-item $jsonDb.dbFilePath)
    $db_file_dir_path = $db_file.Directory.FullName
    $db_file_basename = $db_file.BaseName
    $db_file_extension = $db_file.Extension
    $bak_dir_path = "$db_file_dir_path\$($jsonDb.backupDirName)"
    $bak_file_name ="$($db_file_basename)_bak_$(get-date -format "yyyy_MM_dd__HH_mm_ss")$db_file_extension"
    Confirm-OrCreateDirPath $bak_dir_path -quiet
    $backup_file_path = "$bak_dir_path\$bak_file_name"
    Write-Host "Creating bakup file " -noNewLine
    Write-Host $bak_file_name -foregroundColor cyan -NoNewline
    Write-Host " in "
    Write-Host "    $bak_dir_path"-foregroundColor cyan
    Copy-Item -Path $jsonDb.dbFilePath -Destination $backup_file_path -Force
    if(Test-Path $backup_file_path){
        Write-Host "[OK]" -ForegroundColor green
    }else{
        Write-Host "[failed]" -ForegroundColor red
    }
}

#***************************************************
#
function Restore-JsonDbFromFile {
    [cmdletbinding()]
    param(
        $jsonDb,
        [switch] $removeDeprecatedPropNames,
        [switch] $addNewDefaultProps
    )

    if($jsonDb.dbFilePath -eq ""){
        throw "Can't initialize JsonDb: the filepath wasn't set!"
    }

    if(Test-Path $jsonDb.dbFilePath){
        # deprecated props won't be imported and will be overwritten/deleted at next DB write action for its parent
        Write-Host "Loading json database from file $($jsonDb.dbFilePath)" -ForegroundColor Green
        $data = (Get-Content $jsonDb.dbFilePath | Out-String)
        if($data){
        ($data | convertfrom-json).psobject.properties `
            | ForEach-Object {
            $importedObject = $_.Value
            if($removeDeprecatedPropNames){
                # filter out deprecated props
                $importedObject = ($_.Value | Select-Object -Property * -ExcludeProperty $deprecatedPropNames)
            }
            if($addNewDefaultProps){
                # add new default props
                foreach($newProp in $newDefaultProps.GetEnumerator()){
                if(-not($importedObject.psobject.properties.name -contains $newProp.Name)){
                    $importedObject | Add-Member -MemberType NoteProperty -Name $newProp.Name -Value $newProp.Value
                }
                }
            }
            $jsonDb.data[$_.Name] = $importedObject
            }
        # don't trust the order in the file
        $jsonDb.data = $jsonDb.getDbDataReordered()
        }else{
        Write-Warning "Json database file not found: $($jsonDb.dbFilePath)"
        Write-Warning "--> starting with empty local DB."
        $jsonDb.data = [ordered]@{}
        $jsonDb.saveToFile()
        }
    }
}

#***************************************************
#
function Reset-JsonDb {
  param($jsonDb, [bool]$force)
  $jsonDb.removeDbFile($force)
  $jsonDb.restoreFromFile()
}

#***************************************************
#
function Add-JsonDbItemPermanently{
  param($jsonDb, $key, $value)

  if($key -ne ""){
    $jsonDb.data[$key]=$value
    $jsonDb.data = $jsonDb.getDbDataReordered()
    $jsonDb.saveToFile()
  }else{
    throw (
      "Can't store value with empty key."+
      "Value is`n$value"
    )
  }

}

#***************************************************
# Create a json-db object (not the file)
# If the file already exists load the data from it.
#
function Initialize-JsonDb{
  [cmdletbinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$filePath,

    [Parameter(Mandatory=$false)]
    [hashtable]$orderBy = @{Expression={$_.key}; Descending=$false}
  )


  $currDb = [PSCustomObject]@{
    name = $name
    dbFilePath = $filePath
    orderBy = $orderBy
    data = [ordered]@{}
    backupDirName = "bak"
    deprecatedPropNames=@()
    newDefaultProps=@{}
  }

  Add-Member -name restoreFromFile -InputObject $currDb -MemberType ScriptMethod `
    -Value { Restore-JsonDbFromFile $this }

  Add-Member -name saveToFile -InputObject $currDb -MemberType ScriptMethod `
    -Value { param($depth,$forceDirCreate = $false); Save-JsonDbToFile $this $depth $forceDirCreate}

  Add-Member -name reset -InputObject $currDb -MemberType ScriptMethod `
    -Value { Reset-JsonDb $this }

  Add-Member -name removeDbFile -InputObject $currDb -MemberType ScriptMethod `
    -Value { Remove-JsonDbFile $this }

  Add-Member -name createBackupFile -InputObject $currDb -MemberType ScriptMethod `
    -Value { New-JsonDbBackupFile $this }

  Add-Member -name getDbDataReordered -InputObject $currDb -MemberType ScriptMethod `
    -Value { Get-JsonDbDataReordered $this }

   Add-Member -name addItemPermanently -InputObject $currDb -MemberType ScriptMethod `
    -Value { Add-JsonDbItemPermanently $this }

  $currDb.restoreFromFile()
  return $currDb
}

Export-ModuleMember -Function * -Alias *