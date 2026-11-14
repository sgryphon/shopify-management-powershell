# Shopify - Assign postage rates to products

To bulk assign products to particular rates, e.g. if you want to filter a selection of products and use new rates for them.

See the top level instructions for requirements and how to access the Shopify API.

## Accessing the GraphQL API

First set up the base URL and headers, using the variables above.

```powershell
$uri = "https://$shopName.myshopify.com/admin/api/2021-01/graphql.json"
$headers = @{
  'Content-Type' = 'application/graphql';
  'X-Shopify-Access-Token' = $password
}
```

A simple query can be used to check the existing shipping profiles.

```powershell
$body = '{
  deliveryProfiles(first:10) {
    edges {
      node {
        id
        name
        default
      }
    }
  }
}'

Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body | ConvertTo-Json -Depth 5
```

You can also interactively test out queries in the Shopify API developer documentation site:
https://shopify.dev/docs/admin-api/graphql/reference/shipping-and-fulfillment/deliveryprofile#samples

## Get existing shipping profile information

You will need to get the delivery profile ID's and location group ID's to use in other queries.

```powershell
$body = '{
  deliveryProfiles(first:10) {
    edges {
      node {
        id
        name
        default
        profileLocationGroups {
          locationGroup {
            id
          }
        }
      }
    }
  }
}'

$deliveryProfiles = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
$defaultProfileId = ($deliveryProfiles.data.deliveryProfiles.edges | Where-Object { $_.node.default }).node.id
$defaultProfileId
```

You can view the content of a profile, for the zone definitions with the countries in that zone and the list of
delivery methods and prices (for different methods or conditions).

Use this to examine your current profiles, or to check the contents after you have created a new profile for
Australia Post.

## Assigning products to profiles

Get a list of all products you want to assign, e.g. from one vendor.

Parametised queries use `application/json` headers instead of raw `application/graphql`, with the query passed as a string
parameter.

```powershell
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

$wholesaleProducts = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getProductsData)
$wholesaleProducts.data.products.edges.node | Measure-Object
```

You can further filter the objects based on properties.

Then use an update query to add them to a delivery profile.

```powershell
$activeProducts = $wholesaleProducts.data.products.edges.node | ? { $_.status -eq 'ACTIVE' }
$activeProducts | Measure-Object

$activeDeliveryProfileId = ($deliveryProfiles.data.deliveryProfiles.edges | Where-Object { $_.node.name -eq 'Australia Post' }).node.id

$updateProfileQuery = 'mutation($id: ID!, $profile: DeliveryProfileInput!) {
  deliveryProfileUpdate (id: $id, profile: $profile)
  {
    profile {
      id
      name
      profileItems (first: 150) {
        edges {
          node {
            product {
              id
              handle
              vendor
            }
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
      }
    }
    userErrors {
      field
      message
    }
  }
}'

$addActiveProducts = @{
  query = $updateProfileQuery;
  variables = @{
    id = $activeDeliveryProfileId;
    profile = @{
      variantsToAssociate = $activeProducts.variants.edges.node.id
    }
  }
}

$addResult1 = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 4 $addActiveProducts)
$addResult1
```

You can reuse the same query with different variables:

```powershell
$otherProducts = $wholesaleProducts.data.products.edges.node | ? { $_.status -ne 'ACTIVE' }
$otherProducts | Measure-Object

$otherDeliveryProfileId = ($deliveryProfiles.data.deliveryProfiles.edges | Where-Object { $_.node.name -eq 'Australia Post 2' }).node.id

$addOtherProducts = @{
  query = $updateProfileQuery;
  variables = @{
    id = $otherDeliveryProfileId;
    profile = @{
      variantsToAssociate = $otherProducts.variants.edges.node.id
    }
  }
}

$addResult2 = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 4 $addOtherProducts)
$addResult2.data.deliveryProfileUpdate.profile
```
