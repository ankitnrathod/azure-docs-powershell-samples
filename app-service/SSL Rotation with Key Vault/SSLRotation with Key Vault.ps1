Import-Module Az.Websites
Import-Module Az.KeyVault

Connect-AzAccount -Identity

$keyVaultName = "<<keyvaultname>>"
$webSiteCertName = "<<certnameinkeyvault>>"
$webAppName = "<<webappname>>"
$resourceGroupName = "<<resourcegroupaname>>"
$webAppDNSName = "<<websitename>>"  # xyz.abc.com
$issuerName = "<<issuername>>"  #Self or based on Org 

# To get key vault policy for auto cert rotation
$Policy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName "CN=$webAppDNSName" -IssuerName $issuerName -ValidityInMonths 12 

# Generate new version certificate in key vault
Add-AzKeyVaultCertificate -VaultName $keyVaultName -Name $webSiteCertName -CertificatePolicy $Policy

# waiting for certificate renewal to complete
$timeInSeconds = 0
$sleepTime = 30
while(1)
{
    Write-Output "Certificate renewal inprogress"
    Start-Sleep -Seconds $sleepTime
    $timeInSeconds += $sleepTime;
    $operation = Get-AzKeyVaultCertificateOperation -VaultName $keyVaultName -Name $webSiteCertName
    if($operation.Status -eq "completed")
    {
        Write-Output "Certificate got renewed"
        break
    }
    if($operation.Status -eq "failed")
    {
        Write-Output "Certificate renewal got failed"
        break
    }
    if($timeInSeconds -eq 600)
    {
        Write-Output "Certificate renewal got timed out"
        return
    }  
}


$cert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $webSiteCertName

# import new certificate to web app
Import-AzWebAppKeyVaultCertificate  -ResourceGroupName $resourceGroupName -WebAppName $webAppName -KeyVaultName  $keyVaultName -CertName $webSiteCertName
# bind new certificate to web app
New-AzWebAppSSLBinding -ResourceGroupName $resourceGroupName -WebAppName $webAppName -Thumbprint $cert.Thumbprint -Name $webAppDNSName

#get previous version of certificate
$oldCertRecord = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $webSiteCertName -IncludeVersions  | Sort-Object -Property Created -Descending | Select-Object -First 2 | Select-Object -Last 1
$oldCert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $webSiteCertName -Version $oldCertRecord.Version

#remove previous version certificate
Remove-AzWebAppCertificate -ResourceGroupName $resourceGroupName -ThumbPrint $oldCert.Thumbprint
#restart web app
Restart-AzWebApp -ResourceGroupName $resourceGroupName -Name $webAppName 
