$ErrorActionPreference = "Stop"

$apiUrl = "https://hipapi1.s3file.top"
$imageUrl = "https://hip-tx-1.s3imgs.top"
$imageUrlS1 = "https://hip-tx-s1.s3imgs.top"
$encodedAlphabet = "_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
$decodedAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function ConvertFrom-Base64Url {
    param([string]$Value)

    $normalized = $Value.Replace('-', '+').Replace('_', '/')
    while (($normalized.Length % 4) -ne 0) {
        $normalized += '='
    }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($normalized))
}

function ConvertTo-Base64Url {
    param([string]$Value)

    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Decode-ImageList {
    param([string]$Encoded)

    Assert-True ($Encoded.StartsWith('qM9') -and $Encoded.EndsWith('Z7')) "Unexpected image payload envelope"
    $body = $Encoded.Substring(3, $Encoded.Length - 5)
    $tailLength = [math]::Floor(($body.Length - 5) / 3)
    $headLength = [math]::Floor(($body.Length - 5 - $tailLength) / 2)
    $head = $body.Substring(0, $headLength)
    $midStart = $headLength + 2
    $midLength = $body.Length - 3 - $tailLength - $midStart
    $middle = $body.Substring($midStart, $midLength)
    $tail = $body.Substring($body.Length - $tailLength)
    $scrambled = $tail + $head + $middle

    $blocks = for ($i = 0; $i -lt $scrambled.Length; $i += 7) {
        $length = [math]::Min(7, $scrambled.Length - $i)
        $block = $scrambled.Substring($i, $length)
        if (([math]::Floor($i / 7) % 2) -eq 1) {
            -join $block.ToCharArray()[($block.Length - 1)..0]
        } else {
            $block
        }
    }

    $base64 = -join ((-join $blocks).ToCharArray() | ForEach-Object {
        $index = $encodedAlphabet.IndexOf($_)
        Assert-True ($index -ge 0) "Unexpected encoded character: $_"
        $decodedAlphabet[$index]
    })
    $decoded = ConvertFrom-Base64Url $base64 | ConvertFrom-Json
    foreach ($item in $decoded) {
        Write-Output $item
    }
}

Write-Host "Checking manga listing..."
$listing = Invoke-RestMethod -Uri "$apiUrl/v1/mangas?sort=popular&page=1&per_page=18" -TimeoutSec 30
Assert-True ($listing.code -eq 200 -and $listing.data.items.Count -gt 0) "Manga listing failed"
$manga = $listing.data.items[0]

Write-Host "Checking search..."
$search = Invoke-RestMethod -Uri "$apiUrl/v1/search?q=$([uri]::EscapeDataString($manga.title))&page=1&page_size=20" -TimeoutSec 30
Assert-True ($search.code -eq 200 -and $search.data.data.Count -gt 0) "Search failed"

$mid = $manga.mid.Split('-')[0]
Write-Host "Checking details and chapters for $($manga.title)..."
$details = Invoke-RestMethod -Uri "$apiUrl/v1/manga?mid=$mid" -TimeoutSec 30
$chapters = Invoke-RestMethod -Uri "$apiUrl/v1/manga/chapters?mid=$mid&page=1&per_page=50&order=desc" -TimeoutSec 30
Assert-True ($details.code -eq 200 -and -not [string]::IsNullOrWhiteSpace($details.data.title)) "Manga details failed"
Assert-True ($chapters.code -eq 200 -and $chapters.data.items.Count -gt 0) "Chapter list failed"

$chapter = $chapters.data.items[0]
$hidParts = $chapter.hid.Split('-', 2)
$chapterIdentity = (ConvertFrom-Base64Url $hidParts[0]).Split('-', 2)[1]
$apiHid = (ConvertTo-Base64Url $chapterIdentity) + '-' + $hidParts[1]

Write-Host "Checking decoded reader pages for $($chapter.title)..."
$pages = Invoke-RestMethod -Uri "$apiUrl/v2/chapter?hid=$([uri]::EscapeDataString($apiHid))" -TimeoutSec 30
Assert-True ($pages.code -eq 200 -and $pages.data.images.Length -gt 0) "Chapter page payload failed"
$images = @(Decode-ImageList $pages.data.images)
Assert-True ($images.Count -gt 0) "Decoded image list is empty"

$decoyKey = (([int64]$pages.data.sid * 0x9E3779B1L) -bxor ([int64]$images.Count * 0x85EBCA6BL)) % $images.Count
$decoyIndex = [int64]$pages.data.order_id -bxor $decoyKey
if ($decoyIndex -ge 0 -and $decoyIndex -lt $images.Count) {
    $images = @(for ($i = 0; $i -lt $images.Count; $i++) {
        if ($i -ne $decoyIndex) { $images[$i] }
    })
}

$base = if ($pages.data.line -eq 9) { $imageUrlS1 } else { $imageUrl }
$firstImage = $base + $images[0]
Write-Host "Checking first image $firstImage..."
$imageRequest = [Net.HttpWebRequest]::Create($firstImage)
$imageRequest.Method = 'GET'
$imageRequest.AddRange(0, 0)
$imageRequest.Timeout = 30000
$imageResponse = $imageRequest.GetResponse()
$imageStatus = [int]$imageResponse.StatusCode
$imageResponse.Close()
Assert-True ($imageStatus -in 200, 206) "First image request failed"

Write-Host "OK: listing=$($listing.data.items.Count), search=$($search.data.data.Count), chapters=$($chapters.data.items.Count), decodedPages=$($images.Count)"
Write-Host "OK: first image $firstImage"
