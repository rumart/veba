Function Process-Init {
   [CmdletBinding()]
   param()
   Write-Host "$(Get-Date) - Processing Init`n"

   Write-Host "$(Get-Date) - Init Processing Completed`n"
}

Function Process-Shutdown {
   [CmdletBinding()]
   param()
   Write-Host "$(Get-Date) - Processing Shutdown`n"

   Write-Host "$(Get-Date) - Shutdown Processing Completed`n"
}

Function Process-Handler {
   [CmdletBinding()]
   param(
      [Parameter(Position=0,Mandatory=$true)][CloudNative.CloudEvents.CloudEvent]$CloudEvent
   )

   # Decode CloudEvent
   try {
      $cloudEventData = $cloudEvent | Read-CloudEventJsonData -Depth 10
   } catch {
      throw "`nPayload must be JSON encoded"
   }

   try {
      $jsonSecrets = ${env:ALERTMANAGER_SECRET} | ConvertFrom-Json
   } catch {
      throw "`nK8s secrets `$env:ALERTMANAGER_SECRET does not look to be defined"
   }

   if(${env:FUNCTION_DEBUG} -eq "true") {
      #Write-Host "$(Get-Date) - DEBUG: K8s Secrets:`n${env:SLACK_SECRET}`n"
      Write-Host "$(Get-Date) - DEBUG: CloudEvent`n $(${cloudEvent} | Out-String)`n"
      Write-Host "$(Get-Date) - DEBUG: CloudEventData`n $(${cloudEventData} | Out-String)`n"
      Write-Host "$(Get-Date) - DEBUG: CloudEventData`n $(${cloudEventData}.Info | Out-String)`n"
   }

   if($cloudEvent.subject -eq "com.vmware.sso.LoginSuccess"){
      if($cloudEventData.UserName -ne "administrator@vsphere.local"){
         Write-Host "$(Get-Date) - Not an admin login`n"
         return $true
      }
   }

   # Construct Alertmanager message object
   $payload = @(
         @{
            labels = @{
               alertname = $cloudEvent.subject;
               vm = $cloudEventData.Vm.Name;
               host = $cloudEventData.Host.Name;
               cluster = $cloudEventData.ComputeResource.Name;
               message = $cloudEventData.FullFormattedMessage;
            };
            annotations = @{
               message = "vCenter event";
               type = $cloudEvent.Type
            };
            startsAt = $cloudEventData.CreatedTime
            generatorURL = $cloudEvent.Source
         }
      )
   

   # Convert message object into JSON
   $body = ConvertTo-Json -InputObject $payload -Depth 5

   if(${env:FUNCTION_DEBUG} -eq "true") {
      Write-Host "$(Get-Date) - DEBUG: `"$body`""
   }

   Write-Host "$(Get-Date) - Sending Webhook payload to Alertmanager ..."
   $ProgressPreference = "SilentlyContinue"

   try {
      Invoke-WebRequest -Uri $(${jsonSecrets}.ALERTMANAGER_URL) -Method POST -ContentType "application/json" -Body $body
   } catch {
      throw "$(Get-Date) - Failed to send Alertmanager Message: $($_)"
   }

   Write-Host "$(Get-Date) - Successfully sent Webhook ..."
}
