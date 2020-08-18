Add-Type -AssemblyName System.Web

#Setting Parameters
$project = "Piri.Gzt"
$repository = "Piri.Gzt"
$branchPrefix = "GZT-"
$webAppPrefix = "WA-Piri-Test-GZT-"
$dayCount1 = -7
$dayCount2 = -45
$date1 = [System.DateTime]::Now.AddDays($dayCount1).ToString('o')
$date1 = [System.Web.HttpUtility]::UrlEncode($date1)
$date2 = [System.DateTime]::Now.AddDays($dayCount2).ToString('o')
$date2 = [System.Web.HttpUtility]::UrlEncode($date2)
$user = "akb"
$pass = "...."
$pair = "${user}:${pass}"
$subscriptionId = "219b7fc0-cfac-4279-b640-efc409882f27"
$tenantId = "cf96026e-5a90-4f3e-8eb7-1efcf56701c2"
$resourceGroup = "RG-Piri-Test"
$workItemUrl = "https://analytics.dev.azure.com/pirimedya/$project/_odata/v1.0-preview//WorkItems?`$filter=WorkItemType eq 'Task' and State eq 'Done' and StateChangeDate le $date1 and StateChangeDate ge $date2"
$branchGetUrl = "https://dev.azure.com/pirimedya/$project/_apis/git/repositories/$repository/refs/heads/feature/{id}?api-version=4.1-preview.1"
$branchRemoveUrl = "https://dev.azure.com/pirimedya/$project/_apis/git/repositories/$repository/refs?api-version=4.1-preview.1"
$webappRemoveUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/{name}?api-version=2016-08-01"
$tokenGetUrl = "https://login.microsoftonline.com/$tenantId/oauth2/token"
$workItemUpdateUrl="https://dev.azure.com/pirimedya/$project/_apis/wit/workitems/{id}?api-version=4.1"

$resourceDeployGetUrl="https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.Resources/deployments/?api-version=2018-05-01"
$resourceDeployRemoveUrl="https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/providers/Microsoft.Resources/deployments/{deploymentName}?api-version=2018-05-01"

#region Get Azure Token
$tokenBody = @{ 
    grant_type = "client_credentials";
    client_id = "0acd278c-59dd-4074-8a9e-4cdc81933980";
    client_secret = "fe49a906-a610-4a21-aa43-fd68a3be1970";
    resource = "https://management.azure.com/";
 }

 $tokenResult = Invoke-WebRequest -Uri $tokenGetUrl -Method Post -Body $tokenBody -UseBasicParsing
 $token = ($tokenResult  | ConvertFrom-Json).access_token
 Write-Host $token

 $webappHeader = @{ Authorization = "Bearer $token" }
#endregion

#region Generate Authorization Token
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }
#endregion

# remove resource deployment
$deploymentsResult = (Invoke-WebRequest -Uri $resourceDeployGetUrl -Headers $webappHeader -UseBasicParsing) | ConvertFrom-Json
foreach($deploymentsItem in $deploymentsResult.value) {
  try {
        Invoke-WebRequest -Uri $resourceDeployRemoveUrl.replace("{deploymentName}", $deploymentsItem.name) -Method Delete -Headers $webappHeader -UseBasicParsing
    } catch [System.Net.WebException] { 
        Write-Verbose "Hata olustu: $($_.Exception.Message)"
    } 
}

# update workitem url
$workItemUpdateId = $env:BUILD_SOURCEBRANCHNAME.replace($branchPrefix,'');
$bodyWorkitemUpdate = @{
    op="add";
    path= "/fields/Custom.TestUrl";
    value="https://$webAppPrefix$workItemUpdateId.azurewebsites.net";
}
$bodyWorkitemUpdate.value = $bodyWorkitemUpdate.value.ToLower();
Invoke-WebRequest -Method Patch -Headers $headers -ContentType "application/json-patch+json" -Body ("["+($bodyWorkitemUpdate | ConvertTo-Json)+"]") -Uri $workItemUpdateUrl.Replace("{id}",$workItemUpdateId) -UseBasicParsing


# get old work items
$result = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $workItemUrl
$json = ConvertFrom-Json $result


foreach ($workitemId in $json.value.WorkItemId ) {

   $branchResult = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $branchGetUrl.replace("{id}",$branchPrefix+$workitemId) | ConvertFrom-Json 
  
   if ($null -ne $branchResult.value.objectId) {
      
        $body = @{
            name = "refs/heads/feature/abc";
            newObjectId = "0000000000000000000000000000000000000000";
            oldObjectId = "10e4ccb8406907dcbf16f7da36156ce20b7663a3";
        }
        $body.oldObjectId = $branchResult.value.objectId
        $body.name = "refs/heads/feature/$branchPrefix$workitemId"
    
        try { 
            
            #remove branch
            Invoke-WebRequest -Uri $branchRemoveUrl -Method Post -Body ($body | ConvertTo-Json) -Headers $headers -ContentType 'application/json'
            #remove webapp
            Invoke-WebRequest -Uri $webappRemoveUrl.replace("{name}","$webAppPrefix$workitemId") -Method Delete -Headers $webappHeader
       
        } catch [System.Net.WebException] { } 

    
   }
} 
