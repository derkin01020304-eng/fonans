import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

/// Type and diagnostic checks using the analyzer library. This fallback does
/// not register the Flutter lint rules; run flutter analyze on a normal SDK.
Future<void> main() async {
  final root = Directory.current.absolute.path;
  final collection = AnalysisContextCollection(
    includedPaths: ['$root/lib', '$root/test', '$root/integration_test'],
  );
  var errors = 0, warnings = 0;
  for (final context in collection.contexts) {
    for (final file in context.contextRoot.analyzedFiles().where(
      (f) => f.endsWith('.dart') && !f.endsWith('.g.dart'),
    )) {
      final result = await context.currentSession.getResolvedUnit(file);
      if (result is! ResolvedUnitResult) continue;
      for (final issue in result.errors) {
        final severity = issue.errorCode.errorSeverity.name;
        if (severity == 'ERROR') errors++;
        if (severity == 'WARNING') warnings++;
        final location = result.lineInfo.getLocation(issue.offset);
        stdout.writeln(
          '$severity $file:${location.lineNumber} ${issue.errorCode.name} ${issue.message}',
        );
      }
    }
  }
  await collection.dispose();
  stdout.writeln('Analyzer: $errors errors, $warnings warnings');
  exitCode = errors == 0 && warnings == 0 ? 0 : 1;
}
