# JsonDb
Powershell module for quickly using json files as a local database.

The interactions are object based. First you create your db object using Initialize-JsonDb <filename>.
If the file exists data will be loaded into the property 'data' of the db object and you can work with it.
Otherwise a new file will be created. Storing data permanently needs to be initiated by calling saveToFile().
By default the data file is copied to the backup directory before being overwritten by saveToFile() (this
may change in future).
The data structure stored in $db.data is an orderedDictionary.

Example:
    > ($db = Initialize-JsonDb testDb.json)

    name                :
    dbFilePath          : testDb.json
    orderBy             : {Descending, Expression}
    data                : {}
    backupDirName       : bak
    deprecatedPropNames : {}
    newDefaultProps     : {}

    > ($db | get-member -MemberType ScriptMethod).name

    addItemPermanently
    createBackupFile
    getDbDataReordered
    removeDbFile
    reset
    restoreFromFile
    saveToFile

