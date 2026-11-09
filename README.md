# PeiPal App (小培同学)

Chat-first **structured-document collection & generation workstation** with dual-channel output (BLE HID keyboard emulation & multi-packet 2D barcode scanner). Medical records are the primary and most mature use case, but the template/slot/pipeline/catalog/review/output system is domain-agnostic and also fits any structured document or form-entry workflow.

---

## Architecture Overview

1. **Chat & Materials Stream**:
   - Free-text notes, hold-to-record voice with dynamic waveform visualizer and audio player.
   - Multimodal asynchronous ASR (OpenAI Whisper & Xiaomi MiMo v2.5).
   - Document Collation Workbench (`document_collate_sheet.dart`): iOS-style fluid drag reordering (with 38px hysteresis deadband), multi-select merge, single-page disassembly, and title editing.
   - Background OCR image dimension optimizer (`ocr_image_optimizer.dart`) feeding OpenAI Vision and Baidu PaddleOCR VL async job polling.

2. **Generation Engine A (domain-agnostic)**:
   - DAG topological pipeline execution (`pipeline_executor.dart`).
   - JSON Schema compilation (`output_schema_builder.dart`) with markdown fence stripping and bracket auto-repair (`output_sanitizer.dart`).
   - Low-code System Prompt orchestration (`llm_prompt_config.dart`).
   - Prompt monitoring & Dry-Run preview page (`llm_dry_run_preview_page.dart`).
   - Pluggable standard catalogs; the built-in medical preset uses an ICD-10 knowledge base (38k+ records SQLite) with super-fuzzy pinyin matching and a favorite-diagnoses tagging repository.
   - Comprehensive audit logging (`generation_logs` table) and issue validation (`record_validator.dart`).

3. **Global Background Task Center (`task_center.dart`)**:
   - Asynchronous background execution of ASR, OCR, and multi-stage LLM generation tasks.
   - Streaming updates and real-time stage progress indicators surviving UI transitions.

4. **Dual Output Channels**:
   - **BLE HID**: Serial FIFO queue with MTU-aware UTF-8 chunking, `{DONE:<id>}` acknowledgment tracking, dynamic renaming (`{NAME:...}`), and physical vibration/SnackBar feedback.
   - **Multi-Packet QR Code**: `QrPackService` automatically segments long records into `<<SEQ:ID:M/N>>` packets for on-screen carousel display and hardware barcode scanner ingestion.

---

## Getting Started

### Development Requirements
- Flutter SDK `^3.12.2` (Dart `^3.12.0`)
- Android NDK & SDK for native SQLite and JNI builds

### Common Commands
```bash
# Analyze code (0 errors expected)
flutter analyze

# Run unit and generation engine tests
flutter test

# Fast UI development on Chrome
flutter run -d chrome

# Build debug APK
flutter build apk --debug
```

### Deployment
After building the debug APK, copy it to the local share and Downloads:
```bash
cp build/app/outputs/flutter-apk/app-debug.apk /Volumes/192.168.5.100-2/
cp build/app/outputs/flutter-apk/app-debug.apk ~/Downloads/
```
*(Note: `/Volumes/192.168.5.100-2` is the actual network share; avoid using symlinks).*
