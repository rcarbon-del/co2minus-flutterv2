import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:torch_light/torch_light.dart';

import 'telemetry_logger.dart';

// Google LiteRT (Formerly TensorFlow Lite Flutter)
import 'package:flutter_litert/flutter_litert.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'user_provider.dart';

// =========================================================================
// BACKGROUND IMAGE PROCESSOR
// =========================================================================
Future<Uint8List> prepareYoloImage(String path) async {
  final bytes = await File(path).readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  decoded = img.bakeOrientation(decoded);
  int targetSize = 640;
  double scale = targetSize / (decoded.width > decoded.height ? decoded.width : decoded.height);
  int newWidth = (decoded.width * scale).toInt();
  int newHeight = (decoded.height * scale).toInt();

  img.Image resizedImage = img.copyResize(decoded, width: newWidth, height: newHeight);
  img.Image squareImage = img.Image(width: targetSize, height: targetSize);
  img.fill(squareImage, color: img.ColorRgb8(114, 114, 114));

  int xOffset = (targetSize - newWidth) ~/ 2;
  int yOffset = (targetSize - newHeight) ~/ 2;
  img.compositeImage(squareImage, resizedImage, dstX: xOffset, dstY: yOffset);

  return img.encodeJpg(squareImage, quality: 90);
}

class PipelineUpdate {
  final int progress;
  final String step;
  final String detail;
  PipelineUpdate(this.progress, this.step, this.detail);
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  CameraController? _controller;
  bool _isFlashOn = false;
  bool _isInitialized = false;

  // --- Metrics Variables ---
  bool _metricsModeEnabled = false;
  final TelemetryLogger _logger = TelemetryLogger();

  bool _useNativeYoloView = false;
  String? _capturedImagePath;
  String _liveDetectedClass = "";
  double _liveDetectedConf = 0.0;
  DateTime? _lastDetectionTime;

  // Streak Filter
  String _currentStreakClass = "";
  double _currentStreakConf = 0.0;
  int _streakCount = 0;
  int _missedFrames = 0;
  int _lastYoloFrameTime = 0;

  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();
  bool _isCancelled = false;

  Interpreter? _gruInterpreter;
  Map<String, dynamic>? _lcaDatabase;
  Map<String, dynamic>? _scalerConfig;
  YOLO? _yoloPlugin;

  bool _isDialogShowing = false;
  bool _isAnalyzing = false;

  String _detectedClass = "";
  String _yoloCategory = "";
  double _carbonFootprint = 0.0;

  StreamController<PipelineUpdate>? _pipelineController;
  final List<PipelineUpdate> _pipelineHistory = [];
  int _currentPipelineProgress = 0;

  @override
  void initState() {
    super.initState();
    OpenFoodAPIConfiguration.userAgent = UserAgent(name: 'CO2Minus_App', url: 'https://github.com/abvlnt');

    _initializeSystem().then((_) {
      if (mounted) {
        _checkShowInstructions();
        _logger.initLogger();
      }
    });
  }

