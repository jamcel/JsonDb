<#

#>

#***************************************************
#
$methodGetDbDataReordered = {
  $reorderedDbData = [ordered]@{}
  $this.data.GetEnumerator() `
    | Sort-Object -Descending -Property $this.orderBy `
    | ForEach-Object {
        $reorderedDbData[ $_.key ] = $_.value
      }
  $reorderedDbData
}

#***************************************************
#
$methodSaveToFile = { param($depth=20)
    Write-Host "Updating JSON database file $($this.dbFilePath)"
    $dbData=$this.getDbDataReordered()
    ConvertTo-Json $dbData -Depth $depth | out-file $this.dbFilePath
}

#***************************************************
#
$methodRemoveJsonDbFile = {
  param([bool]$force)
  if(Test-Path $this.dbFilePath){
    if(-not $force){
      $confirm = (Read-Host "Are you sure you want to delete the database file (y/n):`n    $($this.dbFilePath)").ToLower()
    }else{
      $confirm = 'y'
    }
    if($confirm -eq 'y'){
      Write-Host "Removing JSON database file $($this.dbFilePath)"
      Remove-Item -Path $this.dbFilePath
    }
  }
}

#***************************************************
#
$methodCreateNewDbBackupFile ={
  import-module "$PSScriptRoot\Modules\utils\utils.psm1"
  $db_file = (get-item $this.dbFilePath)
  $db_file_dir_path = $db_file.Directory.FullName
  $db_file_basename = $db_file.BaseName
  $db_file_extension = $db_file.Extension
  $bak_dir_path = "$db_file_dir_path\$($this.backupDirName)"
  $bak_file_name ="$($db_file_basename)_bak_$(get-date -format "yyyy_MM_dd__HH_mm_ss")$db_file_extension"
  Confirm-OrCreateDirPath $bak_dir_path -quiet
  $backup_file_path = "$bak_dir_path\$bak_file_name"
  Write-Host "Creating bakup file " -noNewLine
  Write-Host $bak_file_name -foregroundColor cyan -NoNewline
  Write-Host " in "
  Write-Host "    $bak_dir_path"-foregroundColor cyan
  Copy-Item -Path $this.dbFilePath -Destination $backup_file_path -Force
  if(Test-Path $backup_file_path){
    Write-Host "[OK]" -ForegroundColor green
  }else{
    Write-Host "[failed]" -ForegroundColor red
  }
}

#***************************************************
#
$methodRestoreFromFile={
  [cmdletbinding()]
  param(
    [switch] $removeDeprecatedPropNames,
    [switch] $addNewDefaultProps
  )

  if($this.dbFilePath -eq ""){
    throw "Can't initialize JsonDb: the filepath wasn't set!"
  }

  if(Test-Path $this.dbFilePath){
    # deprecated props won't be imported and will be overwritten/deleted at next DB write action for its parent
    Write-Host "Loading json database from file $($this.dbFilePath)" -ForegroundColor Green
    $data = (Get-Content $this.dbFilePath | Out-String)
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
          $this.data[$_.Name] = $importedObject
        }
      # don't trust the order in the file
      $this.data = $this.getDbDataReordered()
    }else{
      Write-Warning "Json database file not found: $($this.dbFilePath)"
      Write-Warning "--> starting with empty local DB."
      $this.data = [ordered]@{}
      $this.saveToFile()
    }
  }
}

#***************************************************
#
$methodResetJsonDb={
  param([bool]$force)
  $this.removeDbFile($force)
  $this.restoreFromFile()
}

#***************************************************
#
$methodAddItemPermanently={
  param($key,$value)
  if($key -ne ""){
    $this.data[$key]=$value
    $this.data = $this.getDbDataReordered()
    $this.saveToFile()
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
    -Value $methodRestoreFromFile

  Add-Member -name saveToFile -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodSaveToFile

  Add-Member -name reset -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodResetJsonDb

  Add-Member -name removeDbFile -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodRemoveJsonDbFile

  Add-Member -name createBackupFile -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodCreateNewDbBackupFile

  Add-Member -name getDbDataReordered -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodGetDbDataReordered

   Add-Member -name addItemPermanently -InputObject $currDb -MemberType ScriptMethod `
    -Value $methodAddItemPermanently

  $currDb.restoreFromFile()
  return $currDb
}

Export-ModuleMember -Function * -Alias *