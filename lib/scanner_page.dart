import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'; // NEW: For compute() isolate threading
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'package:image_picker/image_picker.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/yolo.dart';

import 'user_provider.dart';

// =========================================================================
// BACKGROUND IMAGE PROCESSOR (Prevents UI Freezing & Fixes Aspect Ratio)
// =========================================================================
Future<Uint8List> prepareYoloImage(String path) async {
  final bytes = await File(path).readAsBytes();
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // 1. Bake the Android sensor orientation
  decoded = img.bakeOrientation(decoded);

  // 2. Force Portrait orientation if the sensor captured it sideways
  if (decoded.width > decoded.height) {
    decoded = img.copyRotate(decoded, angle: 90);
  }

  // 3. TRUE LETTERBOXING
  // Create a square canvas matching the longest side
  int maxSize = decoded.width > decoded.height ? decoded.width : decoded.height;
  img.Image squareImage = img.Image(width: maxSize, height: maxSize);

  // Fill the empty space with neutral grey (YOLO standard padding: 114, 114, 114)
  img.fill(squareImage, color: img.ColorRgb8(114, 114, 114));

  // Center the actual image inside the square
  int xOffset = (maxSize - decoded.width) ~/ 2;
  int yOffset = (maxSize - decoded.height) ~/ 2;
  img.compositeImage(squareImage, decoded, dstX: xOffset, dstY: yOffset);

  // Compress slightly to speed up C++ parsing
  return img.encodeJpg(squareImage, quality: 85);
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
  static const platform = MethodChannel('co2minus.app/ar_depth');

  CameraController? _controller;
  bool _isFlashOn = false;
  bool _isInitialized = false;

  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _picker = ImagePicker();
  bool _isCancelled = false;

  Interpreter? _gruInterpreter;
  Map<String, dynamic>? _lcaDatabase;
  Map<String, dynamic>? _scalerConfig;
  YOLO? _yoloPlugin;

  String _diagnosticMessage = "Initializing systems...";

  bool _isDialogShowing = false;
  bool _isAnalyzing = false;
  String _detectedClass = "";
  double _carbonFootprint = 0.0;

  StreamController<PipelineUpdate>? _pipelineController;
  final List<PipelineUpdate> _pipelineHistory = [];
  int _currentPipelineProgress = 0;

  @override
  void initState() {
    super.initState();
    // Protect against OpenFoodFacts 503 rate-limiting by providing a valid agent
    OpenFoodAPIConfiguration.userAgent = UserAgent(name: 'CO2Minus_App', url: 'https://github.com/abvlnt');

    _initializeSystem().then((_) {
      if (mounted) {
        _checkShowInstructions();
      }
    });
  }

  Future<void> _initializeSystem() async {
    String diag = "";
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first,
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
        await _controller!.initialize();
        diag += "✅ Camera Lens\n";
        if (mounted) setState(() => _isInitialized = true);
      } else {
        diag += "❌ Camera Lens (Not Found)\n";
      }

      try {
        final lcaString = await rootBundle.loadString('assets/flutter_lca_database.json');
        _lcaDatabase = json.decode(lcaString);
        diag += "✅ LCA Database\n";

        final scalerString = await rootBundle.loadString('assets/flutter_scaler_config.json');
        _scalerConfig = json.decode(scalerString);
        diag += "✅ Scaler Config\n";
      } catch (e) {
        diag += "❌ JSON Databases Error: $e\n";
      }

      try {
        final byteData = await rootBundle.load('assets/models/yolo.tflite');
        final file = File('${Directory.systemTemp.path}/yolo.tflite');
        await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

        _yoloPlugin = YOLO(
          modelPath: file.path,
          task: YOLOTask.detect,
        );
        await _yoloPlugin!.loadModel();
        diag += "✅ YOLO26 Vision Model\n";
      } catch (e) {
        diag += "❌ YOLO26 Model Error: $e\n";
      }

      try {
        _gruInterpreter = await Interpreter.fromAsset('assets/models/gru.tflite');
        diag += "✅ GRU Estimation Model\n";
      } catch (e) {
        diag += "❌ GRU Model Error: $e\n";
      }

    } catch (e) {
      diag += "\nCritical System Error: $e";
    }

    if (mounted) {
      setState(() {
        _diagnosticMessage = diag;
      });
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint("Camera Error: $e");
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

    if (mounted) {
      _showDiagnosticDialog();
    }
  }

  void _showDiagnosticDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF2D3E50), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  "SYSTEM DIAGNOSTICS",
                  style: TextStyle(color: Color(0xFF2D3E50), fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _diagnosticMessage,
                style: const TextStyle(color: Color(0xFF2D3E50), fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D3E50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("PROCEED", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _emitUpdate(int progress, String step, String detail) {
    final update = PipelineUpdate(progress, step, detail);
    _pipelineHistory.insert(0, update);
    _currentPipelineProgress = progress;

    if (_pipelineController != null && !_pipelineController!.isClosed) {
      _pipelineController!.add(update);
    }
  }

  void _cancelPipeline() {
    _isCancelled = true;
    if (_isDialogShowing) {
      Navigator.pop(context);
      _isDialogShowing = false;
    }
    setState(() {
      _isAnalyzing = false;
    });
  }

  // --- YOLO26 ULTRALYTICS INFERENCE WITH BACKGROUND LETTERBOXING ---
  Future<String?> _runYoloInference(String imagePath) async {
    if (_yoloPlugin == null) return null;

    try {
      // Offload to background isolate to prevent UI freezing
      final Uint8List fixedBytes = await compute(prepareYoloImage, imagePath);

      final resultsMap = await _yoloPlugin!.predict(
        fixedBytes,
        confidenceThreshold: 0.15,
      );

      if (resultsMap.isNotEmpty) {
        double bestConf = 0.0;
        String bestLabel = "";

        resultsMap.forEach((key, value) {
          if (value is List) {
            for (var item in value) {
              if (item is Map) {
                double conf = (item['confidence'] ?? item['score'] ?? 0.0).toDouble();
                String label = (item['className'] ?? item['label'] ?? item['class'] ?? "").toString();

                if (conf > bestConf && label.isNotEmpty) {
                  bestConf = conf;
                  bestLabel = label;
                }
              }
            }
          }
        });

        if (bestLabel.isNotEmpty) {
          debugPrint("🎯 Corrected Match: $bestLabel | ${(bestConf * 100).toStringAsFixed(1)}%");
          return bestLabel;
        }
      }
      return null;
    } catch (e) {
      debugPrint("YOLO26 Inference Error: $e");
      return null;
    }
  }

  // --- INTEGRATED GRU ESTIMATOR ---
  Future<double?> _estimateCarbonFootprint(String yoloClass, double weightKg) async {
    if (_gruInterpreter == null || _lcaDatabase == null || _scalerConfig == null) {
      return null;
    }

    if (!_lcaDatabase!.containsKey(yoloClass)) {
      return null;
    }

    try {
      List<dynamic> baseLca = _lcaDatabase![yoloClass];
      List<double> actualLca = baseLca.map((val) => (val as double) * weightKg).toList();

      List<dynamic> scaleVals = _scalerConfig!['scale_vals'];
      List<dynamic> minOffsets = _scalerConfig!['min_offsets'];

      List<double> scaledLca = [];
      for (int i = 0; i < actualLca.length; i++) {
        double scaledValue = (actualLca[i] * scaleVals[i]) + minOffsets[i];
        scaledLca.add(scaledValue);
      }

      var inputTensor = [
        scaledLca.map((val) => [val]).toList()
      ];

      var outputTensor = List.filled(1 * 1, 0.0).reshape([1, 1]);

      _gruInterpreter!.run(inputTensor, outputTensor);

      double finalCarbonFootprint = outputTensor[0][0];

      if (finalCarbonFootprint.isNaN) {
        return null;
      }

      return finalCarbonFootprint;

    } catch (e) {
      debugPrint("GRU Inference failed dynamically: $e");
      return null;
    }
  }

  // --- AUTOMATED TRUE DEPTH SCALING ---
  Future<double> _estimateWeightViaAR(String detectedClass) async {
    double depthToItemCm = 30.0;

    _emitUpdate(65, "3. True Depth (AR)", "⚠️ PLEASE HOLD DEVICE PERFECTLY STILL ⚠️");
    await Future.delayed(const Duration(milliseconds: 1500));
    if (_isCancelled) throw Exception("cancelled_by_user");

    _emitUpdate(70, "3. True Depth (AR)", "Activating Auto-Laser...");
    await Future.delayed(const Duration(milliseconds: 400));

    await _controller?.dispose();
    _controller = null;

    if (mounted && _isDialogShowing) {
      Navigator.pop(context);
      _isDialogShowing = false;
    }

    try {
      final double? result = await platform.invokeMethod('measureDepth');

      if (result != null && result > 0) {
        depthToItemCm = result;
        _emitUpdate(75, "3. True Depth (AR)", "Auto-laser hit! Depth locked at ${depthToItemCm.toStringAsFixed(1)} cm");
      } else {
        _emitUpdate(75, "3. True Depth (AR)", "Laser failed. Using 30cm baseline.");
      }
    } catch (e) {
      debugPrint("Native AR Missing Plugin Error: $e");
      _emitUpdate(75, "3. True Depth (AR)", "AR Module bypassed. Using 30cm baseline.");
    }

    if (mounted) {
      setState(() => _isInitialized = false);
      await _initializeCamera();
    }

    // After AR returns, show the dialog again if the user didn't abort it before AR launched
    if (mounted && !_isDialogShowing && !_isCancelled) {
      _isDialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProcessingDialog(
          updateStream: _pipelineController!.stream,
          initialLogs: _pipelineHistory,
          initialProgress: _currentPipelineProgress,
          onCancel: _cancelPipeline,
        ),
      );
    }

    // Exact Volumetric Scaling
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

    double depthScaleFactor = depthToItemCm / 30.0;
    widthCm *= depthScaleFactor; heightCm *= depthScaleFactor; depthCm *= depthScaleFactor;

    double volumeCm3 = widthCm * heightCm * depthCm;
    double weightGrams = volumeCm3 * densityGCm3;

    return weightGrams / 1000.0;
  }

  Future<void> _debugPause(String stepName, String details) async {
    if (!mounted || _isCancelled) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFC8FFB0), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bug_report_rounded, color: Color(0xFF2D3E50), size: 32),
              const SizedBox(height: 16),
              Text(
                "DEBUG: $stepName",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF2D3E50), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.0),
              ),
              const SizedBox(height: 12),
              Text(
                details,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF2D3E50), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D3E50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CONFIRM & CONTINUE", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runPipeline({XFile? preSelectedImage}) async {
    if (_isDialogShowing || _isAnalyzing) return;
    if (preSelectedImage == null && !_isInitialized) return;

    setState(() {
      _isAnalyzing = true;
      _isDialogShowing = true;
      _isCancelled = false;
    });

    _pipelineHistory.clear();
    _currentPipelineProgress = 0;
    _pipelineController = StreamController<PipelineUpdate>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ProcessingDialog(
        updateStream: _pipelineController!.stream,
        initialLogs: _pipelineHistory,
        initialProgress: _currentPipelineProgress,
        onCancel: _cancelPipeline,
      ),
    );

    try {
      XFile? finalImage;
      String currentDetectedClass = "";
      bool isObjectDetected = false;

      // STEP 1: Image Sourcing & YOLO Passes
      if (preSelectedImage != null) {
        _emitUpdate(5, "1. Image Upload", "Analyzing uploaded image...");
        finalImage = preSelectedImage;
        await Future.delayed(const Duration(milliseconds: 500));
        if (_isCancelled) throw Exception("cancelled_by_user");

        String? yoloResult = await _runYoloInference(finalImage.path);
        if (yoloResult != null) {
          isObjectDetected = true;
          currentDetectedClass = yoloResult;
        }
      } else {
        _emitUpdate(5, "1. Trigger & Identification", "Initiating 5-frame rapid capture...");

        List<XFile> capturedFrames = [];
        for (int i = 0; i < 5; i++) {
          if (_isCancelled) throw Exception("cancelled_by_user");
          capturedFrames.add(await _controller!.takePicture());
          await Future.delayed(const Duration(milliseconds: 150));
        }

        await _debugPause("Capture Initiation", "Successfully captured 5 frames in sequence for analysis.");
        if (_isCancelled) throw Exception("cancelled_by_user");

        for (int i = 0; i < 5; i++) {
          if (_isCancelled) throw Exception("cancelled_by_user");
          _emitUpdate(10 + (i * 6), "1. Vision Model (YOLO26)", "Pass ${i + 1}: Analyzing geometry...");
          finalImage = capturedFrames[i];

          String? yoloResult = await _runYoloInference(finalImage.path);

          if (yoloResult != null) {
            isObjectDetected = true;
            currentDetectedClass = yoloResult;
            break;
          }
        }
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      if (!isObjectDetected || currentDetectedClass.isEmpty) {
        _emitUpdate(40, "1. Vision Model (YOLO26)", "Detection failed. No object found.");
        throw Exception("YOLO Object Detection Failed.");
      }

      _emitUpdate(40, "1. Vision Model (YOLO26)", "Classification Confirmed: $currentDetectedClass");
      if (finalImage == null) throw Exception("Failed to capture image");

      await _debugPause("Step 1 Complete", "Final YOLO26 Classification Selected: $currentDetectedClass");
      if (_isCancelled) throw Exception("cancelled_by_user");

      // STEP 2: OCR Data Extraction
      _emitUpdate(50, "2. Data Extraction (OCR)", "Scanning packaging for weight & labels...");
      final InputImage inputImage = InputImage.fromFilePath(finalImage.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      String ocrText = recognizedText.text.replaceAll('\n', ' ').toLowerCase();

      // =========================================================================
      // DYNAMIC OCR UPGRADE: Sort text physically and grab the top 5 largest blocks
      // =========================================================================
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

      // Grab top 5 words (Usually Brand + Flavor + Style)
      String ocrSearchContext = prominentText.take(5).join(' ');
      String detectedBrand = prominentText.isNotEmpty ? prominentText.first.toUpperCase() : "Unknown";
      // =========================================================================

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

      // STEP 2.5: OPEN FOOD FACTS CLOUD API FALLBACK
      if (!ocrWeightFound) {
        _emitUpdate(58, "2. Cloud API Fallback", "Local OCR failed. Querying OpenFacts DB...");

        // CRITICAL: Search only using OCR labels. Never append YOLO class if OCR is found!
        String searchQuery = ocrSearchContext.isNotEmpty
            ? ocrSearchContext
            : currentDetectedClass.replaceAll('_', ' ');

        try {
          ProductSearchQueryConfiguration configuration = ProductSearchQueryConfiguration(
            parametersList: <Parameter>[
              SearchTerms(terms: [searchQuery]),
            ],
            language: OpenFoodFactsLanguage.ENGLISH,
            fields: [ProductField.QUANTITY, ProductField.BRANDS],
            version: ProductQueryVersion.v3,
          );

          SearchResult result = await OpenFoodAPIClient.searchProducts(
            null,
            configuration,
          );

          if (result.products != null && result.products!.isNotEmpty) {
            for (var product in result.products!) {
              if (product.quantity != null && product.quantity!.isNotEmpty) {
                RegExp regex = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l|cl)', caseSensitive: false);
                var m = regex.firstMatch(product.quantity!);

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
                  detectedBrand = (product.brands ?? detectedBrand).toUpperCase();
                  _emitUpdate(62, "2. Cloud API (Success)", "Matched $detectedBrand: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");
                  break;
                }
              }
            }
          }
        } catch (e) {
          debugPrint("OpenFoodFacts DB Fetch Error: $e");
          _emitUpdate(62, "2. Cloud API", "Cloud server busy. Proceeding to AR.");
        }
      }

      if (_isCancelled) throw Exception("cancelled_by_user");

      String weightDisplay = ocrWeightFound ? "${(detectedWeightKg * 1000).toStringAsFixed(0)}g" : "Not Found";
      String extText = "W: $weightDisplay | B: $detectedBrand";

      _emitUpdate(65, "2. Data Extraction", extText);
      await _debugPause("Step 2 Complete", "Data Extracted:\n$extText");
      if (_isCancelled) throw Exception("cancelled_by_user");

      // STEP 3: Automated True Depth Failsafe
      if (!ocrWeightFound) {
        detectedWeightKg = await _estimateWeightViaAR(currentDetectedClass);
        _emitUpdate(80, "3. True Depth (AR)", "Estimated mass scaled by distance: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");
      } else {
        _emitUpdate(70, "3. True Depth (AR)", "Bypassing AR Laser: Exact weight found.");
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (_isCancelled) throw Exception("cancelled_by_user");
      await _debugPause("Step 3 Complete", "Volumetric calculation complete.\nFinal Assigned Mass: ${(detectedWeightKg * 1000).toStringAsFixed(0)}g");

      // STEP 4: AI Cross-Validation
      _emitUpdate(85, "4. Multi-Modal Validation", "Matching YOLO vision with text context...");
      await Future.delayed(const Duration(milliseconds: 800));

      bool isContradiction = false;
      String mismatchReason = "";

      if (currentDetectedClass.contains("drink") && (ocrText.contains("shampoo") || ocrText.contains("soap") || ocrText.contains("cleaner"))) {
        isContradiction = true; mismatchReason = "Detected Drink, but OCR read cleaning terms.";
      } else if (currentDetectedClass == "cleaning_product" && (ocrText.contains("drink") || ocrText.contains("juice") || ocrText.contains("food"))) {
        isContradiction = true; mismatchReason = "Detected Cleaner, but OCR read food/drink terms.";
      } else if (currentDetectedClass == "can_food" && (ocrText.contains("drink") || ocrText.contains("beverage") || ocrText.contains("soda"))) {
        isContradiction = true; mismatchReason = "Detected Food Can, but OCR read beverage terms.";
      } else if (currentDetectedClass == "instant_noodles" && (ocrText.contains("drink") || ocrText.contains("shampoo"))) {
        isContradiction = true; mismatchReason = "Detected Noodles, but OCR read unrelated terms.";
      }

      if (isContradiction) {
        _emitUpdate(90, "4. Multi-Modal Validation", "Contradiction found! $mismatchReason");
        await Future.delayed(const Duration(milliseconds: 2000));
        throw Exception("Cross-validation failed. $mismatchReason Please re-scan.");
      }

      _emitUpdate(90, "4. Multi-Modal Validation", "Data verified. No contradictions found.");
      if (_isCancelled) throw Exception("cancelled_by_user");

      await _debugPause("Step 4 Complete", "Multi-Modal Validation passed successfully.");
      if (_isCancelled) throw Exception("cancelled_by_user");

      // STEP 5: GRU Carbon Estimation
      _emitUpdate(95, "5. GRU Carbon Estimation", "Feeding validated sequence to RNN...");

      double? finalFootprint = await _estimateCarbonFootprint(currentDetectedClass, detectedWeightKg);

      if (finalFootprint == null || finalFootprint.isNaN || finalFootprint <= 0) {
        finalFootprint = 1.25;
      }

      _emitUpdate(100, "Sequence Complete", "Estimated Footprint: ${finalFootprint.toStringAsFixed(2)} kg CO2e");
      await _debugPause("Step 5 Complete", "GRU Network output: ${finalFootprint.toStringAsFixed(2)} kg CO2e");

      if (!mounted || _isCancelled) return;
      if (_isDialogShowing) {
        Navigator.pop(context);
      }
      setState(() {
        _detectedClass = currentDetectedClass.replaceAll('_', ' ').toUpperCase();
        _carbonFootprint = finalFootprint!;
      });
      _showSuccessPopup(finalImage.path);

    } catch (e) {
      if (e.toString().contains("cancelled_by_user")) {
        debugPrint("Pipeline gracefully aborted by user.");
        return;
      }

      debugPrint("Pipeline Error: $e");
      if (!mounted) return;
      if (_isDialogShowing) {
        Navigator.pop(context);
        _isDialogShowing = false;
      }
      _showFailurePopup();
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
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
        itemName: _detectedClass,
        carbonFootprint: _carbonFootprint,
        onAdd: () async {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.addCarbonFootprint(_carbonFootprint, _getCategory().toLowerCase());
          if (mounted) {
            Navigator.pop(context);
            setState(() => _isDialogShowing = false);
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
          setState(() => _isDialogShowing = false);
        },
      ),
    );
  }

  void _showFailurePopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FailurePopup(
        onRetry: () {
          Navigator.pop(context);
          setState(() => _isDialogShowing = false);
        },
      ),
    );
  }

  String _getCategory() {
    String name = _detectedClass.toUpperCase();
    if (name.contains('DRINK') || name.contains('FOOD') || name.contains('NOODLE') || name.contains('RICE') || name.contains('SNACK')) {
      return 'Food & Drink';
    }
    return 'Shopping';
  }

  @override
  void dispose() {
    _pipelineController?.close();
    _controller?.dispose();
    _textRecognizer.close();
    _gruInterpreter?.close();
    super.dispose();
  }

  void _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await _controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _controller!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Transform.scale(
      scale: scale,
      child: Center(
        child: CameraPreview(_controller!),
      ),
    );
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
            child: _isInitialized && _controller != null
                ? _buildCameraPreview()
                : Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: brandGreen),
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
                        onPressed: _toggleFlash,
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
                    onTap: () => _runPipeline(),
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
                    onPressed: () async {
                      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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

class _ProcessingDialog extends StatefulWidget {
  final Stream<PipelineUpdate> updateStream;
  final List<PipelineUpdate> initialLogs;
  final int initialProgress;
  final VoidCallback onCancel;

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

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.initialProgress;
    _logs.addAll(widget.initialLogs);

    widget.updateStream.listen((update) {
      if (mounted) {
        setState(() {
          _currentProgress = update.progress;
          _logs.insert(0, update);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 520, // Increased height slightly to accommodate the new button
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
                onPressed: widget.onCancel,
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
                      Column(
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
                            style: const TextStyle(
                              color: brandNavy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
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

  const _FailurePopup({required this.onRetry});

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
              child: const Icon(Icons.search_off_rounded, color: Colors.redAccent, size: 40),
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
            const Text(
              "We couldn't identify this item. Please ensure it's within the frame and has good lighting.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xB32D3E50),
                fontSize: 15,
                fontWeight: FontWeight.w600,
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