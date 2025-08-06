# Anki2 - Japanese Learning App

A Flutter-based Japanese learning application with spaced repetition system (FSRS) and dictionary integration.

## Features

### Learning System
- **Spaced Repetition**: Uses FSRS algorithm for optimal review scheduling
- **Session Statistics**: Track your learning progress with real-time analytics
  - Correct/incorrect answer tracking
  - Session accuracy percentage
  - Average response time per card
  - Session duration timer
- **Progress Tracking**: Visual progress bar showing current card position
- **Japanese Support**: Full furigana and kanji support

### Dictionary Integration
- **JMdict Database**: Comprehensive Japanese-English dictionary
- **FTS5 Search**: Fast full-text search capabilities
- **Word Details**: Detailed word information and examples

### Technical Features
- **SQLite Database**: Local storage with FFI support
- **Dark Theme**: Modern dark UI design
- **Cross-Platform**: Supports Android, iOS, Windows, macOS, and Linux

## Recent Updates

### Session Statistics Enhancement
- Added real-time session analytics accessible via the analytics icon in the app bar
- Tracks correct/incorrect answers, accuracy percentage, and average response time
- Provides visual feedback on learning progress during review sessions

## Getting Started

1. Ensure Flutter SDK is installed
2. Run `flutter pub get` to install dependencies
3. Run `flutter run` to start the application

## Dependencies

- `drift`: Database ORM
- `sqflite`: SQLite database
- `kana_kit`: Japanese text processing
- `shared_preferences`: Local storage
- `path_provider`: File system access