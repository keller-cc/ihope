bool textMatchesQuery(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return text.toLowerCase().contains(q);
}
