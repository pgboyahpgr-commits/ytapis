# ytapis &mdash; Dart

Search YouTube and get video metadata &mdash; **no API key required**.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Install

```bash
dart pub add ytapis
```

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

## License

MIT
