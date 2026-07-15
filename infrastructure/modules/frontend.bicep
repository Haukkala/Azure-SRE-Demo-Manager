// Frontend module - React App on Azure App Service
@description('Location for all frontend resources')
param location string

@description('Log Analytics Workspace ID for Application Insights')
param logAnalyticsWorkspaceId string

@description('Environment URLs for the APIs')
param lisbonApiUrl string = ''
param madridApiUrl string = ''
param parisApiUrl string = ''
param berlinApiUrl string = ''
param chaosControlUrl string = ''
param vmHealthControlUrl string = ''

@description('Tags to apply to resources')
param tags object = {}

// App Service Plan (Linux, F1 Free tier).
// NOTE: this subscription has 0 quota for the standardAv2Family VM family (covers Basic/Standard
// tiers) in northeurope - Premium v3 has quota instead but costs meaningfully more. F1 runs on
// shared multi-tenant compute and doesn't draw from that quota pool. Trade-offs: no custom
// domains/SSL, ~60 min/day compute quota, no VNet integration, no Always On. Fine for a demo
// frontend; move to a paid tier (and request an Av2 quota increase, or use Premium v3) for
// anything beyond that.
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-parking-frontend'
  location: location
  tags: tags
  sku: {
    name: 'F1'
    tier: 'Free'
    size: 'F1'
    family: 'F'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux plans
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-parking-frontend'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    RetentionInDays: 30
  }
}

// App Service for React Frontend
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'app-parking-frontend-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: false // Always On isn't available on the Free (F1) tier
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'REACT_APP_LISBON_API_URL'
          value: lisbonApiUrl
        }
        {
          name: 'REACT_APP_MADRID_API_URL'
          value: madridApiUrl
        }
        {
          name: 'REACT_APP_PARIS_API_URL'
          value: parisApiUrl
        }
        {
          name: 'REACT_APP_BERLIN_API_URL'
          value: berlinApiUrl
        }
        {
          name: 'REACT_APP_CHAOS_CONTROL_URL'
          value: chaosControlUrl
        }
        {
          name: 'REACT_APP_VM_HEALTH_CONTROL_URL'
          value: vmHealthControlUrl
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
      ]
      appCommandLine: 'node server.js'
    }
  }
}

// Outputs
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output appServicePlanName string = appServicePlan.name
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
