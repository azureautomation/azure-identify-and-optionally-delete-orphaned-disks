##########################################################################################################
<#
.SYNOPSIS
    Author:     Neil Bird, MSFT
    Version:    2.0.0
    Created:    01/02/2018
    Updated:    14/05/2019

    This script identifies 'Unattached' Disks in an Azure Subscription and can Optionally delete the
    disks, thus saving storage costs. The output is saved to 2 x CSV Files, one for Managed and one
    for Unmanaged Disks.
    
    The script has been updated to Exclude any Managed Disks with "-ASRReplica" at the end of the Disks name.

.DESCRIPTION
    This script automates the process of identifying Unattached Disks in an Azure subscription.
    A script transcript (.log) file is created in addition to 2 x CSV Output files that provide details of any
    Unattached disks, this is spilt into Unmanaged (storage accounts) and Managed Disks.
    Useful information such as the disk size, disk type (standard / premium) is included.

    Lastly, the script provides the optional capabilitiy to delete the Unattached disks that are identifed.

.EXAMPLE
    For Audit mode, run the script with no parameters:

        .\azure-get-orphaned-disks.ps1

    To Delete Orphaned Disks that are identified, pass the "-DeleteUnattachedDisks $True" parameter:

        .\azure-get-orphaned-disks.ps1 -DeleteUnattachedDisks $True

.NOTES
    THIS CODE-SAMPLE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED 
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR 
    FITNESS FOR A PARTICULAR PURPOSE.

    This sample is not supported under any Microsoft standard support program or service. 
    The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    implied warranties including, without limitation, any implied warranties of merchantability
    or of fitness for a particular purpose. The entire risk arising out of the use or performance
    of the sample and documentation remains with you. In no event shall Microsoft, its authors,
    or anyone else involved in the creation, production, or delivery of the script be liable for 
    any damages whatsoever (including, without limitation, damages for loss of business profits, 
    business interruption, loss of business information, or other pecuniary loss) arising out of 
    the use of or inability to use the sample or documentation, even if Microsoft has been advised 
    of the possibility of such damages, rising out of the use of or inability to use the sample script, 
    even if Microsoft has been advised of the possibility of such damages. 

#>
##########################################################################################################

###############################
## SCRIPT OPTIONS & PARAMETERS
###############################

#Requires -Version 3
#Requires -Modules Az.Accounts, Az.Storage

# Define and validate parameters
[CmdletBinding()]
Param(
	    # Optional. Azure Subscription Name, can be passed as a Parameter
	    [parameter(Position=1)]
	    [string]$SubscriptionName = "SUBSCRIPTION NAME",

        # Set $DeleteUnattachedDisks = $True if you want to generate a Report AND Prompt to Delete Unattached Disk
        # Set $DeleteUnattachedDisks = $False if you only want to generate a Report
	    [parameter(Position=2)]
	    [bool]$DeleteUnattachedDisks = $False,

	    # Folder Path for Output, if not specified defaults to script folder
	    [parameter(Position=3)]
        [string]$OutputFolderPath = "FOLDERPATH",
        # Exmaple: C:\Scripts\

        # Unique file names for CSV files, optional Switch parameter so the script defaults to same file name
	    [parameter(Position=4)]
        [switch]$CSVUniqueFileNames,

        # Ignore Access Warnings, optional Switch parameter to not output Storage Account access information
	    [parameter(Position=5)]
        [switch]$IgnoreAccessWarnings

	)

# Set strict mode to identify typographical errors
Set-StrictMode -Version Latest


##########################################################################################################


###################################
## FUNCTION 1 - Out-ToHostAndFile
###################################
# Function used to create a transcript of output, this is in addition to CSVs.
###################################
Function Out-ToHostAndFile {

    Param(
	    # Azure Subscription Name, can be passed as a Parametery or edit variable below
	    [parameter(Position=0,Mandatory=$True)]
	    [string]$Content,

        [parameter(Position=1)]
        [string]$FontColour,

        [parameter(Position=2)]
        [switch]$NoNewLine
    )

    # Write Content to Output File
    if($NoNewLine.IsPresent) {
        Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content -NoNewline
    } else {
        Out-File -FilePath $OutputFolderFilePath -Encoding UTF8 -Append -InputObject $Content
    }

    if([string]::IsNullOrWhiteSpace($FontColour)){
        $FontColour = "White"
    }

    if($NoNewLine.IsPresent) {
        Write-Host $Content -ForegroundColor $FontColour -NoNewline
    } else {
        Write-Host $Content -ForegroundColor $FontColour
    }


}

