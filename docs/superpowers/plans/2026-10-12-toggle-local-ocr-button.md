# Local OCR Toggle Button & Multimodal Direct Passthrough

## Root cause

Mobius automatically runs local GLM-OCR ONNX on user-attached images for models that are not recognized as vision-capable. However:
1. Many cloud API providers (OneAPI, NewAPI, vLLM, custom model proxies) provide multimodal models whose model identifiers do not match built-in vision regexes or whose providers support vision/video directly.
2. When local OCR runs on images for those models, users cannot leverage the cloud model's native visual reasoning capabilities, and video attachments are not passed through to multimodal endpoints.
3. Users currently have no convenient button or toggle in the chat interface to turn off local OCR and force direct image/video passthrough to the model API provider.

## Goal

1. Local OCR (`continue.localOcr.enabled`) remains **enabled by default** (`default: true`).
2. Add a one-click toggle button on the Chat Input toolbar (`MenuId.ChatInput` and `MenuId.ChatExecute`) so users can immediately switch Local OCR between Enabled (On) and Disabled (Off).
3. When Local OCR is turned off (or when the model natively supports vision):
   - Skip local GLM-OCR ONNX preprocessing completely.
   - Collect attached images AND video files (`.mp4`, `.webm`, `.mov`, `.mkv`, etc.) and send them directly to the API provider in multimodal format (`image_url` / `video_url`).
4. Update `VISION_MODEL_PATTERNS` to recognize more multimodal model families (multimodal, omni, video, doubao, kimi, hunyuan, etc.).
5. Ensure the toggle button visually reflects the current status (checked/active styling, tooltip, and label) and persists the configuration.

## Non-goals

- Removing or replacing the bundled GLM-OCR ONNX worker.
- Modifying Ollama or embeddings configuration.

## Tasks

1. [x] Register `continue.localOcr.enabled` boolean configuration setting in `continue.contribution.ts` (default: `true`).
2. [x] Register `continue.toggleLocalOcr` command and `Action2` with `MenuId.ChatInput` (and `MenuId.ChatExecute`), complete with toggle condition `config.continue.localOcr.enabled != false`, custom tooltips, title, and action view item styling in `continueOcrAction.ts`.
3. [x] Update `continueOcrPreprocessor.ts`:
   - Add video file recognition (`isLikelyVideoAttachment`, video mime detection).
   - Support collecting both images and video files into multimodal message parts (`collectAgentRequestMediaParts`).
   - Only feed images to GLM-OCR when local OCR is active.
4. [x] Update `continueChatAgent.ts`:
   - Check `continue.localOcr.enabled` configuration.
   - If disabled, bypass GLM-OCR, collect images and video files, notify user via progress markdown that media is sent directly to the model, and pass them to `buildChatMessages`.
   - Update `buildChatMessages` and attached media handling to support video and image parts.
5. [x] Update `continueLanguageModelProvider.ts`:
   - In `messagesToOpenAI`, support video and data parts (`video_url` and `data` parts with data URLs for OpenAI-compatible providers).
6. [x] Expand `VISION_MODEL_PATTERNS` in `continueModelConfig.ts` with multimodal keywords (omni, video, multimodal, etc.).
7. [x] Verify compilation with `npm run check` and `npm run compile:vscode`, and verify zero errors.

## Acceptance criteria

- `continue.localOcr.enabled` defaults to `true`.
- The toggle button is visible in the chat composer toolbar, shows active/inactive states with clear tooltips, and clicking it toggles the setting immediately.
- When toggled off, attached images and video files skip GLM-OCR and are sent directly to the API provider in multimodal format.
- Code compiles cleanly with no errors.
