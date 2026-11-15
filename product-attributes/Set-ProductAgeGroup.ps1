#!/usr/bin/env pwsh

<# .SYNOPSIS
  Set missing product age groups for one page of Shopify products.

.DESCRIPTION
  Retrieves a page of active products by default and sets missing shopify.age-group
  metafields to gid://shopify/Metaobject/614402326679. Existing age groups are left
  unchanged. Use Filter to change the Shopify product search. Only products with
  an assigned category that supports the metafield are updated.

  CategoryResults caches applicability by category ID, including false results.
  Pass the same hashtable between batches, optionally seeded with known results.
  Newly checked categories are reported with their full name, ID, and result.

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
  [string]$AfterCursor,
  ## Known category IDs and boolean applicability results; reused across batches.
  [ValidateNotNull()]
  [hashtable]$CategoryResults = @{
    'gid://shopify/TaxonomyCategory/aa-6-4' = $true # Brooches & Lapel Pins
    'gid://shopify/TaxonomyCategory/aa-6-5' = $true # Charms & Pendants
    'gid://shopify/TaxonomyCategory/aa-6-6' = $true # Earrings
    'gid://shopify/TaxonomyCategory/aa-6-7' = $true # Jewellery Sets
    'gid://shopify/TaxonomyCategory/aa-6-8' = $true # Necklaces
    'gid://shopify/TaxonomyCategory/ae-2-1-2-8-4' = $false
    'gid://shopify/TaxonomyCategory/ae-3-1-6' = $false
  }
)

$ErrorActionPreference = 'Stop'

function Test-ProductAgeGroupCategory {
  [CmdletBinding()]
  [OutputType([bool])]
  param (
    [Parameter(Mandatory)]
    [string]$CategoryId,
    [Parameter(Mandatory)]
    [string]$CategoryFullName
  )

  if ($CategoryResults.ContainsKey($CategoryId)) {
    return $CategoryResults[$CategoryId]
  }

  $checkAgeGroupQuery = 'query($categoryId: String!) {
    metafieldDefinitions(
      first: 1,
      ownerType: PRODUCT,
      namespace: "shopify",
      key: "age-group",
      constraintSubtype: {
        key: "category",
        value: $categoryId
      },
      constraintStatus: CONSTRAINED_AND_UNCONSTRAINED
    ) {
      nodes {
        id
      }
    }
  }'

  $checkAgeGroupData = @{
    query = $checkAgeGroupQuery;
    variables = @{
      categoryId = $CategoryId
    }
  }

  $checkAgeGroupResult = Invoke-RestMethod -Method Post -Uri $Uri -Headers $JsonHeaders -Body (ConvertTo-Json -Depth 3 $checkAgeGroupData)
  if ($checkAgeGroupResult.errors) { throw (ConvertTo-Json -Depth 5 $checkAgeGroupResult.errors) }

  $applies = @($checkAgeGroupResult.data.metafieldDefinitions.nodes).Count -gt 0
  $CategoryResults[$CategoryId] = $applies
  Write-Verbose "Category '$CategoryFullName': '$CategoryId' = `$$($applies.ToString().ToLowerInvariant())"
  return $applies
}

$getProductsQuery = 'query($first: Int!, $filter: String, $after: String) {
  products(first: $first, query: $filter, after: $after) {
    nodes {
      id
      handle
      category {
        id
        fullName
      }
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
$productsWithoutAgeGroup = @($productNodes |
  Where-Object { $null -eq $_.ageGroup } |
  Where-Object {
    if ($null -eq $_.category) {
      Write-Verbose "Skipping $($_.handle): no assigned category"
      return $false
    }
    Test-ProductAgeGroupCategory -CategoryId $_.category.id -CategoryFullName $_.category.fullName
  })
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
