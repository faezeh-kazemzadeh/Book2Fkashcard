# Privacy Policy – Book2Flashcards AI Pro

_Last updated: [publication date]_

> Template prepared for the developer. Replace bracketed placeholders and have it reviewed by counsel before publishing at https://book2flashcards.app/privacy.

[Developer legal name] ("we") publishes Book2Flashcards AI Pro (the "App"). This policy explains what happens to your information.

## 1. Summary
- Your books, scans, flashcards and study history are stored **on your device**. If you turn on iCloud Sync, they are stored in **your private iCloud database**, which we cannot access.
- To create flashcards with AI, the **text of the lesson being processed** (and, in Advanced OCR, the page image) is sent to the AI provider you choose. We do not sell it, use it for advertising, or use it to train models.
- We do not use third-party analytics, advertising or tracking SDKs.

## 2. Information processed

| Information | Where it goes | Why |
|---|---|---|
| Imported files, scanned pages, OCR text, flashcards, review history, settings | Your device; your private iCloud (if Sync is on) | Core functionality |
| Lesson text and, for low-confidence pages, page images | The AI provider you select: OpenAI, Microsoft Azure OpenAI (your own resource), our proxy service, or Apple Intelligence on-device | Generating cards, explanations, OCR correction |
| Your own API keys | Your device's Keychain, protected by the Secure Enclave; never transmitted to us | Authenticating with your AI provider |
| Purchase information | Apple | Subscriptions (we receive only anonymous entitlement status) |
| Microphone audio (speaking quizzes) | Processed by Apple's speech recognition, on device when supported | Checking spoken answers; not stored |
| Camera images | Your device | Scanning pages |

### Our proxy service (if used)
When you use "Book2Flashcards Cloud", requests pass through our server to forward them to the AI provider. We log only a pseudonymous user identifier, request counts and timestamps for quota and abuse prevention, kept for 30 days. Request contents are not stored.

### Third-party AI providers
Their handling of data is governed by their own terms: OpenAI API data is not used for training by default and is retained up to 30 days for abuse monitoring; Azure OpenAI data stays in your Azure resource's region. Apple Intelligence processes data on your device.

## 3. Children
The App is not directed at children under 13 (or the minimum age in your country). Schools using the App should configure their own AI provider.

## 4. Your choices and rights
- Delete any book (and all related data) in the App; delete everything by deleting the App and, if Sync was on, removing its data under Settings › [your name] › iCloud › Manage Storage.
- Turn off iCloud Sync and AI features at any time; offline card generation works without AI.
- Depending on your location (e.g. GDPR, UK GDPR, CCPA) you may request access, correction or deletion of data we hold (only proxy logs): [privacy@book2flashcards.app].

## 5. Security
Page images are encrypted with AES-256-GCM; your API keys are wrapped with a Secure Enclave key; network traffic uses TLS.

## 6. Changes
We will post updates here and, for material changes, notify you in the App.

## 7. Contact
[Developer legal name], [postal address] – [privacy@book2flashcards.app]
