# Bulk product attribute maintenance

## Retrieving product information

```powershell
$password = '<Password>'
$shopName = '<shop name>'

$uri = "https://$shopName.myshopify.com/admin/api/2026-10/graphql.json"
$jsonHeaders = @{
  'Content-Type' = 'application/json';
  'X-Shopify-Access-Token' = $password
}

$getProductsQuery = 'query($first: Int, $filter: String)
  {
    products(first: $first, query: $filter) {
      edges {
        node {
          id
          handle
          vendor
          status
          variants (first: 2) {
            edges {
              node {
                id
                title
              }
            }
          }
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
  '

$getProductsData = @{
  query = $getProductsQuery;
  variables = @{
    first = 150;
    filter = 'vendor:"Wholesale (AU)"'
  }
}

$products = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
$products.data.products.edges.node | Measure-Object
```

You can examine individual objects:

```
$products.data.products.edges.node[0]
$products.data.products.edges.node[0].variants.edges.node
$products.data.products.edges.node[0] | ConvertTo-Json -Depth 5
```

You can also use a filter in the query, e.g.

```powershell
$getProductsData = @{
  query = $getProductsQuery;
  variables = @{
    first = 150;
    filter = 'vendor:"Wholesale (AU)"'
  }
}
```

Or filter the values you get back:

```powershell
$activeProducts = $wholesaleProducts.data.products.edges.node | ? { $_.status -eq 'ACTIVE' }
$activeProducts | Measure-Object
```

## Use Shopify GraphiQL App

You can add the 'Shopify GraphiQL App' to your store, then open the App to test direct queries against your shop.

Query is in GraphQL:

