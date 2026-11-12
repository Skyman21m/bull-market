/// A small stable hash of [seed], the same on every run (unlike `String.hashCode`), from which the drawn avatars and marks choose their traits and colours.
int seedHash(String seed) {
  var hash = 17;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  // Mixes the bits so that seeds differing in their last characters still differ in every trait.
  hash ^= hash >> 13;
  hash = (hash * 0x5bd1e995) & 0x3fffffff;
  return hash ^ (hash >> 15);
}
