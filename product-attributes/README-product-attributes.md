# Bulk product attribute maintenance

## Retrieving product information

```powershell
$password = '<Password>'
$shopName = '<shop name>'

$uri = "https://$shopName.myshopify.com/admin/api/2021-01/graphql.json"
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

## Operate in batches

## Update general attributes, e.g. age range

## Ideas

- Set product classification attributes required by Zonos, e.g. set Age Range = Adult, so Zonos does flag them for child safety accreditation requirements.

- Using existing SKUs to set custom product identifiers for EU requirements (where barcode aren't available). Or set the non-standard exception flags.

- Use existing 6-digit HS codes to set USA-specific 10-digit HS codes
