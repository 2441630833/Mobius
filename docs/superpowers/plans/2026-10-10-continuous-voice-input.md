# Plan: Continuous Voice Input for Chat Input Box

## Goal
Implement a continuous voice input (Speech-to-Text) feature in the chat input box.
Requirements:
1. Provide a voice input button in the input toolbar.
2. Real-time speech-to-text recognition as the user speaks.
3. Automatically send the transcribed text when the user finishes speaking (detected via speech completion & silence debounce).
4. Continuous interaction mode: the voice feature does NOT automatically shut down after sending. The user can continuously speak and interact across multiple turns without needing to re-activate the microphone, until they explicitly toggle it off.
5. If the model is currently streaming when the user finishes speaking, smoothly queue the transcribed message and auto-send it as soon as the stream finishes.
6. Graceful error handling (permissions, lack of Web Speech API support, speech network errors).

## Non-goals
- Offline on-device neural STT (Whisper server) which requires multi-gigabyte models or external Python daemon setups.
- Modifying backend LLM inference protocol.

## Tasks
- [x] 1. Create `continue/gui/src/hooks/useVoiceInput.ts` implementing continuous speech recognition, real-time transcription, silence detection for auto-send, stream-wait queueing, and auto-restart loop.
- [x] 2. Update `continue/gui/src/components/mainInput/InputToolbar.tsx` to add the microphone toggle button, pulsing active indicator, soundwave animation, and status banner.
- [x] 3. Wire `useVoiceInput` into `continue/gui/src/components/mainInput/TipTapEditor/TipTapEditor.tsx` to bind the active TipTap editor instance, streaming state, and `onEnter` submission.
- [x] 4. Build `continue/gui` and run `npm run sync:gui`.
- [x] 5. Verify build and check for errors.

## Acceptance Criteria
- Microphone icon appears in the input toolbar.
- Clicking the microphone icon toggles continuous voice listening.
- While speaking, speech is recognized in real time and displayed in the editor.
- When the user finishes speaking and pauses (~1.2s silence debounce), the text is automatically sent.
- After sending, voice listening remains active; `onend` automatically restarts recognition; the user can continue speaking the next message without re-clicking.
- Clicking the microphone again cleanly stops voice mode.
- GUI compiles cleanly without TypeScript errors and syncs to `continue/extensions/vscode/gui`.
