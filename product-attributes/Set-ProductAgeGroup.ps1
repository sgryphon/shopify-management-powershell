#!/usr/bin/env pwsh

<# .SYNOPSIS
  Set missing product age groups for one page of Shopify products.

.DESCRIPTION
  Retrieves a page of active products by default and sets missing shopify.age-group
  metafields to gid://shopify/Metaobject/614402326679. Existing age groups are left
  unchanged. Use Filter to change the Shopify product search.

  Returns RecordCount, UpdateCount, and NextAfterCursor. NextAfterCursor is null
  when there are no more pages. Requires product read and write permissions.

.EXAMPLE
  $VerbosePreference = 'Continue'
  $result = .\Set-ProductAgeGroup.ps1 -Uri $uri -JsonHeaders $jsonHeaders -BatchSize 25 -Verbose
  $result = .\Set-ProductAgeGroup.ps1 -Uri $uri -JsonHeaders $jsonHeaders -BatchSize 25 -AfterCursor $result.NextAfterCursor -Verbose
#>
[CmdletBinding()]
param (
  ## Shopify GraphQL Admin API endpoint.
  [Parameter(Mandatory)]
  [string]$Uri,
  ## JSON content type and Shopify access token headers.
  [Parameter(Mandatory)]
  [hashtable]$JsonHeaders,
  ## Number of products to retrieve (at most 25 metafields per update).
  [ValidateRange(1, 25)]
  [int]$BatchSize = 25,
  ## Shopify product search; use an empty string to include all products.
  [string]$Filter = 'status:ACTIVE',
  ## End cursor from the previous page; omit for the first page.
  [string]$AfterCursor
)

$ErrorActionPreference = 'Stop'

$getProductsQuery = 'query($first: Int!, $filter: String, $after: String) {
  products(first: $first, query: $filter, after: $after) {
    nodes {
      id
      handle
      ageGroup: metafield(namespace: "shopify", key: "age-group") {
        id
      }
      variants(first: 1) {
        nodes {
          sku
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}'

$getProductsData = @{
  query = $getProductsQuery;
  variables = @{
    first = $BatchSize;
    filter = $Filter;
    after = if ($AfterCursor) { $AfterCursor } else { $null }
  }
}

$products = Invoke-RestMethod -Method Post -Uri $Uri -Headers $JsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
if ($products.errors) { throw (ConvertTo-Json -Depth 5 $products.errors) }

$productNodes = @($products.data.products.nodes)
$productsWithoutAgeGroup = @($productNodes | Where-Object { $null -eq $_.ageGroup })
$updateCount = 0

if ($productsWithoutAgeGroup.Count -gt 0) {
  $setAgeGroupQuery = 'mutation($metafields: [MetafieldsSetInput!]!) {
    metafieldsSet(metafields: $metafields) {
      metafields {
        id
      }
      userErrors {
        field
        message
      }
    }
  }'

  $ageGroupValue = ConvertTo-Json -InputObject @('gid://shopify/Metaobject/614402326679') -Compress
  $metafieldsToSet = @($productsWithoutAgeGroup | ForEach-Object {
    Write-Verbose "Setting age group for $($_.handle), SKU: $($_.variants.nodes[0].sku)"
    @{
      ownerId = $_.id;
      namespace = 'shopify';
      key = 'age-group';
      type = 'list.metaobject_reference';
      value = $ageGroupValue
    }
  })

  $setAgeGroupData = @{
    query = $setAgeGroupQuery;
    variables = @{
      metafields = $metafieldsToSet
    }
  }

  $setAgeGroupResult = Invoke-RestMethod -Method Post -Uri $Uri -Headers $JsonHeaders -Body (ConvertTo-Json -Depth 5 $setAgeGroupData)
  if ($setAgeGroupResult.errors) { throw (ConvertTo-Json -Depth 5 $setAgeGroupResult.errors) }
  if ($setAgeGroupResult.data.metafieldsSet.userErrors) { throw (ConvertTo-Json -Depth 5 $setAgeGroupResult.data.metafieldsSet.userErrors) }
  $updateCount = @($setAgeGroupResult.data.metafieldsSet.metafields).Count
}

[pscustomobject]@{
  RecordCount = $productNodes.Count
  UpdateCount = $updateCount
  NextAfterCursor = if ($products.data.products.pageInfo.hasNextPage) { $products.data.products.pageInfo.endCursor } else { $null }
}
