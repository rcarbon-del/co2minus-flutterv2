import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class TelemetryLogger {
  static final TelemetryLogger _instance = TelemetryLogger._internal();
  factory TelemetryLogger() => _instance;
  TelemetryLogger._internal();

  // Hardcoded to the universal Android Downloads folder to bypass Scoped Storage limits
  final String currentDirPath = "/storage/emulated/0/Download/CO2minus_Metrics";

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }

      if (status.isGranted) {
        return true;
      } else {
        debugPrint("Permission denied. Forcing App Settings...");
        await openAppSettings();
        return false;
      }
    }
    return true;
  }

  Future<void> initLogger() async {
    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) return;

    final dir = Directory(currentDirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final imgDir = Directory("$currentDirPath/images");
    if (!await imgDir.exists()) await imgDir.create(recursive: true);

    final csvFile = File("$currentDirPath/telemetry_log.csv");
    if (!await csvFile.exists()) {
      await csvFile.writeAsString(
          "Timestamp,Item_Class,YOLO_Confidence,Extraction_Method,Extracted_Weight_kg,GRU_CO2e_Output,Latency_ms,Status,Image_Saved\n");
    }
  }

  Future<void> logScanData({
    required String itemClass,
    required double yoloConfidence,
    required String extractionMethod,
    required double weight,
    required double co2eOutput,
    required int latencyMs,
    required String status,
    required String? originalImagePath,
  }) async {
    await initLogger();

    final String now = DateFormat('HH:mm:ss').format(DateTime.now());
    String savedImageName = "None";

    // Copy image to the metrics folder
    if (originalImagePath != null && originalImagePath.isNotEmpty) {
      try {
        final String imgTimestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        savedImageName = "img_$imgTimestamp.jpg";
        final File originalImage = File(originalImagePath);
        if (await originalImage.exists()) {
          await originalImage.copy("$currentDirPath/images/$savedImageName");
        }
      } catch (e) {
        debugPrint("Image Copy Error: $e");
        savedImageName = "Copy_Failed";
      }
    }

    final String csvRow = "$now,$itemClass,$yoloConfidence,$extractionMethod,$weight,$co2eOutput,$latencyMs,$status,$savedImageName\n";
    final csvFile = File("$currentDirPath/telemetry_log.csv");
    await csvFile.writeAsString(csvRow, mode: FileMode.append);
  }

  Future<void> archiveCurrentRun() async {
    await initLogger();

    final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final archiveDir = Directory("$currentDirPath/previous_run_$timestamp");
    await archiveDir.create(recursive: true);

    final csvFile = File("$currentDirPath/telemetry_log.csv");
    if (await csvFile.exists()) {
      await csvFile.copy("${archiveDir.path}/telemetry_log.csv");
      await csvFile.delete();
    }

    final imgDir = Directory("$currentDirPath/images");
    if (await imgDir.exists()) {
      final newImgDir = Directory("${archiveDir.path}/images");
      await newImgDir.create(recursive: true);

      List<FileSystemEntity> files = imgDir.listSync();
      for (var file in files) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          await file.copy("${newImgDir.path}/$fileName");
          await file.delete();
        }
      }
    }
  }
}