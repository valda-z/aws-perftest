param acaName string = 'jjazacaperf'
param acrName string = 'jjazacrperf'
param location string = 'Sweden Central'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource env 'Microsoft.App/managedEnvironments@2022-10-01' = {
  name: acaName
  location: location
  properties: {
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
          resources: {
              cpu: json('.25')
              memory: '.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 100
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}
