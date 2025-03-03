// lib/widgets/flashcard.dart
class Flashcard {
  final String question;
  final String answer;

  Flashcard({required this.question, required this.answer});
}

List<Flashcard> mockFlashcards = [
  Flashcard(question: "子供", answer: "Child"),
  Flashcard(question: "先生", answer: "Teacher"),
  Flashcard(question: "学校", answer: "School"),
];