#######################################
## FUNCTION 2 - Set-OutputLogFiles
#######################################
# Generate unique log file names
#######################################
Function Set-OutputLogFiles {

    [string]$FileNameDataTime = Get-Date -Format "yy-MM-dd_HHmmss"

    # Default to script folder, or user profile folder.
    if([string]::IsNullOrWhiteSpace($script:MyInvocation.MyCommand.Path)){
        $ScriptDir = "."
    } else {
        $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
    }

    if($OutputFolderPath -eq "FOLDERPATH") {
        # OutputFolderPath param not used
        $OutputFolderPath = $ScriptDir
        $script:OutputFolderFilePath = "$($ScriptDir)\azure-get-orphaned-disks_$($FileNameDataTime).log"

    } else {
        # OutputFolderPath param has been set, test it is valid
        if(Test-Path($OutputFolderPath)){
            # Specified folder is valid, use it.
            $script:OutputFolderFilePath = "$OutputFolderPath\azure-get-orphaned-disks_$($FileNameDataTime).log"

        } else {
            # Folder specified is not valid, default to script or user profile folder.
            $OutputFolderPath = $ScriptDir
            $script:OutputFolderFilePath = "$($ScriptDir)\azure-get-orphaned-disks_$($FileNameDataTime).log"

        }
    }

    #CSV Output File Paths, can be unique depending on boolean flag
    if($CSVUniqueFileNames.IsPresent) {
        $script:OutputFileUnmanagedDisksCSV = "$OutputFolderPath\azure-orphaned-Unmanaged-disks_$($FileNameDataTime).csv"
        $script:OutputFileManagedDisksCSV = "$OutputFolderPath\azure-orphaned-Managed-disks_$($FileNameDataTime).csv"
    } else {
        $script:OutputFileUnmanagedDisksCSV = "$OutputFolderPath\azure-orphaned-Unmanaged-disks.csv"
        $script:OutputFileManagedDisksCSV = "$OutputFolderPath\azure-orphaned-Managed-disks.csv"
    }
}



#######################################
## FUNCTION 3 - Get-AzurePSConnection
#######################################

