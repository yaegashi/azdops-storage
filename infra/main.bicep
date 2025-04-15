targetScope = 'subscription'

param environmentName string

param location string

param principalId string

param resourceGroupName string = ''

param userAssignedIdentityName string = ''

param keyVaultName string = ''

param storageAccountName string = ''

param storageAccountOwnerPrincipalId string = ''

param githubRepositoryUrl string = ''

param githubActionsRunUrl string = ''

var abbrs = loadJsonContent('./abbreviations.json')

var tags = {
  'azd-env-name': environmentName
}

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: union(
    tags,
    !empty(githubRepositoryUrl) ? { 'github-repository-url': githubRepositoryUrl } : {},
    !empty(githubActionsRunUrl) ? { 'github-actions-run-url': githubActionsRunUrl } : {}
  )
}

module userAssignedIdentity './app/identity.bicep' = {
  name: 'userAssignedIdentity'
  scope: rg
  params: {
    name: !empty(userAssignedIdentityName)
      ? userAssignedIdentityName
      : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVaultAccessUserAssignedIdentity './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessUserAssignedIdentity'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: userAssignedIdentity.outputs.principalId
    permissions: {
      secrets: ['list', 'get']
      certificates: ['list', 'get', 'import']
    }
  }
}

module keyVaultAccessDeployment './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessDeployment'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
    permissions: {
      secrets: ['list', 'get', 'set']
      certificates: ['list', 'get', 'import']
    }
  }
}

module storageAccount 'core/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

var ownerRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
)

module storageAccountAccess 'app/storage-access.bicep' = if (!empty(storageAccountOwnerPrincipalId)) {
  name: 'storageAccountAccess'
  scope: rg
  params: {
    storageAccountName: storageAccount.outputs.name
    roleDefinitionId: ownerRoleDefinitionId
    principalId: storageAccountOwnerPrincipalId
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_PRINCIPAL_ID string = principalId
output AZURE_RESOURCE_GROUP_NAME string = rg.name
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
