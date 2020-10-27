Azure - Identify and Optionally Delete Orphaned Disks
=====================================================

            

PowerShell script to automate identifying 'Orphaned Disks' in an Azure subscription. An Orphaned Disk is a Disk that does NOT have an 'Active Lease' (Unmanaged Disks) or does NOT have a 'ManagedBy' property set to a VM (Managed Disks). The script outputs
 information to a log file and CSV and can Optionally Delete the Disks it identifies. 


 



**Script:**

**    Version:    2.0.0    Created:    01/02/2018    Updated:   14/05/2019
**


**Update History:
**



**2.0.0** - 14th May 2019 - Updated script to use 'Az' Module (*instead of AzureRM*) and added a filter to exclude Managed Disks with '-ASRReplica' at the end of the disk name, to remove Azure Site Recovery (ASR) Replica disks
 from being identified.





**1.5.0** - 11th July 2018 - Minor update to 'Get-AzureStorageBlob' to include '-Blob *.vhd' due to issues with storage accounts with a very large
 number of blobs

**1.4.0** - 7th March 2018 - Minor update: Hash tables updated to use
[ordered]@{} to set order of columns in CSV Output

**1.3.1** - 21st Feb 2018 - First version published on TechNet Gallery


 


**Dependencies:**




**Az.Accounts and Az.Storage **Modules 




 

**

PowerShell
#Install the Azure Resource Manager modules from the PowerShell Gallery 
Install-Module -Name Az

#Or if already installed, Update the Azure Resource Manager modules from the PowerShell Gallery 
Update-Module -Name Az

**

**Syntax Examples:**

**

PowerShell
**#Audit Mode: **
.\azure-get-orphaned-disks.ps1 

 

**#Audit and Optional Delete Mode (*still displays a prompt to confirm deletion*):**
.\azure-get-orphaned-disks.ps1 -DeleteUnattachedDisks $True

 


**#Audit and Ignore Storage Account Access Warnings:**
.\azure-get-orphaned-disks.ps1 -IgnoreAccessWarnings

 


**#Audit and Delete Mode with Unique CSV File Names :**
.\azure-get-orphaned-disks.ps1 -DeleteUnattachedDisks $True -CSVUniqueFileNames

 


**#Audit and Delete Mode, Unique CSV File Names and Specify Export Folder Path:**
.\azure-get-orphaned-disks.ps1 -DeleteUnattachedDisks $True -CSVUniqueFileNames -OutputFolderPath 'C:\CSVExportFolder'




 


**Additional Information:**


[https://blogs.technet.microsoft.com/ukplatforms/2018/02/21/azure-cost-optimisation-series-identify-orphaned-disks-using-powershell](https://blogs.technet.microsoft.com/ukplatforms/2018/02/21/azure-cost-optimisation-series-identify-orphaned-disks-using-powershell)


** **

**

        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