Function Get-AzurePSConnection {

    # Title for Out-GridView Dialog box
    if($DeleteUnattachedDisks) {
        [string]$GridViewTile = "Select the Subscription/Tenant ID to IDENTIFY AND DELETE any Unattached Disks"
    } else {
        [string]$GridViewTile = "Select the Subscription/Tenant ID to IDENTIFY any Unattached Disks"
    }

    # Ensure $SubscriptionName Parameter has been Passed or edited in the script Params.
    if($SubscriptionName -eq "SUBSCRIPTION NAME") {

        Try {

            $AzContext = (Get-AzSubscription -ErrorAction Stop | Out-GridView `
            -Title $GridViewTile `
            -PassThru)

            Try {
                Set-AzContext -TenantId $AzContext.TenantID -SubscriptionName $AzContext.Name -ErrorAction Stop -WarningAction Stop
            } Catch [System.Management.Automation.PSInvalidOperationException] {
                Write-Error "Error: $($error[0].Exception)"
                Exit
            }

        } Catch {

            # If not logged into Azure
            if($error[0].Exception.ToString().Contains("Run Login-AzAccount to login.")) {

                # Login to Azure
                Login-AzAccount -ErrorAction Stop

                # Show Out-GridView for a pick list of Tenants / Subscriptions
                $AzContext = (Get-AzSubscription -ErrorAction Stop | Out-GridView `
                -Title $GridViewTile `
                -PassThru)

                Try {
                    Set-AzContext -TenantId $AzContext.TenantID -SubscriptionName $AzContext.Name -ErrorAction Stop -WarningAction Stop
                } Catch [System.Management.Automation.PSInvalidOperationException] {
                    Write-Error "Error: $($error[0].Exception)"
                    Exit
                }

            } else { # EndIf Not Logged In

                Write-Error "Error: $($error[0].Exception)"
                Exit

            }
        }

    } else { # $SubscriptionName has been specified

        # Check if we are already logged into Azure...
        Try {

            # Set Azure RM Context to -SubscriptionName, On Error Stop, so we can Catch the Error.
            Set-AzContext -SubscriptionName $SubscriptionName -WarningAction Stop -ErrorAction Stop

        } Catch {

            # If not logged into Azure
            if($error[0].Exception.ToString().Contains("Run Login-AzAccount to login.")) {

                # Connect to Azure, as no existing connection.
                Out-ToHostAndFile "No Azure PowerShell Session found"
                Out-ToHostAndFile  "`nPrompting for Azure Credentials and Authenticating..."

                # Login to Azure Resource Manager (ARM), if this fails, stop script.
                try {
                    Login-AzAccount -SubscriptionName $SubscriptionName -ErrorAction Stop
                } catch {

                    # Authenticated with Azure, but does not have access to subscription.
                    if($error[0].Exception.ToString().Contains("does not have access to subscription name")) {

                        Out-ToHostAndFile "Error: Unable to access Azure Subscription: '$($SubscriptionName)', please check this is the correct name and/or that your account has access.`n" "Red"
                        Out-ToHostAndFile "`nDisplaying GUI to select the correct subscription...."

                        Login-AzAccount -ErrorAction Stop

                        $AzContext = (Get-AzSubscription -ErrorAction Stop | Out-GridView `
                        -Title $GridViewTile `
                        -PassThru)

                        Try {
                            Set-AzContext -TenantId $AzContext.TenantID -SubscriptionName $AzContext.Name -ErrorAction Stop -WarningAction Stop
                        } Catch [System.Management.Automation.PSInvalidOperationException] {
                            Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                            Exit
                        }
                    }
                }

            # Already logged into Azure, but Subscription does NOT exist.
            } elseif($error[0].Exception.ToString().Contains("Please provide a valid tenant or a valid subscription.")) {

                Out-ToHostAndFile "Error: You are logged into Azure with account: '$((Get-AzContext).Account.id)', but the Subscription: '$($SubscriptionName)' does not exist, or this account does not have access to it.`n" "Red"
                Out-ToHostAndFile "`nDisplaying GUI to select the correct subscription...."

                $AzContext = (Get-AzSubscription -ErrorAction Stop | Out-GridView `
                -Title $GridViewTile `
                -PassThru)

                Try {
                    Set-AzContext -TenantId $AzContext.TenantID -SubscriptionName $AzContext.Name -ErrorAction Stop -WarningAction Stop
                } Catch [System.Management.Automation.PSInvalidOperationException] {
                    Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                    Exit
                }

            # Already authenticated with Azure, but does not have access to subscription.
            } elseif($error[0].Exception.ToString().Contains("does not have access to subscription name")) {

                Out-ToHostAndFile "Error: Unable to access Azure Subscription: '$($SubscriptionName)', please check this is the correct name and/or that account '$((Get-AzContext).Account.id)' has access.`n" "Red"
                Exit

            # All other errors.
            } else {

                Out-ToHostAndFile "Error: $($error[0].Exception)" "Red"
                # Exit script
                Exit

            } # EndIf Checking for $error[0] conditions

        } # End Catch

    } # EndIf $SubscriptionName has been set

    $Script:ActiveSubscriptionName = (Get-AzContext).Subscription.Name
    $Script:ActiveSubscriptionID = (Get-AzContext).Subscription.Id

    # Successfully logged into Az
    Out-ToHostAndFile "SUCCESS: " "Green" -nonewline; `
    Out-ToHostAndFile "Logged into Azure using Account ID: " -NoNewline; `
    Out-ToHostAndFile (Get-AzContext).Account.Id "Green"
    Out-ToHostAndFile " "
    Out-ToHostAndFile "Subscription Name: " -NoNewline; `
    Out-ToHostAndFile $Script:ActiveSubscriptionName "Green"
    Out-ToHostAndFile "Subscription ID: " -NoNewline; `
    Out-ToHostAndFile $Script:ActiveSubscriptionID "Green"
    Out-ToHostAndFile " "

} # End of function Login-To-Azure


