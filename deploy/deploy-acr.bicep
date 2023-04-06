param acrName string = 'jjazacrperf'
param location string = 'Sweden Central'

resource acr 'Microsoft.ContainerRegistry/registries@2019-05-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
  }
}