```
query ($first: Int, $filter: String) {
  products(first: $first, query: $filter) {
    nodes {
      id
      handle
      vendor
      status
      title
      metafields(first: 10) {
        nodes {
          key
          namespace
          jsonValue
          value
        }
      }
      variants(first: 2) {
        nodes {
          id
          title
          sku
          barcodes(first: 3) {
            nodes {
              type
              value
            }
          }
          metafields(first: 5) {
            nodes {
              key
              namespace
              jsonValue
              value
            }
          }
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

Use the query argument in the products connection to filter by standard attributes or
metafields. The syntax follows field:value or metafields.{namespace}.{key}:value.

- Standard Filters: title, vendor, product_type, tag, handle, status, inventory_total.
- Metafield Filters: metafields.custom.material:silk or metafields.custom.color:red.
- Date/Range: created_at:>'2020-10-21' or inventory_total:>500.

For more info see https://shopify.dev/docs/api/usage/search-syntax

Parameters are provided in JSON, e.g. title starting with word:

```json
{
  "first": 5,
  "filter": "title:christmas"
}
```

Handle search appears to be exact match, e.g. "handle:christmas-heels" only matches one product, but supports wildcards, e.g. "handle:christmas-heels\*" returns both retail and wholesale set.

It's not clear how the filter applies, e.g. the following matches 'christmas-heels' as above, and 'christmas-heart-box-clicker', but for some reason also matches 'heart-of-christmas-earrings':

```json
{
  "first": 5,
  "filter": "handle:christmas-he*"
}
```

SKU search is a starts-with, e.g. the following is just the wholesale product, but "sku:190015" returns both retail and wholesale.

```json
{
  "first": 5,
  "filter": "sku:190015-W6"
}
```

### Invalid filters

Although you can filter on properties like metafields, not all metafields are valid.

Some get errors like "definition-not-admin-filterable".

```json
{
  "first": 100,
  "filter": "steampunk and status:ACTIVE and metafields.shopify.age-group:*"
}
```

## Query of relevant attributes

```powershell
$getProductsQuery = 'query ($first: Int, $filter: String) {
  products(first: $first, query: $filter) {
    nodes {
      id
      handle
      vendor
      status
      title
      metafields(first: 10) {
        nodes {
          key
          namespace
          jsonValue
          value
        }
      }
      variants(first: 2) {
        nodes {
          id
          title
          sku
          barcodes(first: 3) {
            nodes {
              type
              value
            }
          }
          metafields(first: 10) {
            nodes {
              key
              namespace
              jsonValue
              value
            }
          }
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
    first = 5;
    filter = 'handle:orchid-whispers-necklace'
  }
}

$products = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
$products.data.products.nodes | Measure-Object
$products.data.products.nodes[0] | ConvertTo-Json -Depth 10
```

## Operate in batches

```powershell
$getProductsQuery = 'query ($first: Int, $filter: String, $after: String) {
  products(first: $first, query: $filter, after: $after) {
    nodes {
      id
      handle
      vendor
      status
      title
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

$getAllFilterProducts = @{
  query = $getProductsQuery;
  variables = @{
    first = 200;
    filter = "steampunk";
  }
}

$allFilterProducts = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getAllFilterProducts)
$allFilterProducts.data.products.nodes | Measure-Object -Count | Select Count
$allFilterProducts.data.products.nodes[0].title
```

Use a filter that selects a small number of records, e.g. ~20

Initialise a variable to hold the latest cursor:

```powershell
$endCursor = $null
```

The query with a small row limit, e.g. 5, show the page info, and store the ending cursor.
Repeat the commands to get the next page until all results are returned.

```powershell
# Repeat from here
$getProductsData = @{
  query = $getProductsQuery;
  variables = @{
    first = 5;
    filter = "steampunk";
    after = $endCursor;
  }
}
$products = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
$products.data.products.nodes | Measure-Object | Select Count
$products.data.products.nodes[0].title
$products.data.products.pageInfo
$endCursor = $products.data.products.pageInfo.endCursor

# Repeat query from above until complete
```

## Update general attributes, e.g. age range

Age range is stored as a metafield on the product, so create a query that includes the metafield:

```powershell
$getProductsQuery = 'query ($first: Int, $filter: String, $after: String) {
  products(first: $first, query: $filter, after: $after) {
    nodes {
      id
      handle
      vendor
      status
      title
      metafields(first: 10) {
        nodes {
          key
          namespace
          jsonValue
          value
        }
      }
      variants(first: 2) {
        nodes {
          id
          title
          sku
          barcodes(first: 3) {
            nodes {
              type
              value
            }
          }
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}'
```

Also prep the update query:

```powershell
$setAgeGroupQuery = 'mutation($metafields: [MetafieldsSetInput!]!) {
  metafieldsSet(metafields: $metafields) {
    metafields {
      namespace
      key
      jsonValue
    }
    userErrors {
      field
      message
    }
  }
}'

$ageGroupValue = ConvertTo-Json -InputObject @('gid://shopify/Metaobject/614402326679') -Compress
```

### Update one batch at a time

We want to operate on one page at a time, so select a page of data:

```powershell
$endCursor = $null # Skip this for subsequent batches

$getProductsData = @{
  query = $getProductsQuery;
  variables = @{
    first = 5;
    filter = "steampunk and status:ACTIVE";
    after = $endCursor;
  }
}
$products = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
$products.data.products.nodes | Measure-Object | Select Count
$products.data.products.nodes[0].title
$endCursor = $products.data.products.pageInfo.endCursor
```

Filter products in the batch that do not have age-group metafield:

```powershell
$productsWithoutAgeGroup = $products.data.products.nodes | Where-Object {
    @($_.metafields.nodes | Where-Object {
        $_.namespace -eq 'shopify' -and $_.key -eq 'age-group'
    }).Count -eq 0
}
$productsWithoutAgeGroup | Measure-Object | Select Count
```

Set the `shopify.age-group` metafield on those products. The value for this list metafield must be a JSON array, and `metafieldsSet` accepts up to 25 metafields per request:

```powershell
$metafieldsToSet = @($productsWithoutAgeGroup | ForEach-Object {
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

$setAgeGroupResult = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 5 $setAgeGroupData)
$setAgeGroupResult.errors
```

### Update products with a script

[Set-ProductAgeGroup.ps1](Set-ProductAgeGroup.ps1) updates one page of 'shopify.age-group' values where missing,
only for products whose assigned category supports the metafield. Products without a category are skipped.

Required parameters:

- `-Uri`: Shopify GraphQL Admin API endpoint.
- `-JsonHeaders`: JSON content type and Shopify access token headers.
- `-AfterCursor`: Pass the previous end cursor for the next page.

Optional:

- `-BatchSize`: Number of products to retrieve; default 25.
- `-Filter`: Shopify product search; defaults to 'status:ACTIVE'
- `-CategoryResults`: Hashtable of category IDs and boolean applicability results; defaults to an empty cache.

Category applicability is checked only after finding a missing age group, once per unknown category.
Both supported and unsupported categories are cached. Verbose output for each new result includes
the category full name, ID, and `$true` or `$false`. Use those results to seed the cache for future runs:

```powershell
$categoryResults = @{
  # 'gid://shopify/TaxonomyCategory/<category ID>' = $true
  # 'gid://shopify/TaxonomyCategory/<another category ID>' = $false
}
```

To run one batch:

```powershell
$VerbosePreference = 'Continue'
$result = .\Set-ProductAgeGroup.ps1 -Uri $uri -JsonHeaders $jsonHeaders -CategoryResults $categoryResults
$result
```

To process all pages:

```powershell
$VerbosePreference = 'Continue'
$result = $null
do {
  $result = .\Set-ProductAgeGroup.ps1 -Uri $uri -JsonHeaders $jsonHeaders -AfterCursor $result.NextAfterCursor
} while ($result.nextAfterCursor)
```

## Ideas

- Set product classification attributes required by Zonos, e.g. set Age Range = Adult, so Zonos does flag them for child safety accreditation requirements.

- Using existing SKUs to set custom product identifiers for EU requirements (where barcode aren't available). Or set the non-standard exception flags.

- Use existing 6-digit HS codes to set USA-specific 10-digit HS codes