###############################################
## FUNCTION 4 - Export-ReportDataCSV
###############################################
function Export-ReportDataCSV
{
    param (
        [Parameter(Position=0,Mandatory=$true)]
        $HashtableOfData,

        [Parameter(Position=1,Mandatory=$true)]
        $FullFilePath
    )

	# Create an empty Array to hold Hash Table
	$Data = @()
	$Row = New-Object PSObject
	$HashtableOfData.GetEnumerator() | ForEach-Object {
		# Loop Hash Table and add to PSObject
		$Row | Add-Member NoteProperty -Name $_.Name -Value $_.Value
    }

    # Add Subscription Name and ID to CSV File for Reporting
    $Row | Add-Member NoteProperty -Name "Subscription Name" -Value $Script:ActiveSubscriptionName
    $Row | Add-Member NoteProperty -Name "Subscription ID" -Value $Script:ActiveSubscriptionID

	# Assign PSObject to Array
	$Data = $Row

	# Export Array to CSV
    $Data | Export-CSV -Path $FullFilePath -Encoding UTF8 -NoTypeInformation -Append -Force

}

###############################################
## FUNCTION 5 - Get-BlobSpaceUsedInGB
###############################################
function Get-BlobSpaceUsedInGB
{
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageBlob]$Blob
        )

    # Base + blob name
    $blobSizeInBytes = 124 + $Blob.Name.Length * 2

    # Get size of metadata
    $metadataEnumerator = $Blob.ICloudBlob.Metadata.GetEnumerator()
    while ($metadataEnumerator.MoveNext())
    {
        $blobSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + $metadataEnumerator.Current.Value.Length
    }

    if ($Blob.BlobType -eq [Microsoft.WindowsAzure.Storage.Blob.BlobType]::BlockBlob) 
    {
        try {
            #BlockBlob 
            $blobSizeInBytes += 8
            $Blob.ICloudBlob.DownloadBlockList() | ForEach-Object { $blobSizeInBytes += $_.Length + $_.Name.Length }
        } catch {
            #Error, unable to determine Block Blob used space
            Out-ToHostAndFile "Info: " "Yellow" -NoNewLine
            Out-ToHostAndFile "Unable to determine the Used Space inside Block Blob: $($Blob)"
            Out-ToHostAndFile " "
            return "Unknown"
        }
    } else { 
        try {
            #Page Blob
            $Blob.ICloudBlob.GetPageRanges() | ForEach-Object { $blobSizeInBytes += 12 + $_.EndOffset - $_.StartOffset }
        } catch {
            # Error, unable to determine Page Blob used space
            Out-ToHostAndFile "Info: " "Yellow" -NoNewLine
            Out-ToHostAndFile "Unable to determine the Used Space inside Page Blob: $($Blob)"
            Out-ToHostAndFile " "
            return "Unknown"
        }
    }

    # Return the BlobSize in GB
    return ([math]::Round($blobSizeInBytes / 1024 / 1024 / 1024))
}

###############################################
## FUNCTION 6 - Get-UnattachedUnmanagedDisks
###############################################

