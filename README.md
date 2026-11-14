# Shopify Management with PowerShell and GraphQL

Use a Shopify Private App API via PowerShell for bulk management of your Shopify data.

Note that directly modifying Shopify data is risky, and you could end up deleting data accidentally -- make sure you know what you are doing and have a backup, e.g. downloaded CSV files or using a third-party backup app.

Examples are provided for the following operations:

- Managing postage rates, with examples for setting up standard Aus Post rates. See [auspost-rates](auspost-rates/README-auspost-rates.md)
- Bulk assigning Products to postage rates. See [product-assign-rates](product-assign-rates/README-assign-rates.md)
- Bulk managing Product attributes, with a focus on various attributes needed top satisfy postage rules, e.g. as EU product identifiers, USA HS Codes, and validation attributes such as those reported by Zonos (the customs service used by Australia Post)

## Requirements

This project contains PowerShell scripts that can be used to upload shipping rates to Shopify via the API.

You will need to have PowerShell Core (crossplatform) installed to run the scripts.

## Configure a Private App to get access to the API

In the Shopfiy admin, go to Settings > Apps > Develop apps.

**Can no longer create private apps; need to use Dev Dashboard**

You will need to enable private apps, and then create a new app (call it something like "AusPost Rates" or "Data Manager", or whatever name makes sense to you). It will need Read and write permission to Shipping, as well as other functions you want to use, e.g. to use scripts to add products to shipping, you need Read access to Products.

Record the API parameters in variables, which will be used in other scripts. For graph queries you will need the 'Password' value (you don't need the API key for Shared Secret).

```powershell
$password = '<Password>'
$shopName = '<shop name>'
```

## Basic GraphQL API access

First set up the base URL and headers, using the variables above.

```powershell
$uri = "https://$shopName.myshopify.com/admin/api/2021-01/graphql.json"
$headers = @{
  'Content-Type' = 'application/graphql';
  'X-Shopify-Access-Token' = $password
}
```

A simple query can be used to retrieve data:

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

Parametised queries use `application/json` instead of raw `application/graphql`, with the query passed as a string
parameter (see one of the sections for a specific example).

```powershell
$jsonHeaders = @{
  'Content-Type' = 'application/json';
  'X-Shopify-Access-Token' = $password
}

$getDeliveryProfileQuery = 'query($id: ID!)
{
  deliveryProfile (id: $id) {
    profileLocationGroups {
      ... // Rest of query
    }
  }
}'

$getDeliveryProfileData = @{
  query = $getDeliveryProfileQuery;
  variables = @{
    id = $defaultProfileId;
  }
}

$defaultProfileDetails = Invoke-RestMethod -Method Post -Uri $uri -Headers $jsonHeaders -Body (ConvertTo-Json -Depth 3 $getDeliveryProfileData)
$defaultProfileDetails | ConvertTo-Json -Depth 15
```

You can also interactively test out queries in the Shopify API developer documentation site:
https://shopify.dev/docs/admin-api/graphql/reference/shipping-and-fulfillment/deliveryprofile#samples

## Example operations

### Manage Australia Post postage rates

See [auspost-rates](auspost-rates/README-auspost-rates.md)

Managing postage rates, with examples for setting up standard Aus Post rates.

Note: Unless you have specialised requirements, also consider using a third party app that can do this for your automatically.

### Bulk assign products to postage rates

See [product-assign-rates](product-assign-rates/README-assign-rates.md)

Bulk assigning Products to postage rates.

### Bulk managing product attributes

**TODO**

Bulk managing Product attributes, with a focus on various attributes needed top satisfy postage rules, e.g. as EU product identifiers, USA HS Codes, and validation attributes such as those reported by Zonos (the customs service used by Australia Post)
