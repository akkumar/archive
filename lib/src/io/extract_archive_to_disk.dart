import 'dart:io';

import 'package:path/path.dart' as p;

import '../archive.dart';
import '../bzip2_decoder.dart';
import '../gzip_decoder.dart';
import '../tar_decoder.dart';
import '../xz_decoder.dart';
import '../zip_decoder.dart';
import 'input_file_stream.dart';
import 'output_file_stream.dart';

/// Ensure filePath is contained in the outputDir folder, to make sure archives
/// aren't trying to write to some system path.
bool isWithinOutputPath(String outputDir, String filePath) {
  return p.isWithin(p.canonicalize(outputDir), p.canonicalize(filePath));
}

void extractArchiveToDisk(Archive archive, String outputPath,
    {bool asyncWrite = false, int? bufferSize}) {
  final outDir = Directory(outputPath);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }
  for (final file in archive.files) {
    final filePath = p.join(outputPath, p.normalize(file.name));

    if ((!file.isFile && !file.isSymbolicLink) ||
        !isWithinOutputPath(outputPath, filePath)) {
      continue;
    }

    if (asyncWrite) {
      if (file.isSymbolicLink) {
        final link = Link(filePath);
        link.create(p.normalize(file.nameOfLinkedFile), recursive: true);
      } else {
        final output = File(filePath);
        output.create(recursive: true).then((f) {
          f.open(mode: FileMode.write).then((fp) {
            final bytes = file.content as List<int>;
            fp.writeFrom(bytes).then((fp) {
              file.clear();
              fp.close();
            });
          });
        });
      }
    } else {
      if (file.isSymbolicLink) {
        final link = Link(filePath);
        link.createSync(p.normalize(file.nameOfLinkedFile), recursive: true);
      } else {
        final output = OutputFileStream(filePath, bufferSize: bufferSize);
        try {
          file.writeContent(output);
        } catch (err) {
          //
        }
        output.close();
      }
    }
  }
}

Future<void> extractFileToDisk(String inputPath, String outputPath,
    {String? password, bool asyncWrite = false, int? bufferSize}) async {
  Directory? tempDir;
  var archivePath = inputPath;

  var futures = <Future<void>>[];
  if (inputPath.endsWith('tar.gz') || inputPath.endsWith('tgz')) {
    tempDir = Directory.systemTemp.createTempSync('dart_archive');
    archivePath = p.join(tempDir.path, 'temp.tar');
    final input = InputFileStream(inputPath);
    final output = OutputFileStream(archivePath, bufferSize: bufferSize);
    GZipDecoder().decodeStream(input, output);
    futures.add(input.close());
    futures.add(output.close());
  } else if (inputPath.endsWith('tar.bz2') || inputPath.endsWith('tbz')) {
    tempDir = Directory.systemTemp.createTempSync('dart_archive');
    archivePath = p.join(tempDir.path, 'temp.tar');
    final input = InputFileStream(inputPath);
    final output = OutputFileStream(archivePath, bufferSize: bufferSize);
    BZip2Decoder().decodeBuffer(input, output: output);
    futures.add(input.close());
    futures.add(output.close());
  } else if (inputPath.endsWith('tar.xz') || inputPath.endsWith('txz')) {
    tempDir = Directory.systemTemp.createTempSync('dart_archive');
    archivePath = p.join(tempDir.path, 'temp.tar');
    final input = InputFileStream(inputPath);
    final output = OutputFileStream(archivePath, bufferSize: bufferSize);
    output.writeBytes(XZDecoder().decodeBuffer(input));
    futures.add(input.close());
    futures.add(output.close());
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
    futures.clear();
  }

  Archive archive;
  if (archivePath.endsWith('tar')) {
    final input = InputFileStream(archivePath);
    archive = TarDecoder().decodeBuffer(input);
    futures.add(input.close());
  } else if (archivePath.endsWith('zip')) {
    final input = InputFileStream(archivePath);
    archive = ZipDecoder().decodeBuffer(input, password: password);
    futures.add(input.close());
  } else {
    throw ArgumentError.value(inputPath, 'inputPath',
        'Must end tar.gz, tgz, tar.bz2, tbz, tar.xz, txz, tar or zip.');
  }

  for (final file in archive.files) {
    final filePath = p.join(outputPath, p.normalize(file.name));

    if (!isWithinOutputPath(outputPath, filePath)) {
      continue;
    }

    if (!file.isFile && !file.isSymbolicLink) {
      Directory(filePath).createSync(recursive: true);
      continue;
    }

    if (asyncWrite) {
      if (file.isSymbolicLink) {
        final link = Link(filePath);
        await link.create(p.normalize(file.nameOfLinkedFile), recursive: true);
      } else {
        final output = File(filePath);
        final f = await output.create(recursive: true);
        final fp = await f.open(mode: FileMode.write);
        final bytes = file.content as List<int>;
        await fp.writeFrom(bytes);
        file.clear();
        futures.add(fp.close());
      }
    } else {
      if (file.isSymbolicLink) {
        final link = Link(filePath);
        link.createSync(p.normalize(file.nameOfLinkedFile), recursive: true);
      } else {
        final output = OutputFileStream(filePath, bufferSize: bufferSize);
        try {
          file.writeContent(output);
        } catch (err) {
          //
        }
        futures.add(output.close());
      }
    }
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
    futures.clear();
  }

  futures.add(archive.clear());

  if (futures.isNotEmpty) {
    await Future.wait(futures);
    futures.clear();
  }

  if (tempDir != null) {
    futures.add(tempDir.delete(recursive: true));
  }

  if (futures.isNotEmpty) {
    await Future.wait(futures);
    futures.clear();
  }
}
