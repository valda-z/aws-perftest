param acaName string = 'jjazacaperf'
param acrName string = 'jjazacrperf'
param workspaceName string = 'jjazlogsperf'
param applicationInsightsName string = 'jjazlogsaiperf'
param location string = 'Sweden Central'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}
resource applicationInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

resource env 'Microsoft.App/managedEnvironments@2022-10-01' = {
  name: acaName
  location: location
  properties: {
      appLogsConfiguration:{
        logAnalyticsConfiguration: {
          customerId: workspace.properties.customerId
          sharedKey: workspace.listKeys().primarySharedKey
        }
        destination: 'log-analytics'
      }
    }
}

resource app 'Microsoft.App/containerApps@2022-10-01' = {
  name: acaName
  location: location
  properties: {
    environmentId: env.id
    configuration:{
      ingress:{
        external: true
        targetPort: 80        
      }
      secrets: [
        {
          name: 'registry-pwd'
          value: acr.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'registry-pwd'
        }
      ]
    }
    template:{
      containers: [
        {
          name: 'perftest'
          image: '${acr.properties.loginServer}/perftest:v2'
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsights.properties.ConnectionString
            }]
          resources: {
              cpu: json('0.25')
              memory: '.5Gi'
          }
        
        }
      ]
      scale: {
        minReplicas: 3
        maxReplicas: 30
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}
