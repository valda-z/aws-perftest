param acaName string = 'jjazacaperf'
param location string = 'Sweden Central'

resource env 'Microsoft.App/managedEnvironments@2022-10-01' = {
  name: acaName
  location: location
  properties: {
    }
}

// resource app 'Microsoft.App/containerApps@2022-10-01' = {
//   name: acaName
//   location: location
//   properties: {
//     environmentId: env.id
//     }
// }
