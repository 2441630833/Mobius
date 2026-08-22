# Verify GLM-OCR ONNX model files exist (fast gate — no inference).
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\ensure-glm-ocr-onnx.ps1" -Strict
