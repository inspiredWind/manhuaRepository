# Hipmh Mihon extension

This repository contains a Mihon-compatible source extension for [Hipmh](https://m.hipmh.com/).

## Features

- Popular and latest manga lists
- Keyword search with pagination
- Sort, region, genre, and status filters
- Manga details and chapter lists
- Reader image-list decoding and decoy-page removal
- Hipmh website and reader deep links

## Build

Requirements: JDK 17 or newer and an Android SDK containing API 37.

```powershell
.\gradlew.bat :src:zh:xipimanhua:assembleDebug
```

The APK is written below `src/zh/xipimanhua/build/outputs/apk/debug/`.

## Validate the live API

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1
```

The test checks the live listing, search, manga-detail, chapter-list, chapter-page, and first-image endpoints.

## Upstream

The project structure and source API follow the current [Keiyoushi extensions-source](https://github.com/keiyoushi/extensions-source) format (`libVersion = "1.6"`).

This project is not affiliated with Hipmh, Mihon, Tachiyomi, or Keiyoushi.
