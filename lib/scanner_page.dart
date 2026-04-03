import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'package:torch_light/torch_light.dart'; // Handles native hardware flash bypass

// Google LiteRT (Formerly TensorFlow Lite Flutter)
import 'package:flutter_litert/flutter_litert.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'user_provider.dart';

// =========================================================================
// BACKGROUND IMAGE PROCESSOR (Used purely for Uploaded Images now)
// =========================================================================
Future<Uint8List> prepareYoloImage(String path) async {
  final bytes = await File(path).readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // Fix EXIF orientation (e.g. if the image was taken upside down)
  decoded = img.bakeOrientation(decoded);

  // Scale down to max 640px to match YOLO format and save memory
  int targetSize = 640;
  double scale = targetSize / (decoded.width > decoded.height ? decoded.width : decoded.height);
  int newWidth = (decoded.width * scale).toInt();
  int newHeight = (decoded.height * scale).toInt();

  img.Image resizedImage = img.copyResize(decoded, width: newWidth, height: newHeight);

  // Apply letterboxing (gray padding) to make it exactly 640x640
  img.Image squareImage = img.Image(width: targetSize, height: targetSize);
  img.fill(squareImage, color: img.ColorRgb8(114, 114, 114));

  int xOffset = (targetSize - newWidth) ~/ 2;
  int yOffset = (targetSize - newHeight) ~/ 2;
  img.compositeImage(squareImage, resizedImage, dstX: xOffset, dstY: yOffset);

  return img.encodeJpg(squareImage, quality: 90);
}
// =========================================================================

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

  // State for Hybrid Approach
  bool _useNativeYoloView = false; // Start false to prevent camera running behind startup dialogs!
  String? _capturedImagePath; // Stores the frozen frame for the background
  String _liveDetectedClass = "";
  double _liveDetectedConf = 0.0;
  DateTime? _lastDetectionTime;

  // Temporal Smoothing (Streak Filter, Forgiveness Buffer & Thermal Throttle)
  String _currentStreakClass = "";
  double _currentStreakConf = 0.0; // Captures real-time confidence for the UI Pill
  int _streakCount = 0;
  int _missedFrames = 0;
  int _lastYoloFrameTime = 0;

  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();
  bool _isCancelled = false;

  Interpreter? _gruInterpreter;
  Map<String, dynamic>? _lcaDatabase;
  Map<String, dynamic>? _scalerConfig;
  YOLO? _yoloPlugin; // Used purely for static image uploads

  bool _isDialogShowing = false;
  bool _isAnalyzing = false;

  // UI and Logic State variables
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
      }
    });
  }

  Future<void> _initializeSystem() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("❌ Camera Hardware Not Found");
      }

      try {
        final lcaString = await rootBundle.loadString('assets/flutter_lca_database.json');
        _lcaDatabase = json.decode(lcaString);

        final scalerString = await rootBundle.loadString('assets/flutter_scaler_config.json');
        _scalerConfig = json.decode(scalerString);
      } catch (e) {
        debugPrint("❌ JSON Databases Error: $e");
      }

      try {
        // FIX FOR SIGSEGV CRASH:
        // We create TWO separate files. One for the YOLOView live camera stream,
        // and one for the static _yoloPlugin. This prevents them from fighting
        // over the same memory-mapped TFLite file and crashing the GPU delegate.
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

        // Initialize static plugin exclusively on the static file copy
        _yoloPlugin = YOLO(
          modelPath: staticFile.path,
          task: YOLOTask.detect,
        );
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

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
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

    // Only start the camera feed AFTER the startup dialogs are fully closed
    if (mounted) {
      setState(() {
        _useNativeYoloView = true;
      });
    }
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
      if (!poppedBySystem && mounted) {
        Navigator.pop(context, 'system_transition');
      }
    }
    if (mounted) {
      setState(() {
        _useNativeYoloView = true; // Restore the live stream
        _capturedImagePath = null; // Clear frozen frame
        _streakCount = 0; // Reset streaks
        _missedFrames = 0;
        _currentStreakClass = "";
        _currentStreakConf = 0.0;
      });
      // Safety Cooldown: Keep buttons locked for 2.5s to prevent SIGSEGV from rapid unmounting!
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _isAnalyzing = false);
      });
    }
  }

  Future<String?> _runYoloInference(String imagePath) async {
    if (_yoloPlugin == null) return null;
    try {
      final Uint8List fixedBytes = await compute(prepareYoloImage, imagePath);
      if (!mounted || _isCancelled) return null;

      final resultsMap = await _yoloPlugin!.predict(
        fixedBytes,
        // Send a low threshold to the plugin so we grab all candidates,
        // we will filter them using our custom math below!
        confidenceThreshold: 0.20,
      );

      if (resultsMap.isNotEmpty) {
        double bestWeightedScore = 0.0;
        String bestLabel = "";

        resultsMap.forEach((key, value) {
          if (value is List) {
            for (var item in value) {
              if (item is Map) {
                double conf = (item['confidence'] ?? item['score'] ?? 0.0).toDouble();
                String label = (item['className'] ?? item['label'] ?? item['class'] ?? "").toString();

                // 1. DYNAMIC THRESHOLDS FOR STATIC UPLOADS
                double requiredThreshold = 0.30;
                if (label == "instant_noodles" || label == "snack_pack") {
                  requiredThreshold = 0.50; // Stricter for noisy textures
                } else if (label == "cleaning_product" || label == "personal_care") {
                  requiredThreshold = 0.40;
                }

                if (conf >= requiredThreshold && label.isNotEmpty) {
                  // 2. AREA-WEIGHTED SCORING (The "Subject" Filter)
                  // Grabs the size of the bounding box to calculate surface area
                  double l = (item['left'] ?? item['xMin'] ?? 0.0).toDouble();
                  double t = (item['top'] ?? item['yMin'] ?? 0.0).toDouble();
                  double r = (item['right'] ?? item['xMax'] ?? 0.0).toDouble();
                  double b = (item['bottom'] ?? item['yMax'] ?? 0.0).toDouble();

                  double w = (item['width'] ?? (r - l).abs()).toDouble();
                  double h = (item['height'] ?? (b - t).abs()).toDouble();

                  double boxArea = w * h;
                  // Failsafe: if plugin didn't provide coordinates, default to 1.0 (pure confidence)
                  if (boxArea <= 0.0) boxArea = 1.0;

                  // Multiply confidence by Area. This mathematically guarantees that a
                  // huge, prominent 35% Coke can will instantly outscore a tiny 90% background bottle.
                  double weightedScore = conf * boxArea;

                  if (weightedScore > bestWeightedScore) {
                    bestWeightedScore = weightedScore;
                    bestLabel = label;
                  }
                }
              }
            }
          }
        });
        if (bestLabel.isNotEmpty) return bestLabel;
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
      List<double> actualLca = baseLca.map((val) => (val as double) * weightKg).toList();
      List<dynamic> scaleVals = _scalerConfig!['scale_vals'];
      List<dynamic> minOffsets = _scalerConfig!['min_offsets'];

      List<double> scaledLca = [];
      for (int i = 0; i < actualLca.length; i++) {
        scaledLca.add((actualLca[i] * scaleVals[i]) + minOffsets[i]);
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

  // --- AUTOMATED VOLUMETRIC SCALING (AR Axed) ---
  Future<double> _estimateWeightVolumetrically(String detectedClass) async {
    _emitUpdate(65, "5. Volumetric Scaling", "Estimating mass based on product category...");
    await Future.delayed(const Duration(milliseconds: 600));
    if (_isCancelled) throw Exception("cancelled_by_user");

    // Exact Volumetric Scaling Constants (Defaulting to standard 30cm distance parameters)
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

    setState(() {
      _isAnalyzing = true;
      _isDialogShowing = true;
      _isCancelled = false; // Reset on start
      _useNativeYoloView = false; // IMMEDIATELY unmount and stop the live camera feed
      _streakCount = 0;
      _missedFrames = 0;
    });

    // Ensure the native flash is safely turned off before camera control swaps
    if (_isFlashOn) {
      try {
        await TorchLight.disableTorch();
        _isFlashOn = false;
      } catch (_) {}
    }

    if (preSelectedImage != null) {
      setState(() {
        _capturedImagePath = preSelectedImage!.path; // Added '!' to fix null-safety error
      });
    }

    _pipelineHistory.clear();
    _currentPipelineProgress = 0;
    // Broadcast stream so we can pause/recreate the dialog listening to it
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
      String finalImagePath = "";
      String currentDetectedClass = "";
      String uiItemName = "";

      if (preSelectedImage != null) {
        // --- MANUAL UPLOAD LOGIC ---
        _emitUpdate(5, "1. Image Upload", "Safely allocating memory...");
        finalImagePath = preSelectedImage.path; // Added '!' here too just in case

        // Wait 2500ms for YOLOView to fully unmount before running static YOLO prediction
        // This prevents the SIGSEGV crash caused by GPU delegate memory conflicts!
        await Future.delayed(const Duration(milliseconds: 2500));
        if (_isCancelled) throw Exception("cancelled_by_user");

        _emitUpdate(10, "1. Image Upload", "Analyzing uploaded image...");
        String? yoloResult = await _runYoloInference(finalImagePath);
        if (yoloResult == null) {
          throw Exception("YOLO could not classify item.");
        }
        currentDetectedClass = yoloResult;
        _emitUpdate(20, "2. Vision Model", "Verified: $currentDetectedClass");

      } else {
        // --- LIVE HYBRID LOGIC ---
        _emitUpdate(5, "1. Live Detection", "Locking YOLO prediction...");

        // Failsafe: Ensure YOLO actually saw something within the last 1.5 seconds!
        // Because _liveDetectedClass stays in memory for 1.5s, the user has a generous window to tap scan.
        if (_liveDetectedClass.isEmpty || _lastDetectionTime == null || DateTime.now().difference(_lastDetectionTime!).inMilliseconds > 1500) {
          throw Exception("No clear object detected. Please aim at an object first.");
        }

        currentDetectedClass = _liveDetectedClass;
        _emitUpdate(10, "1. Vision Model", "Verified from live stream: $currentDetectedClass (${(_liveDetectedConf * 100).toStringAsFixed(0)}%)");

        _emitUpdate(20, "2. Hardware Override", "Releasing native camera feed...");

        // CRITICAL FIX: Wait to ensure YOLOView hardware and native TFLite thread
        // are completely released by the OS before starting CameraController.
        // The logs showed inference taking ~2000ms. 2500ms safely clears the pipeline.
        await Future.delayed(const Duration(milliseconds: 2500));
        if (_isCancelled) throw Exception("cancelled_by_user");

        // Guarantee camera is released by wrapping in try/finally
        try {
          final cameras = await availableCameras();
          _controller = CameraController(
            cameras.first,
            // Optimization 2: Cap resolution to veryHigh (1080p-2160p) to completely prevent
            // Out-Of-Memory (OOM) crashes on low-end devices with 108MP/200MP sensors!
            ResolutionPreset.veryHigh,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.nv21,
          );
          await _controller!.initialize();
          if (_isCancelled) throw Exception("cancelled_by_user");

          _emitUpdate(30, "3. Image Capture", "Taking high-res snapshot for OCR...");
          final XFile capturedImage = await _controller!.takePicture();
          finalImagePath = capturedImage.path;

          // Freeze the captured image beautifully in the background
          if (mounted) {
            setState(() {
              _capturedImagePath = finalImagePath;
            });
          }
        } finally {
          // Immediately free the camera hardware no matter what happens
          await _controller?.dispose();
          _controller = null;
        }
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      // Optimization 4: Aggressive Garbage Collection
      // Dereference the heavy preSelectedImage XFile before heavy API/ML Kit work
      preSelectedImage = null;

      // Default to YOLO Class Name for UI unless OFF provides a better one
      uiItemName = currentDetectedClass.replaceAll('_', ' ').toUpperCase();

      // STEP 2: OCR Data Extraction
      _emitUpdate(50, "4. Data Extraction (OCR)", "Scanning packaging for weight & labels...");
      final InputImage inputImage = InputImage.fromFilePath(finalImagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      String ocrText = recognizedText.text.replaceAll('\n', ' ').toLowerCase();

      // SPATIAL OCR SORTING
      List<TextBlock> sortedBlocks = recognizedText.blocks.toList();
      sortedBlocks.sort((a, b) {
        double areaA = a.boundingBox.width * a.boundingBox.height;
        double areaB = b.boundingBox.width * b.boundingBox.height;
        return areaB.compareTo(areaA);
      });

      List<String> prominentText = [];
      for (var block in sortedBlocks) {
        String text = block.text.replaceAll('\n', ' ').trim();
        if (text.length > 2 && !text.toLowerCase().contains("net") && !text.toLowerCase().contains("weight")) {
          prominentText.add(text);
        }
      }

      // We intentionally leave the initial query empty so the user builds it from the chips
      String ocrSearchContext = "";
      String detectedBrand = prominentText.isNotEmpty ? prominentText.first.toUpperCase() : "";

      if (_isCancelled) throw Exception("cancelled_by_user");

      double detectedWeightKg = 0.5;
      bool ocrWeightFound = false;

      RegExp weightRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l)', caseSensitive: false);
      var match = weightRegex.firstMatch(ocrText);
      if (match != null) {
        try {
          double val = double.parse(match.group(1)!);
          String unit = match.group(2)!.toLowerCase();

          if (unit == 'g' || unit == 'ml') {
            detectedWeightKg = val / 1000.0;
          } else if (unit == 'kg' || unit == 'l') {
            detectedWeightKg = val;
          }
          ocrWeightFound = true;
        } catch (e) {
          debugPrint("Regex parse error: $e");
        }
      }

      // =======================================================================
      // STEP 2.1: OCR Verification Dialog
      // =======================================================================
      _emitUpdate(55, "4. Verification", "Awaiting user verification of OCR data...");
      await Future.delayed(const Duration(milliseconds: 300));

      if (_isDialogShowing) {
        Navigator.pop(context, 'system_transition'); // Passing system_transition prevents onCancel bug
        _isDialogShowing = false;
      }

      final verificationResult = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _OcrVerificationDialog(
          imagePath: finalImagePath,
          textBlocks: sortedBlocks,
          initialQuery: ocrSearchContext,
          initialWeight: detectedWeightKg,
          weightFound: ocrWeightFound,
        ),
      );

      if (verificationResult == null) {
        throw Exception("cancelled_by_user");
      }

      // Update state with user-verified input
      ocrSearchContext = verificationResult['query'];
      detectedWeightKg = verificationResult['weight'];
      ocrWeightFound = verificationResult['weightFound'];
      detectedBrand = ocrSearchContext.isNotEmpty ? ocrSearchContext.split(' ').first.toUpperCase() : "Unknown";

      // Re-open processing dialog
      _isDialogShowing = true;
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

      _emitUpdate(56, "4. Verification", "Data verified. Query: $ocrSearchContext");
      if (_isCancelled) throw Exception("cancelled_by_user");


      // =======================================================================
      // STEP 2.5: OPEN FOOD FACTS CLOUD API
      // =======================================================================
      _emitUpdate(58, "4. OpenFoodFacts Search", "Querying DB for precise product description...");

      String searchQuery = ocrSearchContext.isNotEmpty
          ? ocrSearchContext
          : currentDetectedClass.replaceAll('_', ' ');

      try {
        ProductSearchQueryConfiguration configuration = ProductSearchQueryConfiguration(
          parametersList: <Parameter>[
            SearchTerms(terms: [searchQuery]),
            PageSize(size: 6), // Only grab max 6 items so the request doesn't freeze!
          ],
          language: OpenFoodFactsLanguage.ENGLISH,
          version: ProductQueryVersion.v3,
        );

        // Added a 10-second timeout to prevent permanent freezing
        SearchResult result = await OpenFoodAPIClient.searchProducts(
          null,
          configuration,
        ).timeout(const Duration(seconds: 10));

        if (result.products != null && result.products!.isNotEmpty) {
          // Pause processing dialog to show product selection
          if (_isDialogShowing) {
            Navigator.pop(context, 'system_transition');
            _isDialogShowing = false;
          }

          // Request dynamic result (can be 'cancel', 'skip', or a Product)
          final dialogResult = await showDialog<dynamic>(
            context: context,
            barrierDismissible: false,
            builder: (context) => _ProductSelectionDialog(products: result.products!),
          );

          if (dialogResult == null || dialogResult == 'cancel') {
            throw Exception("cancelled_by_user");
          }

          // Resume processing dialog
          _isDialogShowing = true;
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

          if (dialogResult is Product) {
            final selectedProduct = dialogResult;
            // 1. Capture the beautiful description/product name for the Success UI
            if (selectedProduct.productName != null && selectedProduct.productName!.isNotEmpty) {
              uiItemName = selectedProduct.productName!;
            }

            // 2. Capture the validated brand
            detectedBrand = (selectedProduct.brands ?? detectedBrand).toUpperCase();

            // 3. Extract the perfect weight if available
            if (selectedProduct.quantity != null && selectedProduct.quantity!.isNotEmpty) {
              RegExp regex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l|cl)', caseSensitive: false);
              var m = regex.firstMatch(selectedProduct.quantity!);

              if (m != null) {
                double val = double.parse(m.group(1)!);
                String unit = m.group(2)!.toLowerCase();

                if (unit == 'g' || unit == 'ml' || unit == 'cl') {
                  if (unit == 'cl') val *= 10;
                  detectedWeightKg = val / 1000.0;
                } else {
                  detectedWeightKg = val;
                }

                ocrWeightFound = true;
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
        debugPrint("OpenFoodFacts DB Fetch Error: $e");
        _emitUpdate(62, "4. Cloud API", "Cloud server busy. Proceeding with local data.");
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      String weightDisplay = ocrWeightFound ? "${(detectedWeightKg * 1000).toStringAsFixed(0)}g" : "Not Found";
      String extText = "W: $weightDisplay | B: $detectedBrand";

      _emitUpdate(65, "4. Data Extraction", extText);
      if (_isCancelled) throw Exception("cancelled_by_user");

      // STEP 3: Volumetric Failsafe (AR Removed)
      if (!ocrWeightFound) {
        detectedWeightKg = await _estimateWeightVolumetrically(currentDetectedClass);
        _emitUpdate(80, "5. Volumetric Scaling", "Estimated mass: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");
      } else {
        _emitUpdate(70, "5. Volumetric Scaling", "Bypassing Volume Math: Exact weight found.");
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      // =======================================================================
      // STEP 4: AI Cross-Validation (Robust Dictionaries)
      // =======================================================================
      _emitUpdate(85, "6. Multi-Modal Validation", "Matching YOLO vision with text context...");
      await Future.delayed(const Duration(milliseconds: 800));

      bool isContradiction = false;
      String mismatchReason = "";

      // Robust keyword dictionaries to catch YOLO hallucinations
      final List<String> cleaningTerms = ['shampoo', 'soap', 'cleaner', 'detergent', 'wash', 'dish', 'laundry', 'surface', 'toilet', 'bleach', 'disinfectant'];
      final List<String> personalCareTerms = ['shampoo', 'lotion', 'hair', 'skin', 'body', 'face', 'toothpaste', 'deodorant', 'conditioner', 'cream'];
      final List<String> drinkTerms = ['drink', 'juice', 'beverage', 'soda', 'cola', 'water', 'tea', 'coffee', 'beer', 'wine', 'liquid', 'drinkable'];
      final List<String> foodTerms = ['tuna', 'meat', 'fish', 'beans', 'soup', 'tomato', 'corn', 'beef', 'pork', 'chicken', 'fruit', 'vegetable', 'meal', 'sauce', 'sardines', 'mackerel'];

      bool containsAny(String text, List<String> keywords) {
        return keywords.any((k) => text.contains(k));
      }

      if (currentDetectedClass == "can_drink" || currentDetectedClass == "plastic-bottle") {
        if (containsAny(ocrText, foodTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Beverage, but OCR found solid food terms (e.g., meat/tuna/beans).";
        } else if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Beverage, but OCR found cleaning or personal care terms.";
        }
      } else if (currentDetectedClass == "can_food") {
        if (containsAny(ocrText, drinkTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Canned Food, but OCR found beverage terms.";
        } else if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Canned Food, but OCR found cleaning or personal care terms.";
        }
      } else if (currentDetectedClass == "cleaning_product" || currentDetectedClass == "personal_care") {
        if (containsAny(ocrText, drinkTerms) || containsAny(ocrText, foodTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Non-Food product, but OCR found food or drink terms.";
        }
      } else if (currentDetectedClass == "cooking_oil_bottle") {
        if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Cooking Oil, but OCR found cleaning or personal care terms.";
        }
      } else if (currentDetectedClass == "instant_noodles" || currentDetectedClass == "snack_pack") {
        if (containsAny(ocrText, cleaningTerms) || containsAny(ocrText, personalCareTerms) || containsAny(ocrText, drinkTerms)) {
          isContradiction = true;
          mismatchReason = "Detected Snack/Noodles, but OCR found unrelated non-food or drink terms.";
        }
      }

      if (isContradiction) {
        _emitUpdate(90, "6. Multi-Modal Validation", "Contradiction found! $mismatchReason");
        await Future.delayed(const Duration(milliseconds: 2000));
        throw Exception("Cross-validation failed. $mismatchReason Please re-scan.");
      }

      _emitUpdate(90, "6. Multi-Modal Validation", "Data verified. No contradictions found.");
      if (_isCancelled) throw Exception("cancelled_by_user");

      // =======================================================================
      // STEP 5: GRU Carbon Estimation
      // =======================================================================
      _emitUpdate(95, "7. GRU Carbon Estimation", "Feeding validated sequence to RNN...");

      // Model uses YOLO class exclusively
      double? finalFootprint = await _estimateCarbonFootprint(currentDetectedClass, detectedWeightKg);

      if (finalFootprint == null || finalFootprint.isNaN || finalFootprint <= 0) {
        finalFootprint = 1.25;
      }

      _emitUpdate(100, "Sequence Complete", "Estimated Footprint: ${finalFootprint.toStringAsFixed(2)} kg CO2e");

      if (!mounted || _isCancelled) return;
      if (_isDialogShowing) {
        Navigator.pop(context, 'system_transition');
        _isDialogShowing = false;
      }
      setState(() {
        _yoloCategory = currentDetectedClass;
        _detectedClass = uiItemName; // Use pretty name for UI
        _carbonFootprint = finalFootprint!;
      });
      _showSuccessPopup(finalImagePath);

    } catch (e) {
      if (e.toString().contains("cancelled_by_user") || e.toString().contains("Cross-validation failed")) {
        debugPrint("Pipeline aborted: $e");

        // Critical: Force UI reset when the user explicitly cancels from any dialog
        if (mounted) {
          setState(() {
            _isDialogShowing = false;
            _useNativeYoloView = true;
            _capturedImagePath = null;
            _streakCount = 0;
            _missedFrames = 0;
            _currentStreakClass = "";
            _currentStreakConf = 0.0;
            // DO NOT reset _isAnalyzing to false instantly! We need a cooldown.
          });
          // Safety Cooldown: Keep buttons locked for 2.5s to prevent SIGSEGV from rapid unmounting!
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) setState(() => _isAnalyzing = false);
          });
        }

        // If it was an AI contradiction, show the failure popup so the user knows *why* it stopped
        if (e.toString().contains("Cross-validation failed")) {
          _showFailurePopup(customMessage: e.toString().replaceAll("Exception: ", ""));
        }

        return;
      }

      debugPrint("Pipeline Error: $e");
      if (!mounted) return;
      if (_isDialogShowing) {
        Navigator.pop(context, 'system_transition');
        _isDialogShowing = false;
      }
      _showFailurePopup();
    } finally {
      // NOTE: _isAnalyzing cooldown takes priority if cancelled_by_user is triggered.
      if (mounted && !_isCancelled) setState(() => _isAnalyzing = false);
      _pipelineController?.close();
    }
  }

  void _showSuccessPopup(String imagePath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SuccessPopup(
        imagePath: imagePath,
        category: _getCategory(),
        itemName: _detectedClass, // Displays beautiful OFF name
        carbonFootprint: _carbonFootprint,
        onAdd: () async {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.addCarbonFootprint(_carbonFootprint, _getCategory().toLowerCase());
          if (mounted) {
            Navigator.pop(context);
            setState(() {
              _isDialogShowing = false;
              _useNativeYoloView = true; // Restore Native Stream
              _capturedImagePath = null;
              _streakCount = 0;
              _missedFrames = 0;
              _currentStreakClass = "";
              _currentStreakConf = 0.0;
              _isAnalyzing = true; // Engage Safety Cooldown
            });
            Future.delayed(const Duration(milliseconds: 2500), () {
              if (mounted) setState(() => _isAnalyzing = false);
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Impact successfully added!"),
                backgroundColor: Color(0xFF2D3E50),
              ),
            );
          }
        },
        onRetry: () {
          Navigator.pop(context);
          setState(() {
            _isDialogShowing = false;
            _useNativeYoloView = true; // Restore Native Stream
            _capturedImagePath = null;
            _streakCount = 0;
            _missedFrames = 0;
            _currentStreakClass = "";
            _currentStreakConf = 0.0;
            _isAnalyzing = true; // Engage Safety Cooldown
          });
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) setState(() => _isAnalyzing = false);
          });
        },
      ),
    );
  }

  void _showFailurePopup({String? customMessage}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FailurePopup(
        message: customMessage ?? "We couldn't identify this item. Please ensure it's within the frame and has good lighting.",
        onRetry: () {
          Navigator.pop(context);
          setState(() {
            _isDialogShowing = false;
            _useNativeYoloView = true; // Restore Native Stream
            _capturedImagePath = null;
            _streakCount = 0;
            _missedFrames = 0;
            _currentStreakClass = "";
            _currentStreakConf = 0.0;
            _isAnalyzing = true; // Engage Safety Cooldown
          });
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) setState(() => _isAnalyzing = false);
          });
        },
      ),
    );
  }

  String _getCategory() {
    String name = _yoloCategory.toUpperCase(); // Rely on YOLO logic, not UI name
    if (name.contains('DRINK') || name.contains('FOOD') || name.contains('NOODLE') || name.contains('RICE') || name.contains('SNACK')) {
      return 'Food & Drink';
    }
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
          // THE HYBRID CAMERA RENDERER
          Positioned.fill(
            child: _isInitialized && _yoloPlugin != null
                ? (_useNativeYoloView
            // Native YOLOView handles its own live streaming and bounding boxes
                ? YOLOView(
              modelPath: '${Directory.systemTemp.path}/yolo_f16_live.tflite', // Specific file for LIVE FEED
              task: YOLOTask.detect,
              onResult: (results) {

                // 1. FRAME THROTTLING (The Thermal Fix)
                // Limit Dart-side processing to ~6 FPS to prevent CPU overheating on budget phones.
                int currentTime = DateTime.now().millisecondsSinceEpoch;
                if (currentTime - _lastYoloFrameTime < 150) return;
                _lastYoloFrameTime = currentTime;

                if (results.isEmpty) {
                  // FORGIVENESS BUFFER: Forgive up to 2 empty/bad frames before breaking streak
                  if (_streakCount > 0 && _missedFrames < 2) {
                    _missedFrames++;
                  } else {
                    if (mounted) {
                      setState(() {
                        _streakCount = 0;
                        _currentStreakClass = "";
                        _currentStreakConf = 0.0;
                        _missedFrames = 0;
                      });
                    }
                  }
                  return;
                }

                double bestConf = 0.0;
                String bestLabel = "";

                // Safely extract the best prediction without type errors
                for (var res in results) {
                  dynamic dynamicRes = res;

                  double conf = 0.0;
                  try { conf = dynamicRes.confidence?.toDouble() ?? 0.0; } catch (_) {}
                  if (conf == 0.0) {
                    try { conf = dynamicRes.score?.toDouble() ?? 0.0; } catch (_) {}
                  }

                  String label = "";
                  try { label = dynamicRes.className?.toString() ?? ""; } catch (_) {}
                  if (label.isEmpty) {
                    try { label = dynamicRes.name?.toString() ?? ""; } catch (_) {}
                  }
                  if (label.isEmpty) {
                    try { label = dynamicRes.label?.toString() ?? ""; } catch (_) {}
                  }

                  if (conf > bestConf && label.isNotEmpty) {
                    bestConf = conf;
                    bestLabel = label;
                  }
                }

                // 2. DYNAMIC CONFIDENCE FILTERING
                double requiredThreshold = 0.545; // Default safe threshold
                if (bestLabel == "instant_noodles" || bestLabel == "snack_pack") {
                  requiredThreshold = 0.75; // Ghost heavily, need higher confidence
                } else if (bestLabel == "cleaning_product" || bestLabel == "personal_care") {
                  requiredThreshold = 0.65;
                } else if (bestLabel == "can_drink" || bestLabel == "plastic-bottle") {
                  requiredThreshold = 0.545; // Stable, trust the F1-curve
                } else {
                  requiredThreshold = 0.60; // General baseline
                }

                if (bestConf >= requiredThreshold) {
                  // 3. TEMPORAL SMOOTHING (The Streak Filter with Forgiveness Buffer)
                  if (bestLabel == _currentStreakClass) {
                    _streakCount++;
                    _missedFrames = 0; // Reset forgiveness buffer on a good match
                  } else {
                    // Different object detected. Should we forgive it?
                    if (_streakCount > 0 && _missedFrames < 2) {
                      _missedFrames++; // Forgive up to 2 bad frames
                    } else {
                      // Forgiveness exceeded or no streak yet, switch to new object
                      _currentStreakClass = bestLabel;
                      _streakCount = 1;
                      _missedFrames = 0;
                    }
                  }

                  // Force UI to show the real-time tracking Pill
                  if (mounted) {
                    setState(() {
                      _currentStreakConf = bestConf;
                    });
                  }

                  // Require exactly 4 consecutive frames (approx. ~0.6s at 6fps) of the SAME object
                  if (_streakCount >= 4) {
                    _liveDetectedClass = _currentStreakClass;
                    _liveDetectedConf = bestConf;
                    _lastDetectionTime = DateTime.now();
                  }
                } else {
                  // If confidence drops below threshold (e.g. blurry frame), use forgiveness buffer
                  if (_streakCount > 0 && _missedFrames < 2) {
                    _missedFrames++;
                  } else {
                    // Instantly break the streak
                    if (mounted) {
                      setState(() {
                        _streakCount = 0;
                        _currentStreakClass = "";
                        _currentStreakConf = 0.0;
                        _missedFrames = 0;
                      });
                    }
                  }
                }
              },
            )
            // 2. Freezes frame perfectly when camera stops during dialogs
                : (_capturedImagePath != null
                ? Image.file(File(_capturedImagePath!), fit: BoxFit.cover)
                : const Center(child: CircularProgressIndicator(color: brandGreen))))
                : const Center(child: CircularProgressIndicator(color: brandGreen)),
          ),

          // ==========================================
          // LIVE TARGETING UI PILL
          // ==========================================
          if (!_isDialogShowing && _useNativeYoloView && _currentStreakClass.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 90,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: _streakCount >= 4
                          ? brandGreen.withValues(alpha: 0.95)
                          : brandNavy.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _streakCount >= 4 ? brandNavy : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _streakCount >= 4 ? Icons.check_circle_rounded : Icons.sync_rounded,
                        color: _streakCount >= 4 ? brandNavy : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentStreakClass.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: _streakCount >= 4 ? brandNavy : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _streakCount >= 4 ? brandNavy.withValues(alpha: 0.1) : brandGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${(_currentStreakConf * 100).toStringAsFixed(0)}%",
                          style: TextStyle(
                            color: _streakCount >= 4 ? brandNavy : brandGreen,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 16,
                    bottom: 20,
                    left: 24,
                    right: 24,
                  ),
                  color: brandNavy.withValues(alpha: 0.4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      ),
                      const Text(
                        "Carbon Scanner",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          // Bypass YOLO native constraints to force Hardware LED on
                          try {
                            if (_isFlashOn) {
                              await TorchLight.disableTorch();
                              setState(() => _isFlashOn = false);
                            } else {
                              await TorchLight.enableTorch();
                              setState(() => _isFlashOn = true);
                            }
                          } catch (e) {
                            debugPrint("Torch error: $e");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Flash not supported on this device.")),
                              );
                            }
                          }
                        },
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _isFlashOn ? brandGreen : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (!_isDialogShowing)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    // Prevent tapping while a pipeline is already running/starting
                    onTap: _isAnalyzing ? null : () => _runPipeline(),
                    child: Container(
                      height: 84,
                      width: 84,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: brandGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _isAnalyzing
                              ? const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(color: brandNavy, strokeWidth: 3),
                          )
                              : const FaIcon(FontAwesomeIcons.camera, color: brandNavy, size: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    // Prevent tapping while a pipeline is already running/starting
                    onPressed: _isAnalyzing ? null : () async {
                      final XFile? image = await _picker.pickImage(
                        source: ImageSource.gallery,
                        // Optimization 3: Hardware pre-scaling for uploaded images
                        // Compresses the image using native Android hardware before Dart ever sees it!
                        maxWidth: 1080,
                        maxHeight: 1080,
                        imageQuality: 85,
                      );
                      if (image != null) {
                        _runPipeline(preSelectedImage: image);
                      }
                    },
                    child: const Text(
                      "UPLOAD IMAGE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
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
// OCR VERIFICATION DIALOG
// ============================================================================
class _OcrVerificationDialog extends StatefulWidget {
  final String imagePath;
  final List<TextBlock> textBlocks;
  final String initialQuery;
  final double initialWeight;
  final bool weightFound;

  const _OcrVerificationDialog({
    required this.imagePath,
    required this.textBlocks,
    required this.initialQuery,
    required this.initialWeight,
    required this.weightFound,
  });

  @override
  State<_OcrVerificationDialog> createState() => _OcrVerificationDialogState();
}

class _OcrVerificationDialogState extends State<_OcrVerificationDialog> {
  late TextEditingController _queryController;
  late TextEditingController _weightController;
  final FocusNode _queryFocus = FocusNode();
  final FocusNode _weightFocus = FocusNode();

  final Color brandNavy = const Color(0xFF2D3E50);
  final Color brandGreen = const Color(0xFFC8FFB0);

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _weightController = TextEditingController(
        text: widget.weightFound ? (widget.initialWeight * 1000).toStringAsFixed(0) : "");
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
      _weightController.text = text;
      _weightController.selection = TextSelection.collapsed(offset: _weightController.text.length);
    } else {
      // Default to adding to query
      final currentText = _queryController.text.trim();
      _queryController.text = currentText.isEmpty ? text : "$currentText $text";
      _queryController.selection = TextSelection.collapsed(offset: _queryController.text.length);
      if (!_queryFocus.hasFocus) {
        FocusScope.of(context).requestFocus(_queryFocus);
      }
    }
  }

  void _submit() {
    double parsedWeight = double.tryParse(_weightController.text) ?? 0.0;
    double finalWeightKg = parsedWeight > 0 ? (parsedWeight / 1000.0) : widget.initialWeight;

    Navigator.pop(context, {
      'query': _queryController.text.trim(),
      'weight': finalWeightKg,
      'weightFound': _weightController.text.trim().isNotEmpty,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Verify Scanned Text",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2D3E50),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Tap the extracted text chips below to build your search query, or type manually.",
                      style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    // Chips container
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.textBlocks.map((block) {
                            String text = block.text.replaceAll('\n', ' ').trim();
                            return ActionChip(
                              label: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              backgroundColor: Colors.white,
                              side: BorderSide(color: brandGreen, width: 1.5),
                              onPressed: () => _onChipTapped(text),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Inputs
                    TextField(
                      controller: _queryController,
                      focusNode: _queryFocus,
                      decoration: InputDecoration(
                        labelText: "Search Query (Brand/Item)",
                        labelStyle: TextStyle(color: brandNavy.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                        filled: true,
                        fillColor: brandNavy.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandGreen, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _weightController,
                      focusNode: _weightFocus,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Weight (in Grams or mL)",
                        labelStyle: TextStyle(color: brandNavy.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                        filled: true,
                        fillColor: brandNavy.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandGreen, width: 2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandNavy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
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
// ============================================================================


class _ProcessingDialog extends StatefulWidget {
  final Stream<PipelineUpdate> updateStream;
  final List<PipelineUpdate> initialLogs;
  final int initialProgress;
  final Function(bool) onCancel; // FIX D: Supports Android system back button

  const _ProcessingDialog({
    required this.updateStream,
    this.initialLogs = const [],
    this.initialProgress = 0,
    required this.onCancel,
  });

  @override
  State<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<_ProcessingDialog> {
  int _currentProgress = 0;
  final List<PipelineUpdate> _logs = [];
  late StreamSubscription<PipelineUpdate> _subscription;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.initialProgress;
    _logs.addAll(widget.initialLogs);

    _subscription = widget.updateStream.listen((update) {
      if (mounted) {
        setState(() {
          _currentProgress = update.progress;
          _logs.insert(0, update);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // ONLY trigger cancellation if it was a true user interaction (back button),
        // NOT a programmed system pop transition!
        if (didPop && result != 'system_transition') {
          widget.onCancel(true);
        }
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          height: 520,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(32),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "ANALYZING",
                        style: TextStyle(
                          color: brandNavy.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$_currentProgress%",
                        style: const TextStyle(
                          color: brandNavy,
                          fontSize: 56,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: _currentProgress / 100,
                      color: brandGreen,
                      backgroundColor: brandNavy.withValues(alpha: 0.1),
                      strokeWidth: 6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final bool isLatest = index == 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isLatest ? brandGreen : brandNavy.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log.step,
                                  style: TextStyle(
                                    color: isLatest ? brandNavy : brandNavy.withValues(alpha: 0.4),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  log.detail,
                                  style: TextStyle(
                                    color: isLatest ? brandNavy.withValues(alpha: 0.8) : brandNavy.withValues(alpha: 0.3),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => widget.onCancel(false), // false = manually cancelled via UI
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                  ),
                  child: const Text(
                    "CANCEL PROCESS",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessPopup extends StatelessWidget {
  final String imagePath;
  final String category;
  final String itemName;
  final double carbonFootprint;
  final VoidCallback onAdd;
  final VoidCallback onRetry;

  const _SuccessPopup({
    required this.imagePath,
    required this.category,
    required this.itemName,
    required this.carbonFootprint,
    required this.onAdd,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.toUpperCase(),
                              style: TextStyle(
                                color: brandNavy.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              itemName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: brandNavy,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: brandGreen.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const FaIcon(FontAwesomeIcons.leaf, color: brandNavy, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: brandNavy.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "ESTIMATED FOOTPRINT",
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: carbonFootprint.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: brandNavy,
                                  fontSize: 52,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const TextSpan(
                                text: " kg CO2e",
                                style: TextStyle(
                                  color: brandNavy,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text("RETRY", style: TextStyle(color: brandNavy, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onAdd,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text("ADD IMPACT", style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
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
  final VoidCallback onRetry;
  final String message;

  const _FailurePopup({
    required this.onRetry,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              "Not Recognized",
              style: TextStyle(
                color: brandNavy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xB32D3E50),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: brandNavy,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    "TRY AGAIN",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
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
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brandGreen.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lightbulb_outline_rounded, color: brandNavy, size: 32),
            ),
            const SizedBox(height: 24),
            const Text(
              "Optimal Detection",
              style: TextStyle(
                color: brandNavy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "For optimal detection, have sufficient lighting, avoid blurry photos, and use the front of the packaging.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xB32D3E50),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _doNotShowAgain,
                    onChanged: (value) {
                      setState(() {
                        _doNotShowAgain = value ?? false;
                      });
                    },
                    activeColor: brandNavy,
                    checkColor: brandGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _doNotShowAgain = !_doNotShowAgain;
                    });
                  },
                  child: const Text(
                    "Don't show again",
                    style: TextStyle(
                      color: brandNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () async {
                if (_doNotShowAgain) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('show_scanner_instructions', false);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: brandNavy,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    "GOT IT",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PRODUCT SELECTION DIALOG
// ============================================================================
class _ProductSelectionDialog extends StatefulWidget {
  final List<Product> products;

  const _ProductSelectionDialog({required this.products});

  @override
  State<_ProductSelectionDialog> createState() => _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  int _currentPage = 0;
  static const int _itemsPerPage = 3;

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);

    final int totalPages = (widget.products.length / _itemsPerPage).ceil();
    final List<Product> displayedProducts = widget.products
        .skip(_currentPage * _itemsPerPage)
        .take(_itemsPerPage)
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Select Product",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Please select the correct item from the database, or skip if it's not listed:",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: displayedProducts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = displayedProducts[index];
                  final name = p.productName != null && p.productName!.isNotEmpty ? p.productName! : "Unknown Product";
                  final brand = p.brands != null && p.brands!.isNotEmpty ? p.brands! : "Unknown Brand";
                  final quantity = p.quantity != null && p.quantity!.isNotEmpty ? p.quantity! : "Unknown Qty";

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: p.imageFrontSmallUrl != null
                          ? Image.network(
                        p.imageFrontSmallUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          width: 48, height: 48, color: Colors.grey[200],
                          child: const Icon(Icons.shopping_bag, color: Colors.grey),
                        ),
                      )
                          : Container(
                        width: 48, height: 48, color: Colors.grey[200],
                        child: const Icon(Icons.shopping_bag, color: Colors.grey),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: brandNavy),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "$brand • $quantity",
                        style: const TextStyle(fontSize: 12, color: brandNavy, fontWeight: FontWeight.w600),
                      ),
                    ),
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
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                    color: _currentPage > 0 ? brandNavy : Colors.grey,
                    onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                  ),
                  Text(
                    "Page ${_currentPage + 1} of $totalPages",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brandNavy),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    color: _currentPage < totalPages - 1 ? brandNavy : Colors.grey,
                    onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, 'cancel'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                    child: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'skip'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("SKIP", style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}