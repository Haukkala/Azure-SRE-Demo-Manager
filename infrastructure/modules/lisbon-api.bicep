// Lisbon API module - Container App for Docker-based API
// NOTE: For production, consider using Azure Container Registry with Managed Identity
// instead of username/password authentication for improved security
@description('Location for all Lisbon API resources')
param location string

@description('Container subnet ID from hub VNet')
param containerSubnetId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Customer ID (Workspace ID for the API)')
param logAnalyticsCustomerId string

@description('Container image name')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container registry server (leave empty for public registries)')
param containerRegistry string = ''

@description('Chaos Control service URL for the chaos middleware to fetch fault configuration')
param chaosControlUrl string = ''

@description('Tags to apply to resources')
param tags object = {}

// Container App Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-parking-lisbon'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: containerSubnetId
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-parking-lisbon'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      // TODO: targetPort/probes point at 80 + '/' to match the placeholder
      // mcr.microsoft.com/azuredocs/containerapps-helloworld image (main.parameters.json doesn't
      // override lisbonContainerImage yet). Once a real image listening on 3001 with /health
      // is pushed via CI/CD, restore targetPort: 3001 and the /health probes below.
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
      registries: empty(containerRegistry) ? [] : [
        {
          server: containerRegistry
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'lisbon-parking-api'
          image: containerImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'PARKING_CITY'
              value: 'Lisbon'
            }
            {
              name: 'PARKING_NAME'
              value: 'Lisbon Central Parking'
            }
            {
              name: 'PARKING_LOCATION'
              value: 'Lisbon, Portugal'
            }
            {
              name: 'WORKSPACE_ID'
              value: logAnalyticsCustomerId
            }
            {
              name: 'SHARED_KEY'
              value: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
            }
            {
              name: 'LOG_TYPE'
              value: 'LisbonParkingLogs'
            }
            {
              name: 'CHAOS_CONTROL_URL'
              value: chaosControlUrl
            }
          ]
          // Custom httpGet probes removed for now: against the placeholder helloworld image they
          // caused the revision controller to hang and never create a revision at all (confirmed via
          // a direct az containerapp create test with no probes, which succeeded instantly). Falls
          // back to Container Apps' default TCP-based checks. Re-add /health probes once a real
          // application image is in place.
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppEnvironmentName string = containerAppEnvironment.name
output containerAppEnvironmentId string = containerAppEnvironment.id
output containerAppPrincipalId string = containerApp.identity.principalId
