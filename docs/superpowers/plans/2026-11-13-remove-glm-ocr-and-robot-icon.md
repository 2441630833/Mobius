# Remove GLM-OCR, ONNX Loading, and Input Robot Icon

> **Date:** 2026-11-13  
> **Status:** In Progress  
> **Target:** Mobius IDE root, vscode submodule, continue submodule, and installed local IDE

## 1. Root Cause & Background

1. **OCR Gating & Local GLM-OCR**:
   - When an image attachment is added to chat, `continueChatAgent.ts` checks model vision capabilities. If unverified or missing declared tokens, it falls back to `confirmLocalOcrForImages()` and `preprocessAgentRequestOcr()`, detouring into local GLM-OCR ONNX inference or cancelling the request.
   - Modern LLMs (including Alibaba Qwen-VL, DeepSeek multimodal, Volcano, Claude, GPT-4o, etc.) accept image URLs / base64 image parts directly.
   - The user requested complete removal of the GLM-OCR model (~658 MB weights) and its ONNX loading pipeline, eliminating local OCR packaging overhead and ensuring media is sent directly to the endpoint.

2. **Input Area Robot Icon**:
   - The chat mode picker in the input toolbar displays `codicon-mobius-mode-agent`, styled via Ant Design `RobotOutlined` SVG mask in `continueMobiusModeIcons.css`.
   - The user requested removing this robot icon from the input area.

## 2. Goals

1. **Remove GLM-OCR Model & Worker**:
   - Delete `onnx-community/GLM-OCR-ONNX` weights from repo and installed app.
   - Clean up GLM-OCR worker scripts (`package-glm-ocr.js`, `verify-glm-ocr-runtime.cjs`, worker esbuild config, `TransformersJsGlmOcrClient.ts`).
   - Remove GLM-OCR packaging steps from `scripts/package.ps1`, `scripts/check-prerequisites.ps1`, `scripts/launch-ide.ps1`, `package.json`, and `vscode/build/lib/extensions.ts`.
2. **Eliminate OCR Gating & Route Direct Multimodal Media**:
   - In `continueChatAgent.ts`: Always route images/media directly to `collectAgentRequestMediaParts` without OCR gating or cancellation dialogs.
   - Retire/decouple `continueOcrAction.ts`, `continueOcrConsent.ts`, and `continueOcrPreprocessor.ts`.
   - Remove the Local OCR toolbar button from `MenuId.ChatInput`.
3. **Remove Input Area Robot Icon**:
   - In `continueMobiusModeIcons.ts` / `modePickerActionItem.ts` / `continueMobiusModeIcons.css`: Remove the robot icon rendering for the Agent mode picker so the input area displays clean text ("Agent") without the robot glyph.
4. **Update Installed Build**:
   - Apply hotpatch to `C:\Users\mi\AppData\Local\Programs\Mobius\...`:
     - Delete installed `onnx-community/GLM-OCR-ONNX` model files.
     - Patch `workbench.desktop.main.js` to bypass OCR gating and remove the robot icon / OCR button.
5. **Verify**:
   - Check TypeScript syntax and compilation in vscode and continue.
   - Verify script execution.

## 3. Non-Goals

- Preserving `@codebase` text embeddings (`all-MiniLM-L6-v2`) which are used for codebase indexing.
- Modifying unrelated chat tools or web search features.

## 4. Execution Checklist

- [x] Task 1: Update `continue` submodule: remove GLM-OCR model, worker esbuild, and commands.
- [x] Task 2: Update `vscode` submodule: remove OCR gate, direct image passthrough in `continueChatAgent.ts`, remove OCR toolbar button, remove robot icon from mode picker.
- [x] Task 3: Update root scripts and package.json: remove GLM-OCR from `package.ps1`, `check-prerequisites.ps1`, `launch-ide.ps1`.
- [x] Task 4: Patch installed Mobius application: remove installed GLM-OCR weights, update `workbench.desktop.main.js`.
- [x] Task 5: Verification and clean git commit.
