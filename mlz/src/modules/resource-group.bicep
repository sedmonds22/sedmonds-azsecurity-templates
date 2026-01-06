/*
Copyright (c) Microsoft Corporation.
Licensed under the MIT License.
*/

targetScope = 'subscription'

@description('When false, skips creating the resource group and returns empty outputs.')
param enabled bool = true

param mlzTags object
param name string
param location string
param tags object = {}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2019-05-01' = if (enabled) {
  name: name
  location: location
  tags: union(tags[?'Microsoft.Resources/resourceGroups'] ?? {}, mlzTags)
}

output id string = resourceGroup.?id ?? ''
output name string = resourceGroup.?name ?? ''
output location string = resourceGroup.?location ?? ''
output tags object = resourceGroup.?tags ?? {}
