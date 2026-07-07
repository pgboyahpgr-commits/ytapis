# ytapis — Dart

Search YouTube and get video metadata. No API key required.

## Usage

```dart
import 'package:ytapis/ytapis.dart';

void main() async {
  final results = await search('cats', limit: 5);
  print(results.first.title);
}
```

### CLI

```bash
dart run bin/ytapis.dart search cats --limit 5
```
