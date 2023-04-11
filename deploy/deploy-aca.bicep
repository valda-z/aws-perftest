param acaName string = 'jjazacaperf'
param acrName string = 'jjazacrperf'
param fdName string = 'jjazfdperf'
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
              cpu: json('1')
              memory: '2Gi'
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

resource fd 'Microsoft.Cdn/profiles@2022-11-01-preview' = {
  name: fdName
  location: 'global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

resource fdEndpoint1 'Microsoft.Cdn/profiles/afdEndpoints@2022-11-01-preview' = {
  parent: fd
  name: fdName
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource fdOriginGroupDefault 'Microsoft.Cdn/profiles/originGroups@2022-11-01-preview' = {
  parent: fd
  name: 'default-origin-group'
  properties: {
    healthProbeSettings: {
      probeProtocol: 'Https'
      probePath: '/testsimple'
      probeRequestType: 'GET'
      probeIntervalInSeconds: 100
    }
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
  }
}

resource fdOriginDefault 'Microsoft.Cdn/profiles/originGroups/origins@2022-11-01-preview' = {
  parent: fdOriginGroupDefault
  name: 'default-origin'
  properties: {
    hostName: app.properties.configuration.ingress.fqdn
    httpPort: 80
    httpsPort: 443
    originHostHeader: app.properties.configuration.ingress.fqdn
    priority: 1
    weight: 1000
    enabledState: 'Enabled'    
    enforceCertificateNameCheck: true
  }
}

resource fdRouteDefault 'Microsoft.Cdn/profiles/afdendpoints/routes@2022-11-01-preview' = {
  parent: fdEndpoint1
  name: 'default-route'
  properties: {
    originGroup: {
      id: fdOriginGroupDefault.id
    }
    enabledState: 'Enabled'
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
  }
}