Function Get-UnattachedUnmanagedDisks {

    Out-ToHostAndFile "Checking for Unattached Unmanaged Disks...."
    Out-ToHostAndFile " "

    $storageAccounts = Get-AzStorageAccount

    [array]$OrphanedDisks = @()

    foreach($storageAccount in $storageAccounts){

        try {
            $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccount.ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction Stop)[0].Value
        } catch {
            # Check switch to ignore these Storage Account Access Warnings
            if(!$IgnoreAccessWarnings.IsPresent) {
                # If there is a lock on the storage account, this can cause an error, skip these.
                if($error[0].Exception.ToString().Contains("Please remove the lock and try again")) {
                    Out-ToHostAndFile "Info: " "Yellow" -NoNewLine
                    Out-ToHostAndFile "Unable to obtain Storage Account Key for Storage Account below due to Read Only Lock:"
                    Out-ToHostAndFile "Storage Account: $($storageAccount.StorageAccountName) - Resource Group: $($storageAccount.ResourceGroupName) - Read Only Lock Present: True"
                    Out-ToHostAndFile " "
                } elseif($error[0].Exception.ToString().Contains("does not have authorization to perform action")) {
                    Out-ToHostAndFile "Info: " "Yellow" -NoNewLine
                    Out-ToHostAndFile "Unable to obtain Storage Account Key for Storage Account below due lack of permissions:"
                    Out-ToHostAndFile "Storage Account: $($storageAccount.StorageAccountName) - Resource Group: $($storageAccount.ResourceGroupName)"
                    Out-ToHostAndFile " "
                }
            }
            # Skip this Storage Account, move to next item in For-Each Loop
            Continue
        }

        $context = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $storageKey
        try {
            $containers = Get-AzStorageContainer -Context $context -ErrorAction Stop
        } catch {
            Out-ToHostAndFile "Error: " "Red" -NoNewLine
            if($error[0].Exception.ToString().Contains("This request is not authorized to perform this operation")) {
                # Error: The remote server returned an error: (403) Forbidden.
                Out-ToHostAndFile "Unable to access the Containers in the Storage Account below, Error 403 Forbidden (not authorized)."
                Out-ToHostAndFile "Storage Account: $($storageAccount.StorageAccountName) - Resource Group: $($storageAccount.ResourceGroupName)"
            } else {
                Out-ToHostAndFile "Storage Account: $($storageAccount.StorageAccountName) - Resource Group: $($storageAccount.ResourceGroupName)"
                Out-ToHostAndFile "$($error[0].Exception)"
            }
            Out-ToHostAndFile " "
            # Skip this Storage Account, move to next item in For-Each Loop
            Continue
        }

        foreach($container in $containers) {

            $blobs = Get-AzStorageBlob -Container $container.Name -Context $context `
            -Blob *.vhd | Where-Object { $_.BlobType -eq 'PageBlob' }

            #Fetch all the Page blobs with extension .vhd as only Page blobs can be attached as disk to Azure VMs
            $blobs | ForEach-Object { 

                #If a Page blob is not attached as disk then LeaseStatus will be unlocked
                if($PSItem.ICloudBlob.Properties.LeaseStatus -eq 'Unlocked') {

                    #Add each Disk to an array, used for deleting disk later
                    $OrphanedDisks += $PSItem
                    #Function to get Used Space
                    $BlobUsedDiskSpace = Get-BlobSpaceUsedInGB $PSItem

                    #Create New Hash Table for results
                    $DiskOutput = [ordered]@{}
                    $DiskOutput.Add("StorageAccountResourceGroup",$storageAccount.ResourceGroupName)
                    $DiskOutput.Add("StorageAccountName",$storageAccount.StorageAccountName)
                    $DiskOutput.Add("StorageAccountType",$storageAccount.Sku.Tier)
                    $DiskOutput.Add("StorageAccountLocation",$storageAccount.Location)
                    $DiskOutput.Add("DiskName",$PSItem.Name)
                    $DiskOutput.Add("DiskSizeGB",[math]::Round($PSItem.ICloudBlob.Properties.Length / 1024 / 1024 / 1024))
                    $DiskOutput.Add("DiskSpaceUsedGB",$BlobUsedDiskSpace)
                    $DiskOutput.Add("LastModified",$PSItem.ICloudBlob.Properties.LastModified)
                    $DiskOutput.Add("DiskUri",$PSItem.ICloudBlob.Uri.AbsoluteUri)
                    $DiskOutput.Add("Metadata_VMName",$PSItem.ICloudBlob.Metadata['MicrosoftAzureCompute_VMName'])
                    $DiskOutput.Add("Metadata_DiskType",$PSItem.ICloudBlob.Metadata['MicrosoftAzureCompute_DiskType'])

                    $DiskOutput.GetEnumerator() | Sort-Object -Property Name -Descending | ForEach-Object {
                        $line = "`t{0} = {1}" -f $_.key, $_.value
                        Out-ToHostAndFile $line
                    }
                    Out-ToHostAndFile " "

                    #Function to export data as CSV
                    Export-ReportDataCSV $DiskOutput $OutputFileUnmanagedDisksCSV

                }

            }

        }

    }

    if($OrphanedDisks.Count -gt 0) {

        Out-ToHostAndFile "Orphaned Unmanaged Disks Count = $($OrphanedDisks.Count)`n" "Red"

        if($DeleteUnattachedDisks) {

            # User prompt confirmation before processing
            [string]$UserPromptMessage = "Do you want to DELETE the $($OrphanedDisks.Count) Unmanaged Disk(s) shown above?"
            $UserPromptMessage = $UserPromptMessage + "`n`nType ""yes"" to confirm....`n`n`t"
            [string]$UserConfirmation = Read-Host -Prompt $UserPromptMessage
            if($UserConfirmation.ToLower() -ne 'yes') {

                # User reponse was NOT "yes", ake no action
                Out-ToHostAndFile "`nUser typed ""$($UserConfirmation)"", No deletion performed...`n`n" "Green"

            } else {
                Out-ToHostAndFile " "
                Out-ToHostAndFile "Proceeding....`n"
                
                foreach ($Disk in $OrphanedDisks) {

                        Out-ToHostAndFile "Deleting unattached VHD with Uri: $($Disk.ICloudBlob.Uri.AbsoluteUri)"
                        # Delete the Disk and use -PassThru to return Boolean for Success / Fail
                        $DeleteDisk = $Disk | Remove-AzStorageBlob -Force -PassThru
                        if($DeleteDisk){
                            Out-ToHostAndFile "SUCCESS: " "Green" -nonewline; `
                            Out-ToHostAndFile "Disk Deleted"
                            Out-ToHostAndFile " "
                        } else {
                            Out-ToHostAndFile "FAILED: " "Red" -nonewline; `
                            Out-ToHostAndFile "Unable to delete unattached VHD with Uri: $($Disk.ICloudBlob.Uri.AbsoluteUri)"
                            Out-ToHostAndFile " "
                        }
                    }
            }
        }
 
    } else {

            Out-ToHostAndFile "No Orphaned Unmanaged Disks found" "Green"
            Out-ToHostAndFile " "

        }
}