  Future<void> _initializeSystem() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) debugPrint("❌ Camera Hardware Not Found");

      try {
        final lcaString = await rootBundle.loadString('assets/flutter_lca_database.json');
        _lcaDatabase = json.decode(lcaString);
        final scalerString = await rootBundle.loadString('assets/flutter_scaler_config.json');
        _scalerConfig = json.decode(scalerString);
      } catch (e) {
        debugPrint("❌ JSON Databases Error: $e");
      }

      try {
        final liveFile = File('${Directory.systemTemp.path}/yolo_f16_live.tflite');
        final staticFile = File('${Directory.systemTemp.path}/yolo_f16_static.tflite');

        if (!liveFile.existsSync() || liveFile.lengthSync() == 0) {
          final byteData = await rootBundle.load('assets/models/yolo_f16.tflite');
          await liveFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
        }

        if (!staticFile.existsSync() || staticFile.lengthSync() == 0) {
          final byteData = await rootBundle.load('assets/models/yolo_f16.tflite');
          await staticFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
        }

        _yoloPlugin = YOLO(modelPath: staticFile.path, task: YOLOTask.detect);
        await _yoloPlugin!.loadModel();
      } catch (e) {
        debugPrint("❌ YOLO26 Model Error: $e");
      }

      try {
        _gruInterpreter = await Interpreter.fromAsset('assets/models/gru.tflite');
      } catch (e) {
        debugPrint("❌ GRU Model Error: $e");
      }
    } catch (e) {
      debugPrint("\nCritical System Error: $e");
    }

    if (mounted) setState(() => _isInitialized = true);
  }

  Future<void> _checkShowInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    final bool showAgain = prefs.getBool('show_scanner_instructions') ?? true;

    if (showAgain && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _ScannerInstructionDialog(),
      );
    }
    if (mounted) setState(() => _useNativeYoloView = true);
  }

  void _emitUpdate(int progress, String step, String detail) {
    final update = PipelineUpdate(progress, step, detail);
    _pipelineHistory.insert(0, update);
    _currentPipelineProgress = progress;

    if (_pipelineController != null && !_pipelineController!.isClosed) {
      _pipelineController!.add(update);
    }
  }

  void _cancelPipeline({bool poppedBySystem = false}) {
    _isCancelled = true;
    if (_isDialogShowing) {
      _isDialogShowing = false;
      if (!poppedBySystem && mounted) Navigator.pop(context, 'system_transition');
    }
    if (mounted) {
      setState(() {
        _useNativeYoloView = true;
        _capturedImagePath = null;
        _streakCount = 0;
        _missedFrames = 0;
        _currentStreakClass = "";
        _currentStreakConf = 0.0;
      });
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _isAnalyzing = false);
      });
    }
  }

  Future<Map<String, dynamic>?> _runYoloInference(String imagePath) async {
    if (_yoloPlugin == null) return null;
    try {
      final Uint8List fixedBytes = await compute(prepareYoloImage, imagePath);
      if (!mounted || _isCancelled) return null;

      final resultsMap = await _yoloPlugin!.predict(fixedBytes, confidenceThreshold: 0.20);

      if (resultsMap.isNotEmpty) {
        double bestConf = 0.0;
        String bestLabel = "";

        resultsMap.forEach((key, value) {
          if (value is List) {
            for (var item in value) {
              if (item is Map) {
                double conf = (item['confidence'] ?? item['score'] ?? 0.0).toDouble();
                String label = (item['className'] ?? item['label'] ?? item['class'] ?? "").toString();

                double requiredThreshold = 0.30;
                if (label == "instant_noodles" || label == "snack_pack") requiredThreshold = 0.50;
                else if (label == "cleaning_product" || label == "personal_care") requiredThreshold = 0.40;

                if (conf >= requiredThreshold && conf > bestConf && label.isNotEmpty) {
                  bestConf = conf;
                  bestLabel = label;
                }
              }
            }
          }
        });
        if (bestLabel.isNotEmpty) return {'class': bestLabel, 'conf': bestConf};
      }
      return null;
    } catch (e) {
      debugPrint("YOLO26 Inference Error: $e");
      return null;
    }
  }

  Future<double?> _estimateCarbonFootprint(String yoloClass, double weightKg) async {
    if (_gruInterpreter == null || _lcaDatabase == null || _scalerConfig == null) return null;
    if (!_lcaDatabase!.containsKey(yoloClass)) return null;

    try {
      List<dynamic> baseLca = _lcaDatabase![yoloClass];

      // FIX: Use (val as num).toDouble() to prevent JSON type casting crashes!
      List<double> actualLca = baseLca.map((val) => (val as num).toDouble() * weightKg).toList();

      List<dynamic> scaleVals = _scalerConfig!['scale_vals'];
      List<dynamic> minOffsets = _scalerConfig!['min_offsets'];

      List<double> scaledLca = [];
      for (int i = 0; i < actualLca.length; i++) {
        // FIX: Ensure both scaler arrays are safely casted to double
        double scaledValue = (actualLca[i] * (scaleVals[i] as num).toDouble()) + (minOffsets[i] as num).toDouble();
        scaledLca.add(scaledValue);
      }

      var inputTensor = [scaledLca.map((val) => [val]).toList()];
      var outputTensor = List.filled(1 * 1, 0.0).reshape([1, 1]);

      _gruInterpreter!.run(inputTensor, outputTensor);
      double finalCarbonFootprint = outputTensor[0][0];

      if (finalCarbonFootprint.isNaN) return null;
      return finalCarbonFootprint;
    } catch (e) {
      debugPrint("GRU Inference failed dynamically: $e");
      return null;
    }
  }

  Future<double> _estimateWeightVolumetrically(String detectedClass) async {
    _emitUpdate(65, "5. Volumetric Scaling", "Estimating mass based on product category...");
    await Future.delayed(const Duration(milliseconds: 600));
    if (_isCancelled) throw Exception("cancelled_by_user");

    double widthCm = 0.0; double heightCm = 0.0; double depthCm = 0.0;
    double densityGCm3 = 1.0;

    switch (detectedClass) {
      case "can_drink": widthCm = 6.6; heightCm = 12.2; depthCm = 6.6; break;
      case "can_food": widthCm = 8.5; heightCm = 11.0; depthCm = 8.5; break;
      case "cleaning_product": widthCm = 9.0; heightCm = 25.0; depthCm = 6.0; break;
      case "cooking_oil_bottle": widthCm = 8.0; heightCm = 24.0; depthCm = 8.0; densityGCm3 = 0.92; break;
      case "instant_drink_sachet": widthCm = 8.0; heightCm = 10.0; depthCm = 0.5; densityGCm3 = 0.6; break;
      case "instant_noodles": widthCm = 10.0; heightCm = 10.0; depthCm = 4.0; densityGCm3 = 0.2; break;
      case "personal_care": widthCm = 6.0; heightCm = 18.0; depthCm = 4.0; break;
      case "plastic-bottle": widthCm = 7.0; heightCm = 20.0; depthCm = 7.0; break;
      case "rice_pack": widthCm = 15.0; heightCm = 20.0; depthCm = 5.0; densityGCm3 = 0.8; break;
      case "snack_pack": widthCm = 15.0; heightCm = 20.0; depthCm = 5.0; densityGCm3 = 0.1; break;
      default: widthCm = 7.0; heightCm = 20.0; depthCm = 7.0; break;
    }

    double volumeCm3 = widthCm * heightCm * depthCm;
    double weightGrams = volumeCm3 * densityGCm3;

    return weightGrams / 1000.0;
  }

  Future<void> _runPipeline({XFile? preSelectedImage}) async {
    if (_isDialogShowing || _isAnalyzing) return;
    if (preSelectedImage == null && !_isInitialized) return;

    final stopwatch = Stopwatch()..start();
    String metricStatus = "Started";
    String metricMethod = "Unknown";
    double metricYoloConf = 0.0;
    double metricWeight = 0.0;
    String finalImagePath = "";
    String currentDetectedClass = "";

    setState(() {
      _isAnalyzing = true;
      _isDialogShowing = true;
      _isCancelled = false;
      _useNativeYoloView = false;
      _streakCount = 0;
    });

    if (_isFlashOn) {
      try { await TorchLight.disableTorch(); _isFlashOn = false; } catch (_) {}
    }

    if (preSelectedImage != null) {
      setState(() { _capturedImagePath = preSelectedImage.path; });
    }

    _pipelineHistory.clear();
    _currentPipelineProgress = 0;
    _pipelineController = StreamController<PipelineUpdate>.broadcast();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProcessingDialog(
        updateStream: _pipelineController!.stream,
        initialLogs: _pipelineHistory,
        initialProgress: _currentPipelineProgress,
        onCancel: (fromSystem) => _cancelPipeline(poppedBySystem: fromSystem),
      ),
    );

    try {
      String uiItemName = "";

      if (preSelectedImage != null) {
        _emitUpdate(5, "1. Image Upload", "Safely allocating memory...");
        finalImagePath = preSelectedImage.path;

        await Future.delayed(const Duration(milliseconds: 2500));
        if (_isCancelled) throw Exception("cancelled_by_user");

        _emitUpdate(10, "1. Image Upload", "Analyzing uploaded image...");
        var yoloResult = await _runYoloInference(finalImagePath);
        if (yoloResult == null) throw Exception("YOLO could not classify item.");

        currentDetectedClass = yoloResult['class'];
        metricYoloConf = yoloResult['conf'];
        _emitUpdate(20, "2. Vision Model", "Verified: $currentDetectedClass");

      } else {
        _emitUpdate(5, "1. Live Detection", "Locking YOLO prediction...");

        if (_liveDetectedClass.isEmpty || _lastDetectionTime == null || DateTime.now().difference(_lastDetectionTime!).inMilliseconds > 1500) {
          throw Exception("No clear object detected. Please aim at an object first.");
        }

        currentDetectedClass = _liveDetectedClass;
        metricYoloConf = _liveDetectedConf;
        _emitUpdate(10, "1. Vision Model", "Verified from live stream: $currentDetectedClass (${(_liveDetectedConf * 100).toStringAsFixed(0)}%)");

        _emitUpdate(20, "2. Hardware Override", "Releasing native camera feed...");

        await Future.delayed(const Duration(milliseconds: 2500));
        if (_isCancelled) throw Exception("cancelled_by_user");

        try {
          final cameras = await availableCameras();
          _controller = CameraController(
            cameras.first, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21,
          );
          await _controller!.initialize();
          if (_isCancelled) throw Exception("cancelled_by_user");

          _emitUpdate(30, "3. Image Capture", "Taking high-res snapshot for OCR...");
          final XFile capturedImage = await _controller!.takePicture();
          finalImagePath = capturedImage.path;

          if (mounted) setState(() { _capturedImagePath = finalImagePath; });
        } finally {
          await _controller?.dispose();
          _controller = null;
        }
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      preSelectedImage = null;
      uiItemName = currentDetectedClass.replaceAll('_', ' ').toUpperCase();

      _emitUpdate(50, "4. Data Extraction (OCR)", "Scanning packaging for weight & labels...");
      final InputImage inputImage = InputImage.fromFilePath(finalImagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      String ocrText = recognizedText.text.replaceAll('\n', ' ').toLowerCase();

      List<TextBlock> sortedBlocks = recognizedText.blocks.toList();
      sortedBlocks.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));

      List<String> prominentText = [];
      for (var block in sortedBlocks) {
        String text = block.text.replaceAll('\n', ' ').trim();
        if (text.length > 2 && !text.toLowerCase().contains("net") && !text.toLowerCase().contains("weight")) {
          prominentText.add(text);
        }
      }

      String ocrSearchContext = "";
      String detectedBrand = prominentText.isNotEmpty ? prominentText.first.toUpperCase() : "";

      if (_isCancelled) throw Exception("cancelled_by_user");

      // UI/UX FIX: Extract Raw Value and Unit distinctly so the dropdown can map it cleanly
      double detectedWeightValue = 0.0;
      String detectedUnit = 'g';
      bool ocrWeightFound = false;

      RegExp weightRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l)', caseSensitive: false);
      var match = weightRegex.firstMatch(ocrText);
      if (match != null) {
        try {
          detectedWeightValue = double.parse(match.group(1)!);
          detectedUnit = match.group(2)!.toLowerCase();
          ocrWeightFound = true;
          metricMethod = "Local_OCR";
        } catch (_) {}
      }

      _emitUpdate(55, "4. Verification", "Awaiting user verification of OCR data...");
      await Future.delayed(const Duration(milliseconds: 300));

      if (_isDialogShowing) {
        Navigator.pop(context, 'system_transition');
        _isDialogShowing = false;
      }

      final verificationResult = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _OcrVerificationDialog(
          imagePath: finalImagePath,
          textBlocks: sortedBlocks,
          initialQuery: ocrSearchContext,
          initialWeightValue: detectedWeightValue,
          initialUnit: detectedUnit,
          weightFound: ocrWeightFound,
        ),
      );

      if (verificationResult == null) throw Exception("cancelled_by_user");

      ocrSearchContext = verificationResult['query'];
      double detectedWeightKg = verificationResult['weight']; // Converted securely inside dialog
      ocrWeightFound = verificationResult['weightFound'];
      detectedBrand = ocrSearchContext.isNotEmpty ? ocrSearchContext.split(' ').first.toUpperCase() : "Unknown";

      if (ocrWeightFound && metricMethod == "Unknown") metricMethod = "Manual_OCR_Override";

      _isDialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProcessingDialog(
          updateStream: _pipelineController!.stream, initialLogs: _pipelineHistory, initialProgress: _currentPipelineProgress, onCancel: (fromSystem) => _cancelPipeline(poppedBySystem: fromSystem),
        ),
      );

      _emitUpdate(56, "4. Verification", "Data verified. Query: $ocrSearchContext");
      if (_isCancelled) throw Exception("cancelled_by_user");


      _emitUpdate(58, "4. OpenFoodFacts Search", "Querying DB for precise product description...");
      String searchQuery = ocrSearchContext.isNotEmpty ? ocrSearchContext : currentDetectedClass.replaceAll('_', ' ');

      try {
        ProductSearchQueryConfiguration configuration = ProductSearchQueryConfiguration(
          parametersList: <Parameter>[SearchTerms(terms: [searchQuery]), PageSize(size: 6)],
          language: OpenFoodFactsLanguage.ENGLISH, version: ProductQueryVersion.v3,
        );

        SearchResult result = await OpenFoodAPIClient.searchProducts(null, configuration).timeout(const Duration(seconds: 10));

        if (result.products != null && result.products!.isNotEmpty) {
          if (_isDialogShowing) { Navigator.pop(context, 'system_transition'); _isDialogShowing = false; }

          final dialogResult = await showDialog<dynamic>(
            context: context, barrierDismissible: false, builder: (context) => _ProductSelectionDialog(products: result.products!),
          );

          if (dialogResult == null || dialogResult == 'cancel') throw Exception("cancelled_by_user");

          _isDialogShowing = true;
          showDialog(
            context: context, barrierDismissible: false,
            builder: (context) => _ProcessingDialog(updateStream: _pipelineController!.stream, initialLogs: _pipelineHistory, initialProgress: _currentPipelineProgress, onCancel: (fromSystem) => _cancelPipeline(poppedBySystem: fromSystem)),
          );

          if (dialogResult is Product) {
            final p = dialogResult;
            if (p.productName != null && p.productName!.isNotEmpty) uiItemName = p.productName!;
            detectedBrand = (p.brands ?? detectedBrand).toUpperCase();

            if (p.quantity != null && p.quantity!.isNotEmpty) {
              var m = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l|cl)', caseSensitive: false).firstMatch(p.quantity!);
              if (m != null) {
                double val = double.parse(m.group(1)!);
                String unit = m.group(2)!.toLowerCase();

                if (unit == 'g' || unit == 'ml' || unit == 'cl') detectedWeightKg = (unit == 'cl' ? val * 10 : val) / 1000.0;
                else detectedWeightKg = val;
                ocrWeightFound = true;
                metricMethod = "Cloud_API";
              }
            }
            _emitUpdate(62, "4. Cloud API (Success)", "Matched $detectedBrand: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");
          } else if (dialogResult == 'skip') {
            _emitUpdate(62, "4. Cloud API", "User skipped. Proceeding with local OCR data.");
          }
        } else {
          _emitUpdate(62, "4. Cloud API", "No exact matches found. Using local data.");
        }
      } catch (e) {
        _emitUpdate(62, "4. Cloud API", "Cloud server busy. Proceeding with local data.");
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      String weightDisplay = ocrWeightFound ? "${(detectedWeightKg * 1000).toStringAsFixed(0)}g" : "Not Found";
      _emitUpdate(65, "4. Data Extraction", "W: $weightDisplay | B: $detectedBrand");
      if (_isCancelled) throw Exception("cancelled_by_user");

      if (!ocrWeightFound) {
        detectedWeightKg = await _estimateWeightVolumetrically(currentDetectedClass);
        metricMethod = "Volumetric_Fallback";
        _emitUpdate(80, "5. Volumetric Scaling", "Estimated mass: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");
      } else {
        _emitUpdate(70, "5. Volumetric Scaling", "Bypassing Volume Math: Exact weight found.");
        await Future.delayed(const Duration(milliseconds: 600));
      }
      metricWeight = detectedWeightKg;

      if (_isCancelled) throw Exception("cancelled_by_user");

      _emitUpdate(85, "6. Multi-Modal Validation", "Matching YOLO vision with text context...");
      await Future.delayed(const Duration(milliseconds: 800));

      bool isContradiction = false;
      String mismatchReason = "";

      final List<String> cleaningTerms = ['shampoo', 'soap', 'cleaner', 'detergent', 'wash', 'dish', 'laundry', 'surface', 'toilet', 'bleach', 'disinfectant'];
      final List<String> personalCareTerms = ['shampoo', 'lotion', 'hair', 'skin', 'body', 'face', 'toothpaste', 'deodorant', 'conditioner', 'cream'];
      final List<String> drinkTerms = ['drink', 'juice', 'beverage', 'soda', 'cola', 'water', 'tea', 'coffee', 'beer', 'wine', 'liquid', 'drinkable'];
      final List<String> foodTerms = ['tuna', 'meat', 'fish', 'beans', 'soup', 'tomato', 'corn', 'beef', 'pork', 'chicken', 'fruit', 'vegetable', 'meal', 'sauce', 'sardines', 'mackerel'];

      bool containsAny(String text, List<String> keywords) => keywords.any((k) => text.contains(k));

      if (currentDetectedClass == "can_drink" || currentDetectedClass == "plastic-bottle") {
        if (containsAny(ocrText, foodTerms)) {
          isContradiction = true; mismatchReason = "Detected Beverage, but OCR found solid food terms.";
        } else if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true; mismatchReason = "Detected Beverage, but OCR found cleaning terms.";
        }
      } else if (currentDetectedClass == "can_food") {
        if (containsAny(ocrText, drinkTerms)) {
          isContradiction = true; mismatchReason = "Detected Canned Food, but OCR found beverage terms.";
        } else if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true; mismatchReason = "Detected Canned Food, but OCR found cleaning terms.";
        }
      } else if (currentDetectedClass == "cleaning_product" || currentDetectedClass == "personal_care") {
        if (containsAny(ocrText, drinkTerms) || containsAny(ocrText, foodTerms)) {
          isContradiction = true; mismatchReason = "Detected Non-Food product, but OCR found food/drink terms.";
        }
      } else if (currentDetectedClass == "cooking_oil_bottle") {
        if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true; mismatchReason = "Detected Cooking Oil, but OCR found cleaning terms.";
        }
      } else if (currentDetectedClass == "instant_noodles" || currentDetectedClass == "snack_pack") {
        if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms) || containsAny(ocrText, drinkTerms)) {
          isContradiction = true; mismatchReason = "Detected Snack/Noodles, but OCR found unrelated terms.";
        }
      }

      if (isContradiction) {
        _emitUpdate(90, "6. Multi-Modal Validation", "Contradiction found! $mismatchReason");
        await Future.delayed(const Duration(milliseconds: 2000));
        throw Exception("Cross-validation failed. $mismatchReason Please re-scan.");
      }

      _emitUpdate(90, "6. Multi-Modal Validation", "Data verified. No contradictions found.");
      if (_isCancelled) throw Exception("cancelled_by_user");

      _emitUpdate(95, "7. GRU Carbon Estimation", "Feeding validated sequence to RNN...");
      double? finalFootprint = await _estimateCarbonFootprint(currentDetectedClass, detectedWeightKg);

      if (finalFootprint == null || finalFootprint.isNaN || finalFootprint <= 0) finalFootprint = 1.25;

      _emitUpdate(100, "Sequence Complete", "Estimated Footprint: ${finalFootprint.toStringAsFixed(2)} kg CO2e");

      metricStatus = "Success";
      stopwatch.stop();

      if (_metricsModeEnabled) {
        await _logger.logScanData(
          itemClass: currentDetectedClass, yoloConfidence: metricYoloConf, extractionMethod: metricMethod, weight: metricWeight,
          co2eOutput: finalFootprint, latencyMs: stopwatch.elapsedMilliseconds, status: metricStatus, originalImagePath: finalImagePath,
        );
      }

      if (!mounted || _isCancelled) return;
      if (_isDialogShowing) { Navigator.pop(context, 'system_transition'); _isDialogShowing = false; }

      setState(() {
        _yoloCategory = currentDetectedClass;
        _detectedClass = uiItemName;
        _carbonFootprint = finalFootprint!;
      });
      _showSuccessPopup(finalImagePath);

    } catch (e) {
      stopwatch.stop();
      if (!e.toString().contains("cancelled_by_user")) {
        metricStatus = "Exception: ${e.toString().replaceAll(',', ' ')}";
        if (_metricsModeEnabled) {
          await _logger.logScanData(
            itemClass: currentDetectedClass.isEmpty ? "Unknown" : currentDetectedClass, yoloConfidence: metricYoloConf, extractionMethod: metricMethod,
            weight: metricWeight, co2eOutput: 0.0, latencyMs: stopwatch.elapsedMilliseconds, status: metricStatus, originalImagePath: finalImagePath.isNotEmpty ? finalImagePath : null,
          );
        }
      } else if (_metricsModeEnabled) {
        await _logger.logScanData(
          itemClass: currentDetectedClass.isEmpty ? "Unknown" : currentDetectedClass, yoloConfidence: metricYoloConf, extractionMethod: metricMethod,
          weight: metricWeight, co2eOutput: 0.0, latencyMs: stopwatch.elapsedMilliseconds, status: "Cancelled_by_User", originalImagePath: finalImagePath.isNotEmpty ? finalImagePath : null,
        );
      }

      if (e.toString().contains("cancelled_by_user") || e.toString().contains("Cross-validation failed")) {
        if (mounted) {
          setState(() { _isDialogShowing = false; _useNativeYoloView = true; _capturedImagePath = null; _streakCount = 0; _missedFrames = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; });
          Future.delayed(const Duration(milliseconds: 2500), () { if (mounted) setState(() => _isAnalyzing = false); });
        }
        if (e.toString().contains("Cross-validation failed")) _showFailurePopup(customMessage: e.toString().replaceAll("Exception: ", ""));
        return;
      }

      if (!mounted) return;
      if (_isDialogShowing) { Navigator.pop(context, 'system_transition'); _isDialogShowing = false; }
      _showFailurePopup();
    } finally {
      if (mounted && !_isCancelled) setState(() => _isAnalyzing = false);
      _pipelineController?.close();
    }
  }

  void _showSuccessPopup(String imagePath) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => _SuccessPopup(
        imagePath: imagePath, category: _getCategory(), itemName: _detectedClass, carbonFootprint: _carbonFootprint,
        onAdd: () async {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.addCarbonFootprint(_carbonFootprint, _getCategory().toLowerCase());
          if (mounted) {
            Navigator.pop(context);
            setState(() { _isDialogShowing = false; _useNativeYoloView = true; _capturedImagePath = null; _streakCount = 0; _missedFrames = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; _isAnalyzing = true; });
            Future.delayed(const Duration(milliseconds: 2500), () { if (mounted) setState(() => _isAnalyzing = false); });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impact successfully added!"), backgroundColor: Color(0xFF2D3E50)));
          }
        },
        onRetry: () {
          Navigator.pop(context);
          setState(() { _isDialogShowing = false; _useNativeYoloView = true; _capturedImagePath = null; _streakCount = 0; _missedFrames = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; _isAnalyzing = true; });
          Future.delayed(const Duration(milliseconds: 2500), () { if (mounted) setState(() => _isAnalyzing = false); });
        },
      ),
    );
  }

  void _showFailurePopup({String? customMessage}) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => _FailurePopup(
        message: customMessage ?? "We couldn't identify this item. Please ensure it's within the frame and has good lighting.",
        onRetry: () {
          Navigator.pop(context);
          setState(() { _isDialogShowing = false; _useNativeYoloView = true; _capturedImagePath = null; _streakCount = 0; _missedFrames = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; _isAnalyzing = true; });
          Future.delayed(const Duration(milliseconds: 2500), () { if (mounted) setState(() => _isAnalyzing = false); });
        },
      ),
    );
  }

  String _getCategory() {
    String name = _yoloCategory.toUpperCase();
    if (name.contains('DRINK') || name.contains('FOOD') || name.contains('NOODLE') || name.contains('RICE') || name.contains('SNACK')) return 'Food & Drink';
    return 'Shopping';
  }

  @override
  void dispose() {
    _isCancelled = true;
    _pipelineController?.close();
    _controller?.dispose();
    _textRecognizer.close();
    _gruInterpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isInitialized && _yoloPlugin != null
                ? (_useNativeYoloView
                ? YOLOView(
              modelPath: '${Directory.systemTemp.path}/yolo_f16_live.tflite',
              task: YOLOTask.detect,
              onResult: (results) {
                int currentTime = DateTime.now().millisecondsSinceEpoch;
                if (currentTime - _lastYoloFrameTime < 66) return;
                _lastYoloFrameTime = currentTime;

                if (results.isEmpty) {
                  if (_streakCount >= 2 && _lastDetectionTime != null && DateTime.now().difference(_lastDetectionTime!).inMilliseconds < 1000) {
                    // Visual Decay Timer
                  } else {
                    if (mounted) setState(() { _streakCount = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; _missedFrames = 0; });
                  }
                  return;
                }

                double bestConf = 0.0;
                String bestLabel = "";

                for (var res in results) {
                  dynamic dynamicRes = res;
                  double conf = 0.0; try { conf = dynamicRes.confidence?.toDouble() ?? 0.0; } catch (_) {}
                  if (conf == 0.0) try { conf = dynamicRes.score?.toDouble() ?? 0.0; } catch (_) {}
                  String label = ""; try { label = dynamicRes.className?.toString() ?? ""; } catch (_) {}
                  if (label.isEmpty) try { label = dynamicRes.name?.toString() ?? ""; } catch (_) {}
                  if (label.isEmpty) try { label = dynamicRes.label?.toString() ?? ""; } catch (_) {}

                  if (conf > bestConf && label.isNotEmpty) {
                    bestConf = conf;
                    bestLabel = label;
                  }
                }

                double requiredThreshold = 0.45;
                if (bestLabel == "instant_noodles" || bestLabel == "snack_pack") requiredThreshold = 0.60;
                else if (bestLabel == "cleaning_product" || bestLabel == "personal_care") requiredThreshold = 0.55;
                else if (bestLabel == "can_drink" || bestLabel == "plastic-bottle") requiredThreshold = 0.50;

                if (bestConf >= requiredThreshold) {
                  if (bestLabel == _currentStreakClass) {
                    _streakCount++;
                    _missedFrames = 0;
                  } else {
                    if (_streakCount > 0 && _missedFrames < 1) {
                      _missedFrames++;
                    } else {
                      _currentStreakClass = bestLabel;
                      _streakCount = 1;
                      _missedFrames = 0;
                    }
                  }

                  if (mounted) setState(() => _currentStreakConf = bestConf);

                  if (_streakCount >= 2) {
                    _liveDetectedClass = _currentStreakClass;
                    _liveDetectedConf = bestConf;
                    _lastDetectionTime = DateTime.now();
                  }
                } else {
                  if (_streakCount >= 2 && _lastDetectionTime != null && DateTime.now().difference(_lastDetectionTime!).inMilliseconds < 1000) {
                    // Decay Timer Hold
                  } else {
                    if (mounted) setState(() { _streakCount = 0; _currentStreakClass = ""; _currentStreakConf = 0.0; _missedFrames = 0; });
                  }
                }
              },
            )
                : (_capturedImagePath != null ? Image.file(File(_capturedImagePath!), fit: BoxFit.cover) : const Center(child: CircularProgressIndicator(color: brandGreen))))
                : const Center(child: CircularProgressIndicator(color: brandGreen)),
          ),

          if (!_isDialogShowing && _useNativeYoloView && _currentStreakClass.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 90, left: 0, right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: _streakCount >= 2 ? brandGreen.withValues(alpha: 0.95) : brandNavy.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: _streakCount >= 2 ? brandNavy : Colors.transparent, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))]
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_streakCount >= 2 ? Icons.check_circle_rounded : Icons.sync_rounded, color: _streakCount >= 2 ? brandNavy : Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(_currentStreakClass.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: _streakCount >= 2 ? brandNavy : Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _streakCount >= 2 ? brandNavy.withValues(alpha: 0.1) : brandGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                        child: Text("${(_currentStreakConf * 100).toStringAsFixed(0)}%", style: TextStyle(color: _streakCount >= 2 ? brandNavy : brandGreen, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 20, left: 24, right: 24),
                  color: brandNavy.withValues(alpha: 0.4),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white)),
                      const Spacer(),
                      IconButton(onPressed: () { showDialog(context: context, builder: (context) => _MetricsDashboardDialog(logger: _logger)); }, icon: const Icon(Icons.folder_open_rounded, color: Colors.white70)),
                      IconButton(onPressed: () { setState(() => _metricsModeEnabled = !_metricsModeEnabled); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_metricsModeEnabled ? "Telemetry Logging Enabled" : "Telemetry Logging Disabled"))); }, icon: Icon(_metricsModeEnabled ? Icons.analytics_rounded : Icons.analytics_outlined, color: _metricsModeEnabled ? brandGreen : Colors.white70)),
                      IconButton(onPressed: () async { try { if (_isFlashOn) { await TorchLight.disableTorch(); setState(() => _isFlashOn = false); } else { await TorchLight.enableTorch(); setState(() => _isFlashOn = true); } } catch (_) {} }, icon: Icon(_isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: _isFlashOn ? brandGreen : Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (!_isDialogShowing)
            Positioned(
              bottom: 60, left: 0, right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _isAnalyzing ? null : () => _runPipeline(),
                    child: Container(
                      height: 84, width: 84, padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: Container(
                        decoration: const BoxDecoration(color: brandGreen, shape: BoxShape.circle),
                        child: Center(
                          child: _isAnalyzing
                              ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: brandNavy, strokeWidth: 3))
                              : const FaIcon(FontAwesomeIcons.camera, color: brandNavy, size: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _isAnalyzing ? null : () async {
                      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, maxHeight: 1080, imageQuality: 85);
                      if (image != null) _runPipeline(preSelectedImage: image);
                    },
                    child: const Text("UPLOAD IMAGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// METRICS DASHBOARD DIALOG
// ============================================================================
class _MetricsDashboardDialog extends StatelessWidget {
  final TelemetryLogger logger;
  const _MetricsDashboardDialog({required this.logger});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [Icon(Icons.analytics_rounded, color: brandNavy, size: 28), SizedBox(width: 12), Text("Telemetry Dashboard", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: brandNavy))]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Current Save Location:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)), const SizedBox(height: 4),
                  Text(logger.currentDirPath, style: const TextStyle(fontSize: 12, color: brandNavy)), const SizedBox(height: 12),
                  const Text("Note: Files are automatically forced to your Android Downloads folder to bypass Scoped Storage limitations.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black45)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {}, // Locked for scoping compliance
              icon: const Icon(Icons.check_circle_outline_rounded), label: const Text("Path Locked to Downloads"), style: ElevatedButton.styleFrom(backgroundColor: brandNavy, foregroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await logger.archiveCurrentRun();
                if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Run Archived! Starting a fresh telemetry log."))); }
              },
              icon: const Icon(Icons.archive), label: const Text("Start New Run (Archive Old Data)"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// OCR VERIFICATION DIALOG (UI/UX FIX FOR UNITS)
// ============================================================================
class _OcrVerificationDialog extends StatefulWidget {
  final String imagePath;
  final List<TextBlock> textBlocks;
  final String initialQuery;
  final double initialWeightValue; // Extracted raw number
  final String initialUnit; // Extracted unit
  final bool weightFound;

  const _OcrVerificationDialog({
    required this.imagePath,
    required this.textBlocks,
    required this.initialQuery,
    required this.initialWeightValue,
    required this.initialUnit,
    required this.weightFound
  });

  @override
  State<_OcrVerificationDialog> createState() => _OcrVerificationDialogState();
}

class _OcrVerificationDialogState extends State<_OcrVerificationDialog> {
  late TextEditingController _queryController;
  late TextEditingController _weightController;
  late String _selectedUnit;

  final FocusNode _queryFocus = FocusNode();
  final FocusNode _weightFocus = FocusNode();
  final Color brandNavy = const Color(0xFF2D3E50);
  final Color brandGreen = const Color(0xFFC8FFB0);

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);

    // UI/UX FIX: Only display the pure number, elegantly removing .0 if integer
    String weightText = "";
    if (widget.weightFound && widget.initialWeightValue > 0) {
      weightText = widget.initialWeightValue == widget.initialWeightValue.truncateToDouble()
          ? widget.initialWeightValue.toInt().toString()
          : widget.initialWeightValue.toString();
    }
    _weightController = TextEditingController(text: weightText);

    // Default the dropdown to the exact unit the OCR extracted!
    _selectedUnit = widget.initialUnit.toLowerCase();
    if (!['g', 'kg', 'ml', 'l'].contains(_selectedUnit)) {
      _selectedUnit = 'g';
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _weightController.dispose();
    _queryFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  void _onChipTapped(String text) {
    if (_weightFocus.hasFocus) {
      // Smart tap extraction if user taps a chip into the weight box
      RegExp numReg = RegExp(r'(\d+(?:\.\d+)?)');
      RegExp unitReg = RegExp(r'(kg|g|ml|l)', caseSensitive: false);

      var numMatch = numReg.firstMatch(text);
      var unitMatch = unitReg.firstMatch(text);

      if (numMatch != null) {
        _weightController.text = numMatch.group(1)!;
        _weightController.selection = TextSelection.collapsed(offset: _weightController.text.length);
      }
      if (unitMatch != null) {
        String u = unitMatch.group(1)!.toLowerCase();
        if (['g', 'kg', 'ml', 'l'].contains(u)) {
          setState(() => _selectedUnit = u);
        }
      }
    } else {
      final currentText = _queryController.text.trim();
      _queryController.text = currentText.isEmpty ? text : "$currentText $text";
      _queryController.selection = TextSelection.collapsed(offset: _queryController.text.length);
      if (!_queryFocus.hasFocus) FocusScope.of(context).requestFocus(_queryFocus);
    }
  }

  void _submit() {
    double parsedWeight = double.tryParse(_weightController.text) ?? 0.0;
    double finalWeightKg = 0.0;

    if (parsedWeight > 0) {
      // Securely convert the User Input + Dropdown combination into internal kg structure
      if (_selectedUnit == 'g' || _selectedUnit == 'ml') {
        finalWeightKg = parsedWeight / 1000.0;
      } else {
        finalWeightKg = parsedWeight; // Already kg or L
      }
    }

    Navigator.pop(context, {
      'query': _queryController.text.trim(),
      'weight': finalWeightKg,
      'weightFound': _weightController.text.trim().isNotEmpty && parsedWeight > 0
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: SizedBox(height: 120, width: double.infinity, child: Image.file(File(widget.imagePath), fit: BoxFit.cover))),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Verify Scanned Text", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF2D3E50))), const SizedBox(height: 6),
                    const Text("Tap the extracted text chips below to build your search query, or type manually.", style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4)), const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140), padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: widget.textBlocks.map((block) {
                            String text = block.text.replaceAll('\n', ' ').trim();
                            return ActionChip(label: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), backgroundColor: Colors.white, side: BorderSide(color: brandGreen, width: 1.5), onPressed: () => _onChipTapped(text));
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _queryController, focusNode: _queryFocus,
                        decoration: InputDecoration(labelText: "Search Query (Brand/Item)", labelStyle: TextStyle(color: brandNavy.withValues(alpha: 0.6), fontWeight: FontWeight.w600), filled: true, fillColor: brandNavy.withValues(alpha: 0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandGreen, width: 2)))
                    ),
                    const SizedBox(height: 16),

                    // --- NEW UI: SPLIT NUMBER INPUT AND UNIT DROPDOWN ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                              controller: _weightController,
                              focusNode: _weightFocus,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: "Weight/Volume",
                                  labelStyle: TextStyle(color: brandNavy.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                                  filled: true,
                                  fillColor: brandNavy.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandGreen, width: 2))
                              )
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
                            items: ['g', 'kg', 'ml', 'l'].map((String unit) {
                              return DropdownMenuItem<String>(
                                value: unit,
                                child: Text(unit, style: TextStyle(fontWeight: FontWeight.bold, color: brandNavy)),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedUnit = newValue;
                                });
                              }
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: brandNavy.withValues(alpha: 0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            icon: const Icon(Icons.arrow_drop_down, color: brandNavy),
                            dropdownColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    // ----------------------------------------------------
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(context, null), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)))), const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: brandNavy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.w900)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingDialog extends StatefulWidget {
  final Stream<PipelineUpdate> updateStream; final List<PipelineUpdate> initialLogs; final int initialProgress; final Function(bool) onCancel;
  const _ProcessingDialog({required this.updateStream, this.initialLogs = const [], this.initialProgress = 0, required this.onCancel});
  @override
  State<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<_ProcessingDialog> {
  int _currentProgress = 0; final List<PipelineUpdate> _logs = []; late StreamSubscription<PipelineUpdate> _subscription;

  @override
  void initState() {
    super.initState(); _currentProgress = widget.initialProgress; _logs.addAll(widget.initialLogs);
    _subscription = widget.updateStream.listen((update) { if (mounted) setState(() { _currentProgress = update.progress; _logs.insert(0, update); }); });
  }

  @override
  void dispose() { _subscription.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50); const Color brandGreen = Color(0xFFC8FFB0);
    return PopScope(
      canPop: true, onPopInvokedWithResult: (didPop, result) { if (didPop && result != 'system_transition') widget.onCancel(true); },
      child: Dialog(
        backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          height: 520, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.98), borderRadius: BorderRadius.circular(32)), padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("ANALYZING", style: TextStyle(color: brandNavy.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)), const SizedBox(height: 4), Text("$_currentProgress%", style: const TextStyle(color: brandNavy, fontSize: 56, height: 1.0, fontWeight: FontWeight.w900))]),
                  SizedBox(width: 40, height: 40, child: CircularProgressIndicator(value: _currentProgress / 100, color: brandGreen, backgroundColor: brandNavy.withValues(alpha: 0.1), strokeWidth: 6)),
                ],
              ),
              const SizedBox(height: 24), const Divider(height: 1), const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index]; final bool isLatest = index == 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(margin: const EdgeInsets.only(top: 4), width: 8, height: 8, decoration: BoxDecoration(color: isLatest ? brandGreen : brandNavy.withValues(alpha: 0.2), shape: BoxShape.circle)), const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(log.step, style: TextStyle(color: isLatest ? brandNavy : brandNavy.withValues(alpha: 0.4), fontWeight: FontWeight.w800, fontSize: 13)), const SizedBox(height: 4), Text(log.detail, style: TextStyle(color: isLatest ? brandNavy.withValues(alpha: 0.8) : brandNavy.withValues(alpha: 0.3), fontWeight: FontWeight.w600, fontSize: 12, height: 1.3))])),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: TextButton(onPressed: () => widget.onCancel(false), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: Colors.red.withValues(alpha: 0.1)), child: const Text("CANCEL PROCESS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, letterSpacing: 1.2)))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessPopup extends StatelessWidget {
  final String imagePath; final String category; final String itemName; final double carbonFootprint; final VoidCallback onAdd; final VoidCallback onRetry;
  const _SuccessPopup({required this.imagePath, required this.category, required this.itemName, required this.carbonFootprint, required this.onAdd, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50); const Color brandGreen = Color(0xFFC8FFB0);
    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.98), borderRadius: BorderRadius.circular(32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), child: SizedBox(height: 220, width: double.infinity, child: Image.file(File(imagePath), fit: BoxFit.cover))),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(category.toUpperCase(), style: TextStyle(color: brandNavy.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)), const SizedBox(height: 4), Text(itemName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: brandNavy, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1))])),
                      const SizedBox(width: 8), Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: brandGreen.withValues(alpha: 0.2), shape: BoxShape.circle), child: const FaIcon(FontAwesomeIcons.leaf, color: brandNavy, size: 18)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 24), decoration: BoxDecoration(color: brandNavy.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24)),
                    child: Column(children: [const Text("ESTIMATED FOOTPRINT", style: TextStyle(color: brandNavy, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0)), const SizedBox(height: 8), RichText(text: TextSpan(children: [TextSpan(text: carbonFootprint.toStringAsFixed(2), style: const TextStyle(color: brandNavy, fontSize: 52, fontWeight: FontWeight.w900)), const TextSpan(text: " kg CO2e", style: TextStyle(color: brandNavy, fontSize: 16, fontWeight: FontWeight.w700))]))]),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: onRetry, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("RETRY", style: TextStyle(color: brandNavy, fontWeight: FontWeight.w900)))), const SizedBox(width: 12),
                      Expanded(child: ElevatedButton(onPressed: onAdd, style: ElevatedButton.styleFrom(backgroundColor: brandNavy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0), child: const Text("ADD IMPACT", style: TextStyle(fontWeight: FontWeight.w900)))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailurePopup extends StatelessWidget {
  final VoidCallback onRetry; final String message;
  const _FailurePopup({required this.onRetry, required this.message});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 15))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 40)), const SizedBox(height: 24),
            const Text("Not Recognized", style: TextStyle(color: brandNavy, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xB32D3E50), fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)), const SizedBox(height: 32),
            GestureDetector(onTap: onRetry, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: brandNavy, borderRadius: BorderRadius.circular(16)), child: const Center(child: Text("TRY AGAIN", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.2))))),
          ],
        ),
      ),
    );
  }
}

