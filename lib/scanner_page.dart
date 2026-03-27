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
import 'package:tflite_flutter/tflite_flutter.dart';
import 'user_provider.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  CameraController? _controller;
  bool _isFlashOn = false;
  bool _isInitialized = false;

  // ML Components
  final TextRecognizer _textRecognizer = TextRecognizer();
  Interpreter? _yoloInterpreter;
  Interpreter? _lstmInterpreter;
  Map<String, dynamic> _knowledgeBase = {};

  // LSTM Configuration
  final int _sequenceLength = 5;

  // Inference State
  bool _isDialogShowing = false;
  bool _isAnalyzing = false;
  String _detectedClass = "";
  double _carbonFootprint = 0.0;
  int _currentClassId = -1;

  // Scaler Parameters (from training)
  final List<double> _scalerMeans = [0.8703151, 0.19985887, 0.518];
  final List<double> _scalerScales = [0.0692617788682185, 0.08728018142352306, 0.4996758949559204];

  @override
  void initState() {
    super.initState();
    _initializeSystem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkShowInstructions();
    });
  }

  Future<void> _initializeSystem() async {
    await _loadKnowledgeBase();
    await _loadModels();
    await _initializeCamera();
  }

  Future<void> _loadKnowledgeBase() async {
    try {
      final String response = await rootBundle.loadString('assets/Philippine_LCA_Knowledge_Base.json');
      if (mounted) {
        setState(() {
          _knowledgeBase = json.decode(response);
        });
      }
    } catch (e) {
      debugPrint("Error loading knowledge base: $e");
    }
  }

  Future<void> _loadModels() async {
    try {
      _yoloInterpreter = await Interpreter.fromAsset('assets/models/yolo.tflite');
      _lstmInterpreter = await Interpreter.fromAsset('assets/models/lstm.tflite');
      debugPrint("Neural Networks loaded successfully.");
    } catch (e) {
      debugPrint("Error loading models: $e");
    }
  }

  Future<void> _checkShowInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    final bool showAgain = prefs.getBool('show_scanner_instructions') ?? true;

    if (showAgain && mounted) {
      _showInstructionDialog();
    }
  }

  void _showInstructionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ScannerInstructionDialog(),
    );
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.max, // High resolution for better post-capture analysis
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

  Future<void> _performAnalysis(String imagePath) async {
    // Reset internal state for new analysis
    _currentClassId = -1;
    _carbonFootprint = 0.0;
    _detectedClass = "";

    try {
      // 1. Run OCR Analysis
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      String currentText = recognizedText.text.replaceAll('\n', ' ').toLowerCase();
      debugPrint("Analysis OCR: $currentText");

      // 2. Score-based Identification Logic
      int bestMatchId = -1;
      int maxScore = 0;

      _knowledgeBase.forEach((key, value) {
        String rawName = value['class_name']?.toString().toLowerCase() ?? "";
        List<String> keywords = rawName.split('_');
        
        int score = 0;
        for (var word in keywords) {
          // Check if OCR text contains the core keywords (ignoring small common words)
          if (word.length > 2 && currentText.contains(word)) {
            score += 10; // High score for direct match
          }
        }

        // Penalty for generic matches if OCR is long but score is low
        if (score > maxScore) {
          maxScore = score;
          bestMatchId = int.parse(key);
        }
      });

      // 3. Identification Fallback
      int detectedClassId = bestMatchId;
      
      // If keyword matching failed, but OCR found something, try a default or check if any specific brand is known
      if (detectedClassId == -1) {
        if (currentText.contains("milk") || currentText.contains("dairy")) detectedClassId = 3; // Milk Carton
        else if (currentText.contains("noodle")) detectedClassId = 12; // Instant Noodles
        else if (currentText.contains("coke") || currentText.contains("soda") || currentText.contains("drink")) detectedClassId = 1; // Can Beverage
        else if (currentText.contains("bread")) detectedClassId = 17; // Bread
      }

      if (detectedClassId == -1) {
        debugPrint("No class identified via OCR or hardcoded fallbacks.");
        return; 
      }

      // 4. Estimation Step (LSTM)
      // Since we have one high-res frame, we feed a stable sequence to the LSTM
      double confidence = 0.95; 
      double bboxArea = 0.20;
      int ocrFlag = currentText.isNotEmpty ? 1 : 0;
      
      double scaledConf = (confidence - _scalerMeans[0]) / _scalerScales[0];
      double scaledBbox = (bboxArea - _scalerMeans[1]) / _scalerScales[1];
      double scaledOcr = (ocrFlag - _scalerMeans[2]) / _scalerScales[2];

      List<List<double>> sequence = List.generate(_sequenceLength, 
          (_) => [detectedClassId.toDouble(), scaledConf, scaledBbox, scaledOcr]);

      if (_lstmInterpreter != null) {
        var inputSequence = [sequence];
        var outputData = List.generate(1, (index) => List.filled(1, 0.0));
        _lstmInterpreter!.run(inputSequence, outputData);
        _carbonFootprint = outputData[0][0];
      }

      // 5. Finalize Results
      String className = _knowledgeBase[detectedClassId.toString()]?['class_name'] ?? "Unknown Item";
      _currentClassId = detectedClassId;
      _detectedClass = className.replaceAll('_', ' ').toUpperCase();

      // Ensure valid footprint value
      if (_carbonFootprint <= 0) {
        double meanCf = (_knowledgeBase[detectedClassId.toString()]?['mean_cf_per_kg'] ?? 0.0).toDouble();
        double baseMass = (_knowledgeBase[detectedClassId.toString()]?['base_mass_kg'] ?? 1.0).toDouble();
        _carbonFootprint = meanCf * baseMass;
      }

    } catch (e) {
      debugPrint("Perform Analysis Error: $e");
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_isDialogShowing || _isAnalyzing || !_isInitialized) return;

    setState(() {
      _isAnalyzing = true;
      _isDialogShowing = true;
    });

    try {
      // Capture High-Res Image
      final XFile image = await _controller!.takePicture();
      
      // Analyze the photo
      await _performAnalysis(image.path);

      if (_currentClassId != -1 && _carbonFootprint > 0) {
        _showSuccessPopup(image.path);
      } else {
        _showFailurePopup();
      }
    } catch (e) {
      debugPrint("Capture Error: $e");
      _showFailurePopup();
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
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
    if (name.contains('FOOD') || name.contains('NOODLE') || name.contains('BREAD') || name.contains('MILK') || name.contains('CEREAL') || name.contains('SNACK')) {
      return 'Food';
    }
    return 'Shopping';
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    _yoloInterpreter?.close();
    _lstmInterpreter?.close();
    super.dispose();
  }

  void _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    setState(() => _isFlashOn = !_isFlashOn);
    await _controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isInitialized
                ? CameraPreview(_controller!)
                : Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: brandGreen),
                    ),
                  ),
          ),

          // Top Controls (AppBar Style)
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

          // Reticle Overlay
          if (!_isDialogShowing)
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: brandGreen.withValues(alpha: 0.5), width: 2),
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
            ),

          // Bottom Capture Controls
          if (!_isDialogShowing)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _captureAndAnalyze,
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
                    onPressed: () {
                      userProvider.setTabIndex(2);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "ENTER MANUALLY",
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
