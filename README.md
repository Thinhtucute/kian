# Kian - Flashcard App for Japanese Vocabulary

Anki-clone cross-platform Flutter application for learning Japanese using spaced repetition (FSRS algorithm) with cloud synchronization.

## 🌟 What's in the app

### 🔐 Cloud Sync
- **Cloud Storage**: Automatic sync of learning progress across devices
- **User Authentication**: Secure email/password authentication via Supabase; each user's cards are isolated with Row-Level Security (RLS)

### 📚 Learning System
- **FSRS Algorithm**: Advanced spaced repetition for optimal review scheduling
- **Session Statistics**: Real-time tracking of learning progress
  - Correct/incorrect answer tracking
  - Session accuracy percentage
  - Average response time per card
  - Session duration timer
- Full **furigana** and **kanji** rendering

### 📖 Features
- **JMdict Database**: Comprehensive Japanese-English dictionary converted from XML to SQLite, with fast full-text search with SQLite
- **Word Details**: Detailed information with readings, definitions, and examples in English
- **Add to FSRS**: Each dictionary entry also serves as an individual flashcard
- **Cloud Backup**: Supabase PostgreSQL backend with automatic sync
- **Cross-Platform**: Windows and Android support

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK** (3.6.1 or higher)
- **Dart SDK** (^3.6.1)
- **Git**

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Thinhtucute/kian.git
   cd kian
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up Supabase** (required for authentication)
   
   Create a `.env` file in the project root:
   ```env
   SUPABASE_URL=your_supabase_project_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

### Building for Production

**Windows**:
```bash
flutter build windows --release
```
Output: `build\windows\x64\runner\Release\kian.exe`

**Android APK**:
```bash
flutter build apk --release
```
Output: `build\app\outputs\flutter-apk\app-release.apk`

**Android App Bundle** (for Google Play):
```bash
flutter build appbundle --release
```
Output: `build\app\outputs\bundle\release\app-release.aab`

## 🗄️ Database Setup

### Supabase Configuration

1. Create a Supabase project at [supabase.com](https://supabase.com)

2. Run this SQL in the Supabase SQL Editor:

```sql
-- Create cards table with user isolation
CREATE TABLE cards (
  id BIGSERIAL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  ent_seq INTEGER NOT NULL,
  type INTEGER NOT NULL DEFAULT 0,
  queue INTEGER NOT NULL DEFAULT 0,
  due DOUBLE PRECISION NOT NULL,
  last_review DOUBLE PRECISION,
  reps INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  left_steps INTEGER NOT NULL DEFAULT 2,
  stability DOUBLE PRECISION NOT NULL DEFAULT 2.3065,
  difficulty DOUBLE PRECISION NOT NULL DEFAULT 6.4133,
  PRIMARY KEY (user_id, ent_seq)
);

-- Enable Row Level Security
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can view their own cards"
  ON cards FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own cards"
  ON cards FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own cards"
  ON cards FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own cards"
  ON cards FOR DELETE
  USING (auth.uid() = user_id);

-- Create profiles table (optional)
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  full_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);
```

3. **Disable Email Confirmation** (for development):
   - Go to Authentication → Providers → Email
   - Uncheck "Confirm email"

## 📱 Usage

### First Time Setup
1. Launch the app
2. Click "Sign Up" to create an account
3. Enter email and password
4. Login with your credentials

### Learning Flow
1. **Dictionary Search**: Look up Japanese words
2. **Add Cards**: Click "Add to FSRS" on any word
3. **Review**: Use the Learn screen for spaced repetition
4. **Sync**: Click the sync button to backup progress
5. **Logout**: Your local cards are wiped on logout

### Sync Behavior
- **Login**: Automatically downloads your cards from Supabase
- **Sync Button**: Uploads new reviews and downloads updates
- **Logout**: Wipes all local SQLite data
- **Conflict Resolution**: Most recent review timestamp wins

## 🏗️ Architecture

### Tech Stack
- **Frontend**: Flutter/Dart
- **Local Database**: SQLite with sqflite + drift ORM
- **Cloud Backend**: Supabase (PostgreSQL + Auth)
- **State Management**: Provider
- **Search**: FTS5 full-text search
- **Algorithm**: FSRS (Free Spaced Repetition Scheduler)

### Key Dependencies
```yaml
dependencies:
  supabase_flutter: ^2.10.1    # Authentication & cloud sync
  sqflite: ^2.4.1              # Local SQLite database
  drift: ^2.28.2               # Type-safe SQL queries
  kana_kit: ^3.1.0             # Japanese text processing
  provider: ^6.1.2             # State management
  shared_preferences: ^2.4.11  # Settings storage
  flutter_dotenv: ^5.2.1       # Environment variables
```

## 🔧 Project Structure
```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models
├── screens/                     # UI screens
│   ├── login_screen.dart
│   ├── signup_screen.dart
│   ├── learn_screen.dart
│   └── dictionary_screen.dart
├── services/
│   ├── cloud/                   # Supabase integration
│   │   ├── auth_service.dart    # Authentication
│   │   ├── sync_service.dart    # Cloud sync logic
│   │   └── sync_manager.dart    # Sync UI coordination
│   └── fsrs/                    # Spaced repetition
│       ├── card_fetcher.dart
│       └── review_service.dart
├── helpers/
│   ├── fsrs_helper.dart         # FSRS utilities
│   └── dictionary_helper.dart   # Dictionary queries
└── widgets/                     # Reusable components
```

## 📦 Download

### Latest Release
Download pre-built binaries from [Releases](https://github.com/Thinhtucute/kian/releases):

- **Windows**: `kian-windows-x64.zip` - Extract and run `kian.exe`
- **Android**: `app-release.apk` - Install APK directly

### Build from Source
See [Getting Started](#-getting-started) above.

## 🙏 Acknowledgments

### JMdict / EDICT Dictionary Data

This project uses data from JMdict/EDICT,
© The Electronic Dictionary Research and Development Group (EDRDG),
used under the Creative Commons Attribution–ShareAlike 4.0 License (CC BY-SA 4.0).

More information: https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project

### FSRS Algorithm

This project includes a custom Dart implementation based on the FSRS (Free Spaced Repetition Scheduler) algorithm by Open Spaced Repetition: https://github.com/open-spaced-repetition/fsrs-rs

### Supabase

Powered by Supabase, a serverless backend service provider and an open-source Firebase alternative: https://supabase.com

---

**Note**: This app requires internet connection for initial login and sync. Offline learning is supported after cards are downloaded.
