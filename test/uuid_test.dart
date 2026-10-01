import 'package:uuid/uuid.dart';
void main() {
  final u = const Uuid();
  print(u.v4());
  print(u.v4());
}
