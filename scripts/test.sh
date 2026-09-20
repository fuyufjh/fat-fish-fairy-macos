#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -parse-as-library -I Sources/CSQLite Sources/FatFishFairy/StateStore.swift Sources/FatFishFairy/AppLog.swift Sources/FatFishFairy/PromptBuilder.swift Sources/FatFishFairy/APIConfiguration.swift Sources/FatFishFairy/Models.swift Sources/FatFishFairy/DeepSeek.swift Tests/FatFishFairyTests/*.swift -o .build/checks/SmokeTests
.build/checks/SmokeTests