#############################################
## FUNCTION 7 - Get-UnattachedManagedDisks
#############################################

Function Get-UnattachedManagedDisks {

    Out-ToHostAndFile "Checking for Unattached Managed Disks...."
    Out-ToHostAndFile " "

    # ManagedBy property stores the Id of the VM to which Managed Disk is attached to
    # If ManagedBy property is $null then it means that the Managed Disk is not attached to a VM

    # Additional check added for Azure Site Recovery (ASR): If the Disk Name ends in "-ASRReplica" it is highly likely
    # the disk is a DR replica, this check excludes those disks from processing. 

    $ManagedDisks = @(Get-AzDisk | Where-Object { $PSItem.ManagedBy -eq $Null -and !$PSItem.Name.EndsWith("-ASRReplica")})

    if($ManagedDisks.Count -gt 0) {

        foreach ($Disk in $ManagedDisks) {

            #Create New Hash Table for results
            $DiskOutput = [ordered]@{}
            $DiskOutput.Add("ResourceGroupName",$Disk.ResourceGroupName)
            $DiskOutput.Add("Name",$Disk.Name)
            $DiskOutput.Add("DiskType",$Disk.Sku.Tier)
            $DiskOutput.Add("OSType",$Disk.OSType)
            $DiskOutput.Add("DiskSizeGB",$Disk.DiskSizeGB)
            $DiskOutput.Add("TimeCreated",$Disk.TimeCreated)
            $DiskOutput.Add("ID",$Disk.Id)
            $DiskOutput.Add("Location",$Disk.Location)

            $DiskOutput.GetEnumerator() | Sort-Object -Property Name -Descending | ForEach-Object {
                $line = "`t{0} = {1}" -f $_.key, $_.value
                Out-ToHostAndFile $line
            }
            Out-ToHostAndFile " "

            #Function to export data as CSV
            Export-ReportDataCSV $DiskOutput $OutputFileManagedDisksCSV

        }

        Out-ToHostAndFile "Orphaned Managed Disks Count = $($ManagedDisks.Count)`n" "Red"

        if($DeleteUnattachedDisks) {

            # User prompt confirmation before processing
            [string]$UserPromptMessage = "Do you want to DELETE the $($ManagedDisks.Count) Managed Disk(s) shown above?"
            $UserPromptMessage = $UserPromptMessage + "`n`nType ""yes"" to confirm....`n`n`t"
            [string]$UserConfirmation = Read-Host -Prompt $UserPromptMessage
            if($UserConfirmation.ToLower() -ne 'yes') {

                # User reponse was NOT "yes", ake no action
                Out-ToHostAndFile "`nUser typed ""$($UserConfirmation)"", No deletion performed...`n`n" "Green"

            } else {
                Out-ToHostAndFile " "
                Out-ToHostAndFile "Proceeding....`n"

                foreach ($Disk in $ManagedDisks) {
                    Out-ToHostAndFile "Deleting unattached Managed Disk with Name: $($Disk.Name)"
                    try {
                        # Attempt to delete the disk
                        $DeleteDisk = Remove-AzDisk -ResourceGroupName $Disk.ResourceGroupName `
                        -DiskName $Disk.Name -Force -ErrorAction Stop
                    } catch {

                        if($error[0].Exception.ToString().Contains("Please remove the lock and try again.")) {
                            Out-ToHostAndFile "Info: " "Yellow" -NoNewLine
                            Out-ToHostAndFile "Unable to delete Disk '$($Disk.Name)', as there is a Resource Lock present on the Disk."

                        } else {
                            Out-ToHostAndFile "Error: " "Red" -NoNewLine
                            Out-ToHostAndFile "$($error[0])"

                        }
                        Out-ToHostAndFile " "
                        # Next disk in for-each loop
                        Continue
                    }

                    if($DeleteDisk.Status -eq "Succeeded"){
                        Out-ToHostAndFile "SUCCESS: " "Green" -nonewline; `
                        Out-ToHostAndFile "Disk Deleted"
                        Out-ToHostAndFile " "
                    } else {
                        Out-ToHostAndFile "FAILED: " "Red" -nonewline; `
                        Out-ToHostAndFile "Unable to delete unattached Managed Disk with Name: '$($Disk.Name)' `nId: $($Disk.Id)"
                        Out-ToHostAndFile $DeleteDisk.Error "Red"
                        Out-ToHostAndFile " "
                    }
                }
            }
        }

    } else {

        Out-ToHostAndFile "No Orphaned Managed Disks found" "Green"
        Out-ToHostAndFile " "

    }

}

#######################################################
# Start PowerShell Script
#######################################################


Set-OutputLogFiles

[string]$DateTimeNow = Get-Date -Format "dd/MM/yyyy - HH:mm:ss"
Out-ToHostAndFile "=====================================================================`n"
Out-ToHostAndFile "$($DateTimeNow) - 'Get Orphaned Disks' Script Starting...`n"
Out-ToHostAndFile "====================================================================="
Out-ToHostAndFile " "

Get-AzurePSConnection

Get-UnattachedManagedDisks

Get-UnattachedUnmanagedDisks

[string]$DateTimeNow = Get-Date -Format "dd/MM/yyyy - HH:mm:ss"
Out-ToHostAndFile " "
Out-ToHostAndFile "=====================================================================`n"
Out-ToHostAndFile "$($DateTimeNow) - 'Get Orphaned Disks' Script Complete`n"
Out-ToHostAndFile "=====================================================================`n"