/// The text of a Garage Key as the user typed or pasted it, cleaned as the official client cleans it before reading it: every whitespace removed, then lower case (`GarageKeyInput.tsx` at commit ff1998c).
///
/// What remains is for `GarageKey.parse` alone, which refuses anything that is not a key; a character that is not whitespace, such as an invisible or bidirectional mark, is kept, so the text is refused rather than silently changed.
String normalizeGarageKeyText(String text) =>
    text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