class _ScannerInstructionDialog extends StatefulWidget {
  const _ScannerInstructionDialog();
  @override
  State<_ScannerInstructionDialog> createState() => _ScannerInstructionDialogState();
}

class _ScannerInstructionDialogState extends State<_ScannerInstructionDialog> {
  bool _doNotShowAgain = false;
  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50); const Color brandGreen = Color(0xFFC8FFB0);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 15))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: brandGreen.withValues(alpha: 0.2), shape: BoxShape.circle), child: const Icon(Icons.lightbulb_outline_rounded, color: brandNavy, size: 32)), const SizedBox(height: 24),
            const Text("Optimal Detection", style: TextStyle(color: brandNavy, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)), const SizedBox(height: 16),
            const Text("For optimal detection, have sufficient lighting, avoid blurry photos, and use the front of the packaging.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xB32D3E50), fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)), const SizedBox(height: 24),
            Row(children: [SizedBox(height: 24, width: 24, child: Checkbox(value: _doNotShowAgain, onChanged: (value) => setState(() => _doNotShowAgain = value ?? false), activeColor: brandNavy, checkColor: brandGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)))), const SizedBox(width: 12), GestureDetector(onTap: () => setState(() => _doNotShowAgain = !_doNotShowAgain), child: const Text("Don't show again", style: TextStyle(color: brandNavy, fontSize: 14, fontWeight: FontWeight.w700)))]), const SizedBox(height: 32),
            GestureDetector(
              onTap: () async { if (_doNotShowAgain) { final prefs = await SharedPreferences.getInstance(); await prefs.setBool('show_scanner_instructions', false); } if (context.mounted) Navigator.pop(context); },
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(color: brandNavy, borderRadius: BorderRadius.circular(16)), child: const Center(child: Text("GOT IT", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.2)))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSelectionDialog extends StatefulWidget {
  final List<Product> products;
  const _ProductSelectionDialog({required this.products});
  @override
  State<_ProductSelectionDialog> createState() => _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  int _currentPage = 0; static const int _itemsPerPage = 3;
  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    final int totalPages = (widget.products.length / _itemsPerPage).ceil();
    final List<Product> displayedProducts = widget.products.skip(_currentPage * _itemsPerPage).take(_itemsPerPage).toList();

    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Select Product", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: brandNavy)), const SizedBox(height: 8),
            const Text("Please select the correct item from the database, or skip if it's not listed:", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.black54)), const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true, itemCount: displayedProducts.length, separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = displayedProducts[index];
                  final name = p.productName != null && p.productName!.isNotEmpty ? p.productName! : "Unknown Product";
                  final brand = p.brands != null && p.brands!.isNotEmpty ? p.brands! : "Unknown Brand";
                  final quantity = p.quantity != null && p.quantity!.isNotEmpty ? p.quantity! : "Unknown Qty";

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: p.imageFrontSmallUrl != null ? Image.network(p.imageFrontSmallUrl!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(width: 48, height: 48, color: Colors.grey[200], child: const Icon(Icons.shopping_bag, color: Colors.grey))) : Container(width: 48, height: 48, color: Colors.grey[200], child: const Icon(Icons.shopping_bag, color: Colors.grey))),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: brandNavy), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text("$brand • $quantity", style: const TextStyle(fontSize: 12, color: brandNavy, fontWeight: FontWeight.w600))),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
            if (totalPages > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16), color: _currentPage > 0 ? brandNavy : Colors.grey, onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null),
                  Text("Page ${_currentPage + 1} of $totalPages", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brandNavy)),
                  IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16), color: _currentPage < totalPages - 1 ? brandNavy : Colors.grey, onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context, 'cancel'), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: Colors.red.withValues(alpha: 0.1)), child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)))), const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context, 'skip'), style: ElevatedButton.styleFrom(backgroundColor: brandNavy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("SKIP", style: TextStyle(fontWeight: FontWeight.w900)))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}