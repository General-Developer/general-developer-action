# General Developer Action
 
**General Developer Action** Is complete pack Ci Action For everyone who whant fast deploy, build, anyting without any effort

[![](https://raw.githubusercontent.com/globalcorporation/.github/main/.github/logo/powered.png)](https://www.youtube.com/@Global_Corporation)


**Copyright (c) 2024 GLOBAL CORPORATION - GENERAL DEVELOPER**

## 📚️ Docs

1. [Documentation](https://youtube.com/@GENERAL_DEV)
2. [Youtube](https://youtube.com/@GENERAL_DEV)
3. [Telegram Support Group](https://t.me/DEVELOPER_GLOBAL_PUBLIC)
4. [Contact Developer](https://github.com/General-Developer) (check social media or readme profile github)
 
## Features

1. [x] Flutter & Dart
2. [ ] Installing Developer Dependencies
3. [ ] Including General Developer App For Speed Up Anythings

## 🚀️ Quick Start

Example Quickstart script minimal for insight you or make you use this action because very simple

```yaml
name: General Testing
on: 
  workflow_dispatch: 
jobs: 
  general-action-test:
    name: General Action Test
    timeout-minutes: 30
    strategy:
      # fail-fast: true
      matrix:
        include:
          # check done
          - os: macos-latest # build macos  
          - os: ubuntu-24.04 # build android 
          - os: windows-latest # build windows 
    runs-on: ${{ matrix.os }}
    steps:  
    

      - name: General Developer Action
        uses: General-Developer/general-developer-action@0.0.7
        with:
          flutter_channel: stable
          flutter_version: 3.29.0
          is_use_cache: true
          flutter_cache_key: "flutter-path-${{ runner.os }}-3.29.0"
          install_dependencies_developer: "true" # installing git ffmpeg mpv cmake cpp aand more
          install_java: "true" # Instalaling java

      - name: Mkdir Folder
        shell: bash
        run: |
          mkdir -p another-work

      - name: Flutter Version
        working-directory: another-work
        run: |
          flutter --version
```
 

**Copyright (c) 2024 GLOBAL CORPORATION - GENERAL DEVELOPER**

 